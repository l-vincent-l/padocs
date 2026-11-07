defmodule Textexp.Document do
  @moduledoc """
  The documents and who may access them: their owner can do anything, editors
  (see `Textexp.Document.Membership`) read and write, viewers only read (see
  `Textexp.Document.Policy`).

  A document can have sub-documents, which inherit its accesses: a user's
  role on a document is the best they have on it or any of its ancestors.

  Functions taking a `user` only see and change what that user may: listings
  are filtered in their query, an action reads the user's role, then checks it
  with `Policy`. The others, without user, are for the server itself: e.g.
  YPersistence saves the documents being edited, whose DocServer checks the
  rights of the clients (see `Textexp.Document.Access`).

  A change of a member's role is broadcast on `members_topic/1`, a rename or a
  change of tags on `Textexp.Document.YPersistence.topic/1`, a move on
  `Textexp.Document.YPersistence.documents_topic/0`.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Textexp.Accounts
  alias Textexp.Accounts.User

  alias Textexp.Document.{
    Body,
    Document,
    Membership,
    Policy,
    Tag,
    TagDocument,
    TagSearch,
    Visit,
    YPersistence
  }

  alias Textexp.SqliteRepo, as: Repo

  # Largest Yjs state an import accepts.
  @max_import_bytes 5_000_000

  # Read without their snapshot, which only the editor loads.
  @fields [:id, :title, :excerpt, :owner_id, :parent_id, :deleted_at, :inserted_at, :updated_at]

  # The roles, as ranks: the best is the highest.
  @ranks %{owner: 3, editor: 2, viewer: 1}

  ## Reading

  # The documents `user` can read, each with `user`'s best `rank` on it (see
  # @ranks), as `:access`. Not those in the trash: a document goes there with
  # its sub-documents, so none inherits an access from one there.
  defp readable_by(user) do
    from d in Document,
      as: :document,
      join: a in subquery(ranks(user)),
      as: :access,
      on: a.id == d.id,
      where: is_nil(d.deleted_at)
  end

  # The documents `user` can access: those they own or are a member of, and
  # their descendants, which inherit the access. `%{id, rank}`, the best rank
  # for each.
  defp ranks(user) do
    owned = from d in Document, where: d.owner_id == ^user.id, select: %{id: d.id, rank: 3}

    shared =
      from m in Membership,
        where: m.user_id == ^user.id,
        select: %{
          id: m.document_id,
          rank: fragment("CASE ? WHEN 'editor' THEN 2 ELSE 1 END", m.role)
        }

    inherited =
      from d in Document,
        join: a in "accesses",
        on: d.parent_id == a.id,
        select: %{id: d.id, rank: a.rank}

    from(a in "accesses", group_by: a.id, select: %{id: a.id, rank: max(a.rank)})
    |> recursive_ctes(true)
    |> with_cte("accesses", as: ^(owned |> union_all(^shared) |> union_all(^inherited)))
  end

  defp role(rank), do: Enum.find_value(@ranks, fn {role, r} -> r == rank && role end)

  @doc "The documents `user` can read, last updated first, with their `role` on each."
  def list_documents(user) do
    readable_by(user)
    |> order_by(desc: :updated_at)
    |> with_roles()
  end

  @doc """
  The documents `user` opened last that they can still read, the last opened
  first, at most `limit` (see `opened/2`).
  """
  def list_recent_documents(user, limit \\ 30) do
    readable_by(user)
    |> join(:inner, [document: d], v in Visit,
      as: :visit,
      on: v.document_id == d.id and v.user_id == ^user.id
    )
    |> order_by([visit: v], desc: v.opened_at)
    |> limit(^limit)
    |> with_roles()
  end

  @doc "The documents `user` owns, last updated first."
  def list_own_documents(user) do
    readable_by(user)
    |> where([document: d], d.owner_id == ^user.id)
    |> order_by(desc: :updated_at)
    |> with_roles()
  end

  @doc """
  The documents of others that `user` can read, shared with them or with one
  of their parents, last updated first.
  """
  def list_shared_documents(user) do
    readable_by(user)
    |> where([document: d], d.owner_id != ^user.id)
    |> order_by(desc: :updated_at)
    |> with_roles()
  end

  # The documents of `query`, each with the reader's `role` on it.
  defp with_roles(query) do
    query
    |> select([document: d, access: a], {struct(d, @fields), a.rank})
    |> Repo.all()
    |> Enum.map(fn {document, rank} -> %{document | role: role(rank)} end)
  end

  @doc "Among `ids`, the documents `user` can read."
  def list_documents(user, ids) do
    readable_by(user)
    |> where([document: d], d.id in ^ids)
    |> select([document: d], struct(d, @fields))
    |> Repo.all()
  end

  @doc """
  The documents `user` can read, with the text of their body and the ids of
  their tags: `{document, text, tag_ids}`.
  """
  def list_documents_with_text(user) do
    documents =
      readable_by(user)
      |> select([document: d], struct(d, [:snapshot | @fields]))
      |> Repo.all()

    tag_ids =
      from(l in TagDocument,
        where: l.document_id in ^Enum.map(documents, & &1.id),
        select: {l.document_id, l.tag_id}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Enum.map(documents, fn document ->
      {%{document | snapshot: nil}, body(document.snapshot, :text),
       Map.get(tag_ids, document.id, [])}
    end)
  end

  @doc """
  The document of `id`, if `user` can read it, with their `role` on it:
  `{:ok, document}` or `{:error, :not_found}`.
  """
  def get_document(id, user) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {document, rank} <-
           readable_by(user)
           |> where([document: d], d.id == ^id)
           |> select([document: d, access: a], {struct(d, @fields), a.rank})
           |> Repo.one() do
      {:ok, %{document | role: role(rank)}}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The ancestors of `document` that `user` can read, from the root down to its
  parent.
  """
  def list_ancestors(%Document{parent_id: nil}, _user), do: []

  def list_ancestors(%Document{parent_id: parent_id}, user) do
    first =
      from d in Document,
        where: d.id == ^parent_id,
        select: %{id: d.id, parent_id: d.parent_id, depth: 0}

    next =
      from d in Document,
        join: c in "ancestors",
        on: d.id == c.parent_id,
        select: %{id: d.id, parent_id: d.parent_id, depth: c.depth + 1}

    readable_by(user)
    |> recursive_ctes(true)
    |> with_cte("ancestors", as: ^union_all(first, ^next))
    |> join(:inner, [document: d], c in "ancestors", as: :ancestor, on: c.id == d.id)
    |> order_by([ancestor: c], desc: c.depth)
    |> select([document: d], struct(d, @fields))
    |> Repo.all()
  end

  # The ids of the document of `id` and of its descendants.
  defp subtree_ids(id) do
    first = from d in Document, where: d.id == ^id, select: %{id: d.id}

    next =
      from d in Document,
        join: s in "subtree",
        on: d.parent_id == s.id,
        select: %{id: d.id}

    from(s in "subtree", select: s.id)
    |> recursive_ctes(true)
    |> with_cte("subtree", as: ^union_all(first, ^next))
    |> Repo.all()
  end

  @doc "Whether the document of `id` has sub-documents."
  def has_children?(id), do: Repo.exists?(from d in Document, where: d.parent_id == ^id)

  @doc """
  The roles on the document of `id`, those it has and those it inherits from
  its ancestors: `{:ok, roles}`, `roles` giving the best role of each user's
  id, or `:error` for an unknown document.
  """
  def access_rights(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         chain when chain != [] <- chain(id) do
      owners = for {owner_id, _user_id, _role} <- chain, do: {owner_id, @ranks.owner}

      members =
        for {_owner_id, user_id, role} <- chain, user_id, do: {user_id, @ranks[role]}

      roles =
        (owners ++ members)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {user_id, ranks} -> {user_id, role(Enum.max(ranks))} end)

      {:ok, roles}
    else
      _ -> :error
    end
  end

  # The document of `id` and its ancestors: `{owner_id, member_id, role}` for
  # each of their members, `{owner_id, nil, nil}` for one without members.
  # Nothing for a document in the trash, which nobody reads.
  defp chain(id) do
    first =
      from d in Document,
        where: d.id == ^id and is_nil(d.deleted_at),
        select: %{id: d.id, parent_id: d.parent_id}

    next =
      from d in Document,
        join: c in "chain",
        on: d.id == c.parent_id,
        select: %{id: d.id, parent_id: d.parent_id}

    from(c in "chain",
      join: d in Document,
      on: d.id == c.id,
      left_join: m in Membership,
      on: m.document_id == d.id,
      select: {d.owner_id, m.user_id, m.role}
    )
    |> recursive_ctes(true)
    |> with_cte("chain", as: ^union_all(first, ^next))
    |> Repo.all()
  end

  @doc """
  PubSub topic on which `{:member_changed, document_id, user_id, role}` is
  broadcast when the role of a user on a document changed: a member added,
  changed or removed, on it or one of its ancestors. `role` is the user's
  role on it now, `nil` without access.
  """
  def members_topic(document_id), do: "document_members:#{document_id}"

  # Broadcast for the document of `document_id` and its descendants, which
  # inherit the change.
  defp broadcast_member_changed(document_id, user_id) do
    ids = subtree_ids(document_id)
    ranks = user_ranks(user_id, ids)
    for id <- ids, do: broadcast_role(id, user_id, role(ranks[id]))
    :ok
  end

  defp broadcast_role(document_id, user_id, role) do
    Phoenix.PubSub.broadcast(
      Textexp.PubSub,
      members_topic(document_id),
      {:member_changed, document_id, user_id, role}
    )
  end

  # The best rank of the user of `user_id` on each of the documents of `ids`
  # they can access.
  defp user_ranks(user_id, ids) do
    Repo.all(
      from a in subquery(ranks(%User{id: user_id})),
        where: a.id in ^ids,
        select: {a.id, a.rank}
    )
    |> Map.new()
  end

  # Runs `fun` if `user` may do `action` on the document of `id`, in the same
  # transaction as the reading of their role.
  defp authorized(id, user, action, fun) do
    Repo.transact(fn ->
      case get_document(id, user) do
        {:ok, document} ->
          if Policy.can?(document.role, action), do: fun.(document), else: {:error, :forbidden}

        {:error, _} ->
          {:error, :forbidden}
      end
    end)
  end

  @doc """
  The document `user` opened last (see `opened/2`) if they can still read it,
  else the one last updated, else `nil`.
  """
  def last_opened(user) do
    readable_by(user)
    |> join(:inner, [], u in User, as: :user, on: u.id == ^user.id)
    |> order_by([document: d, user: u], desc: coalesce(d.id == u.last_document_id, false))
    |> order_by([document: d], desc: d.updated_at)
    |> limit(1)
    |> select([document: d], struct(d, @fields))
    |> Repo.one()
  end

  @doc """
  Remembers that `user` opened `document`, for `last_opened/1` and
  `list_recent_documents/2`.
  """
  def opened(user, %Document{id: id}) do
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [last_document_id: id])

    Repo.insert!(
      %Visit{user_id: user.id, document_id: id, opened_at: DateTime.utc_now()},
      on_conflict: {:replace, [:opened_at]},
      conflict_target: [:user_id, :document_id]
    )

    :ok
  end

  @doc "The document of `id`, with its snapshot."
  def get_document!(id), do: Repo.get!(Document, id)

  @doc "The body of a document as Markdown, from its saved snapshot."
  def markdown(%Document{snapshot: snapshot}), do: body(snapshot, :markdown)

  # While the document is being edited, it can miss the changes of the last
  # seconds (see YPersistence).
  defp body(nil, _format), do: ""

  defp body(snapshot, format) do
    doc = Yex.Doc.new()
    Yex.apply_update(doc, snapshot)

    case format do
      :markdown -> Body.to_markdown(doc)
      :text -> Body.text(doc)
    end
  end

  ## Writing

  def create_document(user, attrs \\ %{}) do
    %Document{owner_id: user.id}
    |> Changeset.cast(attrs, [:title])
    |> Repo.insert()
  end

  @doc """
  Creates a sub-document of the document of `parent_id`, which `user` must be
  able to write. `user` owns it; the accesses to the parent apply to it.
  """
  def create_sub_document(parent_id, user) do
    authorized(parent_id, user, :write, fn parent ->
      with {:ok, document} <- Repo.insert(%Document{owner_id: user.id, parent_id: parent.id}) do
        {:ok, %{document | role: :owner}}
      end
    end)
  end

  @doc """
  Moves the document of `id` under the document of `parent_id`, or to the
  root for `nil`. It then inherits the accesses of its new parent instead of
  the old one's, as do its descendants.

  `user` must be able to share the document and to write the new parent. To
  the root, they must own it: an owner by inheritance would lose it. A
  document cannot go under itself or one of its descendants (`:cycle`).

  The roles changed by the move are broadcast on `members_topic/1`, and
  `{:document_moved, id, parent_id}` on `YPersistence.documents_topic/0`.
  """
  def move_document(id, parent_id, user) do
    result =
      authorized(id, user, :share, fn document ->
        ids = subtree_ids(document.id)

        with {:ok, parent_id} <- destination(document, parent_id, ids, user) do
          # Only the users with a role on the old or new parent can see theirs
          # change, on the documents moved.
          users = parent_users(document.parent_id) ++ parent_users(parent_id)
          users = Enum.uniq(users)
          before = Map.new(users, &{&1, user_ranks(&1, ids)})

          Repo.update_all(from(d in Document, where: d.id == ^document.id),
            set: [parent_id: parent_id]
          )

          changes =
            for user_id <- users,
                now = user_ranks(user_id, ids),
                id <- ids,
                now[id] != before[user_id][id],
                do: {id, user_id, role(now[id])}

          {:ok, {%{document | parent_id: parent_id}, changes}}
        end
      end)

    with {:ok, {document, changes}} <- result do
      for {id, user_id, role} <- changes, do: broadcast_role(id, user_id, role)

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        YPersistence.documents_topic(),
        {:document_moved, document.id, document.parent_id}
      )

      {:ok, document}
    end
  end

  defp destination(%Document{owner_id: owner_id}, nil, _ids, %{id: owner_id}), do: {:ok, nil}
  defp destination(_document, nil, _ids, _user), do: {:error, :forbidden}

  defp destination(_document, parent_id, ids, user) do
    with {:ok, parent_id} <- Ecto.UUID.cast(parent_id),
         false <- parent_id in ids,
         {:ok, parent} <- get_document(parent_id, user),
         true <- Policy.can?(parent.role, :write) do
      {:ok, parent_id}
    else
      true -> {:error, :cycle}
      _ -> {:error, :forbidden}
    end
  end

  # The ids of the users with a role on the document of `id`, inherited or not.
  defp parent_users(nil), do: []

  defp parent_users(id) do
    case access_rights(id) do
      {:ok, roles} -> Map.keys(roles)
      :error -> []
    end
  end

  @doc """
  Creates a document from the full Yjs state of its content, e.g. a file
  converted by BlockNote in the browser. The state is checked by applying it,
  and its excerpt saved along.
  """
  def import_document(user, title, snapshot) do
    doc = Yex.Doc.new()

    changeset =
      %Document{owner_id: user.id}
      |> Changeset.cast(%{title: title}, [:title])
      |> Changeset.put_change(:snapshot, snapshot)

    cond do
      not is_binary(snapshot) ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu illisible")}

      byte_size(snapshot) > @max_import_bytes ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu trop volumineux")}

      Yex.apply_update(doc, snapshot) == :ok ->
        changeset |> Changeset.put_change(:excerpt, Body.excerpt(doc)) |> Repo.insert()

      true ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu illisible")}
    end
  end

  @doc """
  Renames a document that `user` can write: owner or editor.
  `{:document_renamed, document_id, title, at}` is broadcast on
  `YPersistence.topic/1`, for the other pages showing it.
  """
  def rename_document(%Document{id: id}, user, title) do
    authorized(id, user, :write, fn document ->
      now = DateTime.utc_now()

      Repo.update_all(from(d in Document, where: d.id == ^id),
        set: [title: title, updated_at: now]
      )

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        YPersistence.topic(id),
        {:document_renamed, id, title, now}
      )

      {:ok, %{document | title: title, updated_at: now}}
    end)
  end

  @doc """
  Replaces the snapshot of a document with the full Yjs state of its content,
  and its excerpt. A document saved without title, but with text, gets a
  dated one. Without text, it stays untitled so that it is deleted when left
  (see YPersistence.unbind).

  One `UPDATE … RETURNING`: the document saved, with its `title` and
  `updated_at`.
  """
  def save_snapshot(id, snapshot, excerpt) do
    dated_title = "Notes du #{Calendar.strftime(Date.utc_today(), "%d-%m-%Y")}"

    {1, [document]} =
      Repo.update_all(
        from(d in Document,
          where: d.id == ^id,
          update: [
            set: [
              snapshot: ^snapshot,
              excerpt: ^excerpt,
              updated_at: ^DateTime.utc_now(),
              # blank: NULL, or only spaces, tabs and line breaks
              title:
                fragment(
                  "CASE WHEN coalesce(trim(?, char(32, 9, 10, 13)), '') = '' AND ? IS NOT NULL THEN ? ELSE ? END",
                  d.title,
                  ^excerpt,
                  ^dated_title,
                  d.title
                )
            ]
          ],
          select: struct(d, [:id, :title, :updated_at])
        ),
        []
      )

    document
  end

  @doc """
  Deletes the document of `id` for good, with its sub-documents (`ON DELETE
  CASCADE`).
  """
  def delete_document(id) do
    Repo.transact(fn ->
      Repo.delete_all(from d in Document, where: d.id == ^id)
      delete_unused_tags()
      {:ok, id}
    end)

    :ok
  end

  ## Trash

  @doc """
  Puts the document of `id` in the trash, with those of its sub-documents not
  there yet, if `user` can share it (its owner, maybe by inheritance). Nobody
  reads them then. `{:document_deleted, id}` is broadcast on
  `YPersistence.documents_topic/0` for each, for the pages showing them.
  """
  def trash_document(id, user) do
    now = DateTime.utc_now()

    result =
      authorized(id, user, :share, fn document ->
        ids = subtree_ids(document.id)

        {_, trashed} =
          Repo.update_all(
            from(d in Document,
              where: d.id in ^ids and is_nil(d.deleted_at),
              select: d.id
            ),
            set: [deleted_at: now, deleted_by_id: user.id]
          )

        {:ok, trashed}
      end)

    with {:ok, trashed} <- result do
      for id <- trashed do
        Phoenix.PubSub.broadcast(
          Textexp.PubSub,
          YPersistence.documents_topic(),
          {:document_deleted, id}
        )
      end

      :ok
    end
  end

  # The documents in the trash `user` can restore or delete for good: those
  # they are the owner of now, maybe by inheritance (ranks/1 ignores the
  # trash), as was needed to put them there. Not by having deleted them: they
  # may since have lost that right, e.g. the document moved away. Only those
  # deleted with none of their parents, the others going with them.
  defp trash(user) do
    from d in Document,
      as: :document,
      join: a in subquery(ranks(user)),
      on: a.id == d.id and a.rank == ^@ranks.owner,
      left_join: p in Document,
      on: p.id == d.parent_id,
      where: not is_nil(d.deleted_at) and is_nil(p.deleted_at)
  end

  @doc """
  The documents in `user`'s trash, the last deleted first: those they own now,
  maybe by inheritance.
  """
  def list_trash(user) do
    trash(user)
    |> order_by([document: d], desc: d.deleted_at)
    |> select([document: d], struct(d, @fields))
    |> Repo.all()
  end

  @doc """
  Takes the document of `id` out of `user`'s trash, with the sub-documents
  deleted along with it. `{:ok, document}`, or `{:error, :not_found}` for a
  document not in their trash.
  """
  def restore_document(id, user) do
    with {:ok, document} <- in_trash(id, user) do
      ids = subtree_ids(document.id)

      Repo.update_all(
        from(d in Document, where: d.id in ^ids and d.deleted_at == ^document.deleted_at),
        set: [deleted_at: nil, deleted_by_id: nil]
      )

      {:ok, %{document | deleted_at: nil}}
    end
  end

  @doc """
  Deletes for good the document of `id`, in `user`'s trash, with its
  sub-documents. `:ok`, or `{:error, :not_found}`.
  """
  def purge_document(id, user) do
    with {:ok, document} <- in_trash(id, user), do: delete_document(document.id)
  end

  @doc "Deletes for good the documents of `user`'s trash."
  def empty_trash(user) do
    for document <- list_trash(user), do: delete_document(document.id)
    :ok
  end

  defp in_trash(id, user) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Document{} = document <-
           trash(user)
           |> where([document: d], d.id == ^id)
           |> select([document: d], struct(d, @fields))
           |> Repo.one() do
      {:ok, document}
    else
      _ -> {:error, :not_found}
    end
  end

  ## Members

  def change_share(attrs \\ %{}), do: Membership.share_changeset(%Membership{}, attrs)

  @doc """
  Shares a document that `owner` owns with the user of `attrs`' `email`, as
  `role`; changes the role of a member. Returns the member as listed by
  `list_members/2`.
  """
  def share_document(owner, document_id, attrs) do
    changeset = change_share(attrs)

    with {:ok, %{email: email, role: role}} <- Changeset.apply_action(changeset, :insert),
         {:ok, member} <-
           authorized(document_id, owner, :share, fn document ->
             with {:ok, user} <- member_user(changeset, email, owner) do
               %Membership{document_id: document.id, user_id: user.id, role: role}
               |> Repo.insert!(
                 on_conflict: [set: [role: role]],
                 conflict_target: [:document_id, :user_id]
               )

               {:ok, Enum.find(members(document.id), &(&1.user_id == user.id))}
             end
           end) do
      broadcast_member_changed(document_id, member.user_id)
      {:ok, member}
    end
  end

  defp member_user(changeset, email, owner) do
    case Accounts.get_user_by_email(email) do
      nil -> error(changeset, "aucun compte avec cette adresse")
      %{id: id} when id == owner.id -> error(changeset, "c'est l'adresse du propriétaire")
      # Whoever registered an unconfirmed account may not own its address.
      %{confirmed_at: nil} -> error(changeset, "ce compte n'a pas encore confirmé son adresse")
      user -> {:ok, user}
    end
  end

  defp error(changeset, message),
    do: {:error, %{Changeset.add_error(changeset, :email, message) | action: :insert}}

  @doc """
  The members of a document that `owner` owns: `%{id, user_id, email, role}`;
  none for another user.
  """
  def list_members(owner, document_id) do
    case authorized(document_id, owner, :share, &{:ok, members(&1.id)}) do
      {:ok, members} -> members
      {:error, _} -> []
    end
  end

  @doc """
  The accesses the document of `document_id` inherits from its ancestors, for
  `user` who can share it: `%{user_id, email, role, from}` for each user, by
  email, with their best role on an ancestor and the nearest ancestor giving
  it, `from`, `%{id, title}`. `from` is `nil` for an ancestor `user` cannot
  read, whose title they must not see.
  """
  def list_inherited_accesses(user, document_id) do
    case authorized(document_id, user, :share, &{:ok, inherited_accesses(&1, user)}) do
      {:ok, accesses} -> accesses
      {:error, _} -> []
    end
  end

  defp inherited_accesses(%Document{parent_id: nil}, _user), do: []

  defp inherited_accesses(%Document{parent_id: parent_id} = document, user) do
    first =
      from d in Document,
        where: d.id == ^parent_id,
        select: %{id: d.id, parent_id: d.parent_id, depth: 0}

    next =
      from d in Document,
        join: c in "ancestors",
        on: d.id == c.parent_id,
        select: %{id: d.id, parent_id: d.parent_id, depth: c.depth + 1}

    ancestors =
      from(c in "ancestors", join: d in Document, as: :ancestor, on: d.id == c.id)
      |> recursive_ctes(true)
      |> with_cte("ancestors", as: ^union_all(first, ^next))

    owners =
      ancestors
      |> join(:inner, [ancestor: d], u in User, on: u.id == d.owner_id)
      |> select([c, d, u], {u.id, u.email, ^@ranks.owner, c.depth, d.id, d.title})
      |> Repo.all()

    members =
      ancestors
      |> join(:inner, [ancestor: d], m in Membership, on: m.document_id == d.id)
      |> join(:inner, [c, d, m], u in User, on: u.id == m.user_id)
      |> select(
        [c, d, m, u],
        {u.id, u.email, fragment("CASE ? WHEN 'editor' THEN 2 ELSE 1 END", m.role), c.depth, d.id,
         d.title}
      )
      |> Repo.all()

    readable = MapSet.new(list_ancestors(document, user), & &1.id)

    (owners ++ members)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {user_id, accesses} ->
      # the best role, from the nearest ancestor
      {_, email, rank, _, id, title} =
        Enum.min_by(accesses, fn {_, _, rank, depth, _, _} -> {-rank, depth} end)

      from = if MapSet.member?(readable, id), do: %{id: id, title: title}
      %{user_id: user_id, email: email, role: role(rank), from: from}
    end)
    |> Enum.sort_by(& &1.email)
  end

  defp members(document_id) do
    Repo.all(
      from m in Membership,
        join: u in assoc(m, :user),
        where: m.document_id == ^document_id,
        order_by: u.email,
        select: %{id: m.id, user_id: u.id, email: u.email, role: m.role}
    )
  end

  @doc """
  Changes the role of a member of a document that `owner` owns: `role` is
  `"editor"` or `"viewer"`. Returns the member as listed by `list_members/2`.
  """
  def change_member_role(owner, membership_id, role) do
    with {:ok, membership_id} <- Ecto.UUID.cast(membership_id),
         {:ok, role} when not is_nil(role) <-
           Ecto.Type.cast(Membership.__schema__(:type, :role), role),
         %Membership{} = membership <- Repo.get(Membership, membership_id),
         {:ok, member} <-
           authorized(membership.document_id, owner, :share, fn document ->
             membership |> Changeset.change(role: role) |> Repo.update!()
             {:ok, Enum.find(members(document.id), &(&1.id == membership.id))}
           end) do
      broadcast_member_changed(membership.document_id, membership.user_id)
      {:ok, member}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Removes a member of a document that `owner` owns."
  def remove_member(owner, membership_id) do
    with {:ok, membership_id} <- Ecto.UUID.cast(membership_id),
         %Membership{} = membership <- Repo.get(Membership, membership_id),
         {:ok, _} <-
           authorized(membership.document_id, owner, :share, fn _document ->
             {:ok, Repo.delete!(membership)}
           end) do
      broadcast_member_changed(membership.document_id, membership.user_id)
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  ## Tags

  @doc """
  The tags of the document of `id`, by label. Whether the user may read it is
  checked beforehand (see `get_document/2`).
  """
  def list_tags(document_id) do
    Repo.all(
      from t in Tag,
        join: l in TagDocument,
        on: l.tag_id == t.id,
        where: l.document_id == ^document_id
    )
    |> Tag.sort_by_label()
  end

  @doc "`documents` with their `tags`, each's by label, in two queries."
  def with_tags(documents) do
    tags =
      Repo.all(
        from t in Tag,
          join: l in TagDocument,
          on: l.tag_id == t.id,
          where: l.document_id in ^Enum.map(documents, & &1.id),
          select: {l.document_id, t}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for document <- documents,
        do: %{document | tags: Tag.sort_by_label(Map.get(tags, document.id, []))}
  end

  @doc "The tags `user` can see, by label: those of the documents they can read."
  def visible_tags(user), do: user |> visible_tags_query() |> Repo.all() |> Tag.sort_by_label()

  @doc """
  Among the tags `user` can see, those whose label contains `query`, whatever
  its case; by label, at most 8.
  """
  def search_tags(user, query) do
    user
    |> visible_tags_query()
    |> where([tag: t], fragment("instr(?, ?) > 0", t.key, ^Tag.key(String.trim(query))))
    |> limit(8)
    |> Repo.all()
    |> Tag.sort_by_label()
  end

  @doc """
  The first `limit` tags `user` can see: those they searched the most (see
  `record_tag_search/2`), then those on the most documents they can read, then
  by label.
  """
  def top_tags(user, limit) do
    readable_by(user)
    |> join(:inner, [document: d], l in TagDocument, as: :link, on: l.document_id == d.id)
    |> join(:inner, [link: l], t in Tag, as: :tag, on: t.id == l.tag_id)
    |> join(:left, [tag: t], s in TagSearch,
      as: :search,
      on: s.tag_id == t.id and s.user_id == ^user.id
    )
    |> group_by([tag: t], t.id)
    |> order_by([link: l, tag: t, search: s],
      desc: coalesce(max(s.count), 0),
      desc: count(l.document_id),
      asc: t.key
    )
    |> limit(^limit)
    |> select([tag: t], t)
    |> Repo.all()
  end

  @doc "Counts a search of the documents of `tag_id` by `user`, for `top_tags/2`."
  def record_tag_search(user, tag_id) do
    now = DateTime.utc_now()

    Repo.insert!(%TagSearch{user_id: user.id, tag_id: tag_id, searched_at: now},
      on_conflict: [inc: [count: 1], set: [searched_at: now]],
      conflict_target: [:user_id, :tag_id]
    )

    :ok
  end

  defp visible_tags_query(user) do
    readable_by(user)
    |> join(:inner, [document: d], l in TagDocument, as: :link, on: l.document_id == d.id)
    |> join(:inner, [link: l], t in Tag, as: :tag, on: t.id == l.tag_id)
    |> distinct(true)
    |> order_by([tag: t], t.key)
    |> select([tag: t], t)
  end

  @doc """
  The documents `user` can read that carry the tag of `tag_id`, last updated
  first, with their `role` on each.
  """
  def list_documents_tagged(user, tag_id) do
    readable_by(user)
    |> join(:inner, [document: d], l in TagDocument,
      on: l.document_id == d.id and l.tag_id == ^tag_id
    )
    |> order_by(desc: :updated_at)
    |> with_roles()
  end

  @doc """
  Puts the tag of `label` on a document that `user` can write, creating the tag
  if no document has it yet. `{:document_tags_changed, document_id}` is
  broadcast on `YPersistence.topic/1`.
  """
  def add_tag(document_id, user, label) do
    case Tag.normalize_label(label) do
      nil ->
        {:error, :invalid}

      label ->
        with {:ok, tag} <-
               authorized(document_id, user, :write, fn document ->
                 tag = get_or_create_tag(label)

                 Repo.insert!(%TagDocument{document_id: document.id, tag_id: tag.id},
                   on_conflict: :nothing
                 )

                 {:ok, tag}
               end) do
          broadcast_tags_changed(document_id)
          {:ok, tag}
        end
    end
  end

  # Concurrent creations of the same tag: the first one wins.
  defp get_or_create_tag(label) do
    key = Tag.key(label)

    Repo.insert!(%Tag{label: label, key: key, color: Tag.color_for(label)},
      on_conflict: :nothing,
      conflict_target: :key
    )

    Repo.get_by!(Tag, key: key)
  end

  @doc """
  Takes a tag off a document that `user` can write; the tag is deleted with its
  last document. Broadcast as `add_tag/3`.
  """
  def remove_tag(document_id, user, tag_id) do
    with {:ok, tag_id} <- Ecto.UUID.cast(tag_id),
         {:ok, _} <-
           authorized(document_id, user, :write, fn document ->
             Repo.delete_all(
               from l in TagDocument,
                 where: l.document_id == ^document.id and l.tag_id == ^tag_id
             )

             delete_unused_tags()
             {:ok, tag_id}
           end) do
      broadcast_tags_changed(document_id)
      :ok
    else
      :error -> {:error, :not_found}
      error -> error
    end
  end

  defp delete_unused_tags do
    Repo.delete_all(
      from t in Tag,
        as: :tag,
        where: not exists(from l in TagDocument, where: l.tag_id == parent_as(:tag).id)
    )
  end

  defp broadcast_tags_changed(document_id) do
    Phoenix.PubSub.broadcast(
      Textexp.PubSub,
      YPersistence.topic(document_id),
      {:document_tags_changed, document_id}
    )
  end
end
