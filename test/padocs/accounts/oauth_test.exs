defmodule Padocs.Accounts.OAuthTest do
  use PadocsWeb.ConnCase

  alias Padocs.Accounts
  alias Padocs.Accounts.{User, UserIdentity}
  alias Padocs.{Fixtures, SqliteRepo}

  # What GitHub (through Assent) gives about the account.
  defp github_user_info(email) do
    %{
      "sub" => "#{System.unique_integer([:positive])}",
      "email" => email,
      "email_verified" => true
    }
  end

  defp register(user_info, provider \\ "github") do
    Accounts.sign_in_with_provider(provider, user_info, %{
      "access_token" => "token",
      "token_type" => "bearer"
    })
  end

  defp identities(user), do: SqliteRepo.all_by(UserIdentity, user_id: user.id)

  test "the sign-in page offers GitHub and GitLab", %{conn: conn} do
    html = conn |> get(~p"/sign-in") |> html_response(200)

    assert html =~ ~s(href="/auth/user/github")
    assert html =~ ~s(href="/auth/user/gitlab")
    assert html =~ "/images/gitlab.svg"
  end

  test "registers a new user, and recognises them when they come back" do
    user_info = github_user_info("octo-#{System.unique_integer([:positive])}@example.com")

    assert {:ok, user} = register(user_info)
    assert user.email == user_info["email"]
    assert user.confirmed_at

    assert [%{strategy: "github", uid: uid}] = identities(user)
    assert uid == user_info["sub"]

    assert {:ok, again} = register(user_info)
    assert again.id == user.id
  end

  test "signs in the confirmed account with the same email" do
    email = "confirmed-#{System.unique_integer([:positive])}@example.com"
    existing = SqliteRepo.insert!(%User{email: email, confirmed_at: DateTime.utc_now()})

    assert {:ok, user} = register(github_user_info(email))
    assert user.id == existing.id
  end

  test "refuses an unconfirmed account with the same email" do
    email = "unconfirmed-#{System.unique_integer([:positive])}@example.com"
    Fixtures.register_user(email)

    assert {:error, :unconfirmed_account} = register(github_user_info(email))
  end

  test "registers a new user with GitLab" do
    user_info = github_user_info("tanuki-#{System.unique_integer([:positive])}@example.com")

    assert {:ok, user} = register(user_info, "gitlab")
    assert user.email == user_info["email"]
    assert [%{strategy: "gitlab"}] = identities(user)
  end

  # Otherwise anyone could declare someone else's address at the provider and
  # get a confirmed account in their name here.
  test "refuses an email address the provider has not verified" do
    email = "unverified-#{System.unique_integer([:positive])}@example.com"
    user_info = %{github_user_info(email) | "email_verified" => false}

    assert {:error, :unverified_email} = register(user_info)
    refute Accounts.get_user_by_email(email)
  end

  test "a failed sign-in with GitHub says so", %{conn: conn} do
    # Not configured in the tests: no client id.
    conn = get(conn, ~p"/auth/user/github")

    assert redirected_to(conn) == ~p"/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Signing in with GitHub failed"
  end
end
