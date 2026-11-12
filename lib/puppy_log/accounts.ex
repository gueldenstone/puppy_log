defmodule PuppyLog.Accounts do
  use Ash.Domain, otp_app: :puppy_log, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource PuppyLog.Accounts.Token
    resource PuppyLog.Accounts.User
  end
end
