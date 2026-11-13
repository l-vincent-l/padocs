defmodule Textexp.Fixtures do
  @moduledoc "Users and sessions for the tests."

  alias Textexp.Accounts

  @password "a-long-password"

  def password, do: @password

  @doc "A user registered with a password, its address unconfirmed."
  def register_user(email \\ "user-#{System.unique_integer([:positive])}@example.com") do
    {:ok, user} =
      Accounts.register_user(
        %{email: email, password: @password, password_confirmation: @password},
        &"/confirm_new_user/#{&1}"
      )

    user
  end

  @doc "A user registered with a password, its address confirmed."
  def confirmed_user(email \\ "user-#{System.unique_integer([:positive])}@example.com") do
    email
    |> register_user()
    |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now())
    |> Textexp.SqliteRepo.update!()
  end

  @doc "A document of `owner`."
  def create_document!(owner, attrs \\ %{}) do
    {:ok, document} = Textexp.Document.create_document(owner, attrs)
    document
  end

  @doc "Shares `document`, of `owner`, with `user` as `role`."
  def share!(owner, document, user, role) do
    {:ok, member} =
      Textexp.Document.share_document(owner, document.id, %{email: user.email, role: role})

    member
  end

  @doc "`conn` signed in as `user`."
  def log_in(conn, user) do
    Phoenix.ConnTest.init_test_session(conn, %{
      user_token: Accounts.generate_user_session_token(user)
    })
  end

  @doc "The Yjs state of a BlockNote document holding one paragraph of `text`."
  def yjs_state(text) do
    doc = Yex.Doc.new()

    doc
    |> Yex.Doc.get_xml_fragment("document-store")
    |> Yex.XmlFragment.push(
      Yex.XmlElementPrelim.new("blockGroup", [
        Yex.XmlElementPrelim.new("blockContainer", [
          Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from(text)])
        ])
      ])
    )

    Yex.encode_state_as_update!(doc)
  end
end
