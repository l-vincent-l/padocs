defmodule PadocsWeb.Presence do
  use Phoenix.Presence,
    otp_app: :y_phoenix,
    pubsub_server: Padocs.PubSub

  @impl Phoenix.Presence
  def init(_opts) do
    {:ok, %{}}
  end

  @impl Phoenix.Presence
  def fetch(_topic, presences) do
    for {key, %{metas: [meta | metas]}} <- presences, into: %{} do
      {key, %{metas: [meta | metas]}}
    end
  end

  @impl Phoenix.Presence
  def handle_metas(topic, %{joins: joins, leaves: leaves}, presences, state) do
    for {user_id, _presence} <- joins do
      user_data = %{id: user_id, metas: Map.fetch!(presences, user_id)}
      msg = {__MODULE__, {:join, user_data}}
      Phoenix.PubSub.local_broadcast(Padocs.PubSub, "proxy:#{topic}", msg)
    end

    for {user_id, _presence} <- leaves do
      metas =
        case Map.fetch(presences, user_id) do
          {:ok, presence_metas} -> presence_metas
          :error -> []
        end

      user_data = %{id: user_id, metas: metas}
      msg = {__MODULE__, {:leave, user_data}}
      Phoenix.PubSub.local_broadcast(Padocs.PubSub, "proxy:#{topic}", msg)
    end

    {:ok, state}
  end

  @behaviour YPhoenix.Presence

  @impl YPhoenix.Presence
  def list_users(topic), do: list(topic) |> Enum.map(fn {_id, presence} -> presence end)
  @impl YPhoenix.Presence
  def track_user(topic, name, params), do: track(self(), topic, name, params)
  def untrack_user(topic, name), do: untrack(self(), topic, name)

  @impl YPhoenix.Presence
  def subscribe(topic), do: Phoenix.PubSub.subscribe(Padocs.PubSub, "proxy:#{topic}")

  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(Padocs.PubSub, "proxy:#{topic}")
end
