defmodule PuppyLog.Fixtures do
  @moduledoc "Test data helpers."

  alias AshAuthentication.{Info, Strategy}
  alias AshAuthentication.Strategy.MagicLink
  alias PuppyLog.Accounts.User

  def user_fixture(attrs \\ %{}) do
    email = Map.get(attrs, :email, "user#{System.unique_integer([:positive])}@example.com")
    {:ok, user} = PuppyLog.Accounts.MagicLinks.create_user(email, Map.get(attrs, :name))
    user
  end

  @doc "Signs the user in via the magic link strategy, returns the user with a session token."
  def sign_in(user) do
    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for(strategy, user)
    {:ok, user} = Strategy.action(strategy, :sign_in, %{"token" => token})
    user
  end

  @doc """
  A fake browser push subscription. Keeps the private key so tests can decrypt
  what the server sent.
  """
  def browser_keys do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)
    auth = :crypto.strong_rand_bytes(16)

    %{
      public: public,
      private: private,
      auth: auth,
      p256dh: Base.url_encode64(public, padding: false),
      auth_b64: Base.url_encode64(auth, padding: false)
    }
  end

  def subscription_fixture(user, attrs \\ %{}) do
    keys = browser_keys()

    {:ok, subscription} =
      PuppyLog.Notifications.subscribe_push(
        Map.merge(
          %{
            endpoint: "https://web.push.apple.com/#{System.unique_integer([:positive])}",
            p256dh: keys.p256dh,
            auth: keys.auth_b64,
            user_agent:
              "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15"
          },
          attrs
        ),
        actor: user
      )

    {subscription, keys}
  end

  @doc "Decrypts an RFC 8291 aes128gcm body the way a browser would."
  def decrypt_push(body, keys) do
    <<salt::binary-16, _rs::32, idlen, as_public::binary-size(idlen), ciphertext::binary>> = body

    ecdh_secret = :crypto.compute_key(:ecdh, as_public, keys.private, :prime256v1)
    prk_key = :crypto.mac(:hmac, :sha256, keys.auth, ecdh_secret)
    key_info = "WebPush: info" <> <<0>> <> keys.public <> as_public
    ikm = :crypto.macN(:hmac, :sha256, prk_key, key_info <> <<1>>, 32)
    prk = :crypto.mac(:hmac, :sha256, salt, ikm)
    cek = :crypto.macN(:hmac, :sha256, prk, "Content-Encoding: aes128gcm" <> <<0, 1>>, 16)
    nonce = :crypto.macN(:hmac, :sha256, prk, "Content-Encoding: nonce" <> <<0, 1>>, 12)

    tag_size = 16
    data_size = byte_size(ciphertext) - tag_size
    <<data::binary-size(^data_size), tag::binary-size(^tag_size)>> = ciphertext

    plaintext = :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, data, <<>>, tag, false)

    # single record: payload followed by the last-record delimiter 0x02
    payload_size = byte_size(plaintext) - 1
    <<payload::binary-size(^payload_size), 2>> = plaintext
    payload
  end
end
