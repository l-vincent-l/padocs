defmodule TextexpWeb.SearchModal do
  @moduledoc """
  A modal searching the documents the user can read, opened from a document's
  menu, in `index`: a `Textexp.Document.SearchIndex` started by the LiveView,
  which stops it when the modal closes, freeing the index. Each search runs in
  a task, as it waits for the index while it is being built.

  Under the empty field, lists of documents, picked by buttons: the user's
  recent documents (first), their own, those shared with them, and their
  trash, where a document is restored or deleted for good. Restoring one sends
  `{:document_restored, message}` to the LiveView, whose sidebar may show it
  again, and which shows `message`.

  Under the empty field too, the user's 4 most searched tags are offered (see
  `Textexp.Document.top_tags/2`), and "…" lists all of them, by label. Under a
  query, the tags whose label contains it. One picked becomes a filter: the results are then the documents carrying it,
  those matching the query if there is one. The LiveView can open the modal
  filtered by a tag (`initial_tag`), picked on the page.

  Closing (its button, a click outside, Escape) sends `close_search` to the
  LiveView, which stops rendering it.
  """
  use TextexpWeb, :live_component

  import TextexpWeb.DocumentComponents

  alias Textexp.Document
  alias Textexp.Document.SearchIndex

  @lists [
    recent: {"Récents", "hero-clock", "Aucun document ouvert récemment"},
    own: {"Mes documents", "hero-user", "Vous n'avez pas encore de document"},
    shared: {"Partagés", "hero-users", "Aucun document partagé avec vous"},
    trash: {"Corbeille", "hero-trash", "La corbeille est vide"}
  ]

  def mount(socket) do
    {:ok,
     socket
     |> assign(
       form: to_form(%{"query" => ""}, as: "search"),
       loading?: false,
       failed?: false,
       searched?: false,
       # The tags offered: the most searched ones, all of them (all_tags?), or
       # those matching the query (at most 8, see Document.search_tags/2)
       tag_suggestions: [],
       more_tags?: false,
       all_tags?: false,
       tag: nil,
       # The list shown under the empty field (see @lists), and how many
       # documents it has
       list: :recent,
       list_count: 0,
       initialized?: false
     )
     |> stream(:results, [])}
  end

  # The first update can bring `initial_tag`, a tag picked on the page: the
  # modal opens filtered by it. Later ones bring it again, ignored.
  def update(assigns, socket) do
    {tag, assigns} = Map.pop(assigns, :initial_tag)
    socket = assign(socket, assigns)

    cond do
      socket.assigns.initialized? -> {:ok, socket}
      tag -> {:ok, socket |> assign(initialized?: true) |> put_tag(tag)}
      true -> {:ok, socket |> assign(initialized?: true) |> put_top_tags() |> put_list()}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="modal modal-open" phx-window-keydown="close_search" phx-key="Escape">
      <section
        id="search-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="search-title"
        class="modal-box flex max-h-[80dvh] w-11/12 max-w-2xl flex-col border-2 border-base-content bg-base-100 p-5 shadow-hard sm:p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <h2 id="search-title" class="text-sm uppercase">Rechercher</h2>
          <button
            id="search-close"
            type="button"
            phx-click="close_search"
            aria-label="Fermer"
            class="btn btn-ghost btn-sm btn-square -mt-1 -mr-2"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <.form
          for={@form}
          id="search-modal-form"
          phx-change="search"
          phx-submit="search"
          phx-target={@myself}
          class="mt-3"
        >
          <label class="flex items-center gap-3 border-2 border-base-content bg-base-100 px-4 py-2.5">
            <.icon name="hero-magnifying-glass" class="size-5 shrink-0 text-base-content/50" />
            <.tag_badge :if={@tag} id="search-active-tag" tag={@tag} class="shrink-0">
              <button
                id="search-clear-tag"
                type="button"
                phx-click={
                  JS.push("clear_tag", target: @myself) |> JS.focus(to: "#search-modal-query")
                }
                aria-label={"Retirer le filtre « #{@tag.label} »"}
                class="-mr-1 cursor-pointer opacity-60 transition-opacity hover:opacity-100"
              >
                <.icon name="hero-x-mark-micro" class="size-3" />
              </button>
            </.tag_badge>
            <input
              id="search-modal-query"
              name={@form[:query].name}
              type="search"
              value={@form[:query].value}
              placeholder={
                if(@tag, do: "Rechercher parmi ces documents", else: "Rechercher dans les documents")
              }
              autocomplete="off"
              phx-debounce="300"
              phx-mounted={JS.focus()}
              phx-hook="SearchNav"
              role="combobox"
              aria-expanded="true"
              aria-autocomplete="list"
              aria-controls="search-results"
              class="min-w-0 grow bg-transparent text-sm outline-none placeholder:text-base-content/50"
            />
            <span
              :if={@loading?}
              id="search-modal-loading"
              class="loading loading-spinner loading-sm text-base-content/40"
              aria-label="Recherche en cours"
            ></span>
          </label>
        </.form>
        <%!-- Picking a tag empties the field (see the SearchNav hook) --%>
        <div
          :if={@tag_suggestions != []}
          id="search-tags"
          class="mt-2 flex max-h-24 flex-wrap items-center gap-1.5 overflow-y-auto"
        >
          <span class="text-xs text-base-content/60">Tags :</span>
          <button
            :for={tag <- @tag_suggestions}
            id={"search-tag-#{tag.id}"}
            type="button"
            phx-click={
              JS.push("pick_tag", value: %{id: tag.id}, target: @myself)
              |> JS.focus(to: "#search-modal-query")
            }
            class="flex cursor-pointer"
          >
            <.tag_badge
              tag={tag}
              class="transition-[filter] hover:brightness-95 dark:hover:brightness-125"
            />
          </button>
          <button
            :if={@more_tags?}
            id="search-more-tags"
            type="button"
            phx-click={
              JS.push("show_all_tags", target: @myself) |> JS.focus(to: "#search-modal-query")
            }
            title="Tous les tags"
            aria-label="Afficher tous les tags"
            class="cursor-pointer px-1 text-xs tracking-widest text-base-content/50 transition-colors hover:text-base-content"
          >
            …
          </button>
        </div>
        <%!-- The lists of documents, under the empty field --%>
        <div
          :if={browsing?(assigns)}
          id="search-lists"
          class="mt-3 flex flex-wrap items-center gap-1.5"
        >
          <button
            :for={{name, {label, icon, _empty}} <- lists()}
            id={"search-list-#{name}"}
            type="button"
            phx-click={
              JS.push("show_list", value: %{list: name}, target: @myself)
              |> JS.focus(to: "#search-modal-query")
            }
            aria-pressed={to_string(@list == name)}
            class={[
              "flex cursor-pointer items-center gap-1.5 border-2 px-2.5 py-1 text-xs transition-colors",
              if(@list == name,
                do: "border-base-content bg-base-content text-base-100",
                else:
                  "border-base-content/30 text-base-content/70 hover:border-base-content hover:text-base-content"
              )
            ]}
          >
            <.icon name={icon} class="size-3.5" /> {label}
          </button>
          <button
            :if={@list == :trash and @list_count > 0}
            id="search-empty-trash"
            type="button"
            phx-click="empty_trash"
            phx-target={@myself}
            data-confirm="Supprimer définitivement tous les documents de la corbeille ?"
            class="ml-auto cursor-pointer text-xs text-error decoration-dotted underline-offset-2 hover:underline"
          >
            Vider la corbeille
          </button>
        </div>
        <%!-- Best match first. ↑ ↓ and Enter in the field select and open them
             (see the SearchNav hook). Its padding leaves room for the selected or
             hovered card, raised with a shadow, which it would otherwise cut. --%>
        <ul
          id="search-results"
          role="listbox"
          aria-label="Résultats"
          phx-update="stream"
          class="-mr-2 -ml-1 mt-3 flex min-h-0 flex-col gap-3 overflow-y-auto pt-1 pr-2 pb-2 pl-1"
        >
          <li
            id="search-results-empty"
            class="hidden py-6 text-center text-sm text-base-content/60 only:block"
          >
            <%= cond do %>
              <% @failed? -> %>
                La recherche n'est pas disponible
              <% @searched? -> %>
                Aucun résultat
              <% true -> %>
                {list_empty_text(@list)}
            <% end %>
          </li>
          <%= for {id, document} <- @streams.results do %>
            <%!-- In the trash, not opened: restored or deleted for good --%>
            <li :if={document.deleted_at} id={id}>
              <.trashed_card document={document} myself={@myself} />
            </li>
            <li
              :if={!document.deleted_at}
              id={id}
              role="option"
              class="[&[aria-selected=true]>a]:-translate-x-0.5 [&[aria-selected=true]>a]:-translate-y-0.5 [&[aria-selected=true]>a]:shadow-hard"
            >
              <.document_card document={document} snippet={document.snippet} />
            </li>
          <% end %>
        </ul>
        <p class="mt-3 hidden text-xs text-base-content/60 sm:block">
          ↑ ↓ pour choisir · Entrée pour ouvrir · Échap pour fermer
        </p>
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_search"
        aria-label="Fermer"
        tabindex="-1"
      ></button>
    </div>
    """
  end

  attr :document, :map, required: true
  attr :myself, :any, required: true

  defp trashed_card(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 border-2 border-dashed border-base-content/50 bg-base-100 px-5 py-3">
      <div class="min-w-0">
        <h3 class={[
          "truncate text-base font-medium",
          if(@document.title, do: "text-base-content/80", else: "text-base-content/50")
        ]}>
          {@document.title || "Sans titre"}
        </h3>
        <p class="text-xs text-base-content/60">
          Supprimé le {Calendar.strftime(@document.deleted_at, "%d/%m/%Y %H:%M")} UTC
        </p>
      </div>
      <div class="flex shrink-0 items-center gap-1">
        <button
          id={"restore-#{@document.id}"}
          type="button"
          phx-click="restore"
          phx-value-id={@document.id}
          phx-target={@myself}
          class="btn btn-sm border-base-content bg-base-100 hover:bg-primary hover:text-primary-content"
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" /> Restaurer
        </button>
        <button
          id={"purge-#{@document.id}"}
          type="button"
          phx-click="purge"
          phx-value-id={@document.id}
          phx-target={@myself}
          data-confirm={"Supprimer définitivement « #{@document.title || "Sans titre"} » et ses sous-documents ?"}
          aria-label={"Supprimer définitivement « #{@document.title || "Sans titre"} »"}
          title="Supprimer définitivement"
          class="btn btn-ghost btn-sm btn-square text-error"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
    </div>
    """
  end

  defp lists, do: @lists

  defp list_empty_text(list), do: @lists |> Keyword.fetch!(list) |> elem(2)

  # The field is empty, without tag: the lists are shown.
  defp browsing?(%{tag: tag, form: form}),
    do: is_nil(tag) and String.trim(form[:query].value || "") == ""

  def handle_event("show_list", %{"list" => list}, socket) do
    case Enum.find(Keyword.keys(@lists), &(Atom.to_string(&1) == list)) do
      nil -> {:noreply, socket}
      list -> {:noreply, socket |> assign(list: list) |> put_list()}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    case Document.restore_document(id, socket.assigns.user) do
      {:ok, document} ->
        # The LiveView shows it in its sidebar if it belongs there, and the
        # flash, which a component's would not reach
        send(self(), {:document_restored, "« #{document.title || "Sans titre"} » restauré"})
        {:noreply, put_list(socket)}

      {:error, _} ->
        {:noreply, put_list(socket)}
    end
  end

  def handle_event("purge", %{"id" => id}, socket) do
    _ = Document.purge_document(id, socket.assigns.user)
    {:noreply, put_list(socket)}
  end

  def handle_event("empty_trash", _params, socket) do
    :ok = Document.empty_trash(socket.assigns.user)
    {:noreply, put_list(socket)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply, search(socket, query)}
  end

  def handle_event("pick_tag", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.tag_suggestions, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      tag ->
        Document.record_tag_search(socket.assigns.user, tag.id)
        {:noreply, socket |> push_event("search:clear", %{}) |> put_tag(tag)}
    end
  end

  # Kept until the modal closes: an empty field then offers all the tags.
  def handle_event("show_all_tags", _params, socket) do
    {:noreply, socket |> assign(all_tags?: true) |> put_top_tags()}
  end

  def handle_event("clear_tag", _params, socket) do
    {:noreply,
     socket
     |> assign(tag: nil)
     |> search(socket.assigns.form[:query].value)}
  end

  # Filters by `tag`, the field emptied: every document carrying it. A query
  # then searches among them in the index, which does not follow the tags put
  # while the modal is open.
  defp put_tag(socket, tag) do
    documents = Document.list_documents_tagged(socket.assigns.user, tag.id)

    socket
    |> assign(
      tag: tag,
      form: to_form(%{"query" => ""}, as: "search"),
      tag_suggestions: [],
      more_tags?: false
    )
    |> show_results({:ok, documents})
  end

  # The tags offered under the empty field: the 4 most searched, "…" showing
  # whether there are others; or all of them, by label.
  defp put_top_tags(%{assigns: %{all_tags?: true}} = socket) do
    assign(socket, tag_suggestions: Document.visible_tags(socket.assigns.user), more_tags?: false)
  end

  defp put_top_tags(socket) do
    tags = Document.top_tags(socket.assigns.user, 5)
    assign(socket, tag_suggestions: Enum.take(tags, 4), more_tags?: length(tags) > 4)
  end

  # The list picked, under the empty field.
  defp put_list(socket) do
    user = socket.assigns.user

    documents =
      case socket.assigns.list do
        :recent -> Document.list_recent_documents(user)
        :own -> Document.list_own_documents(user)
        :shared -> Document.list_shared_documents(user)
        :trash -> Document.list_trash(user)
      end

    socket
    |> assign(failed?: false, searched?: false, list_count: length(documents))
    |> stream(:results, documents, reset: true)
  end

  defp search(socket, query) do
    socket = assign(socket, form: to_form(%{"query" => query}, as: "search"))
    %{user: user, tag: tag} = socket.assigns

    case String.trim(query) do
      "" when is_nil(tag) ->
        socket
        |> assign(loading?: false)
        |> put_top_tags()
        |> put_list()

      # Every document carrying the tag
      "" ->
        documents = Document.list_documents_tagged(user, tag.id)

        socket
        |> assign(tag_suggestions: [], more_tags?: false)
        |> show_results({:ok, documents})

      query ->
        index = socket.assigns.index
        tag_id = tag && tag.id

        socket
        |> assign(
          loading?: true,
          tag_suggestions: tag_suggestions(user, query, tag),
          more_tags?: false
        )
        |> start_async(:search, fn ->
          {query, SearchIndex.search(index, query, tag_id)}
        end)
    end
  end

  defp tag_suggestions(user, query, tag) do
    user
    |> Document.search_tags(query)
    |> Enum.reject(&(tag && &1.id == tag.id))
  end

  # A search replaced by another one is dropped by LiveView; one answering a
  # query since cleared, here.
  def handle_async(:search, {:ok, {query, result}}, socket) do
    if query == String.trim(socket.assigns.form[:query].value) do
      {:noreply, show_results(socket, result)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:search, {:exit, _reason}, socket),
    do: {:noreply, show_results(socket, {:error, :exit})}

  defp show_results(socket, {:ok, documents}) do
    socket
    |> assign(loading?: false, failed?: false, searched?: true)
    |> stream(:results, documents, reset: true)
  end

  defp show_results(socket, {:error, _reason}) do
    socket
    |> assign(loading?: false, failed?: true)
    |> stream(:results, [], reset: true)
  end
end
