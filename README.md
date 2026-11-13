# PuppyLog

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## What the app does

A mobile-first LiveView PWA for one household and its puppy, used from the iPhone home screen.
The UI is German, code and URLs are English. Design reference: `docs/design/DESIGN.md`.

* „Heute“ (`/`): today's routines with live state on every phone, quick buttons to log events.
* „Verlauf“ (`/history`): adherence and house-training statistics over a chosen period, and a day
  view (`/history/:date`) to correct past days.
* „Gesundheit“ (`/health`): weight curve; profile (`/profile`) with the puppy's arrival date.
* „Haushalt & Mitteilungen“ (`/settings`): who gets reminders, quiet hours, push on this device.

## Household members and sign-in

There is no self sign-up. Create members and hand out single-use sign-in links (valid 24 hours):

    mix puppy_log.user.create lisa@example.com --name Lisa
    mix puppy_log.magic_link lisa@example.com --base-url https://puppy.example.com

In a release use `bin/puppy_log rpc 'PuppyLog.Accounts.MagicLinks.print("lisa@example.com")'`.
Web Push needs a stable VAPID key pair: generate it once with `mix puppy_log.gen.vapid` and set
`VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` and `VAPID_SUBJECT` in production.

## Routines and reminders

Routines (`/routines`) are the puppy's daily schedule, domain `PuppyLog.Daily`:

* A routine has a name, a kind (what fulfils it: „Lösen“, „Mahlzeit“, „Gassi“, „Schlaf“, „Spiel“,
  „Training“ or „Nur abhaken“), a fixed time or a time window, weekdays, an optional assignee,
  a reminder switch and an optional follow-up after N minutes.
* Routines can be set up before the puppy arrives. Each day's occurrences are planned from the
  arrival date in the profile on (and from the day a routine was created), so history keeps the
  plan each day had even when a routine is edited or archived later.
* An occurrence is open, done, skipped or missed. Done within 15 minutes of the planned time (or
  the window) counts as kept; the exact deviation in minutes is stored for the statistics.
* Logged events (pee/poo, meal, walk, …) fulfil a matching open routine automatically within
  ±15 minutes; otherwise the form offers the day's open matching routines. An accident inside
  never fulfils a routine.

Reminders are sent by `PuppyLog.Daily.Reminders`, a process that ticks once a minute:

* At the planned time (window start) every member whose reminder switch is on in `/settings` gets
  a Web Push on each subscribed device; an optional follow-up goes out after the routine's
  follow-up minutes (counted from the window end for window routines) if it is still open.
  Tapping a push opens the routine's sheet (`/routine/<id>`). Editing a routine's time or reminder
  settings after its reminder makes it due again at the new time.
* When someone ticks off or skips the routine, the others' notification is replaced (same tag) by
  a short one: title „Pipi-Runde erledigt ✓“, body „Riv, 07:05“ (or „… übersprungen“). Editing
  the event that ticked it off sends nothing new.
* Quiet hours (household-wide, set in `/settings`) suppress reminders, follow-ups and these
  done/skipped notices. They are dropped, not sent afterwards; corrections of days before
  yesterday notify nobody.

The process only runs when enabled:

    # config/config.exs (on by default), config/test.exs sets it to false
    config :puppy_log, PuppyLog.Daily.Reminders, enabled: true

Tests call `PuppyLog.Daily.Reminders.tick/1` directly and send done notifications inline
(`config :puppy_log, PuppyLog.Daily.Notify, async: false`).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
