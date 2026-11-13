defmodule PadocsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PadocsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the signed-in user, if any"

  attr :full_width, :boolean,
    default: false,
    doc: "when true, the content spans the whole page instead of a centered column"

  attr :sidebar, :boolean,
    default: false,
    doc:
      "when true, the page has no header: its sidebar holds the logo (`logo/1`) and the account controls (`account/1`)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header
      :if={!@sidebar}
      class="navbar h-14 min-h-14 border-b-2 border-base-content px-4 sm:px-6 lg:px-8"
    >
      <div class="flex-1">
        <.logo />
      </div>
      <div class="flex-none">
        <ul class="flex items-center gap-4 text-sm">
          <%!-- Signed in, the rest is in the preferences --%>
          <li :if={@current_user}>
            <.link
              id="header-preferences-link"
              navigate={~p"/preferences"}
              title={gettext("Preferences")}
              class="flex items-center gap-1.5 hover:underline"
            >
              <span class="hidden sm:inline">{@current_user.email}</span>
              <.icon name="hero-cog-6-tooth" class="size-4" />
              <span class="sr-only">{gettext("Preferences")}</span>
            </.link>
          </li>
          <li :if={!@current_user}>
            <.link href={~p"/sign-in"} class="link">{gettext("Sign in")}</.link>
          </li>
          <li :if={!@current_user}>
            <.locale_switch />
          </li>
          <li :if={!@current_user}>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main :if={@full_width} class="flex-1">
      {render_slot(@inner_block)}
    </main>

    <main :if={!@full_width} class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc "The site's name, linking to the documents."
  attr :class, :any, default: nil

  def logo(assigns) do
    ~H"""
    <.link
      id="documents-link"
      navigate={~p"/documents"}
      class={[
        "font-pixel text-base uppercase tracking-wide no-underline hover:underline hover:decoration-dotted",
        @class
      ]}
    >
      padocs
    </.link>
    """
  end

  @doc """
  The account at the bottom of a page's sidebar: the user's email, leading
  to their preferences (language, theme, signing out, see
  `PadocsWeb.PreferencesLive`). See the `sidebar` attribute of `app/1`.
  """
  attr :current_user, :map, required: true

  def account(assigns) do
    ~H"""
    <div id="account" class="mt-auto border-t-2 border-dotted border-base-content/40 pt-4 text-sm">
      <.link
        id="preferences-link"
        navigate={~p"/preferences"}
        title={gettext("Preferences")}
        class="group -mx-2 flex items-center gap-2 px-2 py-1.5 transition-colors hover:bg-base-200"
      >
        <span class="min-w-0 flex-1 truncate">{@current_user.email}</span>
        <.icon
          name="hero-cog-6-tooth"
          class="size-4 shrink-0 text-base-content/60 transition-transform duration-300 group-hover:rotate-45 group-hover:text-base-content"
        />
        <span class="sr-only">{gettext("Preferences")}</span>
      </.link>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  The languages of the interface, the current one marked: a choice posts it
  to `PadocsWeb.LocaleController`, which keeps it and reloads the page.
  """
  def locale_switch(assigns) do
    assigns = assign(assigns, :current, Gettext.get_locale(PadocsWeb.Gettext))

    ~H"""
    <form
      id="locale-switch"
      action={~p"/locale"}
      method="post"
      class="flex border-2 border-base-content text-xs"
      aria-label={gettext("Language")}
    >
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <button
        :for={{locale, label, name} <- [{"fr", "FR", "Français"}, {"en", "EN", "English"}]}
        id={"locale-#{locale}"}
        type="submit"
        name="locale"
        value={locale}
        lang={locale}
        title={name}
        aria-pressed={to_string(locale == @current)}
        class={[
          "cursor-pointer px-1.5 py-1 font-medium transition-colors",
          if(locale == @current,
            do: "bg-base-300",
            else: "text-base-content/60 hover:bg-base-200 hover:text-base-content"
          )
        ]}
      >
        {label}
      </button>
    </form>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center border-2 border-base-content">
      <div class="absolute h-full w-1/3 bg-base-300 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="relative flex w-1/3 cursor-pointer p-1.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label={gettext("System theme")}
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="relative flex w-1/3 cursor-pointer p-1.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label={gettext("Light theme")}
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="relative flex w-1/3 cursor-pointer p-1.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label={gettext("Dark theme")}
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
