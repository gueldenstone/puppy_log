defmodule PuppyLog.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        PuppyLog.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:puppy_log, :token_signing_secret)
  end
end
