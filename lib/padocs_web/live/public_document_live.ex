defmodule PadocsWeb.PublicDocumentLive do
  @moduledoc """
  A document opened by its public link (`/p/:token`, see
  `Padocs.Document.enable_public_link/2`): anyone reads it, live, without an
  account, but not its sub-documents. A signed-in user who can read it is
  sent to its usual page.

  Its editor joins the document's channel with the token, read-only (see
  `PadocsWeb.YDocRoomChannel`). When the link is changed or removed, or the
  document deleted, the page says so and the channel is left.
  """
  use PadocsWeb, :live_view

  alias Padocs.Document
  alias Padocs.Document.YPersistence

  on_mount {PadocsWeb.LiveUserAuth, :current_user}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width>
      <link phx-track-static rel="stylesheet" href={~p"/assets/js/blocknote.css"} />
      <%= if @document do %>
        <article
          id="public-document"
          class="mx-auto flex min-h-[calc(100dvh-3.5rem)] max-w-4xl flex-col"
        >
          <div class="document-header px-[54px] pt-8">
            <p
              id="public-badge"
              class="inline-flex items-center gap-1.5 border-2 border-base-content/40 px-2 py-0.5 text-xs text-base-content/70"
            >
              <.icon name="hero-globe-alt" class="size-3.5" /> Lecture seule, par un lien public
            </p>
            <h1 id="public-title" class="mt-3 text-3xl font-bold break-words">
              {@document.title || "Sans titre"}
            </h1>
            <hr class="mt-3 mb-1 border-t-2 border-dotted border-base-content/40" />
          </div>
          <%!-- Managed by the DocumentEditor hook (see DocumentLive): LiveView
               must not touch it. The token lets its channel join read-only;
               nothing is kept in the browser. --%>
          <div
            id={"public-editor-#{@document.id}"}
            class="flex-1 w-full pb-16"
            phx-hook="DocumentEditor"
            phx-update="ignore"
            data-document-id={@document.id}
            data-public-token={@token}
            data-user-id="public"
            data-user-name="Lecteur anonyme"
            data-editable="false"
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
            </div>
            <div data-editor hidden></div>
          </div>
        </article>
      <% else %>
        <section
          id="public-unavailable"
          class="mx-auto mt-24 max-w-md border-2 border-base-content bg-base-100 p-6 shadow-hard"
        >
          <.icon name="hero-link-slash" class="size-6" />
          <h1 class="mt-3 text-lg font-bold">Ce lien ne mène à aucun document</h1>
          <p class="mt-1 text-sm text-base-content/70">
            Son propriétaire a pu le désactiver ou le remplacer, ou le document a été supprimé.
          </p>
          <.link
            :if={!@current_user}
            id="public-sign-in"
            navigate={~p"/sign-in"}
            class="btn btn-primary btn-sm mt-4"
          >
            Se connecter
          </.link>
        </section>
      <% end %>
    </Layouts.app>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    with {:ok, document} <- Document.get_public_document(token) do
      if member?(document, socket.assigns.current_user) do
        {:ok, push_navigate(socket, to: ~p"/documents/#{document.id}")}
      else
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Padocs.PubSub, YPersistence.topic(document.id))
          Phoenix.PubSub.subscribe(Padocs.PubSub, Document.members_topic(document.id))
          Phoenix.PubSub.subscribe(Padocs.PubSub, YPersistence.documents_topic())
        end

        {:ok,
         assign(socket,
           document: document,
           token: token,
           page_title: document.title || "Sans titre"
         )}
      end
    else
      {:error, :not_found} -> {:ok, unavailable(socket)}
    end
  end

  defp member?(_document, nil), do: false
  defp member?(document, user), do: match?({:ok, _}, Document.get_document(document.id, user))

  defp unavailable(socket),
    do: assign(socket, document: nil, token: nil, page_title: "Lien indisponible")

  # The names of the comments' authors: not their email addresses, which
  # the public does not see.
  def handle_event("resolve_users", %{"ids" => ids}, socket) when is_list(ids) do
    {:reply, %{users: Enum.map(ids, &%{id: &1, username: "Membre", avatarUrl: ""})}, socket}
  end

  # Not offered here: exports and versions belong to DocumentLive.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  def handle_info({:public_link_changed, id, token}, %{assigns: %{document: %{id: id}}} = socket) do
    if token == socket.assigns.token,
      do: {:noreply, socket},
      else: {:noreply, unavailable(socket)}
  end

  # Put in the trash, or deleted while empty.
  def handle_info({:access_reloaded, id}, %{assigns: %{document: %{id: id}}} = socket) do
    case Document.get_public_document(socket.assigns.token) do
      {:ok, _document} -> {:noreply, socket}
      {:error, :not_found} -> {:noreply, unavailable(socket)}
    end
  end

  def handle_info({:document_deleted, id}, %{assigns: %{document: %{id: id}}} = socket),
    do: {:noreply, unavailable(socket)}

  def handle_info(
        {:document_updated, id, _at, title},
        %{assigns: %{document: %{id: id}}} = socket
      ),
      do: {:noreply, put_title(socket, title)}

  def handle_info(
        {:document_renamed, id, title, _at},
        %{assigns: %{document: %{id: id}}} = socket
      ),
      do: {:noreply, put_title(socket, title)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp put_title(socket, title) do
    assign(socket,
      document: %{socket.assigns.document | title: title},
      page_title: title || "Sans titre"
    )
  end
end
