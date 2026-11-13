defmodule Padocs.Accounts.UserNotifier do
  @moduledoc "The emails sent to users: links to confirm, sign in, reset a password."
  import Swoosh.Email

  alias Padocs.Mailer

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your email address", """
    <p>Click this link to confirm your email:</p>
    <p><a href="#{url}">#{url}</a></p>
    """)
  end

  def deliver_login_instructions(user, url) do
    deliver(user.email, "Your login link", """
    <p>Hello, #{user.email}! Click this link to sign in:</p>
    <p><a href="#{url}">#{url}</a></p>
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your password", """
    <p>Click this link to reset your password:</p>
    <p><a href="#{url}">#{url}</a></p>
    """)
  end

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
