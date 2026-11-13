defmodule PadocsWeb.SearchModal do
  @moduledoc """
  A modal searching the documents the user can read, opened from a document's
  menu (see `Padocs.Document.Search`). Each search runs in a task, so that
  the modal stays responsive meanwhile.

  Under the empty field, the user's recent documents, and buttons picking a
  scope: their recent documents, their own, those shared with them, or their
  trash. Picked, it shows in the field like a tag, and lists its documents;
  a query, or a tag, then searches among them. In the trash, a document is
  restored or deleted for good; restoring one sends `{:document_restored,
  message}` to the LiveView, whose sidebar may show it again, and which shows
  `message`.

  Under the empty field too, the user's 4 most searched tags are offered (see
  `Padocs.Document.top_tags/2`), and "…" lists all of them, by label. Under a
  query, the tags whose label contains it. One picked becomes a filter: the results are then the documents carrying it,
  those matching the query if there is one. The LiveView can open the modal
  filtered by a tag (`initial_tag`), picked on the page.

  Closing (its button, a click outside, Escape) sends `close_search` to the
  LiveView, which stops rendering it.
  """
  use PadocsWeb, :live_component

  import PadocsWeb.DocumentComponents

  alias Padocs.Document
  alias Padocs.Document.Search

  @scope_names [:recent, :own, :shared, :trash]

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
       # How many tags show on small screens
       mobile_tags: 2,
       all_tags?: false,
       tag: nil,
       # The scope picked (see scopes/0), if any, and how many documents the
       # trash has, when it is the scope
       scope: nil,
       trash_count: 0,
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
      true -> {:ok, socket |> assign(initialized?: true) |> search("")}
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
        class="modal-box flex max-h-[85dvh] w-11/12 max-w-2xl flex-col border-2 border-base-content bg-base-100 p-4 shadow-hard sm:max-h-[80dvh] sm:p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <h2 id="search-title" class="text-sm uppercase">{gettext("Search")}</h2>
          <button
            id="search-close"
            type="button"
            phx-click="close_search"
            aria-label={gettext("Close")}
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
          <label class="flex items-center gap-3 border-2 border-base-content/40 bg-base-100 px-3 py-2 transition-colors focus-within:border-base-content sm:px-4 sm:py-2.5">
            <.icon name="hero-magnifying-glass" class="size-5 shrink-0 text-base-content/50" />
            <span
              :if={@scope}
              id="search-active-scope"
              class="flex shrink-0 items-center gap-1 border border-base-content/40 bg-base-200 px-1.5 py-0.5 text-[0.6875rem]"
            >
              <.icon name={scope_icon(@scope)} class="size-3" />
              {scope_label(@scope)}
              <button
                id="search-clear-scope"
                type="button"
                phx-click={
                  JS.push("clear_scope", target: @myself) |> JS.focus(to: "#search-modal-query")
                }
                aria-label={gettext("Remove “%{filter}”", filter: scope_label(@scope))}
                class="cursor-pointer opacity-60 transition-opacity hover:opacity-100"
              >
                <.icon name="hero-x-mark-micro" class="size-3" />
              </button>
            </span>
            <.tag_badge :if={@tag} id="search-active-tag" tag={@tag} class="shrink-0">
              <button
                id="search-clear-tag"
                type="button"
                phx-click={
                  JS.push("clear_tag", target: @myself) |> JS.focus(to: "#search-modal-query")
                }
                aria-label={gettext("Remove the filter “%{filter}”", filter: @tag.label)}
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
                if(@tag || @scope,
                  do: gettext("Search these documents"),
                  else: gettext("Search the documents")
                )
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
              aria-label={gettext("Searching")}
            ></span>
          </label>
        </.form>
        <%!-- Picking a tag empties the field (see the SearchNav hook). On small
             screens, only the first two, unless all of them were asked for: the
             others show with "…" --%>
        <div
          :if={@tag_suggestions != []}
          id="search-tags"
          class="mt-2 flex max-h-24 flex-wrap items-center gap-1.5 overflow-y-auto"
        >
          <span class="text-xs text-base-content/70">{gettext("Tags:")}</span>
          <button
            :for={{tag, index} <- Enum.with_index(@tag_suggestions)}
            id={"search-tag-#{tag.id}"}
            type="button"
            phx-click={
              JS.push("pick_tag", value: %{id: tag.id}, target: @myself)
              |> JS.focus(to: "#search-modal-query")
            }
            data-extra-tag={index >= @mobile_tags and !@all_tags?}
            class={[
              "flex cursor-pointer",
              (index >= @mobile_tags and !@all_tags?) && "max-sm:hidden"
            ]}
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
            title={gettext("All the tags")}
            aria-label={gettext("Show all the tags")}
            class="cursor-pointer px-1 text-xs tracking-widest text-base-content/50 transition-colors hover:text-base-content"
          >
            …
          </button>
          <%!-- Small screens: shows the tags hidden there --%>
          <button
            :if={!@more_tags? and !@all_tags? and length(@tag_suggestions) > @mobile_tags}
            id="search-more-tags-mobile"
            type="button"
            phx-click={
              JS.remove_class("max-sm:hidden", to: "#search-tags [data-extra-tag]")
              |> JS.hide()
            }
            title={gettext("All the tags")}
            aria-label={gettext("Show all the tags")}
            class="cursor-pointer px-1 text-xs tracking-widest text-base-content/50 transition-colors hover:text-base-content sm:hidden"
          >
            …
          </button>
        </div>
        <%!-- The scopes, under the empty field, before one is picked --%>
        <div
          :if={browsing?(assigns)}
          id="search-scopes"
          class="mt-3 flex flex-wrap items-center gap-1.5"
        >
          <button
            :for={{name, {label, icon, _empty}} <- scopes()}
            id={"search-scope-#{name}"}
            type="button"
            phx-click={
              JS.push("pick_scope", value: %{scope: name}, target: @myself)
              |> JS.focus(to: "#search-modal-query")
            }
            class="flex cursor-pointer items-center gap-1.5 border border-base-content/40 px-2.5 py-1 text-xs text-base-content/80 transition-colors hover:border-base-content hover:bg-base-200 hover:text-base-content"
          >
            <.icon name={icon} class="size-3.5" /> {label}
          </button>
        </div>
        <div
          :if={@scope == :trash and @trash_count > 0}
          class="mt-2 flex justify-end"
        >
          <button
            id="search-empty-trash"
            type="button"
            phx-click="empty_trash"
            phx-target={@myself}
            data-confirm={gettext("Delete for good all the documents of the trash?")}
            class="cursor-pointer text-xs text-error decoration-dotted underline-offset-2 hover:underline"
          >
            {gettext("Empty the trash")}
          </button>
        </div>
        <%!-- Best match first. ↑ ↓ and Enter in the field select and open them
             (see the SearchNav hook). Its right padding keeps the scrollbar off the
             cards. --%>
        <ul
          id="search-results"
          role="listbox"
          aria-label={gettext("Results")}
          phx-update="stream"
          class="-mr-2 mt-3 flex min-h-0 flex-col gap-2 overflow-y-auto pr-2 pb-1"
        >
          <li
            id="search-results-empty"
            class="hidden py-6 text-center text-sm text-base-content/70 only:block"
          >
            <%= cond do %>
              <% @failed? -> %>
                {gettext("The search is not available")}
              <% @searched? -> %>
                {gettext("No result")}
              <% true -> %>
                {scope_empty_text(@scope || :recent)}
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
              class="[&[aria-selected=true]>div]:border-base-content [&[aria-selected=true]>div]:bg-base-200"
            >
              <.document_card
                document={document}
                snippet={document.snippet}
                on_tag={
                  &(JS.push("filter_tag", value: %{id: &1.id}, target: @myself)
                    |> JS.focus(to: "#search-modal-query"))
                }
              />
            </li>
          <% end %>
        </ul>
        <p class="mt-3 hidden text-xs text-base-content/70 sm:block">
          {gettext("↑ ↓ to choose · Enter to open · Esc to close")}
        </p>
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_search"
        aria-label={gettext("Close")}
        tabindex="-1"
      ></button>
    </div>
    """
  end

  attr :document, :map, required: true
  attr :myself, :any, required: true

  defp trashed_card(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 border-2 border-dashed border-base-content/30 bg-base-100 px-3 py-2.5 sm:gap-4 sm:px-4 sm:py-3">
      <div class="min-w-0">
        <h3 class={[
          "line-clamp-2 text-sm font-medium sm:truncate sm:text-base",
          if(@document.title, do: "text-base-content/80", else: "text-base-content/50")
        ]}>
          {@document.title || gettext("Untitled")}
        </h3>
        <p class="text-[0.6875rem] text-base-content/70 sm:text-xs">
          {gettext("Deleted on %{at} UTC",
            at: Calendar.strftime(@document.deleted_at, gettext("%m/%d/%Y %H:%M"))
          )}
        </p>
      </div>
      <div class="flex shrink-0 items-center gap-1">
        <button
          id={"restore-#{@document.id}"}
          type="button"
          phx-click="restore"
          phx-value-id={@document.id}
          phx-target={@myself}
          aria-label={gettext("Restore “%{title}”", title: @document.title || gettext("Untitled"))}
          title={gettext("Restore")}
          class="btn btn-sm border-base-content bg-base-100 px-2 hover:bg-primary hover:text-primary-content sm:px-3"
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" />
          <span class="hidden sm:inline">{gettext("Restore")}</span>
        </button>
        <button
          id={"purge-#{@document.id}"}
          type="button"
          phx-click="purge"
          phx-value-id={@document.id}
          phx-target={@myself}
          data-confirm={
            gettext("Delete for good “%{title}” and its sub-documents?",
              title: @document.title || gettext("Untitled")
            )
          }
          aria-label={
            gettext("Delete “%{title}” for good", title: @document.title || gettext("Untitled"))
          }
          title={gettext("Delete for good")}
          class="btn btn-ghost btn-sm btn-square text-error"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
    </div>
    """
  end

  # The scopes: their label, icon, and the text of their empty list, in the
  # user's language (see PadocsWeb.Locale)
  defp scopes do
    [
      recent: {gettext("Recent"), "hero-clock", gettext("No document opened recently")},
      own: {gettext("My documents"), "hero-user", gettext("You have no document yet")},
      shared: {gettext("Shared with me"), "hero-users", gettext("No document shared with you")},
      trash: {gettext("Trash"), "hero-trash", gettext("The trash is empty")}
    ]
  end

  defp scope_label(scope), do: scopes() |> Keyword.fetch!(scope) |> elem(0)
  defp scope_icon(scope), do: scopes() |> Keyword.fetch!(scope) |> elem(1)
  defp scope_empty_text(scope), do: scopes() |> Keyword.fetch!(scope) |> elem(2)

  # Neither scope, tag nor query: the scopes are offered.
  defp browsing?(%{scope: scope, tag: tag, form: form}),
    do: is_nil(scope) and is_nil(tag) and String.trim(form[:query].value || "") == ""

  # The field emptied, like for a tag.
  def handle_event("pick_scope", %{"scope" => scope}, socket) do
    case Enum.find(@scope_names, &(Atom.to_string(&1) == scope)) do
      nil ->
        {:noreply, socket}

      scope ->
        {:noreply,
         socket
         |> assign(scope: scope)
         |> push_event("search:clear", %{})
         |> search("")}
    end
  end

  def handle_event("clear_scope", _params, socket) do
    {:noreply,
     socket
     |> assign(scope: nil)
     |> search(socket.assigns.form[:query].value)}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    case Document.restore_document(id, socket.assigns.user) do
      {:ok, document} ->
        # The LiveView shows it in its sidebar if it belongs there, and the
        # flash, which a component's would not reach
        send(
          self(),
          {:document_restored,
           gettext("“%{title}” restored", title: document.title || gettext("Untitled"))}
        )

        {:noreply, search_again(socket)}

      {:error, _} ->
        {:noreply, search_again(socket)}
    end
  end

  def handle_event("purge", %{"id" => id}, socket) do
    _ = Document.purge_document(id, socket.assigns.user)
    {:noreply, search_again(socket)}
  end

  def handle_event("empty_trash", _params, socket) do
    :ok = Document.empty_trash(socket.assigns.user)
    {:noreply, search_again(socket)}
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

  # A tag of a result: it becomes the filter, in place of the previous one.
  # Looked up among the tags the user can see, the id coming from the browser.
  def handle_event("filter_tag", %{"id" => id}, socket) do
    case Enum.find(Document.visible_tags(socket.assigns.user), &(&1.id == id)) do
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
  # then searches among them in the index, which follows the tags put a few
  # seconds later.
  defp put_tag(socket, tag), do: socket |> assign(tag: tag) |> search("")

  # The tags offered under the empty field: the 4 most searched, "…" showing
  # whether there are others; or all of them, by label.
  defp put_top_tags(%{assigns: %{all_tags?: true}} = socket) do
    assign(socket, tag_suggestions: Document.visible_tags(socket.assigns.user), more_tags?: false)
  end

  defp put_top_tags(%{assigns: %{scope: :trash}} = socket),
    do: assign(socket, tag_suggestions: [], more_tags?: false)

  defp put_top_tags(socket) do
    tags = Document.top_tags(socket.assigns.user, 5)
    assign(socket, tag_suggestions: Enum.take(tags, 4), more_tags?: length(tags) > 4)
  end

  defp search_again(socket), do: search(socket, socket.assigns.form[:query].value)

  defp search(socket, query) do
    socket = assign(socket, form: to_form(%{"query" => query}, as: "search"))
    %{user: user, tag: tag, scope: scope} = socket.assigns

    case {String.trim(query), tag, scope} do
      # In the trash, which the index does not hold: by title
      {query, _tag, :trash} ->
        documents =
          user
          |> Document.list_trash()
          |> Document.with_tags()
          |> Enum.filter(
            &((is_nil(tag) or Enum.any?(&1.tags, fn t -> t.id == tag.id end)) and
                title_matches?(&1, query))
          )

        socket
        |> assign(loading?: false, trash_count: length(Document.list_trash(user)))
        |> put_top_tags()
        |> show_results({:ok, documents}, query != "" or tag != nil)

      # The recent documents, or those of the scope
      {"", nil, scope} ->
        socket
        |> assign(loading?: false)
        |> put_top_tags()
        |> show_results({:ok, scope_documents(user, scope || :recent)}, false)

      # Every document carrying the tag, in the scope
      {"", tag, scope} ->
        documents = Document.list_documents_tagged(user, tag.id)

        socket
        |> assign(loading?: false, tag_suggestions: [], more_tags?: false)
        |> show_results({:ok, in_scope(documents, user, scope)})

      {query, tag, scope} ->
        tag_id = tag && tag.id

        socket
        |> assign(
          loading?: true,
          tag_suggestions: tag_suggestions(user, query, tag),
          more_tags?: false
        )
        |> start_async(:search, fn ->
          {query, {:ok, query |> Search.search(user, tag_id) |> in_scope(user, scope)}}
        end)
    end
  end

  defp scope_documents(user, :recent), do: Document.list_recent_documents(user)
  defp scope_documents(user, :own), do: Document.list_own_documents(user)
  defp scope_documents(user, :shared), do: Document.list_shared_documents(user)

  # Those of `documents` in `scope`, in their order.
  defp in_scope(documents, _user, nil), do: documents
  defp in_scope(documents, user, :own), do: Enum.filter(documents, &(&1.owner_id == user.id))
  defp in_scope(documents, user, :shared), do: Enum.reject(documents, &(&1.owner_id == user.id))

  defp in_scope(documents, user, :recent) do
    recent = MapSet.new(Document.list_recent_documents(user), & &1.id)
    Enum.filter(documents, &MapSet.member?(recent, &1.id))
  end

  defp title_matches?(_document, ""), do: true

  defp title_matches?(document, query),
    do: String.contains?(String.downcase(document.title || ""), String.downcase(query))

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

  # `searched?`: the results answer a query or a tag, rather than list a scope.
  defp show_results(socket, result, searched? \\ true)

  defp show_results(socket, {:ok, documents}, searched?) do
    socket
    |> assign(loading?: false, failed?: false, searched?: searched?)
    |> stream(:results, Document.with_tags(documents), reset: true)
  end

  defp show_results(socket, {:error, _reason}, _searched?) do
    socket
    |> assign(loading?: false, failed?: true)
    |> stream(:results, [], reset: true)
  end
end
