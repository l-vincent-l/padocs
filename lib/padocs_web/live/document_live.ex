defmodule PadocsWeb.DocumentLive do
  use PadocsWeb, :live_view

  import PadocsWeb.DocumentComponents, only: [tag_badge: 1]

  alias Padocs.Accounts
  alias Padocs.Document
  alias Padocs.Files
  alias Padocs.Document.{Archive, Policy, YPersistence}
  alias PadocsWeb.Presence

  on_mount {PadocsWeb.LiveUserAuth, :live_user_required}

  # How many documents the menu lists among those opened last
  @recent 15

  # The entries of an archive read at most, beyond its documents and images
  @max_archive_entries 20_000

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width sidebar>
      <link phx-track-static rel="stylesheet" href={~p"/assets/js/blocknote.css"} />
      <%!-- On large screens, the menu folds and is resized (see the Sidebar
           hook): its width is --sidebar-width --%>
      <div
        id="app-drawer"
        phx-hook=".Sidebar"
        class="group/drawer drawer lg:drawer-open min-h-dvh [--sidebar-width:16rem]"
      >
        <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

        <%!-- Room for the history panel, on large screens --%>
        <%!-- With the sub-documents shown on the page, the document keeps
             the place it has without them, the column taking its left
             margin; when the margin is narrower than the column, the
             document moves just beside it (100cqw: the width of this
             element, the column's included) --%>
        <div class={[
          "@container drawer-content flex flex-col transition-[padding] duration-200 ease-out lg:flex-row",
          if(@history_open?,
            do: "lg:pr-80",
            else:
              "lg:group-data-[tree-pinned]/drawer:[--reading-margin:max(0px,calc((100cqw_-_var(--reading-width))_/_2_-_16rem))]"
          )
        ]}>
          <div class="flex min-w-0 flex-1 flex-col">
            <%!-- The menu's open button (small screens only), the breadcrumb
               of the open document, and its actions on the right, above the
               title. It stays at the top of the screen, on a blur that fades
               out downwards: the document scrolled under it shows blurred
               there. --%>
            <div class="sticky top-0 z-10 flex h-14 items-center justify-between gap-2 px-2 pt-2 lg:h-16 lg:px-[54px] lg:pt-4">
              <div
                aria-hidden="true"
                class="pointer-events-none absolute inset-x-0 top-0 -bottom-6 -z-10 bg-base-100/70 backdrop-blur-md [mask-image:linear-gradient(to_bottom,black_55%,transparent)]"
              >
              </div>
              <%!-- On large screens, close to the menu's edge --%>
              <div class="flex min-w-0 flex-1 items-center gap-1 lg:-ml-[46px]">
                <label
                  id="sidebar-open"
                  for="sidebar-drawer"
                  aria-label={gettext("Open the menu")}
                  class="btn btn-square btn-ghost drawer-button shrink-0 lg:hidden"
                >
                  <.icon name="hero-bars-3" class="size-5" />
                </label>
                <.breadcrumb
                  :if={@document}
                  document={@document}
                  ancestors={@ancestors}
                  documents={@documents}
                  can_edit?={@can_edit?}
                  history_open?={@history_open?}
                />
              </div>
              <.document_actions :if={@document} document={@document} can_share?={@can_share?} />
            </div>

            <%!-- The title shares the margins of the BlockNote editor, which takes the theme's colors and font (see blocknote.css) --%>
            <div class="flex flex-1 flex-col">
              <div class="document-header mr-auto ml-(--reading-margin) w-full max-w-(--reading-width) px-[54px] pt-1">
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
                    placeholder={gettext("Untitled")}
                    phx-debounce="300"
                    autocomplete="off"
                    readonly={!@can_edit?}
                    class="w-full bg-transparent text-(--color-document) text-3xl font-medium leading-tight tracking-wide outline-none placeholder:text-base-content/30 sm:text-4xl"
                  />
                </.form>
                <%!-- Under the title, on one line: its tags, its last update, and
                   the people who have it open --%>
                <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1.5">
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
                  <p id="last-update" class="text-xs text-base-content/70">
                    {gettext("Last update: %{at} UTC",
                      at: Calendar.strftime(@last_update, gettext("%m/%d/%Y %H:%M:%S"))
                    )}
                  </p>
                  <%!-- People who have this document open --%>
                  <ul id="viewers" class="ml-auto flex -space-x-1.5" phx-update="stream">
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
                  module={PadocsWeb.SearchModal}
                  id="search-modal"
                  user={@current_user}
                  initial_tag={@search_tag}
                  initial_scope={@search_scope}
                />
                <.move_panel
                  :if={@moving?}
                  document={@document}
                  destinations={@move_destinations}
                  can_move_to_root?={
                    @document.parent_id != nil and @document.owner_id == @current_user.id
                  }
                />
                <.share_panel
                  :if={@sharing?}
                  form={@share_form}
                  members={@streams.members}
                  inherited={@inherited_accesses}
                  current_user_id={@current_user.id}
                  public_token={@public_token}
                />
                <.history_panel :if={@history_open?} versions={@streams.versions} />
                <hr class="mt-3 mb-1 border-t-2 border-dotted border-base-content/40" />
              </div>
              <.version_banner
                :if={@viewed_version}
                version={@viewed_version}
                can_edit?={@can_edit?}
              />
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
                data-report-empty
              >
                <div
                  data-skeleton
                  role="status"
                  aria-label={gettext("Loading the document")}
                  class="mr-auto ml-(--reading-margin) flex w-full max-w-(--reading-width) flex-col gap-3 px-[54px] py-4 motion-safe:animate-pulse"
                >
                  <div class="h-4 w-3/4 bg-base-300"></div>
                  <div class="h-4 w-full bg-base-300"></div>
                  <div class="h-4 w-5/6 bg-base-300"></div>
                  <div class="h-4 w-2/5 bg-base-300"></div>
                  <div class="mt-4 h-4 w-11/12 bg-base-300"></div>
                  <div class="h-4 w-2/3 bg-base-300"></div>
                </div>
                <div data-editor hidden></div>
                <%!-- State of the sync with the server, set by the editor in
                     data-state: hidden while all is well, shown when the
                     connection is lost or the document's server does not
                     answer, then briefly once synced again (see
                     assets/js/blocknote/sync_status.ts). --%>
                <div
                  data-sync-status
                  data-state="hidden"
                  role="status"
                  aria-live="polite"
                  class={[
                    "group pointer-events-none fixed bottom-5 left-1/2 z-30 -translate-x-1/2",
                    "flex max-w-[calc(100vw-2rem)] items-center gap-2 border-2 border-base-content px-3 py-1.5",
                    "text-sm font-medium shadow-[3px_3px_0_0_var(--color-base-content)]",
                    "bg-base-100 text-base-content transition duration-300 ease-out",
                    "data-[state=hidden]:translate-y-3 data-[state=hidden]:opacity-0",
                    "data-[state=offline]:bg-warning data-[state=offline]:text-warning-content",
                    "data-[state=server_down]:bg-error data-[state=server_down]:text-error-content",
                    "data-[state=synced]:bg-success data-[state=synced]:text-success-content"
                  ]}
                >
                  <span class="hidden items-center gap-2 group-data-[state=offline]:inline-flex">
                    <.icon name="hero-signal-slash" class="size-4 shrink-0" />
                    {gettext("Offline — your edits are kept on this device")}
                  </span>
                  <span class="hidden items-center gap-2 group-data-[state=syncing]:inline-flex">
                    <.icon name="hero-arrow-path" class="size-4 shrink-0 motion-safe:animate-spin" />
                    {gettext("Syncing…")}
                  </span>
                  <span class="hidden items-center gap-2 group-data-[state=server_down]:inline-flex">
                    <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
                    {gettext("The server does not answer, trying again soon")}
                  </span>
                  <span class="hidden items-center gap-2 group-data-[state=synced]:inline-flex">
                    <.icon name="hero-check" class="size-4 shrink-0" /> {gettext("Synced")}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <%!-- The tree of the open document, from its highest parent,
               shown on the page from the breadcrumb's menus: a column beside
               the menu (on top of the page on small screens), hidden while
               the history is open. See the SubDocuments hook. --%>
          <aside
            id="tree-panel"
            phx-hook=".SubDocuments"
            aria-labelledby="tree-title"
            class={[
              "hidden flex-col border-b border-base-content/20 px-4 py-4",
              !@history_open? &&
                [
                  "group-data-[tree-pinned]/drawer:order-first group-data-[tree-pinned]/drawer:flex",
                  "lg:sticky lg:top-0 lg:h-dvh lg:w-64 lg:shrink-0 lg:overflow-y-auto lg:border-b-0 lg:pt-6"
                ]
            ]}
          >
            <h2 id="tree-title" class="mb-2 px-1 text-xs uppercase text-base-content/70">
              {gettext("Sub-documents")}
            </h2>
            <.document_tree
              document={@document}
              ancestors={@ancestors}
              documents={@documents}
              expanded={@expanded}
              user_id={@current_user.id}
              active_empty?={@body_empty?}
              deleting={@deleting}
            />
            <button
              id="tree-unpin"
              type="button"
              data-tree-pin
              class="mt-3 flex items-center gap-1.5 self-start px-1 text-xs text-base-content/70 hover:text-base-content hover:underline"
            >
              <.icon name="hero-arrow-right-start-on-rectangle-micro" class="size-4" />
              {gettext("Remove from the page")}
            </button>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".SubDocuments">
              // Shows the tree of sub-documents on the page, or not, from the
              // [data-tree-pin] buttons (the breadcrumb's menus, the column's
              // own), the choice being kept in this browser. The state is an
              // attribute of #app-drawer, set through this.js() so that
              // LiveView's patches keep it.
              const KEY = "padocs:sub-documents"

              export default {
                mounted() {
                  this.drawer = document.getElementById("app-drawer")
                  this.pinned = this.load()
                  this.apply()
                  this.onClick = e => {
                    if (!e.target.closest("[data-tree-pin]")) return
                    e.target.closest("[popover]")?.hidePopover()
                    this.pinned = !this.pinned
                    this.apply()
                    this.save()
                  }
                  document.addEventListener("click", this.onClick)
                },
                destroyed() {
                  document.removeEventListener("click", this.onClick)
                },
                apply() {
                  if (this.pinned) this.js().setAttribute(this.drawer, "data-tree-pinned", "")
                  else this.js().removeAttribute(this.drawer, "data-tree-pinned")
                },
                load() {
                  try {
                    return localStorage.getItem(KEY) === "pinned"
                  } catch {
                    return false
                  }
                },
                save() {
                  try {
                    if (this.pinned) localStorage.setItem(KEY, "pinned")
                    else localStorage.removeItem(KEY)
                  } catch {}
                }
              }
            </script>
          </aside>
        </div>

        <div class="drawer-side z-20">
          <label for="sidebar-drawer" aria-label={gettext("Close the menu")} class="drawer-overlay"></label>
          <div
            id="sidebar"
            class={[
              "relative flex min-h-full w-64 flex-col border-r border-base-content/20 bg-base-100 p-4 lg:w-(--sidebar-width)",
              "lg:group-data-[ready]/drawer:transition-[margin-left,visibility] lg:duration-200 lg:ease-out",
              "lg:group-data-[resizing]/drawer:transition-none",
              "lg:group-data-[collapsed]/drawer:invisible lg:group-data-[collapsed]/drawer:-ml-(--sidebar-width)"
            ]}
          >
            <div class="mb-3 flex items-center justify-between">
              <Layouts.logo class="px-1" />
              <button
                id="search-button"
                type="button"
                phx-click="open_search"
                aria-label={gettext("Search")}
                title={gettext("Search")}
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
                <.icon name="hero-plus" class="size-4" /> {gettext("New document")}
              </button>
              <%!-- Each file chosen is converted in the browser and sent to the
                   server (see the DocumentImport hook) --%>
              <label
                id="import-document"
                data-import
                title={gettext("Import files (Markdown, HTML, text, Word or a zip of them)")}
                class="group btn btn-sm btn-square border-base-content bg-base-100 hover:bg-primary hover:text-primary-content focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-base-content aria-busy:pointer-events-none"
              >
                <.icon name="hero-arrow-up-tray" class="size-4 group-aria-busy:hidden" />
                <span class="loading loading-spinner loading-xs hidden group-aria-busy:inline-block"></span>
                <span class="sr-only">{gettext(
                  "Import files (Markdown, HTML, text, Word or a zip of them)"
                )}</span>
                <input
                  id="import-files"
                  type="file"
                  multiple
                  accept=".md,.markdown,.txt,.html,.htm,.docx,.zip,application/zip,text/markdown,text/plain,text/html,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                  phx-hook="DocumentImport"
                  class="sr-only"
                />
              </label>
            </div>
            <%!-- The documents of the scope picked above them: those the user
                 opened last (the last first), their own, those shared with
                 them (the last updated first), or their trash (the last
                 deleted first), where they are restored --%>
            <nav
              id="sidebar-list"
              aria-labelledby="sidebar-scope-button"
              class="min-h-0 min-w-0 flex-1"
            >
              <div class="relative mb-2" phx-click-away={JS.hide(to: "#sidebar-scopes")}>
                <button
                  id="sidebar-scope-button"
                  type="button"
                  aria-haspopup="true"
                  aria-controls="sidebar-scopes"
                  phx-click={JS.toggle(to: "#sidebar-scopes")}
                  class="flex cursor-pointer items-center gap-1 px-1 text-xs uppercase text-base-content/70 transition-colors hover:text-base-content"
                >
                  {scope_label(@sidebar_scope)}
                  <.icon name="hero-chevron-down-micro" class="size-4" />
                </button>
                <ul
                  id="sidebar-scopes"
                  phx-window-keydown={JS.hide(to: "#sidebar-scopes")}
                  phx-key="Escape"
                  class="absolute top-full left-0 z-20 mt-1 hidden w-52 border-2 border-base-content bg-base-100 py-1 shadow-hard"
                >
                  <li :for={{name, {label, icon, _empty}} <- PadocsWeb.SearchModal.scopes()}>
                    <button
                      id={"sidebar-scope-#{name}"}
                      type="button"
                      phx-click={
                        JS.hide(to: "#sidebar-scopes")
                        |> JS.push("pick_sidebar_scope", value: %{scope: name})
                      }
                      aria-current={to_string(name == @sidebar_scope)}
                      class="flex w-full cursor-pointer items-center gap-2 px-3 py-1.5 text-left text-sm hover:bg-base-200 aria-[current=true]:font-medium"
                    >
                      <.icon name={icon} class="size-4 shrink-0" /> {label}
                      <.icon
                        :if={name == @sidebar_scope}
                        name="hero-check-micro"
                        class="ml-auto size-4"
                      />
                    </button>
                  </li>
                </ul>
              </div>
              <ul id="sidebar-documents" class="menu w-full p-0">
                <li class="hidden px-1 py-1 text-xs text-base-content/60 only:block">
                  {scope_empty_text(@sidebar_scope)}
                </li>
                <li
                  :for={document <- sidebar_documents(assigns)}
                  id={"sidebar-#{document.id}"}
                  class="w-full min-w-0"
                >
                  <.link
                    :if={@sidebar_scope != :trash}
                    patch={~p"/documents/#{document.id}"}
                    class={[
                      "group flex w-full min-w-0 items-center gap-2 py-1 pl-1",
                      @document && @document.id == document.id && "menu-active"
                    ]}
                  >
                    <.icon name="hero-document-text" class="size-4 shrink-0" />
                    <span class="min-w-0 flex-1 truncate group-hover:whitespace-normal group-hover:[overflow-wrap:anywhere] group-focus-visible:whitespace-normal group-focus-visible:[overflow-wrap:anywhere]">
                      {document.title || gettext("Untitled")}
                    </span>
                  </.link>
                  <div
                    :if={@sidebar_scope == :trash}
                    class="group flex w-full min-w-0 items-center gap-2 py-1 pr-1 pl-1 text-base-content/70 hover:bg-transparent"
                  >
                    <.icon name="hero-document-text" class="size-4 shrink-0" />
                    <span class="min-w-0 flex-1 truncate group-hover:whitespace-normal group-hover:[overflow-wrap:anywhere]">
                      {document.title || gettext("Untitled")}
                    </span>
                    <button
                      id={"sidebar-restore-#{document.id}"}
                      type="button"
                      phx-click="restore_document"
                      phx-value-id={document.id}
                      title={gettext("Restore")}
                      aria-label={
                        gettext("Restore “%{title}”", title: document.title || gettext("Untitled"))
                      }
                      class="flex size-5 shrink-0 cursor-pointer items-center justify-center opacity-60 hover:opacity-100"
                    >
                      <.icon name="hero-arrow-uturn-left-micro" class="size-4" />
                    </button>
                  </div>
                </li>
              </ul>
              <%!-- Deleting for good is done in the search's trash --%>
              <.link
                :if={@sidebar_scope == :trash and @document}
                id="sidebar-open-trash"
                patch={~p"/documents/#{@document.id}?search=trash"}
                class="mt-2 block px-1 text-xs text-base-content/70 decoration-dotted underline-offset-2 hover:text-base-content hover:underline"
              >
                {gettext("Manage the trash")}
              </.link>
            </nav>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".Sidebar">
              // Folds the menu (its buttons, or Ctrl+\) and resizes it (its
              // handle, dragged or moved with the arrows), on large screens. The
              // choice is kept in this browser. The attributes it sets go through
              // this.js(), so that LiveView's patches keep them.
              const KEY = "padocs:sidebar"
              const MIN = 192
              const MAX = 480
              const DEFAULT = 256

              export default {
                mounted() {
                  const saved = this.load()
                  this.width = this.clamp(Number(saved.width) || DEFAULT)
                  this.collapsed = saved.collapsed === true
                  this.handle = this.el.querySelector("[data-sidebar-resize]")
                  this.apply()
                  // Not animated before: the menu opens as it was left
                  requestAnimationFrame(() => this.js().setAttribute(this.el, "data-ready", ""))

                  this.el.addEventListener("click", e => {
                    if (e.target.closest("[data-sidebar-toggle]")) this.toggle(true)
                  })
                  this.onKey = e => {
                    if ((e.ctrlKey || e.metaKey) && e.key === "\\") {
                      e.preventDefault()
                      this.toggle(false)
                    }
                  }
                  window.addEventListener("keydown", this.onKey)

                  this.handle.addEventListener("pointerdown", e => this.resize(e))
                  this.handle.addEventListener("dblclick", () => this.setWidth(DEFAULT))
                  this.handle.addEventListener("keydown", e => {
                    const step = e.shiftKey ? 64 : 16
                    const width = {
                      ArrowLeft: this.width - step,
                      ArrowRight: this.width + step,
                      Home: MIN,
                      End: MAX
                    }[e.key]
                    if (width === undefined) return
                    e.preventDefault()
                    this.setWidth(width)
                  })
                },
                destroyed() {
                  window.removeEventListener("keydown", this.onKey)
                },
                // Follows the pointer until released; the width is kept then.
                resize(e) {
                  if (e.button !== 0) return
                  e.preventDefault()
                  const {clientX: startX, pointerId} = e
                  const startWidth = this.width
                  this.handle.setPointerCapture(pointerId)
                  this.js().setAttribute(this.el, "data-resizing", "")
                  const move = e => {
                    this.width = this.clamp(startWidth + e.clientX - startX)
                    this.apply()
                  }
                  const end = () => {
                    this.handle.removeEventListener("pointermove", move)
                    this.handle.removeEventListener("pointerup", end)
                    this.handle.removeEventListener("pointercancel", end)
                    this.js().removeAttribute(this.el, "data-resizing")
                    this.save()
                  }
                  this.handle.addEventListener("pointermove", move)
                  this.handle.addEventListener("pointerup", end)
                  this.handle.addEventListener("pointercancel", end)
                },
                setWidth(width) {
                  this.width = this.clamp(width)
                  this.apply()
                  this.save()
                },
                // From a button, the focus goes to the one that undoes it.
                toggle(moveFocus) {
                  this.collapsed = !this.collapsed
                  this.apply()
                  this.save()
                  if (moveFocus)
                    document.getElementById(this.collapsed ? "sidebar-expand" : "sidebar-collapse")?.focus()
                },
                apply() {
                  const js = this.js()
                  js.setAttribute(this.el, "style", `--sidebar-width: ${this.width}px`)
                  if (this.collapsed) js.setAttribute(this.el, "data-collapsed", "")
                  else js.removeAttribute(this.el, "data-collapsed")
                  js.setAttribute(this.handle, "aria-valuenow", String(this.width))
                  for (const button of this.el.querySelectorAll("[data-sidebar-toggle]"))
                    js.setAttribute(button, "aria-expanded", String(!this.collapsed))
                },
                clamp(width) {
                  return Math.round(Math.min(MAX, Math.max(MIN, width)))
                },
                load() {
                  try {
                    return JSON.parse(localStorage.getItem(KEY)) || {}
                  } catch {
                    return {}
                  }
                },
                save() {
                  try {
                    localStorage.setItem(KEY, JSON.stringify({width: this.width, collapsed: this.collapsed}))
                  } catch {}
                }
              }
            </script>
            <Layouts.account current_user={@current_user} />
          </div>
        </div>
        <%!-- Tabs floating on the menu's edge, at mid-height (large screens):
             one folds the menu, the other, on the screen's edge, unfolds it --%>
        <button
          id="sidebar-collapse"
          type="button"
          data-sidebar-toggle
          aria-controls="sidebar"
          aria-label={gettext("Fold the menu")}
          title={gettext("Fold the menu (Ctrl+\\)")}
          class={[
            "fixed top-1/2 left-[calc(var(--sidebar-width)-0.625rem)] z-40 hidden h-10 w-5 -translate-y-1/2",
            "cursor-pointer items-center justify-center border border-base-content/40 bg-base-100 text-base-content/70",
            "transition-colors hover:border-base-content hover:bg-base-200 hover:text-base-content",
            "focus-visible:border-base-content focus-visible:outline-none",
            "lg:flex lg:group-data-[collapsed]/drawer:hidden"
          ]}
        >
          <.icon name="hero-chevron-left-micro" class="size-4" />
        </button>
        <button
          id="sidebar-expand"
          type="button"
          data-sidebar-toggle
          aria-controls="sidebar"
          aria-label={gettext("Unfold the menu")}
          title={gettext("Unfold the menu (Ctrl+\\)")}
          class={[
            "fixed top-1/2 left-0 z-40 hidden h-10 w-5 -translate-y-1/2",
            "cursor-pointer items-center justify-center border border-l-0 border-base-content/40 bg-base-100 text-base-content/70",
            "transition-colors hover:border-base-content hover:bg-base-200 hover:text-base-content",
            "focus-visible:border-base-content focus-visible:outline-none",
            "lg:group-data-[collapsed]/drawer:flex"
          ]}
        >
          <.icon name="hero-chevron-right-micro" class="size-4" />
        </button>
        <%!-- Dragged, or moved with the arrows, to resize the menu; a double
             click gives it back its width. Fixed on the menu's edge, outside it
             (it clips what overflows): 6 px on the menu's side, where its strip
             shows, 8 px on the document's side, only widening the area to grab --%>
        <div
          id="sidebar-resize"
          data-sidebar-resize
          role="separator"
          aria-orientation="vertical"
          aria-controls="sidebar"
          aria-label={gettext("Width of the menu")}
          aria-valuemin="192"
          aria-valuemax="480"
          tabindex="0"
          title={gettext("Drag to resize, double-click for the default width")}
          class={[
            "group/handle fixed inset-y-0 left-[calc(var(--sidebar-width)-0.375rem)] z-30 hidden w-3.5",
            "cursor-col-resize touch-none focus-visible:outline-none lg:block lg:group-data-[collapsed]/drawer:hidden"
          ]}
        >
          <span class={[
            "absolute inset-y-0 left-0 w-1.5 transition-colors",
            "group-hover/handle:bg-base-content/30 group-focus-visible/handle:bg-base-content/50",
            "group-data-[resizing]/drawer:bg-base-content/50"
          ]}></span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :document, :any, required: true
  attr :ancestors, :list, required: true, doc: "the parents of the document, the highest first"
  attr :documents, :map, required: true, doc: "the documents listed, by id"
  attr :can_edit?, :boolean, required: true
  attr :history_open?, :boolean, required: true

  # The path to the open document, in the top bar, while its tree is not
  # shown on the page. The first document is a link; each next one, with the
  # › before it, is one zone opening the list of its parent's sub-documents
  # (itself marked), with, for an editor, a button creating one. After the open document: "› …"
  # for its own sub-documents, or "› +" creating the first one. The menus are
  # popovers, out of the path, which scrolls sideways when too long; the
  # Breadcrumb hook puts each under its button.
  defp breadcrumb(assigns) do
    children = children(assigns.documents)
    path = assigns.ancestors ++ [assigns.document]

    assigns =
      assign(assigns,
        children: children,
        path: path,
        menus:
          path
          |> Enum.with_index()
          |> Enum.map(fn {crumb, index} ->
            %{
              crumb: crumb,
              next_id: Enum.at(path, index + 1) && Enum.at(path, index + 1).id,
              documents: Map.get(children, crumb.id, []),
              can_add?:
                if(crumb.id == assigns.document.id,
                  do: assigns.can_edit?,
                  else: Policy.can?(Map.get(assigns.documents, crumb.id, crumb).role, :write)
                )
            }
          end)
          |> Enum.filter(&(&1.documents != [] or &1.next_id != nil))
      )

    ~H"""
    <nav
      id="breadcrumb"
      phx-hook=".Breadcrumb"
      aria-label={gettext("Path to the document")}
      class={[
        "flex min-w-0 flex-1 items-center gap-0.5 overflow-x-auto text-xs text-base-content/70 [scrollbar-width:none]",
        "data-[scrolled]:[mask-image:linear-gradient(to_right,transparent,black_1.5rem)]",
        !@history_open? && "group-data-[tree-pinned]/drawer:invisible"
      ]}
    >
      <%!-- The first document: a link. Each next one, with the › before
           it: one zone opening the list of the documents of its level, its
           parent's sub-documents, itself marked in it. --%>
      <%= for {crumb, parent} <- Enum.zip(@path, [nil | @path]) do %>
        <.link
          :if={is_nil(parent) and crumb.id != @document.id}
          id={"breadcrumb-#{crumb.id}"}
          patch={~p"/documents/#{crumb.id}"}
          class="max-w-40 shrink-0 truncate px-1 py-1 decoration-dotted underline-offset-2 hover:text-base-content hover:underline"
        >
          {crumb.title || gettext("Untitled")}
        </.link>
        <span
          :if={is_nil(parent) and crumb.id == @document.id}
          id="breadcrumb-current"
          aria-current="page"
          class="max-w-48 shrink-0 truncate px-1 py-1 font-medium text-base-content"
        >
          {crumb.title || gettext("Untitled")}
        </span>
        <button
          :if={parent}
          id={if(crumb.id == @document.id, do: "breadcrumb-current", else: "breadcrumb-#{crumb.id}")}
          type="button"
          popovertarget={"breadcrumb-menu-#{parent.id}"}
          aria-current={crumb.id == @document.id && "page"}
          aria-label={
            gettext("Sub-documents of “%{title}”", title: parent.title || gettext("Untitled"))
          }
          class={[
            "flex h-7 min-w-0 shrink-0 cursor-pointer items-center gap-0.5 pr-1.5 hover:bg-base-200 hover:text-base-content",
            crumb.id == @document.id && "font-medium text-base-content"
          ]}
        >
          <.icon name="hero-chevron-right-micro" class="size-4 shrink-0" />
          <span class={["truncate", if(crumb.id == @document.id, do: "max-w-48", else: "max-w-40")]}>
            {crumb.title || gettext("Untitled")}
          </span>
        </button>
      <% end %>
      <button
        :if={Map.has_key?(@children, @document.id)}
        id="breadcrumb-sub-documents"
        type="button"
        popovertarget={"breadcrumb-menu-#{@document.id}"}
        aria-label={gettext("Sub-documents")}
        title={gettext("Sub-documents")}
        class="flex h-6 shrink-0 cursor-pointer items-center justify-center px-1.5 tracking-widest hover:bg-base-200 hover:text-base-content"
      >
        <.icon name="hero-chevron-right-micro" class="size-4" />…
      </button>
      <button
        :if={!Map.has_key?(@children, @document.id) and @can_edit?}
        id="breadcrumb-new"
        type="button"
        phx-click="new_sub_document"
        phx-value-id={@document.id}
        aria-label={gettext("New sub-document")}
        title={gettext("New sub-document")}
        class="flex h-6 shrink-0 cursor-pointer items-center justify-center px-1.5 hover:bg-base-200 hover:text-base-content"
      >
        <.icon name="hero-chevron-right-micro" class="size-4" />
        <.icon name="hero-plus-micro" class="size-4" />
      </button>
    </nav>
    <div
      :for={menu <- @menus}
      id={"breadcrumb-menu-#{menu.crumb.id}"}
      popover
      class="fixed inset-auto m-0 w-64 max-w-[calc(100vw-1rem)] border-2 border-base-content bg-base-100 py-1 text-sm text-base-content shadow-hard"
    >
      <ul class="max-h-80 overflow-y-auto">
        <li :for={document <- menu.documents}>
          <.link
            id={"breadcrumb-menu-#{menu.crumb.id}-#{document.id}"}
            patch={~p"/documents/#{document.id}"}
            aria-current={to_string(document.id == menu.next_id)}
            class="flex min-w-0 items-center gap-2 px-3 py-1.5 hover:bg-base-200 aria-[current=true]:font-medium"
          >
            <.icon name="hero-document-text" class="size-4 shrink-0" />
            <span class="truncate">{document.title || gettext("Untitled")}</span>
          </.link>
        </li>
      </ul>
      <div class="mt-1 border-t-2 border-dotted border-base-content/30 pt-1 text-xs text-base-content/70">
        <button
          :if={menu.can_add?}
          id={"breadcrumb-menu-#{menu.crumb.id}-new"}
          type="button"
          phx-click="new_sub_document"
          phx-value-id={menu.crumb.id}
          class="flex w-full cursor-pointer items-center gap-2 px-3 py-1.5 text-left hover:bg-base-200 hover:text-base-content"
        >
          <.icon name="hero-plus-micro" class="size-4" /> {gettext("New sub-document")}
        </button>
        <button
          id={"breadcrumb-menu-#{menu.crumb.id}-pin"}
          type="button"
          data-tree-pin
          class="flex w-full cursor-pointer items-center gap-2 px-3 py-1.5 text-left hover:bg-base-200 hover:text-base-content"
        >
          <.icon name="hero-arrow-left-end-on-rectangle-micro" class="size-4" />
          {gettext("Show the tree on the page")}
        </button>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Breadcrumb">
      // Keeps the end of the path in view, fading its start out once
      // scrolled (data-scrolled), and puts each menu of the path
      // (a popover, see breadcrumb/1) under the button opening it, within
      // the screen; a document chosen or created closes it. Attributes set
      // through this.js(), so that LiveView's patches keep them.
      export default {
        mounted() {
          this.toEnd()
          this.onToggle = e => {
            if (e.newState !== "open" || !e.target.id?.startsWith("breadcrumb-menu-")) return
            const button = document.querySelector(`[popovertarget="${e.target.id}"]`)
            if (!button) return
            const rect = button.getBoundingClientRect()
            const width = e.target.offsetWidth || 256
            const left = Math.max(8, Math.min(rect.left, window.innerWidth - width - 8))
            this.js().setAttribute(e.target, "style", `top: ${rect.bottom + 4}px; left: ${left}px`)
          }
          this.onClick = e => {
            const menu = e.target.closest('[popover][id^="breadcrumb-menu-"]')
            if (menu && e.target.closest("a, [phx-click]")) menu.hidePopover()
          }
          document.addEventListener("beforetoggle", this.onToggle, true)
          document.addEventListener("click", this.onClick)
          this.el.addEventListener("scroll", () => this.markScrolled(), {passive: true})
        },
        updated() {
          this.toEnd()
        },
        destroyed() {
          document.removeEventListener("beforetoggle", this.onToggle, true)
          document.removeEventListener("click", this.onClick)
        },
        toEnd() {
          this.el.scrollLeft = this.el.scrollWidth
          this.markScrolled()
        },
        markScrolled() {
          if (this.el.scrollLeft > 0) this.js().setAttribute(this.el, "data-scrolled", "")
          else this.js().removeAttribute(this.el, "data-scrolled")
        }
      }
    </script>
    """
  end

  attr :document, :any, required: true
  attr :ancestors, :list, required: true
  attr :documents, :map, required: true, doc: "the documents listed, by id"
  attr :expanded, :any, required: true
  attr :user_id, :string, required: true
  attr :active_empty?, :boolean, required: true
  attr :deleting, :any, required: true

  # The tree of the open document, from its highest parent, the others being
  # found by the search. They are dragged onto one another to move them (see
  # the DocumentTree hook).
  defp document_tree(assigns) do
    ~H"""
    <div id="documents-tree" phx-hook=".DocumentTree" class="group/tree">
      <ul id="documents" class="menu w-full p-0">
        <.document_items
          documents={tree_root(@document, @ancestors, @documents)}
          children={children(@documents)}
          active_id={@document && @document.id}
          expanded={@expanded}
          user_id={@user_id}
          active_empty?={@active_empty?}
          deleting={@deleting}
        />
      </ul>
      <div
        id="documents-root-drop"
        data-drop-target="root"
        class="mt-1 hidden items-center justify-center gap-1.5 border-2 border-dashed border-base-content/40 px-3 py-2 text-xs text-base-content/70 transition-colors group-data-[dragging=root]/tree:flex data-[drop-over]:border-base-content data-[drop-over]:bg-base-200 data-[drop-over]:text-base-content"
      >
        <.icon name="hero-arrow-up-left-micro" class="size-4" /> {gettext("Move to the root")}
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".DocumentTree">
      // Drags a document of the sidebar: into another, before or after
      // another (the top, middle or bottom of its row), or onto the root's
      // zone; then asks the server to move it there. The rows tell what
      // they allow (see document_items/1). The attributes it sets go
      // through this.js(), so that LiveView's patches keep them.
      export default {
        mounted() {
          this.el.addEventListener("dragstart", e => {
            const row = e.target.closest?.("[data-document-row][draggable=true]")
            if (!row) return
            this.dragged = row
            e.dataTransfer.effectAllowed = "move"
            e.dataTransfer.setData("text/plain", row.dataset.documentId)
            const toRoot = this.canMove() && "canRoot" in row.dataset && row.dataset.parentId
            this.js().setAttribute(this.el, "data-dragging", toRoot ? "root" : "")
            this.js().setAttribute(row, "data-dragged", "")
          })
          this.el.addEventListener("dragover", e => {
            const target = this.target(e)
            this.over(target)
            if (!target) return
            e.preventDefault()
            e.dataTransfer.dropEffect = "move"
          })
          this.el.addEventListener("dragleave", e => {
            if (!this.el.contains(e.relatedTarget)) this.over(null)
          })
          this.el.addEventListener("drop", e => {
            const target = this.target(e)
            if (!target) return
            e.preventDefault()
            const id = this.dragged.dataset.documentId
            if (target.place === "root")
              this.pushEvent("move_document", {id, parent_id: null})
            else if (target.place === "into")
              this.pushEvent("move_document", {id, parent_id: target.el.dataset.documentId})
            else
              this.pushEvent("place_document", {
                id,
                sibling_id: target.el.dataset.documentId,
                place: target.place
              })
            this.end()
          })
          this.el.addEventListener("dragend", () => this.end())
        },
        // Its owner can move it under another parent; whoever can write its
        // parent can order it there.
        canMove() {
          return "canMove" in this.dragged.dataset
        },
        // Where the dragged document may go, under the pointer, as `{el,
        // place}`: before or after a document whose parent its user can
        // write (to order it among its siblings, or move it there); into a
        // document they can write; or the root. Never itself nor one of its
        // descendants.
        target(e) {
          if (!this.dragged) return null
          const zone = e.target.closest?.('[data-drop-target="root"]')
          if (zone)
            return this.el.dataset.dragging === "root" ? {el: zone, place: "root"} : null
          const row = e.target.closest?.("[data-document-row]")
          if (!row || this.dragged.closest("li").contains(row)) return null

          const sameParent = row.dataset.parentId === this.dragged.dataset.parentId
          const inOrder =
            "inOrder" in row.dataset &&
            (sameParent ? "inOrder" in this.dragged.dataset : this.canMove())
          const into =
            row.dataset.dropTarget === "document" &&
            this.canMove() &&
            row.dataset.documentId !== this.dragged.dataset.parentId

          const rect = row.getBoundingClientRect()
          const y = (e.clientY - rect.top) / rect.height
          const edge = into ? 0.25 : 0.5
          if (inOrder && y < edge) return {el: row, place: "before"}
          if (inOrder && y > 1 - edge) return {el: row, place: "after"}
          return into ? {el: row, place: "into"} : null
        },
        // Highlights `target`; a folded document held under the pointer, to
        // drop into, unfolds, to drop among its sub-documents.
        over(target) {
          const same =
            target && this.current && target.el === this.current.el && target.place === this.current.place
          if (same || (!target && !this.current)) return
          if (this.current) this.js().removeAttribute(this.current.el, "data-drop-over")
          clearTimeout(this.unfold)
          this.current = target
          if (!target) return
          this.js().setAttribute(target.el, "data-drop-over", target.place)
          if (target.place === "into" && "folded" in target.el.dataset) {
            const id = target.el.dataset.documentId
            this.unfold = setTimeout(() => this.pushEvent("toggle_document", {id}), 700)
          }
        },
        end() {
          this.over(null)
          if (this.dragged) this.js().removeAttribute(this.dragged, "data-dragged")
          this.dragged = null
          this.js().removeAttribute(this.el, "data-dragging")
        },
        destroyed() {
          clearTimeout(this.unfold)
        }
      }
    </script>
    """
  end

  attr :documents, :list, required: true
  attr :children, :map, required: true, doc: "the sub-documents of each document's id"
  attr :active_id, :string, required: true
  attr :expanded, :any, required: true, doc: "the ids of the documents unfolded"
  attr :user_id, :string, required: true
  attr :active_empty?, :boolean, required: true, doc: "whether the open document's body is empty"
  attr :deleting, :any, required: true, doc: "the ids of the empty documents left, being deleted"

  attr :parent_writable?, :boolean,
    default: false,
    doc: "whether the user can write the parent of these documents, to order them"

  # Documents of the sidebar, each with its sub-documents under it when
  # unfolded, and for an editor a button creating one. A document is dragged
  # (see the DocumentTree hook) onto another to move it in (by its owner, onto
  # one they can write; to the root, by its real owner, see
  # Document.move_document/4), or before or after another to order them (by
  # whoever can write their parent, see Document.place_document/4).
  defp document_items(assigns) do
    ~H"""
    <li :for={document <- @documents} id={"documents-#{document.id}"}>
      <div
        data-document-row
        data-document-id={document.id}
        data-parent-id={document.parent_id}
        data-can-root={document.owner_id == @user_id}
        data-drop-target={Policy.can?(document.role, :write) && "document"}
        data-can-move={Policy.can?(document.role, :share)}
        data-in-order={@parent_writable?}
        data-folded={@children[document.id] && !MapSet.member?(@expanded, document.id)}
        draggable={to_string(Policy.can?(document.role, :share) or @parent_writable?)}
        class={[
          "group gap-1 py-1 pr-1 pl-1 transition-[opacity,box-shadow] duration-150",
          "data-[drop-over=into]:bg-base-200 data-[drop-over=into]:ring-2 data-[drop-over=into]:ring-base-content data-[drop-over=into]:ring-inset",
          "data-[drop-over=before]:shadow-[inset_0_2px_0_0_var(--color-base-content)]",
          "data-[drop-over=after]:shadow-[inset_0_-2px_0_0_var(--color-base-content)]",
          "data-[dragged]:opacity-40",
          @active_id == document.id && "menu-active"
        ]}
      >
        <button
          :if={@children[document.id]}
          id={"documents-#{document.id}-toggle"}
          type="button"
          phx-click="toggle_document"
          phx-value-id={document.id}
          aria-expanded={to_string(MapSet.member?(@expanded, document.id))}
          aria-label={
            gettext("Sub-documents of “%{title}”", title: document.title || gettext("Untitled"))
          }
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
        <.link
          patch={~p"/documents/#{document.id}"}
          draggable="false"
          class="flex min-w-0 flex-1 items-center gap-2"
        >
          <.icon name="hero-document-text" class="size-4 shrink-0" />
          <%!-- The whole title while pointed at or focused --%>
          <span class="truncate group-hover:whitespace-normal group-hover:[overflow-wrap:anywhere] group-has-focus-visible:whitespace-normal group-has-focus-visible:[overflow-wrap:anywhere]">
            {document.title || gettext("Untitled")}
          </span>
        </.link>
        <.deletion_mark
          :if={MapSet.member?(@deleting, document.id)}
          id={"documents-#{document.id}-deleting"}
          countdown
        />
        <.deletion_mark
          :if={
            @active_id == document.id and @active_empty? and blank?(document.title) and
              !@children[document.id]
          }
          id={"documents-#{document.id}-empty"}
        />
        <button
          :if={Policy.can?(document.role, :write)}
          id={"documents-#{document.id}-new"}
          type="button"
          phx-click="new_sub_document"
          phx-value-id={document.id}
          title={gettext("New sub-document")}
          aria-label={
            gettext("New sub-document of “%{title}”", title: document.title || gettext("Untitled"))
          }
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
          user_id={@user_id}
          active_empty?={@active_empty?}
          deleting={@deleting}
          parent_writable?={Policy.can?(document.role, :write)}
        />
      </ul>
    </li>
    """
  end

  # The first level of the sidebar: the highest of the open document's
  # ancestors, so that it shows in their whole tree; itself without any. Only
  # those linked to it without a gap: a parent the user cannot read would
  # leave it out of the tree.
  attr :id, :string, required: true
  attr :countdown, :boolean, default: false, doc: "whether the document was left, being deleted"

  # An empty document, deleted for good when left (see YPersistence), not put
  # in the trash: a cross in a dotted ring while open; once left, in a ring
  # emptying over the seconds before its deletion.
  defp deletion_mark(assigns) do
    assigns =
      assign(
        assigns,
        :label,
        if(assigns.countdown,
          do: gettext("Empty: being deleted"),
          else: gettext("Empty: deleted when you leave it")
        )
      )

    ~H"""
    <span
      id={@id}
      role="img"
      aria-label={@label}
      title={@label}
      class={[
        "relative flex size-5 shrink-0 items-center justify-center",
        if(@countdown, do: "text-error", else: "text-base-content/60")
      ]}
    >
      <svg viewBox="0 0 20 20" class="absolute inset-0 size-5 -rotate-90" aria-hidden="true">
        <circle
          cx="10"
          cy="10"
          r="8.5"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          class={
            if(@countdown,
              do: "[stroke-dasharray:53.41] motion-safe:animate-countdown",
              else: "[stroke-dasharray:2_2.45]"
            )
          }
        />
      </svg>
      <.icon name="hero-x-mark-micro" class="size-3" />
    </span>
    """
  end

  # The documents of the sidebar's scope: the recent ones still listed (the
  # others were deleted or are no longer readable), the user's own or those
  # shared with them, the last updated first, or their trash.
  defp sidebar_documents(%{sidebar_scope: :recent, recent_ids: ids, documents: documents}),
    do: for(id <- ids, document = documents[id], do: document)

  defp sidebar_documents(%{sidebar_scope: :trash, trash: trash}), do: trash

  defp sidebar_documents(%{sidebar_scope: scope, documents: documents, current_user: user}) do
    own? = scope == :own

    documents
    |> Map.values()
    |> Enum.filter(&(&1.owner_id == user.id == own?))
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
  end

  defp scope_label(scope), do: PadocsWeb.SearchModal.scopes() |> Keyword.fetch!(scope) |> elem(0)

  defp scope_empty_text(scope),
    do: PadocsWeb.SearchModal.scopes() |> Keyword.fetch!(scope) |> elem(2)

  # The trash, read again when the sidebar lists it.
  defp reload_trash(%{assigns: %{sidebar_scope: :trash}} = socket),
    do: assign(socket, trash: Document.list_trash(socket.assigns.current_user))

  defp reload_trash(socket), do: assign(socket, trash: [])

  defp tree_root(nil, _ancestors, _documents), do: []

  defp tree_root(document, ancestors, documents) do
    root =
      ancestors
      |> Enum.reverse()
      |> Enum.reduce_while(document, fn ancestor, child ->
        if ancestor.id == child.parent_id, do: {:cont, ancestor}, else: {:halt, child}
      end)

    [Map.get(documents, root.id, root)]
  end

  # The sub-documents of each document, in their order (see Document.place_document/4).
  defp children(documents) do
    documents
    |> Map.values()
    |> Enum.filter(&(&1.parent_id && Map.has_key?(documents, &1.parent_id)))
    |> Enum.sort_by(
      &{&1.position || 2_147_483_647, DateTime.to_unix(&1.inserted_at, :microsecond)}
    )
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
              phx-click="search_tag"
              phx-value-id={tag.id}
              title={gettext("Documents with the tag “%{tag}”", tag: tag.label)}
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
            aria-label={gettext("Remove the tag “%{tag}”", tag: tag.label)}
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
            placeholder={gettext("New tag")}
            maxlength="40"
            autocomplete="off"
            phx-mounted={JS.focus()}
            phx-blur="close_tag_form"
            aria-label={gettext("New tag")}
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
          title={gettext("Add a tag")}
          class={[
            "-ml-1 inline-flex h-5 cursor-pointer items-center gap-0.5 px-1 text-xs text-base-content/70",
            "transition-colors hover:text-base-content"
          ]}
        >
          <.icon name="hero-plus-micro" class="size-3.5" />
          <span :if={@tag_count == 0}>{gettext("Add a tag")}</span>
          <span :if={@tag_count > 0} class="sr-only">{gettext("Add a tag")}</span>
        </button>
      <% end %>
    <% end %>
    """
  end

  attr :document, :any, required: true
  attr :can_share?, :boolean, required: true

  # The menu of the document's actions: exporting it, and for its owner,
  # sharing, moving it, and putting it in the trash. Opened and closed in the
  # browser; closed by a click outside or Escape.
  defp document_actions(assigns) do
    ~H"""
    <div id="document-actions" class="relative ml-auto" phx-click-away={hide_actions()}>
      <button
        id="document-actions-button"
        type="button"
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls="document-actions-menu"
        aria-label={gettext("Actions of the document")}
        title={if(@can_share?, do: gettext("Share, move, export…"), else: gettext("Export…"))}
        phx-click={toggle_actions()}
        class="btn btn-sm btn-square border-base-content bg-base-100 hover:bg-primary hover:text-primary-content aria-expanded:bg-primary aria-expanded:text-primary-content"
      >
        <.icon name="hero-ellipsis-horizontal" class="size-5" />
      </button>
      <div
        id="document-actions-menu"
        role="menu"
        aria-labelledby="document-actions-button"
        phx-window-keydown={hide_actions()}
        phx-key="Escape"
        class="absolute right-0 top-full z-30 mt-2 hidden w-60 border-2 border-base-content bg-base-100 py-1 shadow-hard"
      >
        <%= if @can_share? do %>
          <.action_item id="share-button" icon="hero-user-plus" event="toggle_share">
            {gettext("Share…")}
          </.action_item>
          <.action_item id="move-button" icon="hero-arrows-right-left" event="open_move">
            {gettext("Move to…")}
          </.action_item>
          <div class="my-1 border-t border-dotted border-base-content/30"></div>
        <% end %>
        <.action_item id="history-button" icon="hero-clock" event="open_history">
          {gettext("History…")}
        </.action_item>
        <div class="my-1 border-t border-dotted border-base-content/30"></div>
        <p class="px-3 pt-1.5 pb-0.5 text-xs text-base-content/70">{gettext("Export as")}</p>
        <%!-- PDF, Markdown and Typst: made on the server, downloaded; Word and
             OpenDocument: made from the editor (see the DocumentEditor hook) --%>
        <.export_link document={@document} format="pdf" icon="hero-document-arrow-down">
          PDF
        </.export_link>
        <.export_item format="docx" icon="hero-document-text">Word (.docx)</.export_item>
        <.export_item format="odt" icon="hero-document-text">OpenDocument (.odt)</.export_item>
        <.export_link document={@document} format="md" icon="hero-hashtag">
          Markdown (.md)
        </.export_link>
        <.export_link document={@document} format="typ" icon="hero-code-bracket">
          Typst (.typ)
        </.export_link>
        <div :if={@can_share?} class="my-1 border-t border-dotted border-base-content/30"></div>
        <button
          :if={@can_share?}
          id="trash-button"
          type="button"
          role="menuitem"
          phx-click={hide_actions() |> JS.push("trash_document")}
          data-confirm={gettext("Put this document and its sub-documents in the trash?")}
          class="flex w-full cursor-pointer items-center gap-2.5 px-3 py-2 text-left text-sm text-error transition-colors hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none"
        >
          <.icon name="hero-trash" class="size-4 shrink-0" /> {gettext("Put in the trash")}
        </button>
      </div>
    </div>
    """
  end

  attr :document, :any, required: true
  attr :format, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  # A file made on the server (see ExportController).
  defp export_link(assigns) do
    ~H"""
    <a
      id={"export-#{@format}"}
      href={~p"/documents/#{@document.id}/export/#{@format}"}
      download
      role="menuitem"
      class="flex w-full cursor-pointer items-center gap-2.5 px-3 py-2 text-left text-sm no-underline transition-colors hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none"
    >
      <.icon name={@icon} class="size-4 shrink-0" />
      {render_slot(@inner_block)}
    </a>
    """
  end

  attr :format, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  # A file made from the editor, in the browser.
  defp export_item(assigns) do
    ~H"""
    <button
      id={"export-#{@format}"}
      type="button"
      role="menuitem"
      phx-click={hide_actions() |> JS.push("export", value: %{format: @format})}
      class="flex w-full cursor-pointer items-center gap-2.5 px-3 py-2 text-left text-sm transition-colors hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none"
    >
      <.icon name={@icon} class="size-4 shrink-0" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :event, :string, required: true
  slot :inner_block, required: true

  defp action_item(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="menuitem"
      aria-haspopup="dialog"
      phx-click={hide_actions() |> JS.push(@event)}
      class="flex w-full cursor-pointer items-center gap-2.5 px-3 py-2 text-left text-sm transition-colors hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none"
    >
      <.icon name={@icon} class="size-4 shrink-0" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp toggle_actions do
    JS.toggle(
      to: "#document-actions-menu",
      in:
        {"transition ease-out duration-100", "opacity-0 -translate-y-1",
         "opacity-100 translate-y-0"},
      out: {"transition ease-in duration-75", "opacity-100", "opacity-0"}
    )
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#document-actions-button")
    |> JS.focus_first(to: "#document-actions-menu")
  end

  defp hide_actions do
    JS.hide(
      to: "#document-actions-menu",
      transition: {"transition ease-in duration-75", "opacity-100", "opacity-0"}
    )
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#document-actions-button")
  end

  attr :versions, :any, required: true

  # The points of the document's history, the last first, by day (see
  # Document.list_versions/2). Choosing one shows it in place of the editor
  # (see version_banner/1). Closed by its button or Escape.
  defp history_panel(assigns) do
    ~H"""
    <aside
      id="history-panel"
      role="dialog"
      aria-labelledby="history-title"
      phx-window-keydown="close_history"
      phx-key="Escape"
      phx-mounted={
        JS.transition(
          {"transition ease-out duration-200", "translate-x-full opacity-0",
           "translate-x-0 opacity-100"},
          time: 200
        )
        |> JS.focus_first(to: "#history-versions")
      }
      class="fixed inset-y-0 right-0 z-40 flex w-80 max-w-[calc(100vw-2rem)] flex-col border-l-2 border-base-content bg-base-100 shadow-hard"
    >
      <div class="flex items-start justify-between gap-4 border-b-2 border-dotted border-base-content/40 px-4 py-3">
        <div class="min-w-0">
          <h2 id="history-title" class="text-sm uppercase">{gettext("History")}</h2>
          <p class="mt-0.5 text-xs text-base-content/70">
            {gettext("The edits, by minute, then by hour, day and week as they age (UTC).")}
          </p>
        </div>
        <button
          id="history-close"
          type="button"
          phx-click="close_history"
          aria-label={gettext("Close the history")}
          class="btn btn-ghost btn-sm btn-square -mt-1 -mr-2"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
      <ul id="history-versions" phx-update="stream" class="flex-1 overflow-y-auto px-2 py-2">
        <li id="history-empty" class="hidden px-2 py-3 text-sm text-base-content/70 only:block">
          {gettext("No edit saved yet.")}
        </li>
        <li :for={{dom_id, version} <- @versions} id={dom_id}>
          <p
            :if={version.first_of_day?}
            class="px-2 pt-3 pb-1 text-xs font-medium uppercase tracking-wide text-base-content/70 first:pt-1"
          >
            {day_label(version.ended_at)}
          </p>
          <button
            id={"show-version-#{version.id}"}
            type="button"
            phx-click={
              JS.push("show_version", value: %{id: version.id})
              |> JS.remove_attribute("aria-current", to: "#history-versions [aria-current]")
              |> JS.set_attribute({"aria-current", "true"})
            }
            class={[
              "group flex w-full cursor-pointer items-center justify-between gap-2 border-2 border-transparent px-2 py-1.5 text-left text-sm",
              "transition-colors duration-100 hover:bg-base-200 focus-visible:border-base-content focus-visible:outline-none",
              "aria-[current]:border-base-content aria-[current]:bg-primary aria-[current]:text-primary-content"
            ]}
          >
            <span class="tabular-nums">{range_label(version)}</span>
            <span
              :if={version.last?}
              class="text-xs text-base-content/70 group-aria-[current]:text-primary-content/80"
            >
              {gettext("the latest")}
            </span>
          </button>
        </li>
      </ul>
    </aside>
    """
  end

  attr :version, :map, required: true
  attr :can_edit?, :boolean, required: true

  # Above the version shown in place of the editor: what it is, restoring it
  # (for those who can write), going back to the document.
  defp version_banner(assigns) do
    ~H"""
    <div
      id="version-banner"
      role="status"
      class="sticky top-14 z-20 mx-2 lg:top-16 mb-2 flex flex-wrap items-center gap-x-3 gap-y-2 border-2 border-base-content bg-base-200 px-3 py-2 text-sm shadow-hard lg:mx-[54px]"
    >
      <.icon name="hero-clock" class="size-4 shrink-0" />
      <span class="min-w-0 flex-1 basis-56">
        {gettext("Version of %{at} UTC",
          at: Calendar.strftime(@version.ended_at, gettext("%m/%d/%Y at %H:%M"))
        )}
        <span class="text-base-content/70">— {gettext("read only")}</span>
      </span>
      <button
        :if={@can_edit?}
        id="restore-version"
        type="button"
        phx-click="restore_version"
        data-confirm={
          gettext(
            "Replace the content of the document with this version? The edits made since stay in the history."
          )
        }
        class="btn btn-sm border-base-content bg-base-100 hover:bg-primary hover:text-primary-content"
      >
        <.icon name="hero-arrow-uturn-left" class="size-4" /> {gettext("Restore this version")}
      </button>
      <button
        id="leave-version"
        type="button"
        phx-click="hide_version"
        class="btn btn-sm btn-ghost"
      >
        {gettext("Back to the document")}
      </button>
    </div>
    """
  end

  defp day_label(at) do
    today = Date.utc_today()

    case Date.diff(today, DateTime.to_date(at)) do
      0 -> gettext("Today")
      1 -> gettext("Yesterday")
      _ -> Calendar.strftime(at, gettext("%m/%d/%Y"))
    end
  end

  # The minutes of the range of edits, its day if it spans several.
  defp range_label(%{started_at: started_at, ended_at: ended_at}) do
    cond do
      DateTime.to_date(started_at) != DateTime.to_date(ended_at) ->
        "#{Calendar.strftime(started_at, gettext("%m/%d %H:%M"))} – #{Calendar.strftime(ended_at, gettext("%m/%d %H:%M"))}"

      Calendar.strftime(started_at, "%H:%M") == Calendar.strftime(ended_at, "%H:%M") ->
        Calendar.strftime(ended_at, "%H:%M")

      true ->
        "#{Calendar.strftime(started_at, "%H:%M")} – #{Calendar.strftime(ended_at, "%H:%M")}"
    end
  end

  attr :document, :any, required: true
  attr :destinations, :list, required: true, doc: "`{document, path}`, see move_destinations/1"
  attr :can_move_to_root?, :boolean, required: true

  # A modal listing where the open document can go: the documents its user
  # can write, each under the titles of its parents, and the root. Closed by
  # its button, a click outside or Escape.
  defp move_panel(assigns) do
    ~H"""
    <div id="move-modal" class="modal modal-open" phx-window-keydown="close_move" phx-key="Escape">
      <section
        id="move-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="move-title"
        phx-mounted={JS.focus_first(to: "#move-destinations")}
        class="modal-box w-11/12 max-w-lg border-2 border-base-content bg-base-100 p-5 shadow-hard sm:p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 id="move-title" class="text-sm uppercase">{gettext("Move to…")}</h2>
            <p class="mt-0.5 truncate text-xs text-base-content/70">
              {gettext("“%{title}” will take the accesses of its new parent.",
                title: @document.title || gettext("Untitled")
              )}
            </p>
          </div>
          <button
            id="move-close"
            type="button"
            phx-click="close_move"
            aria-label={gettext("Close")}
            class="btn btn-ghost btn-sm btn-square -mt-1 -mr-2"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <ul
          id="move-destinations"
          class="mt-3 max-h-80 divide-y-2 divide-dotted divide-base-content/30 overflow-y-auto"
        >
          <li :if={@can_move_to_root?}>
            <.move_destination id="move-to-root" document_id={@document.id} parent_id="">
              <.icon name="hero-arrow-up-left" class="size-4 shrink-0" />
              <span class="font-medium">{gettext("Root")}</span>
            </.move_destination>
          </li>
          <li :for={{destination, path} <- @destinations}>
            <.move_destination
              id={"move-to-#{destination.id}"}
              document_id={@document.id}
              parent_id={destination.id}
            >
              <.icon name="hero-document-text" class="size-4 shrink-0" />
              <span class="flex min-w-0 flex-col">
                <span :if={path != []} class="truncate text-xs text-base-content/70">
                  {Enum.join(path, " / ")}
                </span>
                <span class="truncate">{destination.title || gettext("Untitled")}</span>
              </span>
            </.move_destination>
          </li>
          <li
            :if={@destinations == [] and !@can_move_to_root?}
            id="move-empty"
            class="py-2 text-sm text-base-content/70"
          >
            {gettext("No other document to put it in.")}
          </li>
        </ul>
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_move"
        aria-label={gettext("Close")}
        tabindex="-1"
      ></button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :document_id, :string, required: true
  attr :parent_id, :string, required: true
  slot :inner_block, required: true

  defp move_destination(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="move_document"
      phx-value-id={@document_id}
      phx-value-parent_id={@parent_id}
      class="flex w-full cursor-pointer items-center gap-2 px-2 py-2 text-left text-sm transition-colors hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none"
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  # The public link of the document (see Document.enable_public_link/2):
  # created, copied, replaced by a new one, or removed.
  attr :token, :string, default: nil

  defp public_link(assigns) do
    ~H"""
    <div id="public-link" class="mt-5 border-t-2 border-dotted border-base-content/30 pt-4">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0">
          <h3 class="flex items-center gap-1.5 text-xs uppercase">
            <.icon name="hero-globe-alt" class="size-4" /> {gettext("Public link")}
          </h3>
          <p class="mt-0.5 text-xs text-base-content/70">
            <%= if @token do %>
              {gettext(
                "Anyone with this link reads the document, without an account, but not its sub-documents."
              )}
            <% else %>
              {gettext("To let people without an account read this document, read only.")}
            <% end %>
          </p>
        </div>
        <button
          :if={!@token}
          id="public-link-enable"
          type="button"
          phx-click="enable_public_link"
          phx-disable-with={gettext("Creating…")}
          class="btn btn-sm border-base-content bg-base-100 transition-transform hover:-translate-y-px"
        >
          <.icon name="hero-link" class="size-4" /> {gettext("Create a link")}
        </button>
      </div>
      <div :if={@token} class="mt-2 flex flex-wrap items-center gap-2">
        <input
          id="public-link-url"
          type="text"
          readonly
          value={url(~p"/p/#{@token}")}
          aria-label={gettext("Public link")}
          phx-click={JS.dispatch("select")}
          class="input input-sm min-w-56 flex-1 border-base-content font-mono text-xs"
        />
        <button
          id="public-link-copy"
          type="button"
          phx-hook=".CopyLink"
          data-target="#public-link-url"
          class="group btn btn-sm btn-primary w-24"
        >
          <span class="inline-flex items-center gap-1 group-data-[copied]:hidden">
            <.icon name="hero-clipboard" class="size-4" /> {gettext("Copy")}
          </span>
          <span class="hidden items-center gap-1 group-data-[copied]:inline-flex">
            <.icon name="hero-check" class="size-4" /> {gettext("Copied")}
          </span>
        </button>
        <button
          id="public-link-regenerate"
          type="button"
          phx-click="enable_public_link"
          data-confirm={gettext("The current link will stop working. Create a new link?")}
          title={gettext("Replace with a new link: the current one will stop working")}
          class="btn btn-sm btn-ghost"
        >
          <.icon name="hero-arrow-path" class="size-4" /> {gettext("New link")}
        </button>
        <button
          id="public-link-disable"
          type="button"
          phx-click="disable_public_link"
          data-confirm={
            gettext(
              "Disable the public link? The people who have it will no longer read the document."
            )
          }
          class="btn btn-sm btn-ghost text-error"
        >
          <.icon name="hero-link-slash" class="size-4" /> {gettext("Disable")}
        </button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyLink">
          export default {
            mounted() {
              this.el.addEventListener("click", async () => {
                const input = document.querySelector(this.el.dataset.target)
                try {
                  await navigator.clipboard.writeText(input.value)
                } catch {
                  // without the clipboard API (e.g. over plain HTTP), selected for a copy by hand
                  input.select()
                  return
                }
                this.el.dataset.copied = ""
                clearTimeout(this.timer)
                this.timer = setTimeout(() => delete this.el.dataset.copied, 1500)
              })
            },
            destroyed() { clearTimeout(this.timer) }
          }
        </script>
      </div>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :members, :any, required: true
  attr :inherited, :list, required: true, doc: "see Document.list_inherited_accesses/2"
  attr :current_user_id, :string, required: true
  attr :public_token, :string, default: nil

  # A modal that invites an address as viewer or editor, and lists the members,
  # then the accesses inherited from the parents, changed from there, and the
  # public link. Closed by its button, a click outside or Escape.
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
            <h2 id="share-title" class="text-sm uppercase">{gettext("Share this document")}</h2>
            <p class="mt-0.5 text-xs text-base-content/70">
              {gettext("The person must already have an account.")}
            </p>
          </div>
          <button
            id="share-close"
            type="button"
            phx-click="close_share"
            aria-label={gettext("Close")}
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
              placeholder={gettext("address@example.com")}
              autocomplete="off"
              required
            />
          </div>
          <.input
            field={@form[:role]}
            type="select"
            options={role_options()}
            class="select w-32"
          />
          <button
            id="share-submit"
            class="btn btn-primary"
            phx-disable-with={gettext("Inviting…")}
          >
            {gettext("Invite")}
          </button>
        </.form>
        <ul
          id="members"
          phx-update="stream"
          class="mt-2 divide-y-2 divide-dotted divide-base-content/30"
        >
          <li id="members-empty" class="hidden py-2 text-sm text-base-content/70 only:block">
            {if @inherited == [],
              do: gettext("Not shared yet."),
              else: gettext("No access of its own to this document.")}
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
                  options={role_options()}
                  aria-label={gettext("Role of %{email}", email: member.email)}
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
                data-confirm={gettext("Remove the access of %{email}?", email: member.email)}
                aria-label={gettext("Remove %{email}", email: member.email)}
                class="btn btn-ghost btn-xs btn-square opacity-60 transition-opacity hover:opacity-100"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </span>
          </li>
        </ul>
        <div :if={@inherited != []} id="inherited-accesses" class="mt-5">
          <h3 class="text-xs uppercase">{gettext("Inherited accesses")}</h3>
          <p class="mt-0.5 text-xs text-base-content/70">
            {gettext("Given by the parent documents: they are changed from these documents.")}
          </p>
          <ul class="mt-1 divide-y-2 divide-dotted divide-base-content/30">
            <li
              :for={access <- @inherited}
              id={"inherited-#{access.user_id}"}
              class="flex items-center justify-between gap-3 py-2 text-sm"
            >
              <span class="flex min-w-0 items-center gap-2">
                <span class="flex size-7 shrink-0 items-center justify-center border-2 border-dashed border-base-content/60 text-xs font-medium uppercase text-base-content/70">
                  {String.first(access.email)}
                </span>
                <span class="truncate text-base-content/80">
                  {access.email}<span
                    :if={access.user_id == @current_user_id}
                    class="text-base-content/50"
                  >{gettext("(you)")}</span>
                </span>
              </span>
              <span class="flex min-w-0 shrink-0 items-center gap-2 text-xs text-base-content/70">
                <%= if access.from do %>
                  <.link
                    id={"inherited-#{access.user_id}-from"}
                    patch={~p"/documents/#{access.from.id}"}
                    title={
                      gettext("Inherited from “%{title}”",
                        title: access.from.title || gettext("Untitled")
                      )
                    }
                    class="hidden max-w-40 truncate decoration-dotted underline-offset-2 hover:text-base-content hover:underline sm:inline"
                  >
                    {gettext("via %{title}", title: access.from.title || gettext("Untitled"))}
                  </.link>
                <% else %>
                  <span class="hidden sm:inline">{gettext("via a parent document")}</span>
                <% end %>
                <span class="w-28 border-2 border-base-content/40 px-2 py-0.5 text-center whitespace-nowrap">
                  {role_label(access.role)}
                </span>
              </span>
            </li>
          </ul>
        </div>
        <.public_link token={@public_token} />
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_share"
        aria-label={gettext("Close")}
        tabindex="-1"
      ></button>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Padocs.PubSub, YPersistence.documents_topic())
    end

    documents = Document.list_documents(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(
       document: nil,
       can_edit?: false,
       can_share?: false,
       sharing?: false,
       moving?: false,
       move_destinations: [],
       inherited_accesses: [],
       public_token: nil,
       search_open?: false,
       search_tag: nil,
       search_scope: nil,
       share_form: nil,
       history_open?: false,
       # the versions listed, by id, and the one shown in place of the editor
       versions: %{},
       viewed_version: nil,
       # The sidebar's documents, by id: a map rather than a stream, to show
       # them as trees (see document_items/1), and the documents unfolded.
       documents: Map.new(documents, &{&1.id, &1}),
       # the ids of the documents opened last, the last first (see recent/2)
       # what the sidebar lists (see sidebar_documents/1), and the trash,
       # read when listed
       sidebar_scope: :recent,
       trash: [],
       recent_ids:
         socket.assigns.current_user
         |> Document.list_recent_documents(@recent)
         |> Enum.map(& &1.id),
       expanded: MapSet.new(),
       ancestors: [],
       # whether the open document's body is empty (told by its editor), and
       # the empty documents left, deleted a few seconds later (see YPersistence)
       body_empty?: false,
       deleting: MapSet.new()
     )
     |> stream(:viewers, [])
     |> stream(:members, [])
     |> stream(:versions, [])}
  end

  # /documents opens the document the user opened last, else the one they
  # updated last, else a new one (deleted if left empty, see YPersistence).
  # ?search=trash (e.g. the link of the message after putting a document in
  # the trash) goes along, to open the trash there.
  def handle_params(params, _uri, %{assigns: %{live_action: :index}} = socket) do
    user = socket.assigns.current_user

    document =
      with nil <- Document.last_opened(user) do
        {:ok, document} = Document.create_document(user)
        document
      end

    query = Map.take(params, ["search"])
    {:noreply, push_patch(socket, to: ~p"/documents/#{document.id}?#{query}", replace: true)}
  end

  # The trash, in the search modal. The address keeps its parameter while it
  # is open (a reload opens it again), and loses it when it closes.
  def handle_params(%{"id" => id, "search" => "trash"}, uri, socket) do
    {:noreply, socket} = handle_params(%{"id" => id}, uri, socket)

    if socket.assigns.document && socket.assigns.document.id == id do
      {:noreply, assign(socket, search_open?: true, search_tag: nil, search_scope: :trash)}
    else
      {:noreply, socket}
    end
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
         |> put_flash(:error, gettext("Document not found"))
         |> push_navigate(to: ~p"/documents")}
    end
  end

  defp open_document(socket, document) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Padocs.PubSub, YPersistence.topic(document.id))
      Phoenix.PubSub.subscribe(Padocs.PubSub, Document.members_topic(document.id))

      user = socket.assigns.current_user
      Document.opened(user, document)
      Presence.subscribe(viewers_topic(document.id))
      Presence.track_user(viewers_topic(document.id), user.id, %{id: user.id, email: user.email})
    end

    # its parents, unfolded in the sidebar, where it shows in their tree
    ancestors = Document.list_ancestors(document, socket.assigns.current_user)

    socket
    |> close_search()
    |> assign(
      ancestors: ancestors,
      expanded:
        socket.assigns.expanded
        |> MapSet.union(MapSet.new(ancestors, & &1.id))
        |> MapSet.put(document.id),
      document: document,
      recent_ids:
        Enum.take([document.id | List.delete(socket.assigns.recent_ids, document.id)], @recent),
      can_edit?: Policy.can?(document.role, :write),
      can_share?: Policy.can?(document.role, :share),
      sharing?: false,
      moving?: false,
      history_open?: false,
      versions: %{},
      viewed_version: nil,
      page_title: document.title || gettext("Untitled"),
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

  defp open_search(socket, tag), do: assign(socket, search_open?: true, search_tag: tag)

  defp close_search(socket),
    do: assign(socket, search_open?: false, search_tag: nil, search_scope: nil)

  # Lists the versions of the open document, each with whether it is the
  # first of its day (the list being the last first) and the last of all.
  defp open_history(socket) do
    %{document: document, current_user: user} = socket.assigns

    case Document.list_versions(document.id, user) do
      {:ok, versions} ->
        versions =
          versions
          |> Enum.with_index()
          |> Enum.map_reduce(nil, fn {version, index}, previous_day ->
            day = DateTime.to_date(version.ended_at)
            {Map.merge(version, %{first_of_day?: day != previous_day, last?: index == 0}), day}
          end)
          |> elem(0)

        socket
        |> assign(history_open?: true, versions: Map.new(versions, &{&1.id, &1}))
        |> stream(:versions, versions, reset: true)

      {:error, _} ->
        put_flash(socket, :error, gettext("You can no longer read this document"))
    end
  end

  defp hide_version(%{assigns: %{viewed_version: nil}} = socket), do: socket

  defp hide_version(socket) do
    socket |> assign(viewed_version: nil) |> push_event("hide_version", %{})
  end

  defp leave_document(%{assigns: %{document: nil}} = socket), do: socket

  defp leave_document(socket) do
    document_id = socket.assigns.document.id
    socket = socket |> mark_deleting() |> assign(body_empty?: false)

    if connected?(socket) do
      Phoenix.PubSub.unsubscribe(Padocs.PubSub, YPersistence.topic(document_id))
      Phoenix.PubSub.unsubscribe(Padocs.PubSub, Document.members_topic(document_id))
      Presence.unsubscribe(viewers_topic(document_id))
      Presence.untrack_user(viewers_topic(document_id), socket.assigns.current_user.id)
    end

    socket
  end

  # The open document, left empty: YPersistence deletes it once no one has it
  # open, a few seconds later. Unless other people still have it open, the
  # sidebar shows it going until :document_deleted, or for 15 s at most.
  defp mark_deleting(socket) do
    %{document: document, body_empty?: empty?, current_user: user} = socket.assigns

    alone? =
      not connected?(socket) or Enum.all?(viewers(document.id), &(&1.id == user.id))

    if empty? and blank?(document.title) and alone? and not Document.has_children?(document.id) do
      Process.send_after(self(), {:forget_deleting, document.id}, :timer.seconds(15))
      update(socket, :deleting, &MapSet.put(&1, document.id))
    else
      socket
    end
  end

  defp blank?(title), do: is_nil(title) or String.trim(title) == ""

  def handle_info({:forget_deleting, document_id}, socket),
    do: {:noreply, update(socket, :deleting, &MapSet.delete(&1, document_id))}

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

  # Tags added or removed, on this page or another.
  def handle_info({:document_tags_changed, document_id}, socket) do
    if socket.assigns.document.id == document_id do
      {:noreply, put_tags(socket, Document.list_tags(document_id))}
    else
      {:noreply, socket}
    end
  end

  # A document put in the trash, or an empty one left and deleted (see
  # YPersistence): the latter is open nowhere, so an open one went to the
  # trash, on this page (which said so) or another.
  def handle_info({:document_deleted, document_id}, socket) do
    socket =
      socket
      |> update(:documents, &Map.delete(&1, document_id))
      |> update(:deleting, &MapSet.delete(&1, document_id))
      |> reload_trash()

    if socket.assigns.document.id == document_id do
      socket =
        if Phoenix.Flash.get(socket.assigns.flash, :info),
          do: socket,
          else: put_flash(socket, :info, gettext("This document was put in the trash"))

      {:noreply, push_navigate(socket, to: ~p"/documents")}
    else
      {:noreply, socket}
    end
  end

  # A document restored from the trash (see SearchModal): the sidebar may show
  # it again.
  def handle_info({:document_restored, message}, socket) do
    documents = Document.list_documents(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(documents: Map.new(documents, &{&1.id, &1}))
     |> reload_trash()
     |> put_flash(:info, message)}
  end

  # Sub-documents ordered or moved, on this page or another: the sidebar shows
  # those it lists in their new order.
  def handle_info({:children_reordered, _parent_id, ids}, socket) do
    positions = ids |> Enum.with_index() |> Map.new()

    {:noreply,
     update(socket, :documents, fn documents ->
       Map.new(documents, fn {id, document} ->
         case positions do
           %{^id => position} -> {id, %{document | position: position}}
           _ -> {id, document}
         end
       end)
     end)}
  end

  # Moved on this page or another: the sidebar shows it under its new parent,
  # and the breadcrumb follows if the open document is among those moved.
  def handle_info({:document_moved, document_id, parent_id}, socket),
    do: {:noreply, put_moved(socket, document_id, parent_id)}

  # The roles of the open document read again by its DocServer, as it was put
  # in the trash (the page leaves it on :document_deleted) or restored.
  def handle_info({:access_reloaded, _document_id}, socket), do: {:noreply, socket}

  # The public link changed on another page of its owner.
  def handle_info({:public_link_changed, document_id, token}, socket) do
    if socket.assigns.document.id == document_id,
      do: {:noreply, assign(socket, public_token: token)},
      else: {:noreply, socket}
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
         |> put_flash(:error, gettext("Your access to this document was removed"))
         |> push_navigate(to: ~p"/documents")}

      true ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Your rights on this document changed"))
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

  # Told by the editor when the open document's body becomes empty or not.
  def handle_event("body_emptiness", %{"id" => id, "empty" => empty}, socket) do
    if socket.assigns.document.id == id and is_boolean(empty),
      do: {:noreply, assign(socket, body_empty?: empty)},
      else: {:noreply, socket}
  end

  def handle_event("new_document", _params, socket) do
    {:ok, document} = Document.create_document(socket.assigns.current_user)

    {:noreply,
     socket
     |> list_new_document(%{document | role: :owner})
     |> push_patch(to: ~p"/documents/#{document.id}")}
  end

  # A file converted by the DocumentImport hook: its Yjs state, in base64.
  def handle_event("import_document", %{"name" => name, "state" => state} = params, socket) do
    title = name |> Path.rootname() |> String.trim()

    with {:ok, snapshot} <- Base.decode64(state),
         {:ok, document} <-
           Document.import_document(
             socket.assigns.current_user,
             title,
             snapshot,
             List.wrap(params["file_ids"])
           ) do
      {:reply, %{id: document.id},
       socket
       |> list_new_document(%{document | role: :owner})
       |> put_flash(:info, imported_message(title, params["missing_images"]))}
    else
      _ ->
        # its images, uploaded beforehand, are of no use
        Files.discard(socket.assigns.current_user, List.wrap(params["file_ids"]))

        {:reply, %{},
         put_flash(socket, :error, gettext("“%{name}” could not be imported", name: name))}
    end
  end

  # An archive read by the DocumentImport hook: the plan of its import (see
  # Padocs.Document.Archive), from the paths of its entries.
  def handle_event("import_archive_plan", %{"name" => name, "paths" => paths}, socket)
      when is_binary(name) and is_list(paths) do
    plan =
      paths |> Enum.filter(&is_binary/1) |> Enum.take(@max_archive_entries) |> Archive.plan(name)

    {:reply,
     %{
       documents: plan.documents,
       attachments: plan.attachments,
       skipped:
         for(
           %{path: path, reason: reason} <- plan.skipped,
           do: %{path: path, reason: to_string(reason)}
         )
     }, socket}
  end

  # A document of the plan, converted by the hook, or a folder without
  # content. Its front matter may give its title and tags.
  def handle_event("import_archive_document", %{"title" => title} = params, socket)
      when is_binary(title) do
    meta = Archive.front_matter(params["front_matter"])

    with {:ok, snapshot} <- archive_state(params["state"]),
         {:ok, document} <-
           Document.import_document(
             socket.assigns.current_user,
             meta.title || String.trim(title),
             snapshot,
             List.wrap(params["file_ids"]),
             parent_id: params["parent_id"],
             tags: meta.tags
           ) do
      {:reply, %{id: document.id}, list_new_document(socket, %{document | role: :owner})}
    else
      _ ->
        Files.discard(socket.assigns.current_user, List.wrap(params["file_ids"]))
        {:reply, %{}, socket}
    end
  end

  # The archive imported: what was, and the root opened.
  def handle_event("import_archive_done", %{"name" => name} = params, socket) do
    imported = integer(params["imported"])
    left_out = integer(params["left_out"])

    message =
      [
        ngettext(
          "“%{name}”: %{count} document imported",
          "“%{name}”: %{count} documents imported",
          imported,
          name: name
        ),
        left_out > 0 &&
          ngettext("%{count} file left out", "%{count} files left out", left_out)
      ]
      |> Enum.filter(& &1)
      |> Enum.join(", ")

    socket = put_flash(socket, if(imported > 0, do: :info, else: :error), message)

    case params["root_id"] &&
           Document.get_document(params["root_id"], socket.assigns.current_user) do
      {:ok, root} -> {:noreply, push_patch(socket, to: ~p"/documents/#{root.id}")}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("import_failed", %{"name" => name, "reason" => reason} = params, socket) do
    message =
      case reason do
        "too_large" ->
          gettext("“%{name}” is too large (%{max} MB at most)",
            name: name,
            max: megabytes(params["max_bytes"])
          )

        _ ->
          gettext("“%{name}” could not be read", name: name)
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
         put_flash(socket, :error, gettext("You cannot change the tags of this document"))}
    end
  end

  def handle_event("remove_tag", %{"id" => tag_id}, socket) do
    %{document: document, current_user: user} = socket.assigns

    case Document.remove_tag(document.id, user, tag_id) do
      :ok ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, gettext("You cannot change the tags of this document"))}
    end
  end

  def handle_event("toggle_share", _params, %{assigns: %{sharing?: true}} = socket),
    do: {:noreply, assign(socket, sharing?: false)}

  def handle_event("close_share", _params, socket),
    do: {:noreply, assign(socket, sharing?: false)}

  # The search modal's index lives while it is open (see SearchModal).
  def handle_event("open_search", _params, socket), do: {:noreply, open_search(socket, nil)}

  # A tag of the document: the search opens on the documents carrying it.
  def handle_event("search_tag", %{"id" => id}, socket) do
    case Enum.find(Document.list_tags(socket.assigns.document.id), &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      tag ->
        Document.record_tag_search(socket.assigns.current_user, tag.id)
        {:noreply, open_search(socket, tag)}
    end
  end

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
        {:noreply, put_flash(socket, :error, gettext("You cannot add a sub-document here"))}
    end
  end

  def handle_event("close_search", _params, socket) do
    # opened by ?search=trash: the address without it
    socket =
      if socket.assigns.search_scope,
        do: push_patch(socket, to: ~p"/documents/#{socket.assigns.document.id}", replace: true),
        else: socket

    # the trash, maybe emptied there
    {:noreply, socket |> close_search() |> reload_trash()}
  end

  def handle_event("pick_sidebar_scope", %{"scope" => scope}, socket) do
    case Enum.find(Keyword.keys(PadocsWeb.SearchModal.scopes()), &(Atom.to_string(&1) == scope)) do
      nil -> {:noreply, socket}
      scope -> {:noreply, socket |> assign(sidebar_scope: scope) |> reload_trash()}
    end
  end

  # From the sidebar's trash
  def handle_event("restore_document", %{"id" => id}, socket) do
    case Document.restore_document(id, socket.assigns.current_user) do
      {:ok, document} ->
        handle_info(
          {:document_restored,
           gettext("“%{title}” restored", title: document.title || gettext("Untitled"))},
          socket
        )

      {:error, _} ->
        {:noreply, reload_trash(socket)}
    end
  end

  # A Word or OpenDocument file, made from the editor by the DocumentEditor
  # hook, which answers with export_done or export_failed.
  def handle_event("export", %{"format" => format}, socket) when format in ["docx", "odt"] do
    {:noreply,
     push_event(socket, "export_document", %{
       format: format,
       filename: Document.export_filename(socket.assigns.document)
     })}
  end

  def handle_event("export_done", %{"missing_files" => missing}, socket)
      when is_integer(missing) and missing > 0 do
    message =
      ngettext(
        "An image could not be fetched: the export is without it",
        "%{count} images could not be fetched: the export is without them",
        missing
      )

    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_event("export_done", _params, socket), do: {:noreply, socket}

  def handle_event("export_failed", _params, socket),
    do: {:noreply, put_flash(socket, :error, gettext("The export failed"))}

  # With its sub-documents; the page then opens another document. The other
  # pages showing them leave them too (see the :document_deleted message).
  def handle_event("trash_document", _params, socket) do
    document = socket.assigns.document

    case Document.trash_document(document.id, socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, %{
           message:
             gettext("“%{title}” put in the trash", title: document.title || gettext("Untitled")),
           link: {gettext("See the trash"), ~p"/documents?search=trash"}
         })
         |> push_navigate(to: ~p"/documents")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot delete this document"))}
    end
  end

  def handle_event("open_history", _params, socket), do: {:noreply, open_history(socket)}

  def handle_event("close_history", _params, socket) do
    {:noreply, socket |> hide_version() |> assign(history_open?: false, versions: %{})}
  end

  # The version's state goes to the DocumentEditor hook, which shows it read
  # only in place of the editor.
  def handle_event("show_version", %{"id" => id}, socket) when is_integer(id) do
    %{document: document, current_user: user, versions: versions} = socket.assigns

    case {versions[id], Document.version_state(document.id, id, user)} do
      {%{} = version, {:ok, state}} ->
        {:noreply,
         socket
         |> assign(viewed_version: version)
         |> push_event("show_version", %{state: Base.encode64(state)})}

      {_, {:error, :forbidden}} ->
        {:noreply, put_flash(socket, :error, gettext("You can no longer read this document"))}

      _ ->
        {:noreply,
         socket
         |> open_history()
         |> put_flash(:info, gettext("This version was merged with a more recent one"))}
    end
  end

  def handle_event("hide_version", _params, socket), do: {:noreply, hide_version(socket)}

  # Done by the editor, as an edit of this user: the content of the version
  # replaces the document's (see the DocumentEditor hook), which tells when it
  # is done.
  def handle_event("restore_version", _params, socket) do
    if socket.assigns.can_edit? and socket.assigns.viewed_version do
      {:noreply, push_event(socket, "restore_version", %{})}
    else
      {:noreply, put_flash(socket, :error, gettext("You cannot edit this document"))}
    end
  end

  def handle_event("version_restored", _params, socket) do
    message =
      case socket.assigns.viewed_version do
        %{ended_at: at} ->
          gettext("Version of %{at} UTC restored",
            at: Calendar.strftime(at, gettext("%m/%d/%Y at %H:%M"))
          )

        nil ->
          gettext("Version restored")
      end

    {:noreply,
     socket
     |> assign(viewed_version: nil, history_open?: false, versions: %{})
     |> put_flash(:info, message)}
  end

  def handle_event("restore_failed", _params, socket),
    do: {:noreply, put_flash(socket, :error, gettext("The version could not be restored"))}

  def handle_event("open_move", _params, socket) do
    {:noreply, assign(socket, moving?: true, move_destinations: move_destinations(socket))}
  end

  def handle_event("close_move", _params, socket), do: {:noreply, assign(socket, moving?: false)}

  # Before or after another document, from the sidebar (see the DocumentTree
  # hook): ordered among its siblings, or moved there.
  def handle_event(
        "place_document",
        %{"id" => id, "sibling_id" => sibling_id, "place" => place},
        socket
      )
      when place in ["before", "after"] do
    place = if place == "before", do: :before, else: :after

    case Document.place_document(id, sibling_id, place, socket.assigns.current_user) do
      {:ok, _document} ->
        {:noreply, socket}

      {:error, :cycle} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("A document cannot go under itself or one of its sub-documents")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot move this document here"))}
    end
  end

  # From the sidebar (see the DocumentTree hook) or the move panel; an empty
  # or missing parent is the root. The new parent is unfolded.
  def handle_event("move_document", %{"id" => id} = params, socket) do
    parent_id = if params["parent_id"] in [nil, ""], do: nil, else: params["parent_id"]

    case Document.move_document(id, parent_id, socket.assigns.current_user) do
      {:ok, document} ->
        {:noreply,
         socket
         |> assign(moving?: false)
         |> put_moved(document.id, document.parent_id)
         |> update(:expanded, &if(parent_id, do: MapSet.put(&1, parent_id), else: &1))
         |> put_flash(
           :info,
           gettext("“%{title}” moved", title: document.title || gettext("Untitled"))
         )}

      {:error, :cycle} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("A document cannot go under itself or one of its sub-documents")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot move this document here"))}
    end
  end

  def handle_event("toggle_share", _params, socket) do
    %{current_user: user, document: document} = socket.assigns

    {:noreply,
     socket
     |> assign(
       sharing?: true,
       share_form: share_form(),
       public_token:
         case Document.public_link_token(user, document.id) do
           {:ok, token} -> token
           {:error, _} -> nil
         end,
       inherited_accesses:
         Document.list_inherited_accesses(
           socket.assigns.current_user,
           socket.assigns.document.id
         )
     )
     |> stream(:members, members(socket), reset: true)}
  end

  def handle_event("share", %{"share" => params}, socket) do
    case Document.share_document(socket.assigns.current_user, socket.assigns.document.id, params) do
      {:ok, member} ->
        {:noreply,
         socket
         |> assign(share_form: share_form())
         |> stream_insert(:members, member)
         |> put_flash(:info, gettext("Document shared with %{email}", email: member.email))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, share_form: to_form(changeset, as: "share"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot share this document"))}
    end
  end

  def handle_event("change_role", %{"member" => %{"membership_id" => id, "role" => role}}, socket) do
    case Document.change_member_role(socket.assigns.current_user, id, role) do
      {:ok, member} ->
        {:noreply,
         socket
         |> stream_insert(:members, member)
         |> put_flash(:info, role_changed_message(member))}

      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("The role of this member could not be changed"))}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    case Document.remove_member(socket.assigns.current_user, id) do
      :ok -> {:noreply, stream_delete_by_dom_id(socket, :members, "members-#{id}")}
      _ -> {:noreply, put_flash(socket, :error, gettext("This member could not be removed"))}
    end
  end

  # A new token each time: the previous link, if any, stops working.
  def handle_event("enable_public_link", _params, socket) do
    %{current_user: user, document: document} = socket.assigns

    case Document.enable_public_link(user, document.id) do
      {:ok, token} ->
        {:noreply,
         socket |> assign(public_token: token) |> put_flash(:info, gettext("Public link created"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot share this document"))}
    end
  end

  def handle_event("disable_public_link", _params, socket) do
    %{current_user: user, document: document} = socket.assigns

    case Document.disable_public_link(user, document.id) do
      :ok ->
        {:noreply,
         socket |> assign(public_token: nil) |> put_flash(:info, gettext("Public link disabled"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot share this document"))}
    end
  end

  def handle_event("update_title", %{"title" => title}, socket) do
    case Document.rename_document(socket.assigns.document, socket.assigns.current_user, title) do
      {:ok, document} ->
        {:noreply, put_title(socket, document)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot rename this document"))}
    end
  end

  defp put_title(socket, document) do
    socket
    |> assign(
      document: document,
      page_title: document.title || gettext("Untitled"),
      title_form: to_form(%{"title" => document.title})
    )
    |> list_document(document)
  end

  # Updates `document` in the sidebar.
  defp list_document(socket, document) do
    update(
      socket,
      :documents,
      &Map.update(
        &1,
        document.id,
        document,
        fn listed -> %{listed | title: document.title, updated_at: document.updated_at} end
      )
    )
  end

  # A new document, shown in the sidebar.
  # The state of a document of an archive, or an empty one for a folder.
  defp archive_state(nil), do: {:ok, Yex.encode_state_as_update!(Yex.Doc.new())}
  defp archive_state(state) when is_binary(state), do: Base.decode64(state)
  defp archive_state(_state), do: :error

  defp integer(value) when is_integer(value) and value >= 0, do: value
  defp integer(_value), do: 0

  defp list_new_document(socket, document),
    do: update(socket, :documents, &Map.put(&1, document.id, document))

  # The document of `id` now under the document of `parent_id`, `nil` for the
  # root, in the sidebar and, if it is the open document or one of its
  # ancestors, in the breadcrumb.
  defp put_moved(socket, id, parent_id) do
    %{documents: documents, document: document, ancestors: ancestors} = socket.assigns

    socket =
      if Map.has_key?(documents, id),
        do: assign(socket, documents: Map.update!(documents, id, &%{&1 | parent_id: parent_id})),
        else: socket

    cond do
      is_nil(document) ->
        socket

      document.id == id or Enum.any?(ancestors, &(&1.id == id)) ->
        document = if document.id == id, do: %{document | parent_id: parent_id}, else: document
        ancestors = Document.list_ancestors(document, socket.assigns.current_user)

        assign(socket,
          document: document,
          ancestors: ancestors,
          expanded: MapSet.union(socket.assigns.expanded, MapSet.new(ancestors, & &1.id))
        )

      true ->
        socket
    end
  end

  # Where the open document can go: the documents its user can write, but
  # neither it, its descendants nor its parent, each with the titles of its
  # parents (`{document, path}`), by path.
  defp move_destinations(socket) do
    %{document: document, current_user: user} = socket.assigns
    documents = Map.new(Document.list_documents(user), &{&1.id, &1})
    children = Enum.group_by(Map.values(documents), & &1.parent_id, & &1.id)
    excluded = MapSet.new([document.parent_id | subtree(children, document.id)])

    documents
    |> Map.values()
    |> Enum.filter(&(Policy.can?(&1.role, :write) and not MapSet.member?(excluded, &1.id)))
    |> Enum.map(&{&1, title_path(documents, &1)})
    |> Enum.sort_by(fn {document, path} ->
      String.downcase(Enum.join(path ++ [document.title || ""], "/"))
    end)
  end

  # `id` and the ids of its descendants, `children` giving the ids of each
  # document's sub-documents.
  defp subtree(children, id),
    do: [id | Enum.flat_map(Map.get(children, id, []), &subtree(children, &1))]

  # The titles of the parents of `document` among `documents`, from the root.
  defp title_path(documents, document) do
    case Map.get(documents, document.parent_id) do
      nil -> []
      parent -> title_path(documents, parent) ++ [parent.title || gettext("Untitled")]
    end
  end

  # The form of a member's role, in their row of the share panel.
  defp role_form(member) do
    to_form(%{"membership_id" => member.id, "role" => to_string(member.role)},
      as: "member",
      id: "member-#{member.id}"
    )
  end

  defp role_label(:owner), do: gettext("Owner")
  defp role_label(:editor), do: gettext("Editor")
  defp role_label(:viewer), do: gettext("Viewer")

  # The roles a member can be given.
  defp role_options, do: [{role_label(:viewer), "viewer"}, {role_label(:editor), "editor"}]

  defp role_changed_message(%{email: email, role: :editor}),
    do: gettext("%{email} is now an editor", email: email)

  defp role_changed_message(%{email: email}),
    do: gettext("%{email} is now a viewer", email: email)

  # The form inviting an address to the open document.
  defp share_form, do: to_form(Document.change_share(%{role: :viewer}), as: "share")

  # The members of the open document, by email.
  defp members(socket),
    do: Document.list_members(socket.assigns.current_user, socket.assigns.document.id)

  # The images of a Word file the server refused (see convert.ts).
  defp imported_message(title, missing) when is_integer(missing) and missing > 0,
    do:
      ngettext(
        "“%{title}” imported, without its image",
        "“%{title}” imported, without its %{count} images",
        missing,
        title: title
      )

  defp imported_message(title, _missing), do: gettext("“%{title}” imported", title: title)

  defp megabytes(bytes) when is_integer(bytes) and bytes > 0, do: div(bytes, 1_000_000)
  defp megabytes(_bytes), do: 2
end
