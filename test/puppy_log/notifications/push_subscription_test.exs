defmodule PuppyLog.Notifications.PushSubscriptionTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.Notifications

  setup do
    %{lukas: user_fixture(%{name: "Lukas"}), lisa: user_fixture(%{name: "Lisa"})}
  end

  test "subscribe stores the subscription for the actor", %{lukas: lukas} do
    {subscription, _keys} = subscription_fixture(lukas)

    assert subscription.user_id == lukas.id
    assert [%{id: id}] = Notifications.list_push_subscriptions!(actor: lukas)
    assert id == subscription.id
  end

  test "subscribing the same endpoint again updates instead of duplicating", %{
    lukas: lukas,
    lisa: lisa
  } do
    {subscription, _} = subscription_fixture(lukas)
    keys = browser_keys()

    {:ok, again} =
      Notifications.subscribe_push(
        %{endpoint: subscription.endpoint, p256dh: keys.p256dh, auth: keys.auth_b64},
        actor: lisa
      )

    assert again.id == subscription.id
    assert again.user_id == lisa.id
    assert again.p256dh == keys.p256dh
    assert length(Notifications.list_push_subscriptions!(actor: lisa)) == 1
  end

  test "subscribing requires a signed in user" do
    keys = browser_keys()

    assert {:error, _} =
             Notifications.subscribe_push(%{
               endpoint: "https://web.push.apple.com/x",
               p256dh: keys.p256dh,
               auth: keys.auth_b64
             })

    assert Notifications.list_push_subscriptions!(authorize?: false) == []
  end

  test "only the owner can unsubscribe a device", %{lukas: lukas, lisa: lisa} do
    {subscription, _} = subscription_fixture(lukas)

    assert {:error, _} = Notifications.unsubscribe_push(subscription.endpoint, actor: lisa)
    assert :ok = Notifications.unsubscribe_push(subscription.endpoint, actor: lukas)
    assert Notifications.list_push_subscriptions!(actor: lukas) == []
  end

  test "changes are broadcast for live updates", %{lukas: lukas} do
    PuppyLogWeb.Endpoint.subscribe("push_subscriptions:changed")
    subscription_fixture(lukas)

    assert_receive %Phoenix.Socket.Broadcast{topic: "push_subscriptions:changed"}
  end
end
