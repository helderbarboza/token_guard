defmodule TokenGuardWeb.Router do
  use TokenGuardWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TokenGuardWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TokenGuardWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", TokenGuardWeb.API do
    pipe_through :api

    post "/tokens/register", TokenController, :activate
    get "/tokens", TokenController, :index
    get "/tokens/:id", TokenController, :show
    get "/tokens/:id/history", TokenController, :history
    delete "/tokens/active", TokenController, :clear
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:token_guard, :dev_routes) do
    import Phoenix.LiveDashboard.Router
    import Oban.Web.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TokenGuardWeb.Telemetry
      oban_dashboard("/oban")
    end
  end
end
