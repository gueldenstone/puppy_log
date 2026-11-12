defmodule PuppyLogWeb.PageController do
  use PuppyLogWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
