defmodule TextexpWeb.DocumentLive do
  use TextexpWeb, :live_view

  import TextexpWeb.DocumentComponents, only: [tag_badge: 1]

  alias Textexp.Accounts
  alias Textexp.Document
  alias Textexp.Document.{Policy, SearchIndex, YPersistence}
  alias TextexpWeb.Presence

  on_mount {TextexpWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width sidebar>
      <link phx-track-static rel="stylesheet" href={~p"/assets/js/blocknote.css"} />
      <div class="drawer lg:drawer-open min-h-dvh">
        <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

        <div class="drawer-content flex flex-col">
          <%!-- The menu's open button (small screens only), and sharing on the right,
               above the title --%>
          <div class={[
            "flex min-h-12 items-center justify-between px-2 pt-2 lg:px-[54px] lg:pt-4",
            !@can_share? && "lg:hidden"
          ]}>
            <label
              id="sidebar-open"
              for="sidebar-drawer"
              aria-label="Ouvrir le menu"
              class="btn btn-square btn-ghost drawer-button lg:hidden"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </label>
            <button
              :if={@can_share?}
              id="share-button"
              type="button"
              phx-click="toggle_share"
              aria-expanded={to_string(@sharing?)}
              aria-controls="share-panel"
              class={[
                "btn btn-sm ml-auto border-base-content px-4",
                if(@sharing?,
                  do: "btn-primary",
                  else: "bg-base-100 hover:bg-primary hover:text-primary-content"
                )
              ]}
            >
              <.icon name="hero-user-plus" class="size-4" /> Partager
            </button>
          </div>

          <%!-- The title shares the margins of the BlockNote editor, which takes the theme's colors and font (see blocknote.css) --%>
          <div class="flex flex-1 flex-col">
            <div class="document-header px-[54px] pt-1">
              <nav
                :if={@ancestors != []}
                id="breadcrumb"
                aria-label="Documents parents"
                class="mb-1 flex flex-wrap items-center gap-1 text-xs text-base-content/60"
              >
                <%= for ancestor <- @ancestors do %>
                  <.link
                    id={"breadcrumb-#{ancestor.id}"}
                    patch={~p"/documents/#{ancestor.id}"}
                    class="max-w-48 truncate decoration-dotted underline-offset-2 hover:text-base-content hover:underline"
                  >
                    {ancestor.title || "Sans titre"}
                  </.link>
                  <.icon name="hero-chevron-right-micro" class="size-3 shrink-0" />
                <% end %>
              </nav>
              <.form
                for={@title_form}
                id="title-form"
                phx-change="update_title"
                phx-submit="update_title"
              >
                <input
                  id="document-title"
                  name="title"
                  value={@title_form[:title].value}
                  placeholder="Sans titre"
                  phx-debounce="300"
                  autocomplete="off"
                  readonly={!@can_edit?}
                  class="w-full bg-transparent text-2xl font-medium leading-tight tracking-wide outline-none placeholder:text-base-content/30 sm:text-3xl"
                />
              </.form>
              <div class="mt-1 flex items-start justify-between gap-2">
                <div class="flex min-w-0 flex-col gap-1">
                  <div class={[
                    "flex flex-wrap items-center gap-1.5",
                    (@tag_count == 0 and !@can_edit?) && "hidden"
                  ]}>
                    <.tags
                      tags={@streams.tags}
                      tag_count={@tag_count}
                      can_edit?={@can_edit?}
                      adding_tag?={@adding_tag?}
                      form={@tag_form}
                      suggestions={@tag_suggestions}
                    />
                  </div>
                  <p id="last-update" class="text-xs text-base-content/60">
                    Dernière mise à jour : {Calendar.strftime(@last_update, "%d/%m/%Y %H:%M:%S")} UTC
                  </p>
                </div>
                <%!-- People who have this document open --%>
                <ul id="viewers" class="flex -space-x-1.5" phx-update="stream">
                  <li
                    :for={{id, viewer} <- @streams.viewers}
                    id={id}
                    title={viewer.email}
                    class={[
                      "flex size-6 items-center justify-center border-2 border-base-content text-[0.625rem] font-medium uppercase",
                      "transition-transform duration-150 hover:z-10 hover:-translate-y-0.5",
                      if(viewer.id == @current_user.id,
                        do: "bg-primary text-primary-content",
                        else: "bg-base-300 text-base-content"
                      )
                    ]}
                  >
                    {String.first(to_string(viewer.email))}
                  </li>
                </ul>
              </div>
              <.live_component
                :if={@search_open?}
                module={TextexpWeb.SearchModal}
                id="search-modal"
                index={@search_index}
                user={@current_user}
                initial_tag={@search_tag}
              />
              <.share_panel
                :if={@sharing?}
                form={@share_form}
                members={@streams.members}
              />
              <hr class="mt-3 mb-1 border-t-2 border-dotted border-base-content/40" />
            </div>
            <%!-- Managed by the DocumentEditor hook: LiveView must not touch it. Its
                   id changes with the document so that LiveView replaces it, and the
                   hook mounts a new editor. The skeleton is removed and the editor
                   shown once the content is loaded. No ids inside: morphdom would
                   move the previous editor's nodes into the new element. --%>
            <div
              id={"document-editor-#{@document.id}"}
              class={["flex-1 w-full pb-16", @can_edit? && "cursor-text"]}
              phx-hook="DocumentEditor"
              phx-update="ignore"
              data-document-id={@document.id}
              data-user-id={@current_user.id}
              data-user-name={@current_user.email}
              data-editable={to_string(@can_edit?)}
            >
              <div
                data-skeleton
                role="status"
                aria-label="Chargement du document"
                class="flex flex-col gap-3 px-[54px] py-4 motion-safe:animate-pulse"
              >
                <div class="h-4 w-3/4 bg-base-300"></div>
                <div class="h-4 w-full bg-base-300"></div>
                <div class="h-4 w-5/6 bg-base-300"></div>
                <div class="h-4 w-2/5 bg-base-300"></div>
                <div class="mt-4 h-4 w-11/12 bg-base-300"></div>
                <div class="h-4 w-2/3 bg-base-300"></div>
              </div>
              <div data-editor hidden></div>
            </div>
          </div>
        </div>

        <div class="drawer-side z-20">
          <label for="sidebar-drawer" aria-label="Fermer le menu" class="drawer-overlay"></label>
          <div class="flex min-h-full w-64 flex-col border-r border-base-content/20 bg-base-100 p-4">
            <div class="mb-3 flex items-center justify-between">
              <Layouts.logo class="px-1" />
              <button
                id="search-button"
                type="button"
                phx-click="open_search"
                aria-label="Rechercher"
                title="Rechercher"
                class="btn btn-ghost btn-sm btn-square"
              >
                <.icon name="hero-magnifying-glass" class="size-5" />
              </button>
            </div>
            <div class="mb-3 flex gap-2">
              <button
                id="new-document"
                class="btn btn-sm flex-1 justify-start border-base-content bg-base-100 hover:bg-primary hover:text-primary-content"
                phx-click="new_document"
              >
                <.icon name="hero-plus" class="size-4" /> Nouveau document
              </button>
              <%!-- Each file chosen is converted in the browser and sent to the
                   server (see the DocumentImport hook) --%>
              <label
                id="import-document"
                data-import
                title="Importer des fichiers (Markdown, HTML ou texte)"
                class="group btn btn-sm btn-square border-base-content bg-base-100 hover:bg-primary hover:text-primary-content focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-base-content aria-busy:pointer-events-none"
              >
                <.icon name="hero-arrow-up-tray" class="size-4 group-aria-busy:hidden" />
                <span class="loading loading-spinner loading-xs hidden group-aria-busy:inline-block"></span>
                <span class="sr-only">Importer des fichiers (Markdown, HTML ou texte)</span>
                <input
                  id="import-files"
                  type="file"
                  multiple
                  accept=".md,.markdown,.txt,.html,.htm,text/markdown,text/plain,text/html"
                  phx-hook="DocumentImport"
                  class="sr-only"
                />
              </label>
            </div>
            <div
              :if={@list_tag}
              id="documents-filter"
              class="mb-2 flex items-center gap-1.5 px-1 text-xs text-base-content/60"
            >
              <span>Tag :</span>
              <.tag_badge id="documents-filter-tag" tag={@list_tag}>
                <button
                  id="documents-filter-clear"
                  type="button"
                  phx-click="clear_list_tag"
                  aria-label={"Retirer le filtre « #{@list_tag.label} »"}
                  class="-mr-1 cursor-pointer opacity-60 transition-opacity hover:opacity-100"
                >
                  <.icon name="hero-x-mark-micro" class="size-3" />
                </button>
              </.tag_badge>
            </div>
            <ul id="documents" class="menu w-full p-0">
              <li :if={@documents == %{}} id="documents-empty" class="px-3 py-2 text-sm opacity-60">
                Aucun document
              </li>
              <.document_items
                documents={sidebar_items(@documents, @list_tag)}
                children={if(@list_tag, do: %{}, else: children(@documents))}
                active_id={@document && @document.id}
                expanded={@expanded}
              />
            </ul>
            <Layouts.account current_user={@current_user} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :documents, :list, required: true
  attr :children, :map, required: true, doc: "the sub-documents of each document's id"
  attr :active_id, :string, required: true
  attr :expanded, :any, required: true, doc: "the ids of the documents unfolded"

  # Documents of the sidebar, each with its sub-documents under it when
  # unfolded, and for an editor a button creating one.
  defp document_items(assigns) do
    ~H"""
    <li :for={document <- @documents} id={"documents-#{document.id}"}>
      <div class={["group gap-1 py-1 pr-1 pl-1", @active_id == document.id && "menu-active"]}>
        <button
          :if={@children[document.id]}
          id={"documents-#{document.id}-toggle"}
          type="button"
          phx-click="toggle_document"
          phx-value-id={document.id}
          aria-expanded={to_string(MapSet.member?(@expanded, document.id))}
          aria-label={"Sous-documents de « #{document.title || "Sans titre"} »"}
          class="flex size-5 shrink-0 cursor-pointer items-center justify-center opacity-60 hover:opacity-100"
        >
          <.icon
            name="hero-chevron-right-micro"
            class={[
              "size-4 transition-transform duration-150",
              MapSet.member?(@expanded, document.id) && "rotate-90"
            ]}
          />
        </button>
        <span :if={!@children[document.id]} class="size-5 shrink-0"></span>
        <.link patch={~p"/documents/#{document.id}"} class="flex min-w-0 flex-1 items-center gap-2">
          <.icon name="hero-document-text" class="size-4 shrink-0" />
          <span class="truncate">{document.title || "Sans titre"}</span>
        </.link>
        <button
          :if={Policy.can?(document.role, :write)}
          id={"documents-#{document.id}-new"}
          type="button"
          phx-click="new_sub_document"
          phx-value-id={document.id}
          title="Nouveau sous-document"
          aria-label={"Nouveau sous-document de « #{document.title || "Sans titre"} »"}
          class="flex size-5 shrink-0 cursor-pointer items-center justify-center opacity-0 transition-opacity group-hover:opacity-60 hover:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:opacity-60"
        >
          <.icon name="hero-plus-micro" class="size-4" />
        </button>
      </div>
      <ul :if={@children[document.id] && MapSet.member?(@expanded, document.id)}>
        <.document_items
          documents={@children[document.id]}
          children={@children}
          active_id={@active_id}
          expanded={@expanded}
        />
      </ul>
    </li>
    """
  end

  # The documents at the sidebar's first level: those without parent, or
  # whose parent the user cannot read, last updated first. While a tag filters
  # the list, all its documents.
  defp sidebar_items(documents, list_tag) do
    documents
    |> Map.values()
    |> Enum.filter(
      &(list_tag || is_nil(&1.parent_id) || not Map.has_key?(documents, &1.parent_id))
    )
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
  end

  # The sub-documents of each document, in the order they were created.
  defp children(documents) do
    documents
    |> Map.values()
    |> Enum.filter(&(&1.parent_id && Map.has_key?(documents, &1.parent_id)))
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.group_by(& &1.parent_id)
  end

  attr :tags, :any, required: true
  attr :tag_count, :integer, required: true
  attr :can_edit?, :boolean, required: true
  attr :adding_tag?, :boolean, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :suggestions, :list, required: true

  # The tags of the document, and for an editor, the button or the field to add
  # one (Enter adds it, Escape or leaving the field cancels).
  defp tags(assigns) do
    ~H"""
    <ul id="tags" phx-update="stream" class="flex flex-wrap items-center gap-1.5">
      <li :for={{id, tag} <- @tags} id={id} class="flex">
        <.tag_badge tag={tag} class="group">
          <:label>
            <button
              type="button"
              phx-click="filter_tag"
              phx-value-id={tag.id}
              title={"Lister les documents avec le tag « #{tag.label} »"}
              class="cursor-pointer decoration-dotted underline-offset-2 hover:underline"
            >
              {tag.label}
            </button>
          </:label>
          <button
            :if={@can_edit?}
            type="button"
            phx-click="remove_tag"
            phx-value-id={tag.id}
            aria-label={"Retirer le tag « #{tag.label} »"}
            class={[
              "-mr-1 cursor-pointer opacity-0 transition-opacity group-hover:opacity-60 hover:opacity-100",
              "focus-visible:opacity-100 [@media(hover:none)]:opacity-60"
            ]}
          >
            <.icon name="hero-x-mark-micro" class="size-3" />
          </button>
        </.tag_badge>
      </li>
    </ul>
    <%= if @can_edit? do %>
      <%= if @adding_tag? do %>
        <.form
          for={@form}
          id="tag-form"
          phx-submit="add_tag"
          phx-window-keydown="close_tag_form"
          phx-key="Escape"
        >
          <input
            id="tag-label"
            name="label"
            value={@form[:label].value}
            list="tag-suggestions"
            placeholder="Nouveau tag"
            maxlength="40"
            autocomplete="off"
            phx-mounted={JS.focus()}
            phx-blur="close_tag_form"
            aria-label="Nouveau tag"
            class="h-5 w-32 border-b border-base-content/40 bg-transparent px-1 text-[0.6875rem] outline-none placeholder:text-base-content/40 focus:border-base-content"
          />
          <datalist id="tag-suggestions">
            <option :for={label <- @suggestions} value={label}></option>
          </datalist>
        </.form>
      <% else %>
        <button
          id="add-tag"
          type="button"
          phx-click="open_tag_form"
          title="Ajouter un tag"
          class={[
            "inline-flex h-5 cursor-pointer items-center gap-0.5 px-1 text-[0.6875rem] text-base-content/40",
            "transition-colors hover:text-base-content"
          ]}
        >
          <.icon name="hero-plus-micro" class="size-3.5" />
          <span :if={@tag_count == 0}>Ajouter un tag</span>
          <span :if={@tag_count > 0} class="sr-only">Ajouter un tag</span>
        </button>
      <% end %>
    <% end %>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :members, :any, required: true

  # A modal that invites an address as viewer or editor, and lists the members.
  # Closed by its button, a click outside or Escape.
  defp share_panel(assigns) do
    ~H"""
    <div id="share-modal" class="modal modal-open" phx-window-keydown="close_share" phx-key="Escape">
      <section
        id="share-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="share-title"
        phx-mounted={JS.focus(to: "#share_email")}
        class="modal-box w-11/12 max-w-2xl border-2 border-base-content bg-base-100 p-5 shadow-hard sm:p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 id="share-title" class="text-sm uppercase">Partager ce document</h2>
            <p class="mt-0.5 text-xs text-base-content/60">
              La personne doit déjà avoir un compte.
            </p>
          </div>
          <button
            id="share-close"
            type="button"
            phx-click="close_share"
            aria-label="Fermer"
            class="btn btn-ghost btn-sm btn-square -mt-1 -mr-2"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <.form
          for={@form}
          id="share-form"
          phx-submit="share"
          class="mt-3 flex flex-wrap items-start gap-2"
        >
          <div class="min-w-56 flex-1">
            <.input
              field={@form[:email]}
              type="email"
              placeholder="adresse@exemple.fr"
              autocomplete="off"
              required
            />
          </div>
          <.input
            field={@form[:role]}
            type="select"
            options={[{"Lecteur", "viewer"}, {"Éditeur", "editor"}]}
            class="select w-32"
          />
          <button
            id="share-submit"
            class="btn btn-primary"
            phx-disable-with="Invitation…"
          >
            Inviter
          </button>
        </.form>
        <ul
          id="members"
          phx-update="stream"
          class="mt-2 divide-y-2 divide-dotted divide-base-content/30"
        >
          <li id="members-empty" class="hidden py-2 text-sm text-base-content/60 only:block">
            Pas encore partagé.
          </li>
          <li
            :for={{id, member} <- @members}
            id={id}
            class="group flex items-center justify-between gap-3 py-2 text-sm"
          >
            <span class="flex min-w-0 items-center gap-2">
              <span class="flex size-7 shrink-0 items-center justify-center border-2 border-base-content bg-base-300 text-xs font-medium uppercase">
                {String.first(member.email)}
              </span>
              <span class="truncate">{member.email}</span>
            </span>
            <span class="flex shrink-0 items-center gap-1">
              <.form
                :let={f}
                for={role_form(member)}
                id={"role-#{member.id}"}
                phx-change="change_role"
                class="[&_.fieldset]:m-0 [&_.fieldset]:p-0"
              >
                <.input field={f[:membership_id]} type="hidden" />
                <.input
                  field={f[:role]}
                  type="select"
                  options={[{"Lecteur", "viewer"}, {"Éditeur", "editor"}]}
                  aria-label={"Rôle de #{member.email}"}
                  class={[
                    "select select-xs w-24 border-base-content",
                    if(member.role == :editor,
                      do: "bg-primary text-primary-content",
                      else: "bg-base-100 text-base-content"
                    )
                  ]}
                />
              </.form>
              <button
                id={"remove-#{member.id}"}
                type="button"
                phx-click="remove_member"
                phx-value-id={member.id}
                data-confirm={"Retirer l'accès de #{member.email} ?"}
                aria-label={"Retirer #{member.email}"}
                class="btn btn-ghost btn-xs btn-square opacity-60 transition-opacity hover:opacity-100"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </span>
          </li>
        </ul>
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_share"
        aria-label="Fermer"
        tabindex="-1"
      ></button>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.documents_topic())
    end

    documents = Document.list_documents(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(
       document: nil,
       can_edit?: false,
       can_share?: false,
       sharing?: false,
       search_open?: false,
       search_index: nil,
       search_tag: nil,
       share_form: nil,
       # The sidebar's documents, by id: a map rather than a stream, to show
       # them as trees (see document_items/1). The tag filtering them, if any,
       # and the documents unfolded.
       documents: Map.new(documents, &{&1.id, &1}),
       list_tag: nil,
       expanded: MapSet.new(),
       ancestors: []
     )
     |> stream(:viewers, [])
     |> stream(:members, [])}
  end

  # /documents opens the document the user opened last, else the one they
  # updated last, else a new one (deleted if left empty, see YPersistence).
  def handle_params(_params, _uri, %{assigns: %{live_action: :index}} = socket) do
    user = socket.assigns.current_user

    document =
      with nil <- Document.last_opened(user) do
        {:ok, document} = Document.create_document(user)
        document
      end

    {:noreply, push_patch(socket, to: ~p"/documents/#{document.id}", replace: true)}
  end

  # Going from one document to another is a live patch: the same process
  # leaves the previous document and opens the next one.
  def handle_params(%{"id" => id}, _uri, %{assigns: %{document: %{id: id}}} = socket),
    do: {:noreply, socket}

  def handle_params(%{"id" => id}, _uri, socket) do
    case Document.get_document(id, socket.assigns.current_user) do
      {:ok, document} ->
        {:noreply, socket |> leave_document() |> open_document(document)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Document introuvable")
         |> push_navigate(to: ~p"/documents")}
    end
  end

  defp open_document(socket, document) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.topic(document.id))
      Phoenix.PubSub.subscribe(Textexp.PubSub, Document.members_topic(document.id))

      user = socket.assigns.current_user
      Document.opened(user, document)
      Presence.subscribe(viewers_topic(document.id))
      Presence.track_user(viewers_topic(document.id), user.id, %{id: user.id, email: user.email})
    end

    # its parents, unfolded in the sidebar
    ancestors = Document.list_ancestors(document, socket.assigns.current_user)

    socket
    |> close_search()
    |> assign(
      ancestors: ancestors,
      expanded: MapSet.union(socket.assigns.expanded, MapSet.new(ancestors, & &1.id)),
      document: document,
      can_edit?: Policy.can?(document.role, :write),
      can_share?: Policy.can?(document.role, :share),
      sharing?: false,
      page_title: document.title || "Sans titre",
      last_update: document.updated_at,
      title_form: to_form(%{"title" => document.title})
    )
    |> close_tag_form()
    |> put_tags(Document.list_tags(document.id))
    |> stream(:viewers, if(connected?(socket), do: viewers(document.id), else: []), reset: true)
  end

  defp put_tags(socket, tags) do
    socket
    |> assign(tag_count: length(tags))
    |> stream(:tags, tags, reset: true)
  end

  defp close_tag_form(socket) do
    assign(socket, adding_tag?: false, tag_form: to_form(%{"label" => ""}), tag_suggestions: [])
  end

  defp open_search(socket, tag) do
    socket = close_search(socket)
    {:ok, index} = SearchIndex.start_link(socket.assigns.current_user)
    assign(socket, search_open?: true, search_index: index, search_tag: tag)
  end

  defp close_search(%{assigns: %{search_index: nil}} = socket), do: socket

  defp close_search(socket) do
    SearchIndex.stop(socket.assigns.search_index)
    assign(socket, search_open?: false, search_index: nil, search_tag: nil)
  end

  defp leave_document(%{assigns: %{document: nil}} = socket), do: socket

  defp leave_document(socket) do
    document_id = socket.assigns.document.id

    if connected?(socket) do
      Phoenix.PubSub.unsubscribe(Textexp.PubSub, YPersistence.topic(document_id))
      Phoenix.PubSub.unsubscribe(Textexp.PubSub, Document.members_topic(document_id))
      Presence.unsubscribe(viewers_topic(document_id))
      Presence.untrack_user(viewers_topic(document_id), socket.assigns.current_user.id)
    end

    socket
  end

  def handle_info({:document_updated, document_id, at, title}, socket) do
    if socket.assigns.document.id == document_id do
      {:noreply, socket |> assign(last_update: at) |> put_saved_title(title)}
    else
      {:noreply, socket}
    end
  end

  # Renamed on another page (or this one, then already shown). The input keeps
  # what this user is typing: LiveView does not patch a focused input.
  def handle_info({:document_renamed, document_id, title, at}, socket) do
    document = socket.assigns.document

    if document.id == document_id and title != document.title do
      {:noreply,
       socket |> assign(last_update: at) |> put_title(%{document | title: title, updated_at: at})}
    else
      {:noreply, socket}
    end
  end

  # Tags added or removed, on this page or another. The sidebar, filtered by
  # a tag, may then list the document or no longer.
  def handle_info({:document_tags_changed, document_id}, socket) do
    if socket.assigns.document.id == document_id do
      {:noreply,
       socket
       |> put_tags(Document.list_tags(document_id))
       |> put_list(socket.assigns.list_tag)}
    else
      {:noreply, socket}
    end
  end

  # An empty document was left and deleted (see YPersistence).
  def handle_info({:document_deleted, document_id}, socket) do
    socket = update(socket, :documents, &Map.delete(&1, document_id))

    if socket.assigns.document.id == document_id do
      {:noreply, push_navigate(socket, to: ~p"/documents")}
    else
      {:noreply, socket}
    end
  end

  # The user's role on the open document changed: the page is opened again
  # with it, the editor along (its channel already applies it, see
  # YDocRoomChannel). Without access, back to the list.
  def handle_info({:member_changed, document_id, user_id, role}, socket) do
    %{document: document, current_user: user} = socket.assigns

    cond do
      document.id != document_id or user.id != user_id ->
        {:noreply, socket}

      is_nil(role) ->
        {:noreply,
         socket
         |> put_flash(:error, "Votre accès à ce document a été retiré")
         |> push_navigate(to: ~p"/documents")}

      true ->
        {:noreply,
         socket
         |> put_flash(:info, "Vos droits sur ce document ont changé")
         |> push_navigate(to: ~p"/documents/#{document.id}")}
    end
  end

  # May still arrive for a document just left: the viewers of the open one are
  # listed again.
  def handle_info({Presence, {event, _user}}, socket) when event in [:join, :leave] do
    {:noreply, stream(socket, :viewers, viewers(socket.assigns.document.id), reset: true)}
  end

  # Shows the title given by the save to an untitled document. A title being
  # typed is kept: the saved one may predate it.
  defp put_saved_title(socket, title) do
    shown = socket.assigns.title_form[:title].value

    if (shown == nil or String.trim(shown) == "") and title != socket.assigns.document.title do
      put_title(socket, %{socket.assigns.document | title: title})
    else
      socket
    end
  end

  defp viewers_topic(document_id), do: "viewers:#{document_id}"

  # A user with several open tabs only appears once.
  defp viewers(document_id) do
    document_id
    |> viewers_topic()
    |> Presence.list_users()
    |> Enum.map(fn %{metas: [meta | _]} -> meta end)
    |> Enum.sort_by(& &1.email)
  end

  def handle_event("new_document", _params, socket) do
    {:ok, document} = Document.create_document(socket.assigns.current_user)

    {:noreply,
     socket
     |> list_new_document(%{document | role: :owner})
     |> push_patch(to: ~p"/documents/#{document.id}")}
  end

  # A file converted by the DocumentImport hook: its Yjs state, in base64.
  def handle_event("import_document", %{"name" => name, "state" => state}, socket) do
    title = name |> Path.rootname() |> String.trim()

    with {:ok, snapshot} <- Base.decode64(state),
         {:ok, document} <-
           Document.import_document(socket.assigns.current_user, title, snapshot) do
      {:reply, %{id: document.id},
       socket
       |> list_new_document(%{document | role: :owner})
       |> put_flash(:info, "« #{title} » importé")}
    else
      _ -> {:reply, %{}, put_flash(socket, :error, "Impossible d'importer « #{name} »")}
    end
  end

  def handle_event("import_failed", %{"name" => name, "reason" => reason}, socket) do
    message =
      case reason do
        "too_large" -> "« #{name} » est trop volumineux (2 Mo au plus)"
        _ -> "Impossible de lire « #{name} »"
      end

    {:reply, %{}, put_flash(socket, :error, message)}
  end

  def handle_event("resolve_users", %{"ids" => ids}, socket) do
    users =
      for user <- Accounts.list_users_by_ids(ids) do
        %{id: user.id, username: to_string(user.email), avatarUrl: ""}
      end

    {:reply, %{users: users}, socket}
  end

  # Suggests the tags of the documents the user can read, not already here.
  def handle_event("open_tag_form", _params, socket) do
    %{document: document, current_user: user} = socket.assigns
    here = MapSet.new(Document.list_tags(document.id), & &1.id)

    suggestions =
      for tag <- Document.visible_tags(user), tag.id not in here, do: tag.label

    {:noreply, assign(socket, adding_tag?: true, tag_suggestions: suggestions)}
  end

  def handle_event("close_tag_form", _params, socket), do: {:noreply, close_tag_form(socket)}

  # The list is updated by the broadcast (see handle_info/2). The field is
  # closed: LiveView would not empty it while it has the focus.
  def handle_event("add_tag", %{"label" => label}, socket) do
    %{document: document, current_user: user} = socket.assigns

    case Document.add_tag(document.id, user, label) do
      {:ok, _tag} ->
        {:noreply, close_tag_form(socket)}

      {:error, :invalid} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Vous ne pouvez pas modifier les tags de ce document")}
    end
  end

  def handle_event("remove_tag", %{"id" => tag_id}, socket) do
    %{document: document, current_user: user} = socket.assigns

    case Document.remove_tag(document.id, user, tag_id) do
      :ok ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Vous ne pouvez pas modifier les tags de ce document")}
    end
  end

  def handle_event("toggle_share", _params, %{assigns: %{sharing?: true}} = socket),
    do: {:noreply, assign(socket, sharing?: false)}

  def handle_event("close_share", _params, socket),
    do: {:noreply, assign(socket, sharing?: false)}

  # The search modal's index lives while it is open (see SearchModal). It opens
  # filtered by the tag filtering the sidebar, if any.
  def handle_event("open_search", _params, socket),
    do: {:noreply, open_search(socket, socket.assigns.list_tag)}

  # A tag of the document: the sidebar lists the documents carrying it.
  def handle_event("filter_tag", %{"id" => id}, socket) do
    case Enum.find(Document.list_tags(socket.assigns.document.id), &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      tag ->
        Document.record_tag_search(socket.assigns.current_user, tag.id)
        {:noreply, put_list(socket, tag)}
    end
  end

  def handle_event("clear_list_tag", _params, socket), do: {:noreply, put_list(socket, nil)}

  def handle_event("toggle_document", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  # Opened at once, under its parent unfolded.
  def handle_event("new_sub_document", %{"id" => parent_id}, socket) do
    case Document.create_sub_document(parent_id, socket.assigns.current_user) do
      {:ok, document} ->
        {:noreply,
         socket
         |> list_new_document(document)
         |> update(:expanded, &MapSet.put(&1, parent_id))
         |> push_patch(to: ~p"/documents/#{document.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Vous ne pouvez pas ajouter de sous-document ici")}
    end
  end

  def handle_event("close_search", _params, socket), do: {:noreply, close_search(socket)}

  def handle_event("toggle_share", _params, socket) do
    {:noreply,
     socket
     |> assign(sharing?: true, share_form: share_form())
     |> stream(:members, members(socket), reset: true)}
  end

  def handle_event("share", %{"share" => params}, socket) do
    case Document.share_document(socket.assigns.current_user, socket.assigns.document.id, params) do
      {:ok, member} ->
        {:noreply,
         socket
         |> assign(share_form: share_form())
         |> stream_insert(:members, member)
         |> put_flash(:info, "Document partagé avec #{member.email}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, share_form: to_form(changeset, as: "share"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Vous ne pouvez pas partager ce document")}
    end
  end

  def handle_event("change_role", %{"member" => %{"membership_id" => id, "role" => role}}, socket) do
    case Document.change_member_role(socket.assigns.current_user, id, role) do
      {:ok, member} ->
        {:noreply,
         socket
         |> stream_insert(:members, member)
         |> put_flash(:info, "#{member.email} est maintenant #{role_label(member.role)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Impossible de changer le rôle de ce membre")}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    case Document.remove_member(socket.assigns.current_user, id) do
      :ok -> {:noreply, stream_delete_by_dom_id(socket, :members, "members-#{id}")}
      _ -> {:noreply, put_flash(socket, :error, "Impossible de retirer ce membre")}
    end
  end

  def handle_event("update_title", %{"title" => title}, socket) do
    case Document.rename_document(socket.assigns.document, socket.assigns.current_user, title) do
      {:ok, document} ->
        {:noreply, put_title(socket, document)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Vous ne pouvez pas renommer ce document")}
    end
  end

  defp put_title(socket, document) do
    socket
    |> assign(
      document: document,
      page_title: document.title || "Sans titre",
      title_form: to_form(%{"title" => document.title})
    )
    |> list_document(document)
  end

  # The sidebar's documents: every document of the user, or those carrying `tag`.
  defp put_list(socket, tag) do
    user = socket.assigns.current_user

    documents =
      if tag,
        do: Document.list_documents_tagged(user, tag.id),
        else: Document.list_documents(user)

    assign(socket, list_tag: tag, documents: Map.new(documents, &{&1.id, &1}))
  end

  # Updates `document` in the sidebar, unless the tag filtering it leaves the
  # document out.
  defp list_document(socket, document) do
    %{documents: documents, list_tag: list_tag} = socket.assigns

    if list_tag && not Map.has_key?(documents, document.id),
      do: socket,
      else:
        assign(socket,
          documents:
            Map.update(
              documents,
              document.id,
              document,
              &%{&1 | title: document.title, updated_at: document.updated_at}
            )
        )
  end

  # A new document: shown, the filter removed if any.
  defp list_new_document(%{assigns: %{list_tag: nil}} = socket, document),
    do: update(socket, :documents, &Map.put(&1, document.id, document))

  defp list_new_document(socket, _document), do: put_list(socket, nil)

  # The form of a member's role, in their row of the share panel.
  defp role_form(member) do
    to_form(%{"membership_id" => member.id, "role" => to_string(member.role)},
      as: "member",
      id: "member-#{member.id}"
    )
  end

  defp role_label(:editor), do: "éditeur"
  defp role_label(:viewer), do: "lecteur"

  # The form inviting an address to the open document.
  defp share_form, do: to_form(Document.change_share(%{role: :viewer}), as: "share")

  # The members of the open document, by email.
  defp members(socket),
    do: Document.list_members(socket.assigns.current_user, socket.assigns.document.id)
end
