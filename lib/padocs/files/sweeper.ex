defmodule Padocs.Files.Sweeper do
  @moduledoc """
  Deletes, every `:interval_ms` (15 minutes by default), the files without
  document older than `:max_age_ms` (an hour): the images of imports that
  stopped in the browser before creating their documents (see
  `Padocs.Files.delete_pending/1`). On every node: deleting them twice is
  harmless. Without `:interval_ms` (`nil`, as in the tests), it never runs
  by itself.
  """
  use GenServer

  require Logger

  alias Padocs.Files

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Deletes them now: the number deleted."
  def sweep, do: GenServer.call(__MODULE__, :sweep)

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, :timer.minutes(15)),
      max_age_ms: Keyword.get(opts, :max_age_ms, :timer.hours(1))
    }

    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:sweep, _from, state), do: {:reply, run(state), state}

  @impl true
  def handle_info(:sweep, state) do
    run(state)
    schedule(state)
    {:noreply, state}
  end

  defp run(state) do
    before = DateTime.add(DateTime.utc_now(), -state.max_age_ms, :millisecond)
    count = Files.delete_pending(before)
    if count > 0, do: Logger.info("Deleted #{count} files of imports never done")
    count
  end

  defp schedule(%{interval_ms: nil}), do: :ok
  defp schedule(%{interval_ms: interval}), do: Process.send_after(self(), :sweep, interval)
end
