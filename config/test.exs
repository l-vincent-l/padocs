import Config
config :bcrypt_elixir, log_rounds: 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :textexp, Textexp.SqliteRepo,
  database: Path.join(__DIR__, "../base_tests.sqlite"),
  pool: Ecto.Adapters.SQL.Sandbox,
  # One connection: SQLite has one writer at a time. With several, a test
  # could write through one while the previous test's transaction, rolled back
  # asynchronously when it ends, still held another: "Database busy". The
  # tests using the database are not async and share the connection of the
  # running test (see DataCase), so one is enough.
  pool_size: 1

# The files of the documents (see Textexp.Files), in a folder of the system's
# temporary directory.
config :textexp, Textexp.Files,
  storage: {Textexp.Files.LocalStorage, root: Path.join(System.tmp_dir!(), "textexp_test_files")}

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :textexp, TextexpWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "JBFk8hfb/qYj10QxGt83pWM7p5qndA2GtF4GZ9EMjm0Kr51M+xUXszTzAFpGVdHd",
  server: false

# In test we don't send emails
config :textexp, Textexp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# No database when the application starts, in the tests: the search index
# starts empty, the tests' documents are indexed as they change.
config :textexp, Textexp.Document.SearchIndex, build: false
