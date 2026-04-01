defmodule TokenGuardWeb.PageController do
  use TokenGuardWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
