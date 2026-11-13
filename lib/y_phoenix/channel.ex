defmodule YPhoenix.Channel do
  @moduledoc """
  Functions for a Phoenix channel that syncs a Yjs document with a
  `YPhoenix.DocServer`. The app's channel gives the actor joining, whose
  permission the DocServer gives (see `YPhoenix.Access`), and delegates the
  rest:

      def join("y_doc_room:" <> doc_name = topic, _payload, socket) do
        YPhoenix.Channel.join(socket, topic, doc_name, socket.assigns.current_user, @doc_server_opts)
      end

      def handle_in(event, payload, socket), do: YPhoenix.Channel.handle_in(event, payload, socket)
      def handle_info(msg, socket), do: YPhoenix.Channel.handle_info(msg, socket)

  Options: those of `YPhoenix.DocServer`, plus

    * `:supervisor` - `DynamicSupervisor` under which DocServers are started;
    * `:registry_scope` - `:syn` scope in which DocServers are registered by
      document name, so there is only one per document in the cluster;
    * `:awareness` - `false` for a client that neither receives the others'
      awareness (cursors, names) nor shares its own: it then joins a channel
      on the DocServer's `:updates_topic`, while `topic` stays the
      DocServer's own (default `true`).
  A client with the `:read` permission receives the document and its updates,
  and shares its awareness (cursor, presence), but the updates it sends are
  dropped. A client whose access is removed leaves the channel.
  """

  require Logger

  import Phoenix.Channel, only: [push: 3]
  import Phoenix.Socket, only: [assign: 2]

  alias YPhoenix.DocServer

  def join(socket, topic, doc_name, actor, opts) do
    with {:ok, docpid, permission} <- start_and_join(topic, doc_name, actor, opts) do
      uid = "#{node()}_#{System.unique_integer()}"
      Keyword.fetch!(opts, :presence).track_user(topic, uid, %{})

      {:ok,
       assign(socket,
         doc_name: doc_name,
         doc_pid: docpid,
         doc_server_opts: opts,
         doc_topic: topic,
         awareness?: Keyword.get(opts, :awareness, true),
         actor: actor,
         read_only?: permission == :read
       )}
    end
  end

  defp start_and_join(topic, doc_name, actor, opts) do
    with {:ok, docpid} <- start_doc_server(topic, doc_name, opts) do
      case DocServer.join(docpid, actor) do
        {:ok, permission} ->
          Process.monitor(docpid)
          {:ok, docpid, permission}

        {:error, :unauthorized} ->
          {:error, %{reason: "unauthorized"}}
      end
    end
  end

  def handle_in(event, {:binary, chunk}, socket) when event in ["yjs_sync", "yjs"] do
    server = socket.assigns.doc_pid

    cond do
      socket.assigns.read_only? and not read_only_message?(chunk) ->
        Logger.debug("Update of read-only client dropped for #{socket.assigns.doc_name}")

      not socket.assigns.awareness? and awareness_message?(chunk) ->
        :ok

      true ->
        DocServer.process_message_v1(server, chunk, self())
        |> handle_process_message_result(server)
    end

    {:noreply, socket}
  end

  # An awareness, or a query of the others'.
  defp awareness_message?(<<1, _::binary>>), do: true
  defp awareness_message?(<<3>>), do: true
  defp awareness_message?(_chunk), do: false

  # Whether the message leaves the document unchanged, judged on its first
  # bytes as Yex.DocServer itself dispatches them: the client's state vector
  # (step 1 of the sync), its awareness, or a query of the awareness. Anything
  # else, the client's state (step 2), an edit or an unknown message, is
  # refused.
  defp read_only_message?(<<0, 0, _::binary>>), do: true
  defp read_only_message?(<<1, _::binary>>), do: true
  defp read_only_message?(<<3>>), do: true
  defp read_only_message?(_chunk), do: false

  defp handle_process_message_result(result, server) do
    case result do
      {:ok, replies} ->
        Enum.each(replies, fn reply ->
          send(self(), {:yjs, reply, server})
        end)

        :ok

      error ->
        error
    end
  end

  def handle_info({DocServer, :permission, :none}, socket),
    do: {:stop, {:shutdown, :unauthorized}, socket}

  def handle_info({DocServer, :permission, permission}, socket),
    do: {:noreply, assign(socket, read_only?: permission == :read)}

  def handle_info({:yjs, message, _proc}, socket) do
    if socket.assigns.awareness? or not awareness_message?(message) do
      push(socket, "yjs", {:binary, message})
    end

    {:noreply, socket}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %{assigns: %{doc_pid: pid, doc_name: doc_name, doc_server_opts: opts}} = socket
      ) do
    # Only handle :DOWN for the current doc_pid. The new DocServer loads the
    # rights again, which may have changed.
    case start_and_join(socket.assigns.doc_topic, doc_name, socket.assigns.actor, opts) do
      {:ok, docpid, permission} ->
        push(socket, "yjs_resync", %{})
        {:noreply, assign(socket, doc_pid: docpid, read_only?: permission == :read)}

      {:error, %{reason: "unauthorized"}} ->
        {:stop, {:shutdown, :unauthorized}, socket}

      {:error, reason} ->
        push(socket, "yjs_server_down", %{})
        {:stop, {:error, "failed to restart shared doc: #{inspect(reason)}"}, socket}
    end
  end

  # Catch-all for unrelated :DOWNs (do nothing)
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  defp start_doc_server(topic, doc_name, opts) do
    scope = Keyword.fetch!(opts, :registry_scope)

    case :syn.lookup(scope, doc_name) do
      {pid, _metadata} ->
        {:ok, pid}

      :undefined ->
        doc_server_opts =
          [topic: topic, doc_name: doc_name] ++
            Keyword.drop(opts, [:supervisor, :registry_scope, :awareness])

        DynamicSupervisor.start_child(Keyword.fetch!(opts, :supervisor), %{
          id: DocServer,
          start:
            {DocServer, :start_link, [doc_server_opts, [name: {:via, :syn, {scope, doc_name}}]]},
          # the channel restarts the DocServer itself when it stops (see :DOWN)
          restart: :temporary
        })
    end
    |> case do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, :not_found} ->
        {:error, %{reason: "unauthorized"}}

      {:error, reason} ->
        Logger.error("""
        Failed to start shareddoc.
        Room: #{inspect(doc_name)}
        Reason: #{inspect(reason)}
        """)

        {:error, %{reason: "failed to start shareddoc"}}
    end
  end
end
