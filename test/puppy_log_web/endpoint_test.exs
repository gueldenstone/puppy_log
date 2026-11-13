defmodule PuppyLogWeb.EndpointTest do
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 2]

  alias PuppyLogWeb.Endpoint

  describe "log_level/1" do
    test "keeps the calendar feed (secret token in the path) out of the request log" do
      assert Endpoint.log_level(conn(:get, "/calendar/secret-token.ics")) == false
    end

    test "logs other requests at info" do
      assert Endpoint.log_level(conn(:get, "/settings")) == :info
      assert Endpoint.log_level(conn(:get, "/")) == :info
    end
  end
end
