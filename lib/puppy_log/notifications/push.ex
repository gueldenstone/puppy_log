defmodule PuppyLog.Notifications.Push do
  @moduledoc """
  Delivers Web Push messages (RFC 8291 `aes128gcm`, RFC 8292 VAPID).

  The payload is JSON and interpreted by `priv/static/sw.js`:

    * `title`, `body` - notification texts
    * `tag` - notifications with the same tag replace each other
    * `url` - path to open when the notification is tapped

  Subscriptions the push service reports as gone (404/410) are deleted.
  """

  require Logger

  alias PuppyLog.Notifications.PushSubscription

  @type result :: :ok | {:error, :expired | {:http_error, integer, term} | Exception.t()}

  @spec deliver(PushSubscription.t() | Ash.Resource.record(), map, keyword) :: result
  def deliver(%PushSubscription{} = subscription, payload, opts \\ []) when is_map(payload) do
    subscription
    |> build_request(payload, opts)
    |> Req.request()
    |> handle_response(subscription)
  end

  @doc "Builds the encrypted push request without sending it."
  @spec build_request(PushSubscription.t(), map, keyword) :: Req.Request.t()
  def build_request(%PushSubscription{} = subscription, payload, opts \\ []) do
    request =
      WebPushEx.request(
        %WebPushEx.Subscription{
          endpoint: URI.parse(subscription.endpoint),
          keys: %{p256dh: subscription.p256dh, auth: subscription.auth}
        },
        Jason.encode!(payload)
      )

    headers =
      request.headers
      # Req/Finch compute the length themselves; a duplicate header gets rejected.
      |> Map.delete("Content-Length")
      |> Map.put("Urgency", opts |> Keyword.get(:urgency, :high) |> to_string())
      |> Map.put("TTL", opts |> Keyword.get(:ttl, 60 * 60) |> to_string())

    [method: :post, url: URI.to_string(request.endpoint), body: request.body, headers: headers]
    |> Keyword.merge(req_options())
    |> Req.new()
  end

  defp handle_response({:ok, %Req.Response{status: status}}, _subscription)
       when status in 200..299,
       do: :ok

  defp handle_response({:ok, %Req.Response{status: status}}, subscription)
       when status in [404, 410] do
    Logger.info("Push subscription #{subscription.id} is gone (#{status}), removing it")
    Ash.destroy!(subscription, action: :expire, authorize?: false)
    {:error, :expired}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}, subscription) do
    Logger.warning("Push to #{subscription.id} failed with HTTP #{status}: #{inspect(body)}")
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, exception}, subscription) do
    Logger.warning("Push to #{subscription.id} failed: #{Exception.message(exception)}")
    {:error, exception}
  end

  defp req_options do
    :puppy_log
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_options, [])
  end
end
