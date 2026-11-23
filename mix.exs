defmodule Padocs.MixProject do
  use Mix.Project

  def project do
    [
      app: :padocs,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev,
      # The files of the messages, without line numbers: they change only
      # when the messages do (see the precommit alias)
      gettext: [write_reference_line_numbers: false]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Padocs.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # The search index: a fork of tantivy_ex (Searcher.snippet/5 among
      # others), its NIF downloaded precompiled from the fork's releases, as
      # are those of Yex and Typst: no Rust needed. TANTIVY_EX_BUILD=1 builds
      # it from source (Rust 1.91 or later).
      {:tantivy_ex, github: "l-vincent-l/tantivy_ex"},
      # PDF export: Typst, as a precompiled NIF (see Padocs.Document.pdf/1)
      {:typst, "0.4.6"},
      # {:tantivy_ex, path: "../tantivy_ex"},
      {:y_ex, "~> 0.13.0"},
      {:bcrypt_elixir, "~> 3.0"},
      # Sign-in with GitHub and GitLab (OAuth 2, OpenID Connect).
      {:assent, "~> 0.4.0"},
      {:ecto_hrana, github: "l-vincent-l/ecto_hrana"},
      {:phoenix, "~> 1.8.15"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:phoenix_html, "~> 4.4"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      # Load tests (loadtest/README.md)
      {:stampede, "~> 1.4", only: :dev, runtime: false},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.8.1",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.1"},
      {:bandit, "~> 1.5"},
      {:syn, "== 3.4.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind padocs", "esbuild padocs"],
      "assets.deploy": [
        "tailwind padocs --minify",
        "esbuild padocs --minify",
        "phx.digest"
      ],
      precommit: [
        # --force: after a change of mix.exs or mix.lock, an incremental
        # compile warns that the Inspect protocol is already consolidated
        # (Padocs.Accounts.User), a warning a full one does not give
        "compile --force --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        # a message added or changed must be extracted and translated
        "gettext.extract --check-up-to-date",
        "test",
        # the JavaScript of the imports (assets/test)
        "cmd npm test --prefix assets"
      ]
    ]
  end
end
