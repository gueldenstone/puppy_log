defmodule PuppyLog.Accounts do
  use Ash.Domain, otp_app: :puppy_log, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource PuppyLog.Accounts.Token

    resource PuppyLog.Accounts.User do
      define :create_user, action: :create, args: [:email]
      define :get_user_by_email, action: :get_by_email, args: [:email]
      define :list_users, action: :read
    end
  end
end
