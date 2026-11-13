# Shared by the scenarios: their environment, and the sign-in of the
# accounts of loadtest/seed.exs.
defmodule Loadtest.Session do
  @password "loadtest-password"

  @doc "The application's URL: LOADTEST_URL, http://localhost:4000 by default."
  def url, do: System.get_env("LOADTEST_URL", "http://localhost:4000")

  @doc "The ids of LOADTEST_DOCUMENTS, as printed by the seed, in a tuple."
  def documents do
    case System.get_env("LOADTEST_DOCUMENTS") do
      nil -> raise "LOADTEST_DOCUMENTS is missing: the ids printed by loadtest/seed.exs"
      ids -> ids |> String.split(",", trim: true) |> List.to_tuple()
    end
  end

  @doc "The integer in the environment variable `name`, or `default`."
  def env_integer(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  @doc """
  Signs in the LOADTEST_USERS accounts (50), four at a time, before the load:
  bcrypt makes a sign-in costly, and it is not what is measured. Returns their
  sessions (see `sign_in/3`) in a tuple, the account of VU `n` being at
  `rem(n - 1, size)`.
  """
  def sign_in_all(url, document) do
    {:ok, _apps} = Application.ensure_all_started(:req)

    1..env_integer("LOADTEST_USERS", 50)
    |> Task.async_stream(&sign_in(url, document, &1), max_concurrency: 4, timeout: 60_000)
    |> Enum.map(fn {:ok, session} -> session end)
    |> List.to_tuple()
  end

  @doc "The session of VU `vu_id` among `sessions`."
  def for_vu(sessions, vu_id), do: elem(sessions, rem(vu_id - 1, tuple_size(sessions)))

  @doc """
  The session cookie of the account `i`, and the CSRF token of the page of
  `document`, which the sockets ask for to read the session.
  """
  def sign_in(url, document, i) do
    req = Req.new(base_url: url, redirect: false, retry: false)

    page = Req.get!(req, url: "/sign-in")
    cookie = session_cookie(page, nil)

    response =
      Req.post!(req,
        url: "/sign-in",
        headers: [cookie: cookie],
        form: [
          _csrf_token: csrf_token(page.body),
          "user[email]": "loadtest-#{i}@example.com",
          "user[password]": @password
        ]
      )

    if response.status != 302, do: raise("sign-in of loadtest-#{i} failed: #{response.status}")
    cookie = session_cookie(response, cookie)

    page = Req.get!(req, url: "/documents/#{document}", headers: [cookie: cookie])
    if page.status != 200, do: raise("document page for loadtest-#{i}: #{page.status}")

    %{cookie: session_cookie(page, cookie), csrf_token: csrf_token(page.body)}
  end

  defp session_cookie(response, previous) do
    response
    |> Req.Response.get_header("set-cookie")
    |> Enum.find_value(previous, fn header ->
      case Regex.run(~r/^(_textexp_key=[^;]+)/, header) do
        [_, cookie] -> cookie
        nil -> nil
      end
    end)
  end

  defp csrf_token(html) do
    [_, token] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html)
    token
  end
end
