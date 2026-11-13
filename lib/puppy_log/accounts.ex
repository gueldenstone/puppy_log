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
      define :set_reminders, action: :set_reminders
      define :rotate_calendar_token, action: :rotate_calendar_token

      define :get_user_by_calendar_token,
        action: :by_calendar_token,
        args: [:token],
        not_found_error?: false
    end
  end
end
