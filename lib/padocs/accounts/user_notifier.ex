defmodule Padocs.Accounts.UserNotifier do
  @moduledoc """
  The emails sent to users: links to confirm, sign in, reset a password. In
  their language (see `PadocsWeb.Locale`).
  """
  use Gettext, backend: PadocsWeb.Gettext
  import Swoosh.Email

  alias Padocs.Mailer

  def deliver_confirmation_instructions(user, url) do
    in_locale(user, fn ->
      deliver(user.email, gettext("Confirm your email address"), """
      <p>#{gettext("Click this link to confirm your email address:")}</p>
      <p><a href="#{url}">#{url}</a></p>
      """)
    end)
  end

  def deliver_login_instructions(user, url) do
    in_locale(user, fn ->
      deliver(user.email, gettext("Your sign-in link"), """
      <p>#{gettext("Hello, %{email}! Click this link to sign in:", email: user.email)}</p>
      <p><a href="#{url}">#{url}</a></p>
      """)
    end)
  end

  def deliver_reset_password_instructions(user, url) do
    in_locale(user, fn ->
      deliver(user.email, gettext("Reset your password"), """
      <p>#{gettext("Click this link to reset your password:")}</p>
      <p><a href="#{url}">#{url}</a></p>
      """)
    end)
  end

  # In the language the user chose, else the one of the request that sends it
  # (the page they are on).
  defp in_locale(%{locale: locale}, fun) when is_binary(locale),
    do: Gettext.with_locale(PadocsWeb.Gettext, locale, fun)

  defp in_locale(_user, fun), do: fun.()

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> from({"noreply", "noreply@example.com"})
      |> to(recipient)
      |> subject(subject)
      |> html_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email), do: {:ok, email}
  end
end
