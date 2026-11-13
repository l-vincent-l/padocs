defmodule PadocsWeb.OAuthController do
  @moduledoc """
  Sign-in with a GitHub or GitLab account (an OAuth application on each, see
  config/runtime.exs), through Assent: `/auth/user/:provider` sends to the
  provider, which sends back to `/auth/user/:provider/callback`. See
  `Padocs.Accounts.sign_in_with_provider/3` for who is signed in.
  """
  use PadocsWeb, :controller

  alias Padocs.Accounts
  alias PadocsWeb.UserAuth

  # GitLab speaks OpenID Connect: gitlab.com, or a self-hosted instance.
  @providers %{
    "github" => {:github, Assent.Strategy.Github},
    "gitlab" => {:gitlab, Assent.Strategy.OIDC}
  }

  def authorize(conn, %{"provider" => provider}) do
    with {:ok, strategy, config} <- strategy(provider),
         {:ok, %{url: url, session_params: session_params}} <- strategy.authorize_url(config) do
      conn
      |> put_session(:oauth_session_params, session_params)
      |> redirect(external: url)
    else
      _ -> failure(conn, provider)
    end
  end

  def callback(conn, %{"provider" => provider} = params) do
    session_params = get_session(conn, :oauth_session_params)

    with {:ok, strategy, config} <- strategy(provider),
         {:ok, %{user: user_info, token: token}} <-
           strategy.callback(Keyword.put(config, :session_params, session_params), params),
         {:ok, user} <- Accounts.sign_in_with_provider(provider, user_info, token) do
      conn
      |> delete_session(:oauth_session_params)
      |> put_flash(:info, gettext("You are now signed in"))
      |> UserAuth.log_in_user(user)
    else
      _ -> failure(conn, provider)
    end
  end

  # The strategy and configuration of a provider; an error when unknown, or
  # without its client id and secret.
  defp strategy(provider) do
    with {:ok, {key, strategy}} <- Map.fetch(@providers, provider),
         settings = Application.get_env(:padocs, key, []),
         [client_id, client_secret, base] when is_binary(client_id) and is_binary(client_secret) <-
           Enum.map([:client_id, :client_secret, :redirect_uri], &settings[&1]) do
      config = [
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: "#{base}/user/#{provider}/callback"
      ]

      config =
        if key == :gitlab,
          do:
            config ++
              [
                base_url: settings[:base_url],
                authorization_params: [scope: "openid email profile"]
              ],
          else: config

      {:ok, strategy, config}
    else
      _ -> :error
    end
  end

  # Not configured, an email address the provider has not verified, or an
  # unconfirmed account here with the same address.
  defp failure(conn, provider) do
    name = if provider == "gitlab", do: "GitLab", else: "GitHub"

    conn
    |> put_flash(
      :error,
      gettext(
        "Signing in with %{provider} failed. Check that your email address is verified there. If you already have an account here with this address, confirm it first, then sign in again.",
        provider: name
      )
    )
    |> redirect(to: ~p"/sign-in")
  end
end
