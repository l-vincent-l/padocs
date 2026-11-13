defmodule PadocsWeb.StaticChangedTest do
  # Changes the endpoint's config: not async.
  use PadocsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Padocs.Fixtures

  # The digested assets of the version running, as `mix phx.digest` lists
  # them in production.
  # The endpoint takes its whole config again on a change.
  setup do
    config = Application.fetch_env!(:padocs, PadocsWeb.Endpoint)

    latest = %{
      "assets/js/app.js" => "assets/js/app-new.js",
      "assets/css/app.css" => "assets/css/app-new.css"
    }

    PadocsWeb.Endpoint.config_change(
      [{PadocsWeb.Endpoint, Keyword.put(config, :cache_static_manifest_latest, latest)}],
      []
    )

    on_exit(fn -> PadocsWeb.Endpoint.config_change([{PadocsWeb.Endpoint, config}], []) end)

    user = Fixtures.confirmed_user()
    document = Fixtures.create_document!(user, %{title: "Notes"})
    %{conn: Fixtures.log_in(build_conn(), user), document: document}
  end

  defp open(conn, document, statics) do
    conn
    |> put_connect_params(%{"_track_static" => statics})
    |> live(~p"/documents/#{document.id}")
  end

  test "a page of an older version is told to reload", %{conn: conn, document: document} do
    {:ok, view, _html} =
      open(conn, document, [
        "http://localhost/assets/js/app-old.js",
        "http://localhost/assets/css/app-new.css"
      ])

    assert_push_event(view, "static-changed", %{})
  end

  test "a page of this version is not", %{conn: conn, document: document} do
    {:ok, view, _html} =
      open(conn, document, [
        "http://localhost/assets/js/app-new.js",
        "http://localhost/assets/css/app-new.css"
      ])

    refute_push_event(view, "static-changed", %{}, 100)
  end
end
