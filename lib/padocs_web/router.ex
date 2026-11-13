defmodule PadocsWeb.Router do
  use PadocsWeb, :router

  import PadocsWeb.UserAuth, only: [fetch_current_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PadocsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug PadocsWeb.Locale
  end

  # The files of the documents (see FileController): the session and its
  # CSRF token, but neither HTML nor layout.
  pipeline :files do
    plug :fetch_session
    plug :protect_from_forgery
    plug :fetch_current_user
    plug PadocsWeb.Locale
  end

  pipeline :dashboard do
    plug :dashboard_auth
  end

  scope "/", PadocsWeb do
    pipe_through :browser

    # Each LiveView requires a signed-in user (see LiveUserAuth).
    # A page out of date after a deploy is reloaded (see StaticChanged).
    live_session :authenticated_routes,
      on_mount: [
        {PadocsWeb.LiveUserAuth, :current_user},
        PadocsWeb.Locale,
        PadocsWeb.StaticChanged
      ] do
      live "/documents", DocumentLive, :index
      live "/documents/:id", DocumentLive, :show
    end

    # A document read by its public link, signed in or not
    live_session :public_routes,
      on_mount: [
        {PadocsWeb.LiveUserAuth, :current_user},
        PadocsWeb.Locale,
        PadocsWeb.StaticChanged
      ] do
      live "/p/:token", PublicDocumentLive, :show
    end

    # A document as a file: PDF, Markdown or Typst (see ExportController)
    get "/documents/:id/export/:format", ExportController, :show
  end

  scope "/", PadocsWeb do
    pipe_through :files

    post "/files", FileController, :create
    post "/documents/:id/files", FileController, :create
    get "/files/:id", FileController, :show
  end

  scope "/", PadocsWeb do
    pipe_through :browser

    get "/", PageController, :home

    # The language of the interface (see PadocsWeb.Locale)
    post "/locale", LocaleController, :update

    get "/sign-in", AuthController, :sign_in
    post "/sign-in", AuthController, :create_session
    get "/register", AuthController, :register
    post "/register", AuthController, :create_user
    post "/magic-link", AuthController, :request_magic_link
    get "/magic_link/:token", AuthController, :magic_link
    post "/magic_link/:token", AuthController, :sign_in_with_magic_link
    get "/reset", AuthController, :reset
    post "/reset", AuthController, :request_reset
    get "/password-reset/:token", AuthController, :edit_password
    post "/password-reset/:token", AuthController, :reset_password
    get "/confirm_new_user/:token", AuthController, :confirm
    post "/confirm_new_user/:token", AuthController, :confirm_user
    delete "/sign-out", AuthController, :sign_out

    # The callback URLs of the OAuth applications on GitHub and GitLab.
    get "/auth/user/:provider", OAuthController, :authorize
    get "/auth/user/:provider/callback", OAuthController, :callback
  end

  # The LiveDashboard, also in production to look into the running app (memory,
  # processes), behind HTTP basic auth (see dashboard_auth/2).
  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through [:browser, :dashboard]

    live_dashboard "/dashboard", metrics: PadocsWeb.Telemetry
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:padocs, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Asks for the credentials of the :dashboard_auth config. Without them (e.g.
  # unset in production), the dashboard is not found; with `false`, it is open.
  defp dashboard_auth(conn, _opts) do
    case Application.get_env(:padocs, :dashboard_auth) do
      false ->
        conn

      [username: username, password: password]
      when is_binary(username) and username != "" and is_binary(password) and password != "" ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      _missing ->
        conn |> send_resp(:not_found, "Not Found") |> halt()
    end
  end
end
