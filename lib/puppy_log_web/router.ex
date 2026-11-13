defmodule PuppyLogWeb.Router do
  use PuppyLogWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PuppyLogWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Restores the session from the long-lived cookie (PWA stays signed in)
    plug :sign_in_with_remember_me
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", PuppyLogWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # Each LiveView declares its own on_mount from PuppyLogWeb.LiveUserAuth
      live "/", TodayLive, :index
      live "/routine/:id", TodayLive, :routine
      live "/log", TodayLive, :log
      live "/history", PlaceholderLive, :history
      live "/health", HealthLive
      live "/learn", PlaceholderLive, :learn

      live "/profile", ProfileLive
      live "/profile/edit", ProfileFormLive

      live "/weight", WeightLive, :index
      live "/weight/new", WeightLive, :new
      live "/weight/:id", WeightLive, :edit

      live "/settings", SettingsLive

      live "/sign-in", SignInLive
      live "/magic_link/:token", MagicLinkLive
    end

    get "/uploads/:name", UploadController, :show

    auth_routes AuthController, PuppyLog.Accounts.User, path: "/auth"
    sign_out_route AuthController, "/sign-out"
  end

  # Other scopes may use custom stacks.
  # scope "/api", PuppyLogWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:puppy_log, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PuppyLogWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  if Application.compile_env(:puppy_log, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
