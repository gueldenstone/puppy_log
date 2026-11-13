defmodule PuppyLog.Notifications.PushTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.Notifications
  alias PuppyLog.Notifications.Push

  import ExUnit.CaptureLog

  setup do
    %{lukas: user_fixture(%{name: "Lukas"}), lisa: user_fixture(%{name: "Lisa"})}
  end

  test "sends an RFC 8291 encrypted, VAPID signed request", %{lukas: lukas} do
    {subscription, keys} = subscription_fixture(lukas)
    test_pid = self()

    Req.Test.stub(Push, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:push, conn, body})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    assert :ok = Push.deliver(subscription, %{title: "Hallo", body: "Gassi!"})

    assert_receive {:push, conn, body}
    assert conn.request_path == URI.parse(subscription.endpoint).path
    assert Plug.Conn.get_req_header(conn, "urgency") == ["high"]
    assert [ttl] = Plug.Conn.get_req_header(conn, "ttl")
    assert String.to_integer(ttl) > 0

    assert ["vapid t=" <> rest] = Plug.Conn.get_req_header(conn, "authorization")
    [jwt, "k=" <> public_key] = String.split(rest, ", ")
    assert public_key == Application.fetch_env!(:web_push_ex, :vapid)[:public_key]

    claims = jwt |> JOSE.JWT.peek_payload() |> Map.fetch!(:fields)
    assert claims["aud"] == "https://web.push.apple.com"
    assert claims["sub"] =~ ~r/^mailto:/

    assert body |> decrypt_push(keys) |> Jason.decode!() == %{
             "title" => "Hallo",
             "body" => "Gassi!"
           }
  end

  # Req's test adapter strips request content-encoding before calling the
  # plug, so check the header on the request as it leaves our code.
  test "marks the body as aes128gcm", %{lukas: lukas} do
    {subscription, _keys} = subscription_fixture(lukas)
    request = Push.build_request(subscription, %{title: "x"})

    assert Req.Request.get_header(request, "content-encoding") == ["aes128gcm"]
    assert request.method == :post
  end

  test "removes subscriptions the push service reports as gone", %{lukas: lukas} do
    {subscription, _keys} = subscription_fixture(lukas)
    Req.Test.stub(Push, &Plug.Conn.send_resp(&1, 410, ""))

    assert {:error, :expired} = Push.deliver(subscription, %{title: "x"})
    assert Notifications.list_push_subscriptions!(actor: lukas) == []
  end

  test "reports other HTTP errors with status and body", %{lukas: lukas} do
    {subscription, _keys} = subscription_fixture(lukas)
    Req.Test.stub(Push, &Req.Test.json(Plug.Conn.put_status(&1, 403), %{reason: "BadJwtToken"}))

    {result, log} = with_log(fn -> Push.deliver(subscription, %{title: "x"}) end)

    assert {:error, {:http_error, 403, %{"reason" => "BadJwtToken"}}} = result
    assert log =~ "Push to #{subscription.id} failed with HTTP 403"

    assert length(Notifications.list_push_subscriptions!(actor: lukas)) == 1
  end

  test "reports transport errors", %{lukas: lukas} do
    {subscription, _keys} = subscription_fixture(lukas)
    Req.Test.stub(Push, &Req.Test.transport_error(&1, :econnrefused))

    {result, log} = with_log(fn -> Push.deliver(subscription, %{title: "x"}) end)

    assert {:error, %Req.TransportError{reason: :econnrefused}} = result
    assert log =~ "Push to #{subscription.id} failed: connection refused"
  end

  describe "send_test" do
    setup %{lukas: lukas, lisa: lisa} do
      {mine, _} = subscription_fixture(lukas)
      {theirs, _} = subscription_fixture(lisa)
      test_pid = self()

      Req.Test.stub(Push, fn conn ->
        send(test_pid, {:pushed, conn.request_path})
        Plug.Conn.send_resp(conn, 201, "")
      end)

      %{mine: mine, theirs: theirs}
    end

    test "to :me only reaches the actor's devices", %{lukas: lukas, mine: mine} do
      assert {:ok, %{sent: 1, results: [%{user: "Lukas", result: :ok}]}} =
               Notifications.send_test_push(:me, actor: lukas)

      assert_received {:pushed, path}
      assert path == URI.parse(mine.endpoint).path
      refute_received {:pushed, _}
    end

    test "to :all reaches every device of the household", %{lukas: lukas} do
      assert {:ok, %{sent: 2}} = Notifications.send_test_push(:all, actor: lukas)
    end

    test "requires a signed in user" do
      assert {:error, %Ash.Error.Forbidden{}} = Notifications.send_test_push(:all)
    end
  end
end
