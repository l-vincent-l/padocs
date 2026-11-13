defmodule YPhoenix.DocServer do
  @moduledoc """
  Process that holds a shared Yjs document and broadcasts its updates and
  awareness to the clients subscribed to the document's topic.

  Options:

    * `:topic` - Phoenix topic on which Yjs messages are broadcast;
    * `:updates_topic` - optional topic on which only the document's updates
      are broadcast, not the awareness: for clients that must not see the
      others' (see the `:awareness` option of `YPhoenix.Channel`);
    * `:doc_name` - document identifier, passed to the persistence;
    * `:endpoint` - Phoenix endpoint used to broadcast;
    * `:persistence` - module implementing `YPhoenix.Persistence`;
    * `:access` - module implementing `YPhoenix.Access`;
    * `:presence` - module implementing `YPhoenix.Presence`;
    * `:flush_interval_ms` - interval between two saves (default 10 s);
    * `:shutdown_delay_ms` - delay before stopping once the last client has
      left (default 5 s);
    * `:awareness_throttle_ms` - window in which awareness updates are batched
      (default 50 ms).
  """
  use Yex.DocServer
  require Logger
  alias Yex.Awareness
  alias Yex.Sync

  @persistence_origin YPhoenix.Persistence.origin()
  @shutdown_delay_ms 5_000
  @awareness_throttle_ms 50
  @flush_interval_ms :timer.seconds(10)

  @doc """
  Joins the document as `actor`, for the calling process (a channel):
  `{:ok, :write | :read}` or `{:error, :unauthorized}`. The process then
  receives `{YPhoenix.DocServer, :permission, permission}` when its
  permission changes.
  """
  def join(server, actor), do: GenServer.call(server, {:join, actor})

  @impl true
  def init(option, state) do
    doc_name = Keyword.fetch!(option, :doc_name)

    case Keyword.fetch!(option, :access).init(doc_name) do
      {:ok, access_state} -> init(option, state, access_state)
      :not_found -> {:stop, :not_found}
    end
  end

  defp init(option, %{doc: doc} = state, access_state) do
    topic = Keyword.fetch!(option, :topic)
    doc_name = Keyword.fetch!(option, :doc_name)
    endpoint = Keyword.fetch!(option, :endpoint)
    persistence = Keyword.fetch!(option, :persistence)
    presence = Keyword.fetch!(option, :presence)
    access = Keyword.fetch!(option, :access)
    Logger.info("DocServer for #{doc_name} initialized.")

    # So that `terminate/2` (and thus the flush) runs when the supervisor stops
    # the DocServer, including when the application shuts down.
    Process.flag(:trap_exit, true)

    flush_interval_ms = Keyword.get(option, :flush_interval_ms, @flush_interval_ms)
    Process.send_after(self(), :flush, flush_interval_ms)

    persistance_state = persistence.bind(%{}, doc_name, doc)

    presence.subscribe(topic)

    user_count = presence.list_users(topic) |> length()

    shutdown_delay_ms = Keyword.get(option, :shutdown_delay_ms, @shutdown_delay_ms)

    # Clients are tracked once authorized (see YPhoenix.Channel): started for
    # a client then refused, the DocServer stops as if they had left.
    shutdown_timer_ref =
      if user_count <= 0, do: Process.send_after(self(), :delayed_shutdown, shutdown_delay_ms)

    {:ok,
     state
     |> assign(%{
       topic: topic,
       updates_topic: Keyword.get(option, :updates_topic),
       doc_name: doc_name,
       endpoint: endpoint,
       persistence: persistence,
       presence: presence,
       access: access,
       access_state: access_state,
       # channel pid => %{actor, permission, monitor_ref}
       clients: %{},
       origin_clients_map: %{},
       user_count: user_count,
       persistance_state: persistance_state,
       flush_interval_ms: flush_interval_ms,
       shutdown_delay_ms: shutdown_delay_ms,
       shutdown_timer_ref: shutdown_timer_ref,
       awareness_throttle_ms: Keyword.get(option, :awareness_throttle_ms, @awareness_throttle_ms),
       awareness_window_open: false,
       awareness_pending_clients: MapSet.new(),
       awareness_pending_origin: :unset,
       awareness_flush_timer_ref: nil
     })}
  end

  # Content loaded by `bind/3`: already persisted, and no client is connected
  # yet.
  @impl true
  def handle_update_v1(_doc, _update, @persistence_origin, state), do: {:noreply, state}

  def handle_update_v1(doc, update, origin, state) do
    persistance_state =
      state.assigns.persistence.update_v1(
        state.assigns.persistance_state,
        update,
        state.assigns.doc_name,
        doc
      )

    state = assign(state, :persistance_state, persistance_state)

    with {:ok, s} <- Sync.get_update(update),
         {:ok, message} <- Sync.message_encode({:sync, s}) do
      broadcast(state.assigns.endpoint, origin, state.assigns.topic, message)

      if updates_topic = state.assigns.updates_topic do
        broadcast(state.assigns.endpoint, origin, updates_topic, message)
      end
    else
      error ->
        error
    end

    {:noreply, state}
  end

  @impl true
  def handle_awareness_update(
        awareness,
        %{removed: removed, added: added, updated: updated},
        origin,
        state
      ) do
    updated_clients = MapSet.new(added ++ updated ++ removed)

    state =
      if origin do
        monitor_and_update_origin_clients_map(state, origin, added, removed)
      else
        state
      end

    if state.assigns.awareness_window_open do
      pending_clients = MapSet.union(state.assigns.awareness_pending_clients, updated_clients)
      pending_origin = merge_pending_origin(state.assigns.awareness_pending_origin, origin)

      {:noreply,
       assign(state, %{
         awareness_pending_clients: pending_clients,
         awareness_pending_origin: pending_origin
       })}
    else
      with {:ok, update} <- Awareness.encode_update(awareness, MapSet.to_list(updated_clients)),
           {:ok, message} <- Sync.message_encode({:awareness, update}) do
        broadcast(state.assigns.endpoint, origin, state.assigns.topic, message)

        ref =
          Process.send_after(
            self(),
            :flush_awareness,
            state.assigns.awareness_throttle_ms
          )

        {:noreply,
         assign(state, %{
           awareness_window_open: true,
           awareness_pending_clients: MapSet.new(),
           awareness_pending_origin: :unset,
           awareness_flush_timer_ref: ref
         })}
      else
        error ->
          Logger.log(:warning, error)
          {:noreply, state}
      end
    end
  end

  defp broadcast(endpoint, origin, topic, message) do
    if origin do
      endpoint.broadcast_from(origin, topic, "yjs", {:binary, message})
    else
      endpoint.broadcast(topic, "yjs", {:binary, message})
    end
  end

  defp monitor_and_update_origin_clients_map(state, origin, added, removed) do
    origin_clients_map = state.assigns[:origin_clients_map] || %{}
    entry = Map.get(origin_clients_map, origin)
    # Monitor if not already monitored
    ref =
      case entry do
        nil -> Process.monitor(origin)
        %{monitor_ref: r} -> r
      end

    # Update client_ids
    client_ids =
      case entry do
        nil ->
          added

        %{client_ids: prev} ->
          (added ++ prev) |> Enum.uniq() |> Enum.reject(&Enum.member?(removed, &1))
      end

    # Demonitor if no client_ids left
    origin_clients_map =
      if client_ids == [] do
        Process.demonitor(ref, [:flush])
        Map.delete(origin_clients_map, origin)
      else
        # Update map
        Map.put(origin_clients_map, origin, %{monitor_ref: ref, client_ids: client_ids})
      end

    assign(state, %{origin_clients_map: origin_clients_map})
  end

  @impl true
  def handle_call({:join, actor}, {pid, _tag}, state) do
    case state.assigns.access.permission(state.assigns.access_state, actor) do
      :none ->
        {:reply, {:error, :unauthorized}, state}

      permission ->
        ref =
          case state.assigns.clients do
            %{^pid => %{monitor_ref: ref}} -> ref
            _ -> Process.monitor(pid)
          end

        client = %{actor: actor, permission: permission, monitor_ref: ref}

        {:reply, {:ok, permission},
         assign(state, :clients, Map.put(state.assigns.clients, pid, client))}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = assign(state, :clients, Map.delete(state.assigns.clients, pid))
    origin_clients_map = state.assigns[:origin_clients_map] || %{}

    case Map.get(origin_clients_map, pid) do
      %{client_ids: ids} ->
        Awareness.remove_states(state.awareness, ids)
        origin_clients_map = Map.delete(origin_clients_map, pid)
        {:noreply, assign(state, %{origin_clients_map: origin_clients_map})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({presence, {:join, _presence}}, %{assigns: %{presence: presence}} = state) do
    state = assign(state, :user_count, state.assigns.user_count + 1)
    # Cancel shutdown timer if a user joins
    if state.assigns.shutdown_timer_ref do
      Process.cancel_timer(state.assigns.shutdown_timer_ref)
    end

    {:noreply, assign(state, :shutdown_timer_ref, nil)}
  end

  def handle_info({presence, {:leave, _presence}}, %{assigns: %{presence: presence}} = state) do
    user_count = state.assigns.user_count - 1
    state = assign(state, :user_count, user_count)

    # Cancel existing shutdown timer if present
    if state.assigns.shutdown_timer_ref do
      Process.cancel_timer(state.assigns.shutdown_timer_ref)
    end

    # Set new shutdown timer if no users remain
    state =
      if user_count <= 0 do
        ref = Process.send_after(self(), :delayed_shutdown, state.assigns.shutdown_delay_ms)
        assign(state, :shutdown_timer_ref, ref)
      else
        assign(state, :shutdown_timer_ref, nil)
      end

    {:noreply, state}
  end

  def handle_info(:flush_awareness, state) do
    pending_clients = MapSet.to_list(state.assigns.awareness_pending_clients)
    topic = state.assigns.topic
    trailing_origin = resolve_pending_origin(state.assigns.awareness_pending_origin)

    if state.assigns.awareness_flush_timer_ref do
      Process.cancel_timer(state.assigns.awareness_flush_timer_ref)
    end

    state =
      assign(state, %{
        awareness_window_open: false,
        awareness_pending_clients: MapSet.new(),
        awareness_pending_origin: :unset,
        awareness_flush_timer_ref: nil
      })

    case pending_clients do
      [] ->
        {:noreply, state}

      _ ->
        with {:ok, update} <- Awareness.encode_update(state.awareness, pending_clients),
             {:ok, message} <- Sync.message_encode({:awareness, update}) do
          broadcast(state.assigns.endpoint, trailing_origin, topic, message)
          {:noreply, state}
        else
          error ->
            Logger.log(:warning, error)
            {:noreply, state}
        end
    end
  end

  def handle_info(:flush, state) do
    persistance_state =
      state.assigns.persistence.flush(
        state.assigns.persistance_state,
        state.assigns.doc_name,
        state.doc
      )

    Process.send_after(self(), :flush, state.assigns.flush_interval_ms)
    {:noreply, assign(state, :persistance_state, persistance_state)}
  end

  def handle_info(:delayed_shutdown, state) do
    if state.assigns.user_count <= 0 do
      {:stop, :shutdown, state}
    else
      {:noreply, assign(state, :shutdown_timer_ref, nil)}
    end
  end

  def handle_info(msg, state) do
    case state.assigns.access.handle_info(msg, state.assigns.access_state) do
      {:ok, access_state} ->
        state = assign(state, :access_state, access_state)
        {:noreply, assign(state, :clients, update_permissions(state))}

      :ignore ->
        {:noreply, state}
    end
  end

  # Tells the clients whose permission changed; those who lost access are
  # forgotten, their channel leaving.
  defp update_permissions(state) do
    for {pid, client} <- state.assigns.clients,
        permission = state.assigns.access.permission(state.assigns.access_state, client.actor),
        reduce: %{} do
      clients ->
        if permission != client.permission do
          send(pid, {__MODULE__, :permission, permission})
        end

        if permission == :none do
          Process.demonitor(client.monitor_ref, [:flush])
          clients
        else
          Map.put(clients, pid, %{client | permission: permission})
        end
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.assigns.awareness_flush_timer_ref do
      Process.cancel_timer(state.assigns.awareness_flush_timer_ref)
    end

    state.assigns.persistence.unbind(
      state.assigns.persistance_state,
      state.assigns.doc_name,
      state.doc
    )

    Logger.info("DocServer for #{state.assigns.doc_name} terminated.")

    :ok
  end

  defp merge_pending_origin(:unset, origin), do: origin
  defp merge_pending_origin(:mixed, _origin), do: :mixed
  defp merge_pending_origin(origin, origin), do: origin
  defp merge_pending_origin(_origin, _other_origin), do: :mixed

  defp resolve_pending_origin(:unset), do: nil
  defp resolve_pending_origin(:mixed), do: nil
  defp resolve_pending_origin(origin), do: origin
end
