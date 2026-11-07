defmodule Textexp.Document.Access do
  @moduledoc """
  The rights on a document, kept by its DocServer while it runs (see
  `YPhoenix.Access`): the role of each user, those of the document and those
  it inherits from its ancestors (see `Textexp.Document.access_rights/1`),
  loaded in one query then updated by the changes `Textexp.Document`
  broadcasts on `Textexp.Document.members_topic/1`. A document in the trash
  has none.
  """
  @behaviour YPhoenix.Access

  alias Textexp.Document
  alias Textexp.Document.Policy

  @impl true
  def init(document_id) do
    # Subscribed first, so that a change made while loading is not missed.
    Phoenix.PubSub.subscribe(Textexp.PubSub, Document.members_topic(document_id))

    case Document.access_rights(document_id) do
      {:ok, roles} -> {:ok, %{document_id: document_id, roles: roles}}
      :error -> :not_found
    end
  end

  @impl true
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

  # Put in the trash, where it has no role, or restored.
  def handle_info({:access_reloaded, document_id}, %{document_id: document_id} = rights) do
    case Document.access_rights(document_id) do
      {:ok, roles} -> {:ok, %{rights | roles: roles}}
      :error -> {:ok, %{rights | roles: %{}}}
    end
  end

  def handle_info(_msg, _rights), do: :ignore
end
