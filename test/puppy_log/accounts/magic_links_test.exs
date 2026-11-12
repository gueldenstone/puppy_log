defmodule PuppyLog.Accounts.MagicLinksTest do
  use PuppyLog.DataCase, async: false

  alias AshAuthentication.{Info, Strategy}
  alias PuppyLog.Accounts.{MagicLinks, User}

  test "creates users and generates a link that signs them in" do
    {:ok, user} = MagicLinks.create_user("lisa@example.com", "Lisa")
    assert user.name == "Lisa"

    {:ok, url} = MagicLinks.url_for("lisa@example.com", "https://puppy.example.com/")
    assert "https://puppy.example.com/magic_link/" <> token = url

    strategy = Info.strategy!(User, :magic_link)
    assert {:ok, signed_in} = Strategy.action(strategy, :sign_in, %{"token" => token})
    assert signed_in.id == user.id
  end

  test "links are single use" do
    {:ok, _user} = MagicLinks.create_user("lisa@example.com")
    {:ok, url} = MagicLinks.url_for("lisa@example.com")
    [_, token] = String.split(url, "/magic_link/")

    strategy = Info.strategy!(User, :magic_link)
    assert {:ok, _} = Strategy.action(strategy, :sign_in, %{"token" => token})
    assert {:error, _} = Strategy.action(strategy, :sign_in, %{"token" => token})
  end

  test "unknown e-mail addresses get no link" do
    assert {:error, _} = MagicLinks.url_for("nobody@example.com")
  end

  test "there is no self registration" do
    strategy = Info.strategy!(User, :magic_link)
    refute strategy.registration_enabled?

    {:ok, token} =
      AshAuthentication.Strategy.MagicLink.request_token_for_identity(strategy, "new@example.com")

    assert {:error, _} = Strategy.action(strategy, :sign_in, %{"token" => token})
    assert {:error, _} = PuppyLog.Accounts.get_user_by_email("new@example.com", authorize?: false)
  end
end
