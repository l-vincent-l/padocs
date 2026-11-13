defmodule PadocsWeb.Locale do
  @moduledoc """
  The language of the interface, for Gettext (`PadocsWeb.Gettext`): the one
  the user chose, kept on their account (or in the session when signed out,
  see `PadocsWeb.LocaleController`), else the browser's first language we
  have (`Accept-Language`), else French.

  As a plug, in the browser's pipeline, it sets the language of the request
  and keeps it in the session, where the LiveViews read it again
  (`on_mount/4`).
  """
  import Plug.Conn

  @locales ~w(fr en)
  @default "fr"

  @doc "The languages of the interface."
  def locales, do: @locales

  @doc "Whether `locale` is one of the languages of the interface."
  def known?(locale), do: locale in @locales

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      user_locale(conn.assigns[:current_user]) ||
        known(get_session(conn, "locale")) ||
        accepted(get_req_header(conn, "accept-language")) ||
        @default

    Gettext.put_locale(PadocsWeb.Gettext, locale)

    conn
    |> put_session("locale", locale)
    |> assign(:locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale =
      user_locale(socket.assigns[:current_user]) || known(session["locale"]) || @default

    Gettext.put_locale(PadocsWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp user_locale(%{locale: locale}), do: known(locale)
  defp user_locale(_user), do: nil

  defp known(locale) when locale in @locales, do: locale
  defp known(_locale), do: nil

  @doc """
  The first of `headers` (`Accept-Language`) languages we have, by
  preference: `"en-GB,en;q=0.9,fr;q=0.8"` gives `"en"`. `nil` for none.
  """
  def accepted(headers) do
    headers
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&parse_language/1)
    |> Enum.reject(&is_nil/1)
    # stable: of equal weights, the first given
    |> Enum.sort_by(fn {_language, q} -> q end, :desc)
    |> Enum.find_value(fn {language, _q} -> known(language) end)
  end

  defp parse_language(part) do
    [tag | params] = part |> String.trim() |> String.split(";")
    language = tag |> String.split("-") |> hd() |> String.downcase()

    q =
      Enum.find_value(params, 1.0, fn param ->
        with ["q", value] <- param |> String.trim() |> String.split("=", parts: 2),
             {q, _rest} <- Float.parse(value) do
          q
        else
          _ -> nil
        end
      end)

    if language != "" and q > 0, do: {language, q}
  end
end
