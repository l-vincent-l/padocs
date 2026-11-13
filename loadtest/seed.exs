# Creates the accounts and the document the load tests use, in the running
# application (see loadtest/app.sh, which runs it with `bin/textexp rpc`):
#
#   * `loadtest-1@example.com` ... `loadtest-<users>@example.com`, all with the
#     password `loadtest-password`, confirmed;
#   * `documents` documents owned by the first one, "Test de charge 1"...,
#     shared with the others as editors, each holding `paragraphs`
#     paragraphs of text (1: a short one, to edit; the others of 80 words, to
#     search), so that it is not empty (empty documents are deleted when their
#     DocServer stops).
#
# Running it again only adds what is missing. Prints the documents' ids,
# separated by commas.
defmodule Loadtest.Seed do
  import Ecto.Query

  alias Textexp.Accounts
  alias Textexp.Document
  alias Textexp.Document.Document, as: DocumentSchema
  alias Textexp.SqliteRepo, as: Repo

  @password "loadtest-password"
  @words ~w(association assemblée budget compte rendu réunion statuts bureau
             trésorier projet école mairie conseil subvention adhérent vote
             décision calendrier rapport activité bénévole local fête dossier)

  def run(users, documents \\ 1, paragraphs \\ 1) do
    accounts = Enum.map(1..users, &account/1)
    [owner | editors] = accounts

    ids =
      for n <- 1..documents do
        document = document(owner, "Test de charge #{n}", paragraphs)

        for editor <- editors do
          {:ok, _member} =
            Document.share_document(owner, document.id, %{
              "email" => editor.email,
              "role" => "editor"
            })
        end

        document.id
      end

    IO.puts(Enum.join(ids, ","))
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

  defp document(owner, title, paragraphs) do
    query =
      from d in DocumentSchema,
        where: d.owner_id == ^owner.id and d.title == ^title and is_nil(d.deleted_at)

    case Repo.one(query) do
      nil ->
        {:ok, document} = Document.create_document(owner, %{"title" => title})
        Repo.update!(Ecto.Changeset.change(document, snapshot: body(paragraphs)))

      document ->
        document
    end
  end

  # A BlockNote body, in the fragment the editor syncs: a short paragraph,
  # then `paragraphs - 1` of random words.
  defp body(paragraphs) do
    doc = Yex.Doc.new()
    fragment = Yex.Doc.get_xml_fragment(doc, "document-store")

    Yex.XmlFragment.push(
      fragment,
      Yex.XmlElementPrelim.new("blockGroup", [
        Yex.XmlElementPrelim.new("blockContainer", [
          Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from("Texte de départ. ")])
        ])
        | for _ <- 2..paragraphs//1 do
            text = Enum.map_join(1..80, " ", fn _ -> Enum.random(@words) end)

            Yex.XmlElementPrelim.new("blockContainer", [
              Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from(text)])
            ])
          end
      ])
    )

    Yex.encode_state_as_update!(doc)
  end
end
