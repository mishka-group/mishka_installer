# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mishke_installer_developer,
  ecto_repos: [MishkeInstallerDeveloper.Repo]

# Configures the endpoint
config :mishke_installer_developer, MishkeInstallerDeveloperWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: MishkeInstallerDeveloperWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: MishkeInstallerDeveloper.PubSub,
  live_view: [signing_salt: "RMzIRry/"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :mishke_installer_developer, MishkeInstallerDeveloper.Mailer, adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, false

config :mishke_installer_developer, :basic,
  repo: MishkeInstallerDeveloper.Repo,
  pubsub: MishkeInstallerDeveloper.PubSub,
  html_router: MishkeInstallerDeveloperWeb.Router.Helpers

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.0",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason


# ueberauth config can delete in developer pkg
config :ueberauth, Ueberauth,
base_path: "/auth",
providers: [
  github: {Ueberauth.Strategy.Github, [default_scope: "read:user", send_redirect_uri: false]},
  google: {Ueberauth.Strategy.Google, [
     default_scope:
     "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"
   ]},
]

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
   client_id: System.get_env("GITHUB_CLIENT_ID"),
   client_secret: System.get_env("GITHUB_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
   client_id: System.get_env("GOOGLE_CLIENT_ID"),
   client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
   redirect_uri: System.get_env("GOOGLE_REDIRECT_URI")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
