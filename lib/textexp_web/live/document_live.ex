defmodule TextexpWeb.DocumentLive do
  use TextexpWeb, :live_view

  import TextexpWeb.DocumentComponents, only: [tag_badge: 1]

  alias Textexp.Accounts
  alias Textexp.Document
  alias Textexp.Document.{Policy, YPersistence}
  alias TextexpWeb.Presence

  on_mount {TextexpWeb.LiveUserAuth, :live_user_required}

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
        <div class={[
          "drawer-content flex flex-col transition-[padding] duration-200 ease-out",
          @history_open? && "lg:pr-80"
        ]}>
          <%!-- The menu's open button (small screens only), and the document's
               actions on the right, above the title --%>
          <div class="flex min-h-12 items-center justify-between px-2 pt-2 lg:px-[54px] lg:pt-4">
            <label
              id="sidebar-open"
              for="sidebar-drawer"
              aria-label="Ouvrir le menu"
              class="btn btn-square btn-ghost drawer-button lg:hidden"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </label>
            <.document_actions :if={@document} document={@document} can_share?={@can_share?} />
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
                user={@current_user}
                initial_tag={@search_tag}
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
                  Hors ligne — vos modifications sont gardées sur cet appareil
                </span>
                <span class="hidden items-center gap-2 group-data-[state=syncing]:inline-flex">
                  <.icon name="hero-arrow-path" class="size-4 shrink-0 motion-safe:animate-spin" />
                  Synchronisation…
                </span>
                <span class="hidden items-center gap-2 group-data-[state=server_down]:inline-flex">
                  <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
                  Le serveur ne répond pas, nouvel essai bientôt
                </span>
                <span class="hidden items-center gap-2 group-data-[state=synced]:inline-flex">
                  <.icon name="hero-check" class="size-4 shrink-0" /> Synchronisé
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="drawer-side z-20">
          <label for="sidebar-drawer" aria-label="Fermer le menu" class="drawer-overlay"></label>
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
                title="Importer des fichiers (Markdown, HTML, texte ou Word)"
                class="group btn btn-sm btn-square border-base-content bg-base-100 hover:bg-primary hover:text-primary-content focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-base-content aria-busy:pointer-events-none"
              >
                <.icon name="hero-arrow-up-tray" class="size-4 group-aria-busy:hidden" />
                <span class="loading loading-spinner loading-xs hidden group-aria-busy:inline-block"></span>
                <span class="sr-only">Importer des fichiers (Markdown, HTML, texte ou Word)</span>
                <input
                  id="import-files"
                  type="file"
                  multiple
                  accept=".md,.markdown,.txt,.html,.htm,.docx,text/markdown,text/plain,text/html,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                  phx-hook="DocumentImport"
                  class="sr-only"
                />
              </label>
            </div>
            <%!-- The tree of the open document, from its highest parent, the
                 others being found by the search. They are dragged onto one another to move them
                 (see the DocumentTree hook) --%>
            <div id="documents-tree" phx-hook=".DocumentTree" class="group/tree">
              <ul id="documents" class="menu w-full p-0">
                <.document_items
                  documents={tree_root(@document, @ancestors, @documents)}
                  children={children(@documents)}
                  active_id={@document && @document.id}
                  expanded={@expanded}
                  user_id={@current_user.id}
                />
              </ul>
              <div
                id="documents-root-drop"
                data-drop-target="root"
                class="mt-1 hidden items-center justify-center gap-1.5 border-2 border-dashed border-base-content/40 px-3 py-2 text-xs text-base-content/60 transition-colors group-data-[dragging=root]/tree:flex data-[drop-over]:border-base-content data-[drop-over]:bg-base-200 data-[drop-over]:text-base-content"
              >
                <.icon name="hero-arrow-up-left-micro" class="size-4" /> Mettre à la racine
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
            <script :type={Phoenix.LiveView.ColocatedHook} name=".Sidebar">
              // Folds the menu (its buttons, or Ctrl+\) and resizes it (its
              // handle, dragged or moved with the arrows), on large screens. The
              // choice is kept in this browser. The attributes it sets go through
              // this.js(), so that LiveView's patches keep them.
              const KEY = "textexp:sidebar"
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
          aria-label="Replier le menu"
          title="Replier le menu (Ctrl+\)"
          class={[
            "fixed top-1/2 left-[calc(var(--sidebar-width)-0.625rem)] z-40 hidden h-10 w-5 -translate-y-1/2",
            "cursor-pointer items-center justify-center border border-base-content/40 bg-base-100 text-base-content/60",
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
          aria-label="Déplier le menu"
          title="Déplier le menu (Ctrl+\)"
          class={[
            "fixed top-1/2 left-0 z-40 hidden h-10 w-5 -translate-y-1/2",
            "cursor-pointer items-center justify-center border border-l-0 border-base-content/40 bg-base-100 text-base-content/60",
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
          aria-label="Largeur du menu"
          aria-valuemin="192"
          aria-valuemax="480"
          tabindex="0"
          title="Glisser pour redimensionner, double-clic pour la largeur par défaut"
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

  attr :documents, :list, required: true
  attr :children, :map, required: true, doc: "the sub-documents of each document's id"
  attr :active_id, :string, required: true
  attr :expanded, :any, required: true, doc: "the ids of the documents unfolded"
  attr :user_id, :string, required: true

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
        <.link
          patch={~p"/documents/#{document.id}"}
          draggable="false"
          class="flex min-w-0 flex-1 items-center gap-2"
        >
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
          user_id={@user_id}
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
              title={"Documents avec le tag « #{tag.label} »"}
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
        aria-label="Actions du document"
        title={if(@can_share?, do: "Partager, déplacer, exporter…", else: "Exporter…")}
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
            Partager…
          </.action_item>
          <.action_item id="move-button" icon="hero-arrows-right-left" event="open_move">
            Déplacer vers…
          </.action_item>
          <div class="my-1 border-t border-dotted border-base-content/30"></div>
        <% end %>
        <.action_item id="history-button" icon="hero-clock" event="open_history">
          Historique…
        </.action_item>
        <div class="my-1 border-t border-dotted border-base-content/30"></div>
        <p class="px-3 pt-1.5 pb-0.5 text-xs text-base-content/60">Exporter en</p>
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
          data-confirm="Mettre ce document et ses sous-documents à la corbeille ?"
          class="flex w-full cursor-pointer items-center gap-2.5 px-3 py-2 text-left text-sm text-error transition-colors hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none"
        >
          <.icon name="hero-trash" class="size-4 shrink-0" /> Mettre à la corbeille
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
          <h2 id="history-title" class="text-sm uppercase">Historique</h2>
          <p class="mt-0.5 text-xs text-base-content/60">
            Les modifications, par minute, puis par heure, jour et semaine en vieillissant (UTC).
          </p>
        </div>
        <button
          id="history-close"
          type="button"
          phx-click="close_history"
          aria-label="Fermer l'historique"
          class="btn btn-ghost btn-sm btn-square -mt-1 -mr-2"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
      <ul id="history-versions" phx-update="stream" class="flex-1 overflow-y-auto px-2 py-2">
        <li id="history-empty" class="hidden px-2 py-3 text-sm text-base-content/60 only:block">
          Aucune modification enregistrée pour l'instant.
        </li>
        <li :for={{dom_id, version} <- @versions} id={dom_id}>
          <p
            :if={version.first_of_day?}
            class="px-2 pt-3 pb-1 text-xs font-medium uppercase tracking-wide text-base-content/60 first:pt-1"
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
              class="text-xs text-base-content/60 group-aria-[current]:text-primary-content/80"
            >
              la plus récente
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
      class="sticky top-0 z-20 mx-2 mb-2 flex flex-wrap items-center gap-x-3 gap-y-2 border-2 border-base-content bg-base-200 px-3 py-2 text-sm shadow-hard lg:mx-[54px]"
    >
      <.icon name="hero-clock" class="size-4 shrink-0" />
      <span class="min-w-0 flex-1 basis-56">
        Version du {Calendar.strftime(@version.ended_at, "%d/%m/%Y à %H:%M")} UTC
        <span class="text-base-content/60">— lecture seule</span>
      </span>
      <button
        :if={@can_edit?}
        id="restore-version"
        type="button"
        phx-click="restore_version"
        data-confirm="Remplacer le contenu du document par cette version ? Les modifications faites depuis restent dans l'historique."
        class="btn btn-sm border-base-content bg-base-100 hover:bg-primary hover:text-primary-content"
      >
        <.icon name="hero-arrow-uturn-left" class="size-4" /> Restaurer cette version
      </button>
      <button
        id="leave-version"
        type="button"
        phx-click="hide_version"
        class="btn btn-sm btn-ghost"
      >
        Revenir au document
      </button>
    </div>
    """
  end

  defp day_label(at) do
    today = Date.utc_today()

    case Date.diff(today, DateTime.to_date(at)) do
      0 -> "Aujourd'hui"
      1 -> "Hier"
      _ -> Calendar.strftime(at, "%d/%m/%Y")
    end
  end

  # The minutes of the range of edits, its day if it spans several.
  defp range_label(%{started_at: started_at, ended_at: ended_at}) do
    cond do
      DateTime.to_date(started_at) != DateTime.to_date(ended_at) ->
        "#{Calendar.strftime(started_at, "%d/%m %H:%M")} – #{Calendar.strftime(ended_at, "%d/%m %H:%M")}"

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
            <h2 id="move-title" class="text-sm uppercase">Déplacer vers…</h2>
            <p class="mt-0.5 truncate text-xs text-base-content/60">
              « {@document.title || "Sans titre"} » prendra les accès de son nouveau parent.
            </p>
          </div>
          <button
            id="move-close"
            type="button"
            phx-click="close_move"
            aria-label="Fermer"
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
              <span class="font-medium">Racine</span>
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
                <span :if={path != []} class="truncate text-xs text-base-content/60">
                  {Enum.join(path, " / ")}
                </span>
                <span class="truncate">{destination.title || "Sans titre"}</span>
              </span>
            </.move_destination>
          </li>
          <li
            :if={@destinations == [] and !@can_move_to_root?}
            id="move-empty"
            class="py-2 text-sm text-base-content/60"
          >
            Aucun autre document où le mettre.
          </li>
        </ul>
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_move"
        aria-label="Fermer"
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

  attr :form, Phoenix.HTML.Form, required: true
  attr :members, :any, required: true
  attr :inherited, :list, required: true, doc: "see Document.list_inherited_accesses/2"
  attr :current_user_id, :string, required: true

  # A modal that invites an address as viewer or editor, and lists the members,
  # then the accesses inherited from the parents, changed from there. Closed by
  # its button, a click outside or Escape.
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
            {if @inherited == [], do: "Pas encore partagé.", else: "Aucun accès propre à ce document."}
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
        <div :if={@inherited != []} id="inherited-accesses" class="mt-5">
          <h3 class="text-xs uppercase">Accès hérités</h3>
          <p class="mt-0.5 text-xs text-base-content/60">
            Donnés par les documents parents : ils se changent depuis ces documents.
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
                  > (vous)</span>
                </span>
              </span>
              <span class="flex min-w-0 shrink-0 items-center gap-2 text-xs text-base-content/60">
                <%= if access.from do %>
                  <.link
                    id={"inherited-#{access.user_id}-from"}
                    patch={~p"/documents/#{access.from.id}"}
                    title={"Hérité de « #{access.from.title || "Sans titre"} »"}
                    class="hidden max-w-40 truncate decoration-dotted underline-offset-2 hover:text-base-content hover:underline sm:inline"
                  >
                    via {access.from.title || "Sans titre"}
                  </.link>
                <% else %>
                  <span class="hidden sm:inline">via un document parent</span>
                <% end %>
                <span class="w-28 border-2 border-base-content/40 px-2 py-0.5 text-center whitespace-nowrap">
                  {String.capitalize(role_label(access.role))}
                </span>
              </span>
            </li>
          </ul>
        </div>
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
       moving?: false,
       move_destinations: [],
       inherited_accesses: [],
       search_open?: false,
       search_tag: nil,
       share_form: nil,
       history_open?: false,
       # the versions listed, by id, and the one shown in place of the editor
       versions: %{},
       viewed_version: nil,
       # The sidebar's documents, by id: a map rather than a stream, to show
       # them as trees (see document_items/1), and the documents unfolded.
       documents: Map.new(documents, &{&1.id, &1}),
       expanded: MapSet.new(),
       ancestors: []
     )
     |> stream(:viewers, [])
     |> stream(:members, [])
     |> stream(:versions, [])}
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
      can_edit?: Policy.can?(document.role, :write),
      can_share?: Policy.can?(document.role, :share),
      sharing?: false,
      moving?: false,
      history_open?: false,
      versions: %{},
      viewed_version: nil,
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

  defp open_search(socket, tag), do: assign(socket, search_open?: true, search_tag: tag)

  defp close_search(socket), do: assign(socket, search_open?: false, search_tag: nil)

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
        put_flash(socket, :error, "Vous ne pouvez plus lire ce document")
    end
  end

  defp hide_version(%{assigns: %{viewed_version: nil}} = socket), do: socket

  defp hide_version(socket) do
    socket |> assign(viewed_version: nil) |> push_event("hide_version", %{})
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
    socket = update(socket, :documents, &Map.delete(&1, document_id))

    if socket.assigns.document.id == document_id do
      socket =
        if Phoenix.Flash.get(socket.assigns.flash, :info),
          do: socket,
          else: put_flash(socket, :info, "Ce document a été mis à la corbeille")

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
  def handle_event("import_document", %{"name" => name, "state" => state} = params, socket) do
    title = name |> Path.rootname() |> String.trim()

    with {:ok, snapshot} <- Base.decode64(state),
         {:ok, document} <-
           Document.import_document(socket.assigns.current_user, title, snapshot) do
      {:reply, %{id: document.id},
       socket
       |> list_new_document(%{document | role: :owner})
       |> put_flash(:info, imported_message(title, params["missing_images"]))}
    else
      _ -> {:reply, %{}, put_flash(socket, :error, "Impossible d'importer « #{name} »")}
    end
  end

  def handle_event("import_failed", %{"name" => name, "reason" => reason} = params, socket) do
    message =
      case reason do
        "too_large" ->
          "« #{name} » est trop volumineux (#{megabytes(params["max_bytes"])} Mo au plus)"

        _ ->
          "Impossible de lire « #{name} »"
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
        {:noreply, put_flash(socket, :error, "Vous ne pouvez pas ajouter de sous-document ici")}
    end
  end

  def handle_event("close_search", _params, socket), do: {:noreply, close_search(socket)}

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
      if missing == 1,
        do: "Une image n'a pas pu être récupérée : l'export est sans elle",
        else: "#{missing} images n'ont pas pu être récupérées : l'export est sans elles"

    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_event("export_done", _params, socket), do: {:noreply, socket}

  def handle_event("export_failed", _params, socket),
    do: {:noreply, put_flash(socket, :error, "L'export a échoué")}

  # With its sub-documents; the page then opens another document. The other
  # pages showing them leave them too (see the :document_deleted message).
  def handle_event("trash_document", _params, socket) do
    document = socket.assigns.document

    case Document.trash_document(document.id, socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "« #{document.title || "Sans titre"} » mis à la corbeille")
         |> push_navigate(to: ~p"/documents")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Vous ne pouvez pas supprimer ce document")}
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
        {:noreply, put_flash(socket, :error, "Vous ne pouvez plus lire ce document")}

      _ ->
        {:noreply,
         socket
         |> open_history()
         |> put_flash(:info, "Cette version a été regroupée avec une plus récente")}
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
      {:noreply, put_flash(socket, :error, "Vous ne pouvez pas modifier ce document")}
    end
  end

  def handle_event("version_restored", _params, socket) do
    message =
      case socket.assigns.viewed_version do
        %{ended_at: at} -> "Version du #{Calendar.strftime(at, "%d/%m/%Y à %H:%M")} UTC restaurée"
        nil -> "Version restaurée"
      end

    {:noreply,
     socket
     |> assign(viewed_version: nil, history_open?: false, versions: %{})
     |> put_flash(:info, message)}
  end

  def handle_event("restore_failed", _params, socket),
    do: {:noreply, put_flash(socket, :error, "La version n'a pas pu être restaurée")}

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
           "Un document ne peut pas aller sous lui-même ou l'un de ses sous-documents"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Vous ne pouvez pas déplacer ce document ici")}
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
         |> put_flash(:info, "« #{document.title || "Sans titre"} » déplacé")}

      {:error, :cycle} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Un document ne peut pas aller sous lui-même ou l'un de ses sous-documents"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Vous ne pouvez pas déplacer ce document ici")}
    end
  end

  def handle_event("toggle_share", _params, socket) do
    {:noreply,
     socket
     |> assign(
       sharing?: true,
       share_form: share_form(),
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
      parent -> title_path(documents, parent) ++ [parent.title || "Sans titre"]
    end
  end

  # The form of a member's role, in their row of the share panel.
  defp role_form(member) do
    to_form(%{"membership_id" => member.id, "role" => to_string(member.role)},
      as: "member",
      id: "member-#{member.id}"
    )
  end

  defp role_label(:owner), do: "propriétaire"
  defp role_label(:editor), do: "éditeur"
  defp role_label(:viewer), do: "lecteur"

  # The form inviting an address to the open document.
  defp share_form, do: to_form(Document.change_share(%{role: :viewer}), as: "share")

  # The members of the open document, by email.
  defp members(socket),
    do: Document.list_members(socket.assigns.current_user, socket.assigns.document.id)

  # The images of a Word file are left out (see convert.ts).
  defp imported_message(title, 1), do: "« #{title} » importé, sans son image"

  defp imported_message(title, missing) when is_integer(missing) and missing > 1,
    do: "« #{title} » importé, sans ses #{missing} images"

  defp imported_message(title, _missing), do: "« #{title} » importé"

  defp megabytes(bytes) when is_integer(bytes) and bytes > 0, do: div(bytes, 1_000_000)
  defp megabytes(_bytes), do: 2
end
