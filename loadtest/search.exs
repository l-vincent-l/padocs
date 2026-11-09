# Search: every virtual user (VU) opens one of the documents' page as one of
# the accounts of loadtest/seed.exs, opens the search modal, which builds the
# index of all the documents the account can read (every seeded document),
# then searches a word every 3 seconds or so, for a minute, before leaving.
#
# The index is built for each user who opens the search, in native memory,
# and kept while the modal is open: the expected limits are the memory of
# the open indexes and the time to build them.
#
# Measures, besides Stampede's own (`live.page`, `live.join`, `live.event`):
#
#   * `search.first` - from typing the first word to its results, which wait
#     for the index to be built
#   * `search.query` - the same for the next words
#
# Run with loadtest/app.sh, documents filled with text to index, e.g.:
#
#   LOADTEST_USERS=20 LOADTEST_DOCUMENT_COUNT=200 LOADTEST_PARAGRAPHS=20 loadtest/app.sh
#   LOADTEST_USERS=20 LOADTEST_DOCUMENTS=<ids> mix stampede.run loadtest/search.exs
#
# Environment: LOADTEST_URL, LOADTEST_DOCUMENTS, LOADTEST_USERS (see
# loadtest/session.exs).
Code.require_file("session.exs", __DIR__)

defmodule Loadtest.Search do
  use Stampede.Scenario

  alias Loadtest.Session
  alias Stampede.LiveView

  # How long a VU keeps the search open
  @session_ms 60_000
  # Time between two searches, give or take half
  @thinking_ms 3_000
  # The search modal, the page's only LiveComponent, first rendered when it
  # opens: LiveView numbers it 1.
  @modal 1
  @words ~w(association budget réunion statuts trésorier projet école mairie
            subvention adhérent calendrier rapport bénévole dossier assoc budg)

  @impl true
  def options do
    [
      stages: [{[second: 30], 20}, {[minute: 1], 20}, {[second: 10], 0}],
      thresholds: [
        {"search.first", p95: 2_000},
        {"search.query", p95: 500},
        {"iteration.errors", count: 0}
      ]
    ]
  end

  @impl true
  def setup(_opts) do
    url = Session.url()
    documents = Session.documents()
    %{url: url, documents: documents, sessions: Session.sign_in_all(url, elem(documents, 0))}
  end

  @impl true
  def run(vu) do
    %{url: url, documents: documents, sessions: sessions} = vu.data
    session = Session.for_vu(sessions, vu.id)
    document = elem(documents, rem(vu.id - 1, tuple_size(documents)))

    {:ok, view} =
      LiveView.connect("#{url}/documents/#{document}", headers: [{"cookie", session.cookie}])

    {:ok, _reply} = LiveView.click(view, "open_search")
    search(view, "search.first")
    stop_at = now() + @session_ms
    loop(view, stop_at)
  end

  defp loop(view, stop_at) do
    if now() < stop_at do
      Process.sleep(div(@thinking_ms, 2) + :rand.uniform(@thinking_ms))
      search(view, "search.query")
      loop(view, stop_at)
    end
  end

  # Types a word, and waits for the modal to show its results.
  defp search(view, metric) do
    started_at = System.monotonic_time()
    params = %{"search" => %{"query" => Enum.random(@words)}}
    {:ok, _reply} = LiveView.change(view, "search", params, target: @modal)
    {:ok, _diff} = LiveView.await(view, match: &modal_diff?/1, timeout: 30_000)
    Stampede.record(metric, System.monotonic_time() - started_at, :native)
  end

  defp modal_diff?(diff), do: diff |> Map.get("c", %{}) |> Map.has_key?("#{@modal}")

  defp now, do: System.monotonic_time(:millisecond)
end
