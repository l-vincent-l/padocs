defmodule PadocsWeb.SearchModal do
  @moduledoc """
  A modal searching the documents the user can read, opened from a document's
  menu (see `Padocs.Document.Search`). Each search runs in a task, so that
  the modal stays responsive meanwhile.

  Under the empty field, the documents the user can read, the last opened
  first. On the right of the tags, two menus: one sorting the results (see
  `sorts/0`), the other filtering them by scope: the user's own documents,
  those shared with them, or their trash. A scope picked shows in the field
  like a tag, and lists its documents; a query, or a tag, then searches among
  them. In the trash, a document is
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

  # The filters: the scopes of the sidebar but the recent documents, which
  # the sort replaces
  @scope_names [:own, :shared, :trash]
  @sort_names [:relevance, :opened, :updated, :title]

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
       # The order of the results (see sorts/0)
       sort: :relevance,
       initialized?: false
     )
     |> stream(:results, [])}
  end

  # The first update can bring `initial_tag`, a tag picked on the page, or
  # `initial_scope`, e.g. :trash from a link: the modal opens filtered by it.
  # Later ones bring them again, ignored.
  def update(assigns, socket) do
    {tag, assigns} = Map.pop(assigns, :initial_tag)
    {scope, assigns} = Map.pop(assigns, :initial_scope)
    socket = assign(socket, assigns)

    cond do
      socket.assigns.initialized? ->
        {:ok, socket}

      tag ->
        {:ok, socket |> assign(initialized?: true) |> put_tag(tag)}

      scope in @scope_names ->
        {:ok, socket |> assign(initialized?: true, scope: scope) |> search("")}

      true ->
        {:ok, socket |> assign(initialized?: true) |> search("")}
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
        class="modal-box flex max-h-[85dvh] overflow-visible w-11/12 max-w-4xl flex-col border-2 border-base-content bg-base-100 p-4 shadow-hard sm:max-h-[80dvh] sm:p-6"
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
        <%!-- The tags offered, and on their right, the sort and the filter
             menus. Picking a tag empties the field (see the SearchNav hook). On
             small screens, only the first two, unless all of them were asked
             for: the others show with "…" --%>
        <div id="search-toolbar" class="mt-2 flex shrink-0 items-start gap-2">
          <div
            :if={@tag_suggestions != []}
            id="search-tags"
            class="flex max-h-24 min-w-0 flex-1 flex-wrap items-center gap-1.5 overflow-y-auto"
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
          <div class="ml-auto flex shrink-0 items-center gap-1">
            <.search_menu
              id="search-sort"
              icon="hero-arrows-up-down"
              label={gettext("Sort")}
              title={gettext("Sort: %{sort}", sort: sort_label(@sort))}
              active?={@sort != :relevance}
              other="search-filter"
            >
              <li :for={{name, label} <- sorts()}>
                <.search_menu_item
                  id={"search-sort-#{name}"}
                  menu="search-sort"
                  checked?={name == @sort}
                  event="pick_sort"
                  value={%{sort: name}}
                  target={@myself}
                >
                  {label}
                </.search_menu_item>
              </li>
            </.search_menu>
            <.search_menu
              id="search-filter"
              icon="hero-funnel"
              label={gettext("Filter")}
              title={
                if(@scope,
                  do: gettext("Filter: %{filter}", filter: scope_label(@scope)),
                  else: gettext("Filter")
                )
              }
              active?={@scope != nil}
              other="search-sort"
            >
              <li>
                <.search_menu_item
                  id="search-scope-all"
                  menu="search-filter"
                  icon="hero-document-duplicate"
                  checked?={is_nil(@scope)}
                  event="clear_scope"
                  target={@myself}
                >
                  {gettext("All the documents")}
                </.search_menu_item>
              </li>
              <li :for={{name, {label, icon, _empty}} <- filters()}>
                <.search_menu_item
                  id={"search-scope-#{name}"}
                  menu="search-filter"
                  icon={icon}
                  checked?={name == @scope}
                  event="pick_scope"
                  value={%{scope: name}}
                  target={@myself}
                >
                  {label}
                </.search_menu_item>
              </li>
            </.search_menu>
          </div>
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
                {empty_text(@scope)}
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
        <%!-- The keys, drawn as keys: not to be taken for the sort's arrows --%>
        <p
          id="search-keys"
          class="mt-3 hidden items-center gap-4 text-xs text-base-content/70 sm:flex"
        >
          <span class="flex items-center gap-1">
            <.keycap label={gettext("Up")}>↑</.keycap>
            <.keycap label={gettext("Down")}>↓</.keycap>
            {gettext("to choose")}
          </span>
          <span class="flex items-center gap-1">
            <.keycap>{gettext("Enter")}</.keycap>
             {gettext("to open")}
          </span>
          <span class="flex items-center gap-1">
            <.keycap>{gettext("Esc")}</.keycap>
             {gettext("to close")}
          </span>
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

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :title, :string, required: true
  attr :active?, :boolean, default: false
  attr :other, :string, required: true, doc: "the id of the other menu, closed on opening"
  slot :inner_block, required: true

  # A small square button opening a menu under it, on its right edge; marked
  # when its choice differs from the default.
  defp search_menu(assigns) do
    ~H"""
    <div class="relative" phx-click-away={JS.hide(to: "##{@id}-menu")}>
      <button
        id={"#{@id}-button"}
        type="button"
        aria-haspopup="menu"
        aria-controls={"#{@id}-menu"}
        aria-label={@title}
        title={@title}
        phx-click={JS.hide(to: "##{@other}-menu") |> JS.toggle(to: "##{@id}-menu")}
        class={[
          "relative flex size-7 cursor-pointer items-center justify-center border transition-colors",
          "hover:border-base-content hover:bg-base-200 hover:text-base-content",
          if(@active?,
            do: "border-base-content bg-base-200 text-base-content",
            else: "border-base-content/30 text-base-content/60"
          )
        ]}
      >
        <.icon name={@icon} class="size-4" />
        <span
          :if={@active?}
          class="absolute -top-1 -right-1 size-2 border border-base-100 bg-primary"
        ></span>
      </button>
      <div
        id={"#{@id}-menu"}
        role="menu"
        aria-label={@label}
        class="absolute top-full right-0 z-20 mt-1 hidden w-56 border-2 border-base-content bg-base-100 py-1 shadow-hard"
      >
        <p class="px-3 pt-1 pb-1.5 text-[0.6875rem] uppercase text-base-content/60">{@label}</p>
        <ul>{render_slot(@inner_block)}</ul>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :menu, :string, required: true
  attr :icon, :string, default: nil
  attr :checked?, :boolean, required: true
  attr :event, :string, required: true
  attr :value, :map, default: %{}
  attr :target, :any, required: true
  slot :inner_block, required: true

  defp search_menu_item(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="menuitemradio"
      aria-checked={to_string(@checked?)}
      phx-click={
        JS.hide(to: "##{@menu}-menu")
        |> JS.push(@event, value: @value, target: @target)
        |> JS.focus(to: "#search-modal-query")
      }
      class="flex w-full cursor-pointer items-center gap-2 px-3 py-1.5 text-left text-sm transition-colors hover:bg-base-200 aria-[checked=true]:font-medium"
    >
      <.icon :if={@icon} name={@icon} class="size-4 shrink-0" />
      {render_slot(@inner_block)}
      <.icon :if={@checked?} name="hero-check-micro" class="ml-auto size-4" />
    </button>
    """
  end

  attr :label, :string, default: nil, doc: "the key's name, for a symbol"
  slot :inner_block, required: true

  # A key of the keyboard, raised by its thicker lower edge.
  defp keycap(assigns) do
    ~H"""
    <kbd
      aria-label={@label}
      class="inline-flex h-5 min-w-5 items-center justify-center border border-b-2 border-base-content/40 bg-base-200 px-1 font-sans text-[0.625rem] leading-none text-base-content/80"
    >
      {render_slot(@inner_block)}
    </kbd>
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

  @doc """
  The scopes: their label, icon, and the text of their empty list, in the
  user's language (see PadocsWeb.Locale). The sidebar of DocumentLive lists
  them too.
  """
  def scopes do
    [
      recent: {gettext("Recent"), "hero-clock", gettext("No document opened recently")},
      own: {gettext("My documents"), "hero-user", gettext("You have no document yet")},
      shared: {gettext("Shared with me"), "hero-users", gettext("No document shared with you")},
      trash: {gettext("Trash"), "hero-trash", gettext("The trash is empty")}
    ]
  end

  # The scopes the funnel's menu filters by.
  defp filters, do: Keyword.take(scopes(), @scope_names)

  # The orders of the results. By relevance, those of a query come best match
  # first; the others, like the last opened.
  defp sorts do
    [
      relevance: gettext("Relevance"),
      opened: gettext("Last opened"),
      updated: gettext("Last modified"),
      title: gettext("Title")
    ]
  end

  defp scope_label(scope), do: scopes() |> Keyword.fetch!(scope) |> elem(0)
  defp scope_icon(scope), do: scopes() |> Keyword.fetch!(scope) |> elem(1)
  defp sort_label(sort), do: Keyword.fetch!(sorts(), sort)

  defp empty_text(nil), do: gettext("No document yet")
  defp empty_text(scope), do: scopes() |> Keyword.fetch!(scope) |> elem(2)

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

  def handle_event("pick_sort", %{"sort" => sort}, socket) do
    case Enum.find(@sort_names, &(Atom.to_string(&1) == sort)) do
      nil -> {:noreply, socket}
      sort -> {:noreply, socket |> assign(sort: sort) |> search_again()}
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
    %{user: user, tag: tag, scope: scope, sort: sort} = socket.assigns

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
          # by relevance, the last deleted first
          |> sort(user, sort, true)

        socket
        |> assign(loading?: false, trash_count: length(Document.list_trash(user)))
        |> put_top_tags()
        |> show_results({:ok, documents}, query != "" or tag != nil)

      # The documents of the scope, or all of them
      {"", nil, scope} ->
        socket
        |> assign(loading?: false)
        |> put_top_tags()
        |> show_results({:ok, user |> scope_documents(scope) |> sort(user, sort, false)}, false)

      # Every document carrying the tag, in the scope
      {"", tag, scope} ->
        documents = Document.list_documents_tagged(user, tag.id)

        socket
        |> assign(loading?: false, tag_suggestions: [], more_tags?: false)
        |> show_results({:ok, documents |> in_scope(user, scope) |> sort(user, sort, false)})

      {query, tag, scope} ->
        tag_id = tag && tag.id

        socket
        |> assign(
          loading?: true,
          tag_suggestions: tag_suggestions(user, query, tag),
          more_tags?: false
        )
        |> start_async(:search, fn ->
          documents = query |> Search.search(user, tag_id) |> in_scope(user, scope)
          {query, {:ok, sort(documents, user, sort, true)}}
        end)
    end
  end

  defp scope_documents(user, nil), do: Document.list_readable_documents(user)
  defp scope_documents(user, :own), do: Document.list_own_documents(user)
  defp scope_documents(user, :shared), do: Document.list_shared_documents(user)

  # Those of `documents` in `scope`, in their order.
  defp in_scope(documents, _user, nil), do: documents
  defp in_scope(documents, user, :own), do: Enum.filter(documents, &(&1.owner_id == user.id))
  defp in_scope(documents, user, :shared), do: Enum.reject(documents, &(&1.owner_id == user.id))

  # `documents` in the order `sort`; `ranked?`: they already are by
  # relevance, the best match (or, in the trash, the last deleted) first.
  # The documents never opened come after the others, in their order.
  defp sort(documents, _user, :relevance, true), do: documents
  defp sort(documents, user, :relevance, false), do: sort(documents, user, :opened, true)

  defp sort(documents, user, :opened, _ranked?) do
    times = Document.opened_times(user)
    {opened, never} = Enum.split_with(documents, &Map.has_key?(times, &1.id))
    Enum.sort_by(opened, &times[&1.id], {:desc, DateTime}) ++ never
  end

  defp sort(documents, _user, :updated, _ranked?),
    do: Enum.sort_by(documents, & &1.updated_at, {:desc, DateTime})

  # Whatever their case and accents, the untitled ones last
  defp sort(documents, _user, :title, _ranked?),
    do: Enum.sort_by(documents, &{is_nil(&1.title), title_key(&1.title)})

  defp title_key(nil), do: ""

  defp title_key(title),
    do: title |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "") |> String.downcase()

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
