defmodule PadocsWeb.PreferencesLive do
  @moduledoc """
  The preferences of the signed-in user: the language of the interface
  (posted to `PadocsWeb.LocaleController`, which keeps it on their account
  and comes back here), the theme (kept in this browser, see the root
  layout), and signing out.
  """
  use PadocsWeb, :live_view

  on_mount {PadocsWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="preferences" class="space-y-8">
        <div>
          <.link
            id="preferences-back"
            navigate={~p"/documents"}
            class="inline-flex items-center gap-1 text-xs text-base-content/60 transition-colors hover:text-base-content"
          >
            <.icon name="hero-arrow-left-micro" class="size-4" /> {gettext("Back to the documents")}
          </.link>
          <h1 class="mt-2 text-xl uppercase">{gettext("Preferences")}</h1>
        </div>

        <.section id="preferences-language" title={gettext("Language")}>
          <p class="text-xs text-base-content/60">
            {gettext("The language of the interface and of the emails you receive.")}
          </p>
          <form
            id="language-form"
            action={~p"/locale"}
            method="post"
            class="mt-3 grid grid-cols-2 gap-2"
          >
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <.choice
              :for={{locale, name} <- [{"fr", "Français"}, {"en", "English"}]}
              id={"language-#{locale}"}
              type="submit"
              name="locale"
              value={locale}
              lang={locale}
              pressed={locale == @locale}
            >
              {name}
            </.choice>
          </form>
        </.section>

        <.section id="preferences-theme" title={gettext("Theme")}>
          <p class="text-xs text-base-content/60">
            {gettext("Kept in this browser.")}
          </p>
          <%!-- The theme chosen marks its button through the attributes of
               <html> (see the root layout): no round trip to the server --%>
          <div class="mt-3 grid grid-cols-3 gap-2">
            <.choice
              id="theme-system"
              phx-click={JS.dispatch("phx:set-theme")}
              data-phx-theme="system"
              class="[[data-theme-source=system]_&]:border-base-content [[data-theme-source=system]_&]:bg-base-300"
            >
              <.icon name="hero-computer-desktop" class="size-5" /> {gettext("System")}
            </.choice>
            <.choice
              id="theme-light"
              phx-click={JS.dispatch("phx:set-theme")}
              data-phx-theme="light"
              class="[[data-theme-source=user][data-theme=light]_&]:border-base-content [[data-theme-source=user][data-theme=light]_&]:bg-base-300"
            >
              <.icon name="hero-sun" class="size-5" /> {gettext("Light")}
            </.choice>
            <.choice
              id="theme-dark"
              phx-click={JS.dispatch("phx:set-theme")}
              data-phx-theme="dark"
              class="[[data-theme-source=user][data-theme=dark]_&]:border-base-content [[data-theme-source=user][data-theme=dark]_&]:bg-base-300"
            >
              <.icon name="hero-moon" class="size-5" /> {gettext("Dark")}
            </.choice>
          </div>
        </.section>

        <.section id="preferences-account" title={gettext("Account")}>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs text-base-content/60">{gettext("Email address")}</p>
              <p id="account-email" class="truncate">{@current_user.email}</p>
            </div>
            <.link
              id="sign-out"
              href={~p"/sign-out"}
              method="delete"
              class="btn btn-sm border-base-content bg-base-100 transition-transform hover:-translate-y-px hover:bg-error hover:text-error-content"
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
              {gettext("Sign out")}
            </.link>
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby={"#{@id}-title"}
      class="border-t-2 border-dotted border-base-content/40 pt-4"
    >
      <h2 id={"#{@id}-title"} class="mb-1 text-sm uppercase">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  # A button among several, the one chosen marked: by `pressed`, or by its
  # `class` (the theme).
  attr :id, :string, required: true
  attr :pressed, :boolean, default: nil
  attr :class, :any, default: nil
  attr :type, :string, default: "button"
  attr :rest, :global, include: ~w(name value lang)
  slot :inner_block, required: true

  defp choice(assigns) do
    ~H"""
    <button
      id={@id}
      type={@type}
      aria-pressed={@pressed != nil && to_string(@pressed)}
      class={[
        "flex cursor-pointer items-center justify-center gap-2 border-2 px-3 py-2.5 text-sm transition",
        "hover:-translate-y-px hover:border-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-base-content",
        if(@pressed,
          do: "border-base-content bg-base-300 font-medium",
          else: "border-base-content/30 bg-base-100"
        ),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Preferences"))}
  end
end
