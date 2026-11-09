# Creates the accounts and the document the load tests use, in the running
# application (see loadtest/app.sh, which runs it with `bin/textexp rpc`):
#
#   * `loadtest-1@example.com` ... `loadtest-<users>@example.com`, all with the
#     password `loadtest-password`, confirmed;
#   * a document owned by the first one, "Test de charge", shared with the
#     others as editors, holding a paragraph of text so that it is not empty
#     (empty documents are deleted when their DocServer stops).
#
# Running it again only adds what is missing. Prints the document's id.
defmodule Loadtest.Seed do
  import Ecto.Query

  alias Textexp.Accounts
  alias Textexp.Document
  alias Textexp.Document.Document, as: DocumentSchema
  alias Textexp.SqliteRepo, as: Repo

  @password "loadtest-password"
  @title "Test de charge"

  def run(users) do
    accounts = Enum.map(1..users, &account/1)
    [owner | editors] = accounts
    document = document(owner)

    for editor <- editors do
      {:ok, _member} =
        Document.share_document(owner, document.id, %{"email" => editor.email, "role" => "editor"})
    end

    IO.puts(document.id)
  end

  def email(i), do: "loadtest-#{i}@example.com"

  defp account(i) do
    email = email(i)

    user =
      Accounts.get_user_by_email(email) ||
        (
          attrs = %{
            "email" => email,
            "password" => @password,
            "password_confirmation" => @password
          }

          {:ok, user} = Accounts.register_user(attrs, fn _token -> "" end)
          user
        )

    if user.confirmed_at,
      do: user,
      else: Repo.update!(Ecto.Changeset.change(user, confirmed_at: DateTime.utc_now()))
  end

  defp document(owner) do
    query =
      from d in DocumentSchema,
        where: d.owner_id == ^owner.id and d.title == ^@title and is_nil(d.deleted_at)

    case Repo.one(query) do
      nil ->
        {:ok, document} = Document.create_document(owner, %{"title" => @title})
        Repo.update!(Ecto.Changeset.change(document, snapshot: body()))

      document ->
        document
    end
  end

  # A BlockNote body: one paragraph, in the fragment the editor syncs.
  defp body do
    doc = Yex.Doc.new()
    fragment = Yex.Doc.get_xml_fragment(doc, "document-store")

    Yex.XmlFragment.push(
      fragment,
      Yex.XmlElementPrelim.new("blockGroup", [
        Yex.XmlElementPrelim.new("blockContainer", [
          Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from("Texte de départ. ")])
        ])
      ])
    )

    Yex.encode_state_as_update!(doc)
  end
end
