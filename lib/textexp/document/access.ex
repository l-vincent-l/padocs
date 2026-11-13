defmodule Textexp.Document.Access do
  @moduledoc """
  The rights on a document, kept by its DocServer while it runs (see
  `YPhoenix.Access`): the role of each user, those of the document and those
  it inherits from its ancestors (see `Textexp.Document.access_rights/1`),
  loaded in one query then updated by the changes `Textexp.Document`
  broadcasts on `Textexp.Document.members_topic/1`. A document in the trash
  has none.

  The actor joining is a user, or `{:public, token}` for anyone opening the
  document's public link (see `TextexpWeb.PublicDocumentLive`): they read it
  while `token` is its public link's; a link changed or removed sends them
  away.
  """
  @behaviour YPhoenix.Access

  alias Textexp.Document
  alias Textexp.Document.Policy

  @impl true
  def init(document_id) do
    # Subscribed first, so that a change made while loading is not missed.
    Phoenix.PubSub.subscribe(Textexp.PubSub, Document.members_topic(document_id))

    case Document.access_rights(document_id) do
      {:ok, roles} ->
        {:ok,
         %{
           document_id: document_id,
           roles: roles,
           public_token: Document.public_token(document_id)
         }}

      :error ->
        :not_found
    end
  end

  @impl true
  def permission(%{public_token: token}, {:public, token}) when is_binary(token), do: :read
  def permission(_rights, {:public, _token}), do: :none

  def permission(%{roles: roles}, user) do
    role = Map.get(roles, user.id)

    cond do
      Policy.can?(role, :write) -> :write
      Policy.can?(role, :read) -> :read
      true -> :none
    end
  end

  # `role` is the user's role on the document now, whether the change was on
  # it or on an ancestor.
  @impl true
  def handle_info(
        {:member_changed, document_id, user_id, role},
        %{document_id: document_id} = rights
      ) do
    roles =
      if role,
        do: Map.put(rights.roles, user_id, role),
        else: Map.delete(rights.roles, user_id)

    {:ok, %{rights | roles: roles}}
  end

  def handle_info(
        {:public_link_changed, document_id, token},
        %{document_id: document_id} = rights
      ),
      do: {:ok, %{rights | public_token: token}}

  # Put in the trash, where it has no role nor public link, or restored.
  def handle_info({:access_reloaded, document_id}, %{document_id: document_id} = rights) do
    case Document.access_rights(document_id) do
      {:ok, roles} ->
        {:ok, %{rights | roles: roles, public_token: Document.public_token(document_id)}}

      :error ->
        {:ok, %{rights | roles: %{}, public_token: nil}}
    end
  end

  def handle_info(_msg, _rights), do: :ignore
end
