defmodule TextexpWeb.DocumentComponents do
  @moduledoc """
  Components displaying documents.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: TextexpWeb.Endpoint,
    router: TextexpWeb.Router,
    statics: TextexpWeb.static_paths()

  @doc """
  A document of a list, as a card linking to it (its whole area): its title,
  last update, tags if loaded (see `Textexp.Document.with_tags/1`) and
  excerpt (the first lines of its body). On small screens, two tags show,
  then a button unfolding the others.

  The document needs its `title`, `excerpt` and `updated_at`. In search
  results, `snippet` replaces the excerpt: the fragment of the body where the
  searched words appear, as `Textexp.Document.Snippet` segments.
  """
  attr :document, :map, required: true
  attr :snippet, :list, default: nil

  def document_card(assigns) do
    ~H"""
    <%!-- The title's link covers the whole card (its ::after); the button
         unfolding the tags is above it --%>
    <div class="group relative rounded-md border border-base-content/15 bg-base-100 px-3 py-2.5 transition-colors duration-150 hover:border-base-content/40 hover:bg-base-200 has-[a:focus-visible]:outline-2 has-[a:focus-visible]:outline-offset-2 has-[a:focus-visible]:outline-base-content sm:px-4 sm:py-3">
      <%!-- On small screens, the date under the title, which keeps the width --%>
      <div class="flex flex-col sm:flex-row sm:items-baseline sm:justify-between sm:gap-4">
        <h2 class={[
          "line-clamp-2 text-sm font-medium group-hover:underline group-hover:decoration-dotted sm:truncate sm:text-base",
          if(@document.title, do: "text-base-content", else: "text-base-content/50")
        ]}>
          <.link
            navigate={~p"/documents/#{@document.id}"}
            class="no-underline outline-none after:absolute after:inset-0"
          >
            {@document.title || "Sans titre"}
          </.link>
        </h2>
        <time
          datetime={DateTime.to_iso8601(@document.updated_at)}
          class="shrink-0 text-[0.6875rem] tabular-nums text-base-content/60 sm:text-xs"
        >
          {Calendar.strftime(@document.updated_at, "%d/%m/%Y")}
          <span class="hidden sm:inline">
            {Calendar.strftime(@document.updated_at, "%H:%M")} UTC
          </span>
        </time>
      </div>
      <div
        :if={is_list(@document.tags) and @document.tags != []}
        id={"card-tags-#{@document.id}"}
        class="mt-1 flex flex-wrap items-center gap-1 sm:mt-1.5"
      >
        <%!-- On small screens, the first two, then how many others, which
             unfolds them --%>
        <.tag_badge
          :for={{tag, index} <- Enum.with_index(@document.tags)}
          tag={tag}
          data-extra-tag={index >= 2}
          class={index >= 2 && "max-sm:hidden"}
        />
        <button
          :if={length(@document.tags) > 2}
          id={"card-tags-#{@document.id}-more"}
          type="button"
          phx-click={
            JS.remove_class("max-sm:hidden", to: "#card-tags-#{@document.id} [data-extra-tag]")
            |> JS.hide()
          }
          aria-label={"Afficher les #{length(@document.tags)} tags"}
          class="relative z-10 cursor-pointer rounded px-1 text-[0.6875rem] text-base-content/60 transition-colors hover:bg-base-300 hover:text-base-content sm:hidden"
        >
          +{length(@document.tags) - 2}
        </button>
      </div>
      <%!-- On one line: whitespace between the segments, or around the excerpt,
           would show --%>
      <p
        :if={@snippet}
        class="mt-1 line-clamp-2 text-xs leading-relaxed text-base-content/75 sm:mt-1.5 sm:line-clamp-3 sm:text-sm"
        phx-no-format
      ><%= for {kind, text} <- @snippet do %><mark :if={kind == :match} class="bg-base-300 px-0.5 font-medium text-base-content">{text}</mark><span :if={kind == :text}>{text}</span><% end %></p>
      <p
        :if={!@snippet && @document.excerpt}
        class="mt-1 line-clamp-2 whitespace-pre-line text-xs leading-relaxed text-base-content/75 sm:mt-1.5 sm:line-clamp-3 sm:text-sm"
        phx-no-format
      >{@document.excerpt}</p>
    </div>
    """
  end

  @doc """
  A tag, as a discreet badge of its color (see `.tag` in app.css): its label,
  or the `label` slot (e.g. a button), followed by its inner block if any
  (e.g. a button removing it).
  """
  attr :tag, :map, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :label
  slot :inner_block

  def tag_badge(assigns) do
    ~H"""
    <span
      data-color={@tag.color}
      class={["tag badge badge-sm gap-0.5 border-0 px-1.5 text-[0.6875rem]", @class]}
      {@rest}
    >
      <%= if @label != [] do %>
        {render_slot(@label)}
      <% else %>
        {@tag.label}
      <% end %>
      {render_slot(@inner_block)}
    </span>
    """
  end
end
