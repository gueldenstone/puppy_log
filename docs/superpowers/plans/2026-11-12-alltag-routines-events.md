# Alltag (Routines and Events) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Self-made daily routines with live tick-off, events that fulfil routines, reminders with quiet hours, and a history with adherence and house-training statistics.

**Architecture:** New Ash domain `PuppyLog.Daily` with `Routine` (the plan), `Occurrence` (one routine on one day, a snapshot of the plan plus its outcome), `Event` (what happened) and `Settings` (quiet hours). Pure modules hold the rules (`Matching`, `Stats`), a minute-ticking GenServer sends reminders. LiveViews reuse `PuppyLogWeb.UI`; Ash resource lists go through Cinder.

**Tech Stack:** Elixir, Phoenix LiveView 1.2, Ash 3 + AshSqlite, Cinder 0.18, web_push_ex via `PuppyLog.Notifications`, tz (Europe/Berlin).

**Spec:** `docs/superpowers/specs/2026-11-12-alltag-routines-events-design.md`

## Global Constraints

- All URL paths and query parameters are English (user decision 2026-11-13): `/history`, `/health`, `/learn`, `/profile`, `/profile/edit`, `/weight`, `/settings`, `/log?type=pee|poo|meal|walk`, `/routines`, `/routines/new`; UI texts stay German.

- UI text German; code, comments, test names, commit messages English.
- Every created record stores its creator via `change relate_actor(...)`; no "who" field in forms.
- All wall-clock logic in Europe/Berlin through `PuppyLog.Clock`; never `Date.utc_today/0`.
- Tolerance: **15 minutes** before and after (window: both edges). Quick time choices: **Jetzt, vor 15 Min, vor 20 Min, vor 30 Min, Uhrzeit**.
- History periods: **1, 2, 4 weeks; 2, 4, 6 months; 1 year**, rolling, ending today.
- Policies household-wide: `authorize_if actor_present()`; internal jobs use `authorize?: false`.
- Migrations via `mix ash.codegen <name>` (never hand-written); resources added to `ash_domains` in `config/config.exs`.
- PubSub notifiers (`module PuppyLogWeb.Endpoint`, event `"changed"`) on every resource the UI shows.
- UI built from `PuppyLogWeb.UI` (`card`, `chip`, `progress`, `sheet`, `swipe_row`, `swipe_action`, `top_bar`, `page_title`, `action_button`, `empty_state`, `pl_icon`) and core `<.input>`; lists of Ash resources via `Cinder.collection` with `layout={:list}`.
- Each task ends with `mix precommit` green and a commit whose message ends with the two trailer lines
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01KsLYod5k7ufJq8gXoe1hbS`.

## Review Focus

1. **Local day boundary:** an event at 00:10 Berlin time belongs to that local day, not the previous UTC day (test in Task 5).
2. **DST:** a routine at 02:30 on the spring-forward day (29 Mar 2026) must not crash planning or reminders; it is treated as 03:30 (test in Task 4).
3. **Quiet hours across midnight** (22:00–06:30): reminders at 23:00 and 05:00 suppressed, 07:00 sent (test in Task 6).
4. **Two phones tick the same routine at once:** the second gets „Schon erledigt“, no second completion, no second notification (test in Task 4).
5. **Restart / duplicate ticks:** a reminder is never sent twice and never more than 10 minutes late (test in Task 6).

---

### Task 1: Arrival date on the puppy profile

**Files:**
- Modify: `lib/puppy_log/puppy/profile.ex` (attribute + accept lists)
- Modify: `lib/puppy_log_web/live/profile_form_live.ex`, `lib/puppy_log_web/live/profile_live.ex`
- Test: `test/puppy_log/puppy/profile_test.exs`, `test/puppy_log_web/live/profile_live_test.exs`
- Migration: `mix ash.codegen add_arrival_date`

**Interfaces:**
- Produces: `Profile.arrival_date :: Date.t() | nil` (public, accepted in `:create` and `:update`). Later tasks read it via `PuppyLog.Puppy.get_profile!(actor: actor)`.

- [ ] **Step 1: Failing tests**
  - `profile_test.exs` "stores the arrival date": create with `arrival_date: ~D[2026-12-01]` → `profile.arrival_date == ~D[2026-12-01]`.
  - `profile_live_test.exs` "edits the arrival date": submit `form: %{arrival_date: "2026-12-01"}` on `/profil/bearbeiten`; profile page shows `"Eingezogen am 1. Dezember 2026"`; without arrival date it shows `"Einzug noch nicht eingetragen"`.
- [ ] **Step 2:** `mix test test/puppy_log/puppy/profile_test.exs test/puppy_log_web/live/profile_live_test.exs` → FAIL (unknown attribute).
- [ ] **Step 3:** Add `attribute :arrival_date, :date, public?: true` (description "Day the puppy moved in; routines count from here"), add to both accept lists, run `mix ash.codegen add_arrival_date && mix ash.migrate`. Form field `<.input type="date" label="Einzug" />` with hint „Ab diesem Tag zählen Routinen und Erinnerungen.“ below Geburtsdatum. Profile page: extra `<dl>` row „Einzug“.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add arrival date to the puppy profile`.

### Task 2: Daily domain, routines, household settings, reminder switch

**Files:**
- Create: `lib/puppy_log/daily.ex`, `lib/puppy_log/daily/routine.ex`, `lib/puppy_log/daily/settings.ex`
- Modify: `lib/puppy_log/accounts/user.ex`, `lib/puppy_log/accounts.ex`, `config/config.exs` (`ash_domains`)
- Test: `test/puppy_log/daily/routine_test.exs`, `test/puppy_log/daily/settings_test.exs`
- Migration: `mix ash.codegen add_routines_and_daily_settings`

**Interfaces:**
- Produces (domain `PuppyLog.Daily` code interface):
  - `list_routines(opts) :: [Routine]` — action `:active` (archived_at is nil), sorted by `starts_at`.
  - `get_routine(id, opts)`, `create_routine(attrs, opts)`, `update_routine(routine, attrs, opts)`, `archive_routine(routine, opts)` (update action setting `archived_at`).
  - `settings(opts) :: Settings.t()` — stored singleton or an unsaved `%Settings{}` with defaults; `save_settings(attrs, opts)` — create with upsert on identity `:only_one`.
- `Routine` attributes: `name` (string, 1..60, trim), `kind` atom one_of `[:potty, :meal, :walk, :sleep, :play, :training, :manual]`, `starts_at :time`, `ends_at :time | nil` (nil = fixed time, otherwise window), `weekdays {:array, :integer}` (1 = Monday … 7 = Sunday, non-empty, values 1..7, default all), `assignee_id` (belongs_to User, nullable, nilify on delete), `remind? :boolean` default true, `follow_up_minutes :integer | nil` (5..240), `archived_at :utc_datetime_usec | nil`, `created_by`, timestamps. Validation: `ends_at > starts_at` when present (message „muss nach dem Beginn liegen“) — windows never cross midnight.
- `Settings` (table `daily_settings`, singleton like `Profile`): `quiet_hours_enabled` (default false), `quiet_from :time` (default ~T[22:00:00]), `quiet_until :time` (default ~T[06:30:00]).
- `User.receives_reminders :boolean` default true, public; update action `:set_reminders` (accept `[:receives_reminders]`, policy actor_present); `Accounts.set_reminders(user, %{receives_reminders: bool}, opts)`.
- PubSub prefixes: `"routines"`, `"daily_settings"`, `"users"` with event `"changed"`.

- [ ] **Step 1: Failing tests** in `routine_test.exs`:
  - "creates a window routine with assignee and creator": `create_routine(%{name: "Mittagsschlaf", kind: :sleep, starts_at: ~T[12:30:00], ends_at: ~T[14:00:00], weekdays: [1,2,3,4,5], assignee_id: riv.id}, actor: lukas)` → fields match, `created_by_id == lukas.id`.
  - "rejects a window ending before it starts": `ends_at: ~T[12:00:00]` with `starts_at: ~T[12:30:00]` → `{:error, %Ash.Error.Invalid{}}` with error on `:ends_at`.
  - "rejects empty or invalid weekdays": `weekdays: []` and `[0, 8]` → errors.
  - "archived routines disappear from the active list": archive → `list_routines(actor: lukas) == []`, record still readable via `get_routine`.
  - "requires a signed in user": create without actor → `{:error, _}`.
  `settings_test.exs`: defaults without a row (`quiet_hours_enabled == false`, `quiet_from == ~T[22:00:00]`), `save_settings` twice keeps one row, `set_reminders(riv, %{receives_reminders: false}, actor: lukas)` works.
- [ ] **Step 2:** Run tests → FAIL (module missing).
- [ ] **Step 3:** Implement resources, domain, user attribute; `mix ash.codegen add_routines_and_daily_settings && mix ash.migrate`.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add routines and household settings`.

### Task 3: Matching rules (pure)

**Files:**
- Create: `lib/puppy_log/daily/matching.ex`
- Test: `test/puppy_log/daily/matching_test.exs`

**Interfaces:**
- Produces (`PuppyLog.Daily.Matching`, works on plain maps/structs with the listed keys):
  - `tolerance_minutes() :: 15`
  - `deviation_minutes(date :: Date.t(), planned_start :: Time.t(), planned_end :: Time.t() | nil, actual :: NaiveDateTime.t()) :: integer` — negative early, positive late; inside a window 0, else distance to the nearest edge. Uses `NaiveDateTime` so ticks on a later day give large positive values.
  - `kept?(deviation :: integer | nil) :: boolean` — `abs(d) <= 15`; nil → false.
  - `fulfils?(routine_kind :: atom, event :: %{kind: atom, location: atom | nil}) :: boolean` — same kind for `:potty, :meal, :walk, :sleep, :play`; potty only with `location: :outside`; `:training`/`:manual` routines and `:vomit`/`:other` events never.
  - `candidates(occurrences, event, actual :: NaiveDateTime.t()) :: [occurrence]` — open (`status: :open`), `fulfils?`, same `date` as `actual`, sorted by `abs(deviation)` then `planned_start`.
  - `auto_match(occurrences, event, actual) :: occurrence | nil` — first candidate if `kept?(deviation)`.
  - `state(occurrence, now :: NaiveDateTime.t()) :: :open | :overdue | :done | :skipped | :missed` — `:missed` when open and `occurrence.date < NaiveDateTime.to_date(now)`; `:overdue` when open, same day, `now > planned_end_or_start + 15 min`.

- [ ] **Step 1: Failing tests** (date `~D[2026-11-12]`):
  - `deviation_minutes(d, ~T[10:00:00], nil, ~N[2026-11-12 10:20:00]) == 20`; `… ~N[2026-11-12 09:55:00]) == -5`.
  - Window `~T[12:30:00]..~T[14:00:00]`: actual 13:00 → 0; 14:20 → 20; 12:00 → -30.
  - Next-day tick: `deviation_minutes(d, ~T[02:00:00], nil, ~N[2026-11-13 07:00:00]) == 1740`.
  - `kept?(15)`, `kept?(-15)` true; `kept?(16)` false.
  - `fulfils?(:potty, %{kind: :potty, location: :inside})` false; `:outside` true; `fulfils?(:training, %{kind: :play, location: nil})` false.
  - Auto match picks the closest: open potty occurrences at 10:00 and 10:30, event at 10:20 → the 10:30 one (deviation -10 vs 20 → 10:30 is kept, 10:00 is not); event at 10:14 with both 10:00 and 10:30 → 10:00.
  - Outside tolerance: event 10:40, open potty 10:00 and 12:00 → `auto_match == nil`, `candidates` order `[10:00 (40), 12:00 (-80)]`.
  - Done or skipped occurrences are never candidates; occurrences of another date are never candidates.
  - `state/2`: open 10:00, now 10:15 → `:open`; now 10:16 → `:overdue`; yesterday open → `:missed`.
- [ ] **Step 2:** `mix test test/puppy_log/daily/matching_test.exs` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add routine matching rules`.

### Task 4: Occurrences: planning a day, tick off, skip, reopen

**Files:**
- Create: `lib/puppy_log/daily/occurrence.ex`, `lib/puppy_log/daily/planner.ex`, `lib/puppy_log/daily/changes/complete_occurrence.ex`
- Modify: `lib/puppy_log/daily.ex`, `lib/puppy_log/daily/routine.ex` (after-action hooks), `lib/puppy_log/clock.ex`
- Test: `test/puppy_log/daily/planner_test.exs`, `test/puppy_log/daily/occurrence_test.exs`, `test/puppy_log/clock_test.exs`
- Migration: `mix ash.codegen add_occurrences`

**Interfaces:**
- Consumes: `Matching.deviation_minutes/4`, `Routine`, `Profile.arrival_date`.
- Produces:
  - `Clock.now/0` honours an optional test-only override `config :puppy_log, :clock_now, {module, function}` (used by planner, UI and tests; unset in dev/prod); `Clock.today/0` derives from it.
  - `Clock.local_datetime(date, time) :: DateTime.t()` — DST gap → the later valid time (02:30 → 03:30 on 2026-03-29), ambiguous → the first. `Clock.day_bounds(date) :: {DateTime.t(), DateTime.t()}` — UTC start inclusive, next day's start exclusive.
  - `Occurrence` attributes: `routine_id`, `date :date`, snapshot `name`, `kind`, `planned_start :time`, `planned_end :time | nil`, `assignee_id`, `remind?`, `follow_up_minutes`; outcome `status` one_of `[:open, :done, :skipped]` default `:open`, `done_at :utc_datetime_usec | nil`, `deviation_minutes :integer | nil`, `completed_by_id` (User, nilify), `event_id :uuid | nil` (plain attribute without a database reference; Task 5 adds `has_one :occurrence` on `Event` with `destination_attribute: :event_id`), `reminded_at`, `follow_up_sent_at`; timestamps. Identity `:one_per_day [:routine_id, :date]`. PubSub prefix `"occurrences"`.
  - `Daily.ensure_day(date, opts) :: :ok` (plain function delegating to `Planner.ensure_day/2`, runs with `authorize?: false`): for every active routine with `Date.day_of_week(date) in weekdays`, `date >= arrival_date`, and — if the routine was created on `date` — `starts_at` later than its local creation time, upsert an occurrence (identity `:one_per_day`, never overwriting outcome fields). No arrival date → nothing. Archived routines (archived on or before `date`) are skipped.
  - `Daily.ensure_days(first, last, opts) :: :ok` — `ensure_day/2` over the range, clipped to `arrival_date..today`.
  - Read action `:on_date` (argument `date`, sorted by `planned_start`) → `Daily.list_occurrences_on(date, opts)`; `Daily.get_occurrence(id, opts)`.
  - Update `:complete` (arguments `done_at :utc_datetime_usec` required, `event_id :uuid` optional): only from `:open`, otherwise error with message „Schon erledigt“; sets status, done_at, `deviation_minutes` (via `Matching.deviation_minutes(date, planned_start, planned_end, Clock.local(done_at) |> DateTime.to_naive())`), `completed_by` = actor, event_id. → `Daily.complete_occurrence(occ, %{done_at: dt}, opts)`.
  - Update `:skip` (only from `:open`, sets `completed_by`) → `Daily.skip_occurrence(occ, opts)`; update `:reopen` (clears status to open and all outcome fields) → `Daily.reopen_occurrence(occ, opts)`.
  - Routine hooks: `update_routine` → today's still-open occurrence gets the new snapshot (re-plan only today if open); `archive_routine` → today's open occurrence is destroyed. Past occurrences never change.

- [ ] **Step 1: Failing tests**
  - `clock_test.exs`: `Clock.local_datetime(~D[2026-03-29], ~T[02:30:00])` → 03:30 CEST; `day_bounds(~D[2026-11-12])` → `{~U[2026-11-11 23:00:00Z], ~U[2026-11-12 23:00:00Z]}`.
  - `planner_test.exs` (profile with `arrival_date: ~D[2026-11-01]`):
    - "plans routines on their weekdays" (Mon–Fri routine: Thursday 12 Nov → 1 occurrence, Saturday 14 Nov → 0).
    - "nothing before arrival or without arrival date".
    - "idempotent": `ensure_day` twice → one occurrence; a done occurrence stays done.
    - "routine created during the day counts only if still ahead" (create at 15:00 local via a `created_at` override or by inserting with `inserted_at`; routine at 07:00 → no occurrence today, routine at 18:00 → one).
    - "editing a routine changes today's open occurrence, not past ones" (yesterday's snapshot keeps `planned_start ~T[07:00:00]` after changing to 07:30).
    - "archiving removes today's open occurrence, keeps history".
    - "DST spring-forward day plans 02:30 without crashing".
  - `occurrence_test.exs`:
    - "complete stores time, deviation and who": routine 10:00, complete with done_at = local 10:20 → `deviation_minutes == 20`, `completed_by_id == lukas.id`.
    - "second completion fails": complete twice (second as riv) → `{:error, %Ash.Error.Invalid{}}` whose message contains „Schon erledigt“; `completed_by_id` still lukas.
    - "skip and reopen": skip → `:skipped`; reopen → `:open` with outcome fields nil.
    - "late tick for yesterday's 02:00 routine at 07:00 today" → deviation 1740.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement Clock helpers, resource, planner, change, hooks; `mix ash.codegen add_occurrences && mix ash.migrate`.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Plan routine occurrences per day with tick off, skip and reopen`.

### Task 5: Events and their link to routines

**Files:**
- Create: `lib/puppy_log/daily/event.ex`, `lib/puppy_log/daily/changes/link_routine.ex`
- Modify: `lib/puppy_log/daily.ex` (no change to the occurrences table)
- Test: `test/puppy_log/daily/event_test.exs`
- Migration: `mix ash.codegen add_events`

**Interfaces:**
- Consumes: `Matching.auto_match/3`, `Matching.candidates/3`, `Daily.complete_occurrence/3`, `Daily.reopen_occurrence/2`, `Daily.ensure_day/2`, `Clock.day_bounds/1`.
- Produces:
  - `Event` relationship `has_one :occurrence, PuppyLog.Daily.Occurrence, destination_attribute: :event_id`.
  - `Event` attributes: `kind` one_of `[:potty, :meal, :walk, :sleep, :play, :vomit, :other]`, `occurred_at :utc_datetime_usec` (default now), `pee`, `poo`, `nothing` (booleans, default false), `location` one_of `[:outside, :inside] | nil`, `name :string | nil` (1..60), `note :string | nil` (≤ 500), `created_by`, timestamps. PubSub prefix `"events"`.
  - Validations (German messages): potty needs `location` and at least one of pee/poo/nothing („Bitte Pipi, Kaka oder nichts wählen“); `nothing` excludes pee/poo and requires `:outside`; `:other` needs `name`; non-potty kinds ignore pee/poo/nothing/location.
  - Create `:log` with argument `routine :string` default `"auto"` — `"auto"` (Matching.auto_match on that local day after `ensure_day`), `"none"`, or an occurrence id (explicit choice; must be a candidate). After create, completes the chosen occurrence with `done_at = occurred_at` and `event_id`. If the chosen/auto occurrence is already done by hand without an event and is a non-potty kind, only `event_id` is set. → `Daily.log_event(attrs, opts)` (attrs may include `:routine`).
  - Update `:update` (same fields + `routine` argument): reopens the previously linked occurrence, then links again by the same rule. → `Daily.update_event(event, attrs, opts)`.
  - Destroy: reopens the linked occurrence (open; shows as missed for a past day). → `Daily.delete_event(event, opts)`.
  - `Daily.list_events_on(date, opts)` (read `:on_date`, sorted by `occurred_at` desc), `Daily.list_events_between(first, last, opts)`, `Daily.get_event(id, opts)`, `Daily.match_preview(%{kind:, location:, occurred_at:}, opts) :: %{auto: occurrence | nil, candidates: [occurrence]}` (read-only helper for the form).
  - `Daily.recent_other_names(opts) :: [String.t()]` — up to 5 distinct names of the latest `:other` events.

- [ ] **Step 1: Failing tests** (`event_test.exs`, arrival 2026-11-01, potty routines 10:00 and 12:00 daily):
  - "outside pee at 10:10 fulfils the 10:00 routine": `log_event(%{kind: :potty, pee: true, location: :outside, occurred_at: local(10:10)})` → occurrence done, `event_id` set, deviation 10.
  - "pee and poo in one entry fulfil one routine only".
  - "accident inside fulfils nothing".
  - "nothing outside fulfils the routine".
  - "outside tolerance needs a choice": event 10:40 with `routine: "auto"` → no occurrence done; with `routine: occ_1000.id` → that one done with deviation 40; with an id that is not a candidate → error.
  - "back-dated event matches yesterday's routine" (yesterday 10:05 → yesterday's occurrence done, today's still open).
  - "event at 00:10 local belongs to that day" (`list_events_on(today)` contains it; it does not match yesterday's 23:50 routine… use a 00:00 routine today → matched).
  - "deleting the event reopens the routine"; "changing the event time relinks" (10:10 → 12:05 moves the link from 10:00 to 12:00).
  - "meal event links to a meal routine already ticked by hand, keeping its time".
  - Validation cases above.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement; `mix ash.codegen add_events && mix ash.migrate`.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add events that fulfil matching routines`.

### Task 6: Reminders, follow-ups, quiet hours, done notifications

**Files:**
- Create: `lib/puppy_log/daily/reminders.ex` (GenServer + pure helpers), `lib/puppy_log/daily/notify.ex`
- Modify: `lib/puppy_log/notifications.ex` (add `deliver_to_users/2`), `lib/puppy_log/application.ex`, `config/config.exs`, `config/test.exs`, `lib/puppy_log/daily/occurrence.ex` (after-action on `:complete`/`:skip`)
- Test: `test/puppy_log/daily/reminders_test.exs`

**Interfaces:**
- Consumes: `Daily.ensure_day/2`, `Daily.settings/1`, `Clock.local_datetime/2`, `Push.deliver/3` (via `deliver_to_users`), `User.receives_reminders`.
- Produces:
  - `Notifications.deliver_to_users(user_ids :: [Ecto.UUID.t()], payload :: map) :: [Push.result()]` — all subscriptions of those users, `authorize?: false`.
  - `Reminders.tick(now :: DateTime.t()) :: :ok` — public for tests; ensures today, sends due reminders and follow-ups, records `reminded_at` / `follow_up_sent_at` (set before sending → never twice).
  - `Reminders.quiet?(settings, time :: Time.t()) :: boolean` — handles ranges across midnight.
  - Due rule: `remind?` true, status open, `reminded_at` nil, `now` within `[planned_start, planned_start + 10 min]` (window: `planned_start`), not quiet. Follow-up: `follow_up_minutes` set, reminded, `follow_up_sent_at` nil, still open, `now >= planned_start + follow_up_minutes` and not later than that + 10 min, not quiet. Quiet suppresses without catch-up.
  - Recipients: users with `receives_reminders: true`.
  - Payloads (tag `"routine-<occurrence id>"`, `url: "/"`):
    - reminder: `title: name`, `body: "Jetzt fällig (10:00)."` / window `"Zwischen 12:30 und 14:00."`
    - follow-up: `title: "#{name} noch offen"`, `body: "Seit #{n} Minuten fällig."`
    - done: `title: "#{name} erledigt ✓"`, `body: "#{who}, #{HH:MM}"`; skipped: `title: "#{name} übersprungen"`, `body: who`.
  - `Notify.after_outcome(occurrence, actor)` — only if `reminded_at` is set: send done/skipped payload to recipients except the actor. Runs via `Task.Supervisor.start_child(PuppyLog.TaskSupervisor, …)`.
  - Config `config :puppy_log, PuppyLog.Daily.Reminders, enabled: true` (`false` in `config/test.exs`); child started only when enabled; ticks aligned to the next full minute.

- [ ] **Step 1: Failing tests** (Req.Test stub on `PuppyLog.Notifications.Push` collecting decrypted titles, as in `test/puppy_log/notifications/push_test.exs`):
  - "sends at the planned minute once": tick at 10:00 → one push titled the routine name; tick again at 10:01 → none.
  - "not more than 10 minutes late": first tick at 10:11 → nothing, `reminded_at` stays nil.
  - "follow-up after 30 minutes if still open"; "no follow-up when done".
  - "quiet hours 22:00–06:30": routines at 23:00 and 05:00 → no push at their minute nor later; 07:00 → push.
  - "only members with reminders on get pushes".
  - "done replaces the reminder on the other phone": reminded routine completed by lukas → riv's device gets "… erledigt ✓" with tag `routine-<id>`, lukas's does not; not reminded → nothing sent.
  - "two completions send one done notification" (second completion fails, see Task 4).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Send routine reminders with follow-ups and quiet hours`.

### Task 7: „Heute“ with routines, tick off sheet, quick buttons

**Files:**
- Create: `lib/puppy_log_web/time_choice.ex`, `lib/puppy_log_web/components/routine_sheet.ex` (LiveComponent `PuppyLogWeb.RoutineSheet`), `lib/puppy_log_web/components/routine_row.ex` (function component `routine_row/1`)
- Modify: `lib/puppy_log_web/live/today_live.ex`, `lib/puppy_log_web/router.ex`
- Test: `test/puppy_log_web/time_choice_test.exs`, `test/puppy_log_web/live/today_live_test.exs`

**Interfaces:**
- Consumes: `Daily.ensure_day/2`, `Daily.list_occurrences_on/2`, `Daily.complete_occurrence/3`, `Daily.skip_occurrence/2`, `Daily.reopen_occurrence/2`, `Daily.log_event/2` (potty outcome), `Matching.state/2`, `Matching.kept?/1`.
- Produces:
  - `TimeChoice.options() :: [{label, value}]` = `[{"Jetzt", "now"}, {"vor 15 Min", "15"}, {"vor 20 Min", "20"}, {"vor 30 Min", "30"}, {"Uhrzeit", "custom"}]`; `TimeChoice.resolve(choice, custom :: String.t() | nil, now :: DateTime.t()) :: {:ok, DateTime.t()} | :error` (custom is `datetime-local` "2026-11-12T10:05" in Berlin time; future times → `:error`).
  - `routine_row(assigns)` attrs `occurrence`, `now :: NaiveDateTime`, `current_user`, `sheet_path :: String.t()` — check circle (done/late/overdue/skipped styles as `entwuerfe/01`), title, meta („Erledigt 07:05 · Du“, „Seit 20 Min fällig“, „Übersprungen · Riv“, „Um 10:00“ / „12:30 bis 14:00“, „+20 Min“ chip when done late), assignee initial, wrapped in `swipe_row` with action „Überspringen“ (open) or „Wieder öffnen“ (done/skipped).
  - `RoutineSheet` attrs `id`, `occurrence`, `current_user`, `return_to` — time choice segment + for `:potty` outcome buttons „Pipi“, „Kaka“, „Beides“, „Nichts“ (each logs a potty event outside with `routine: occurrence.id`), for other kinds „Abhaken“, plus „Überspringen“ / „Wieder öffnen“.
  - Routes: `live "/", TodayLive, :index`, `live "/routine/:id", TodayLive, :routine`, `live "/eintragen", TodayLive, :log` (log sheet rendered in Task 8; here only the route and quick buttons linking to `/eintragen?typ=pipi|kaka|mahlzeit|gassi` and `/eintragen`).
  - TodayLive subscribes to `occurrences:changed`, `events:changed`, `routines:changed`; re-renders every 60 s (`:tick`) for overdue states. Progress card: „Routinen heute“, „x von y“ (y excludes skipped), percent, `progress`. Empty states: no arrival date → „Tragt im Profil das Einzugsdatum ein …“ with link; no routines → „Legt euren Tagesablauf an“ linking `/routines/new`.
  - Quick tiles: Pipi, Kaka, Mahlzeit, Gassi (design `Main.dc.html`) + full-width secondary „Eintragen“; remove the „Wiegen“ tile.

- [ ] **Step 1: Failing tests**
  - `time_choice_test.exs`: now 10:30 → "now" 10:30, "15" 10:15, "custom" "2026-11-12T09:05" → 09:05 Berlin; "custom" in the future → `:error`; garbage → `:error`.
  - `today_live_test.exs` (routines 07:00 meal, 10:00 potty, 12:30–14:00 sleep; Clock pinned via the `:clock_now` override from Task 4):
    - "shows today's routines in order with progress 0 von 3".
    - "tick off a meal now": click check of 07:00 meal at 07:40 → „Erledigt 07:40 · Du“, chip „+40 Min“, progress „1 von 3“.
    - "potty check opens the sheet; Pipi logs an event and ticks off": patch to `/routine/:id`, click „Pipi“ → occurrence done, event pee outside exists.
    - "tick off 20 minutes ago from the sheet" → done_at 20 min before now.
    - "swipe action skip": `render_click` on „Überspringen“ → „Übersprungen · Du“, progress „0 von 2“.
    - "overdue after 15 minutes": now 10:16 → „Seit 16 Min fällig“.
    - "live: the other person ticks off" → row updates.
    - "without arrival date shows the hint".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Show and tick off today's routines`.

### Task 8: Log sheet for events

**Files:**
- Create: `lib/puppy_log_web/components/event_form.ex` (LiveComponent `PuppyLogWeb.EventForm`)
- Modify: `lib/puppy_log_web/live/today_live.ex` (render sheet for `:log`)
- Test: `test/puppy_log_web/live/event_form_test.exs`

**Interfaces:**
- Consumes: `Daily.log_event/2`, `Daily.update_event/3`, `Daily.match_preview/2`, `Daily.recent_other_names/1`, `TimeChoice`.
- Produces: `EventForm` attrs `id`, `current_user`, `event :: Event | nil` (edit when set), `preset :: map` (from `typ`: `pipi` → `%{kind: :potty, pee: true, location: :outside}`, `kaka` → poo, `mahlzeit` → `:meal`, `gassi` → `:walk`), `default_date :: Date.t()` (for back-dating from the day view), `return_to`. Layout per `Eintragen.dc.html` + `entwuerfe/15`:
  - type tiles Lösen, Mahlzeit, Gassi, Schlaf, Spiel, Erbrechen, Anderes;
  - Lösen: toggles Pipi / Kaka / Nichts gemacht, segment „Draußen“/„Drinnen“, hint „Zählt für die Stubenreinheit.“ / „Wird als Unfall gezählt und erfüllt keine Routine.“; „Nichts gemacht“ disables „Drinnen“;
  - Anderes: „Was genau?“ + recent name chips;
  - „Wann“ time choice;
  - routine area from `match_preview`: auto → „Erfüllt: Pipi-Runde (10:00)“ with „ändern“ revealing the choice list; no auto but candidates → radio list (closest first, none preselected) + „keine“; no candidates → nothing;
  - note; primary „Eintragen“ / „Speichern“; success flash „Eingetragen.“

- [ ] **Step 1: Failing tests**
  - "Pipi quick button preselects pee outside and shows the auto match" (`/eintragen?typ=pipi` at 10:05 → text „Erfüllt: Pipi-Runde (10:00)“).
  - "adding Kaka to the same entry" → one event with pee and poo.
  - "inside shows the accident hint and no routine area".
  - "outside tolerance offers a choice": at 10:40 → radios for 10:00 and 12:00, none checked; choosing 10:00 and saving completes it.
  - "Anderes requires a name" (error „ist erforderlich“) and offers recent names.
  - "vor 20 Min" stores 20 minutes earlier.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add event log sheet with routine matching`.

### Task 9: Manage routines; quiet hours and reminder switches in settings

**Files:**
- Create: `lib/puppy_log_web/live/routines_live.ex`, `lib/puppy_log_web/live/routine_form_live.ex`
- Modify: `lib/puppy_log_web/live/settings_live.ex`, `lib/puppy_log_web/router.ex`
- Test: `test/puppy_log_web/live/routines_live_test.exs`, `test/puppy_log_web/live/settings_live_test.exs`

**Interfaces:**
- Consumes: Task 2 code interface, `Accounts.set_reminders/3`, `Daily.settings/1`, `Daily.save_settings/2`.
- Produces:
  - Routes `live "/routines", RoutinesLive`, `live "/routines/new", RoutineFormLive, :new`, `live "/routines/:id", RoutineFormLive, :edit`.
  - `RoutinesLive` (`entwuerfe/06`): `top_bar` back to `/settings`, intro text, Cinder list of `:active` routines sorted by time, item: kind icon, name, „07:00 · täglich“ / „09:00 bis 11:00 · Mo–Fr“, assignee name, bell or „aus“; footer „Neue Routine“.
  - `RoutineFormLive` (`entwuerfe/07`): name; „Wird erledigt durch“ tiles Lösen, Mahlzeit, Gassi, Schlaf, Spiel, Training, Nur abhaken; segment „Feste Uhrzeit“/„Zeitfenster“ with time inputs; weekday chips Mo–So; „Zuständig“ select (Niemand + members); switches „Erinnern“ and „Nachfragen, wenn offen“ + minutes (15, 30, 45, 60); „Speichern“; edit mode „Routine löschen“ (archive, confirm „Diese Routine löschen? Der Verlauf bleibt erhalten.“).
  - Weekday summary helper `PuppyLogWeb.Format.weekdays([1..7]) :: String.t()` — all → „täglich“, 1–5 → „Mo–Fr“, 6–7 → „Sa, So“, else „Mo, Mi, Fr“.
  - Settings: members get a switch „Erinnerungen“ (`set_reminders`); card „Ruhezeiten“ with switch „Nachts nicht stören“, „Von“/„Bis“ time inputs, hint „In dieser Zeit gibt es keine Erinnerungen.“; row link „Routinen verwalten“.

- [ ] **Step 1: Failing tests**
  - "creates a window routine with weekdays and assignee" via form → listed as „12:30 bis 14:00 · Mo–Fr“ with „Riv“.
  - "validation message for an inverted window" („muss nach dem Beginn liegen“).
  - "archives a routine" → gone from list.
  - `Format.weekdays/1` cases.
  - settings: "turns off reminders for Riv" and "saves quiet hours 22:00–06:30".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Manage routines and quiet hours`.

### Task 10: Statistics (pure)

**Files:**
- Create: `lib/puppy_log/daily/stats.ex`
- Test: `test/puppy_log/daily/stats_test.exs`

**Interfaces:**
- Consumes: `Daily.ensure_days/3`, occurrences and events in a range (read with `authorize?: false` or actor), `Profile.arrival_date`, `Matching.kept?/1`, `Matching.state/2`.
- Produces:
  - `Stats.periods() :: [{key, label}]` = `[{"1w", "1 Woche"}, {"2w", "2 Wochen"}, {"4w", "4 Wochen"}, {"2m", "2 Monate"}, {"4m", "4 Monate"}, {"6m", "6 Monate"}, {"1y", "1 Jahr"}]`.
  - `Stats.range(key, today) :: Date.Range.t()` — weeks: `Date.add(today, -7n + 1)..today`; months/year: `Date.shift(today, month: -n) |> Date.add(1)..today`.
  - `Stats.compute(key, opts) :: %{range, previous_range, buckets, rate, kept, counted, accidents, previous_accidents, pee: %{outside, inside}, poo: %{outside, inside}, nothing, routines}` with `opts` `actor:` and `today:` (default `Clock.today()`).
    - Range clipped to start at `arrival_date`; no arrival date → `counted: 0` and empty lists.
    - Counted occurrence = done or missed (open on a past day); today's open occurrences and all skipped ones are excluded. `kept` = done and `Matching.kept?(deviation)`. `rate` = round(kept / counted × 100) or nil.
    - Buckets: per day when the range has ≤ 28 days (label weekday short „Mo“ or „12.11.“ for 2+ weeks), otherwise per ISO week Monday–Sunday (label „KW 46“). Each bucket: `label`, `first`, `last`, `kept`, `counted`, `rate`, `today?`.
    - Accidents: potty events `:inside` (one per event). Pee/poo counts per flag and location; `nothing` = outside nothing events. Previous period = same length directly before (clipped to arrival).
    - Routines: grouped by `routine_id`, `name` from the latest occurrence, `kept`, `counted`, `skipped`, `missed`, `avg_deviation` (mean of done deviations, rounded, nil if none); sorted by rate ascending (nil last), then name.

- [ ] **Step 1: Failing tests** (arrival 2026-11-01, today 2026-11-12):
  - `range("1w", ~D[2026-11-12]) == Date.range(~D[2026-11-06], ~D[2026-11-12])`; `range("2m", …)` starts `~D[2026-09-13]`; `range("1y", …)` starts `~D[2025-11-13]`.
  - "rate excludes skipped and today's open": fixtures with kept, late, skipped, missed, today-open → `kept: 1, counted: 3, rate: 33`.
  - "4w uses daily buckets, 2m weekly buckets labelled KW".
  - "accidents compare with the previous period": 3 inside this week, 6 the week before → `accidents: 3, previous_accidents: 6`; pee+poo inside in one event counts once.
  - "per routine stats sorted worst first with average deviation" (`avg_deviation: 12` for deviations 10 and 14).
  - "range clipped to arrival".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement (load occurrences/events of `previous_range.first..range.last` once, aggregate in Elixir).
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Compute routine and house-training statistics`.

### Task 11: „Verlauf“ and the day view with corrections

**Files:**
- Create: `lib/puppy_log_web/live/history_live.ex`, `lib/puppy_log_web/live/day_live.ex`, `lib/puppy_log_web/components/history_charts.ex`
- Modify: `lib/puppy_log_web/router.ex`, `lib/puppy_log_web/live/placeholder_live.ex` (remove `:history`)
- Test: `test/puppy_log_web/live/history_live_test.exs`, `test/puppy_log_web/live/day_live_test.exs`

**Interfaces:**
- Consumes: `Stats.periods/0`, `Stats.compute/2`, `RoutineSheet`, `routine_row/1`, `EventForm`, `Daily.list_events_on/2`, `Daily.delete_event/2`, `Daily.ensure_day/2`.
- Produces:
  - Routes `live "/history", HistoryLive` (query `period`, default `"1w"`), `live "/history/:date", DayLive, :index`, `live "/history/:date/routine/:id", DayLive, :routine`, `live "/history/:date/log", DayLive, :log`, `live "/history/:date/events/:id", DayLive, :edit_event`.
  - `HistoryLive` (`Verlauf.dc.html`): `page_title` „Verlauf“, horizontally scrollable period chips (`Stats.periods`, patch), card „Routinen eingehalten“ with rate and SVG bars (`HistoryCharts.adherence_bars/1`; today highlighted, future days dashed, each bar a link to `/history/:date` for daily buckets), card „Stubenreinheit“ (accidents with „Vorher: N“, pee and poo outside/inside bars with text „21 draußen · 2 drinnen“, „Nichts gemacht: N“), card „Routinen“ (per routine: name, „eingehalten 5 von 7“, „Ø 12 Min zu spät“ / „Ø 3 Min zu früh“ / „pünktlich“, „2× übersprungen · 1× verpasst“), link „Heute ansehen“ → `/history/<today>`. Bars have `role="img"` + aria-label text.
  - `DayLive`: `top_bar` with the date (`Format.short_date`) and previous/next day arrows (no future), `ensure_day` on mount for past days, routines via `routine_row` (sheet → tick/skip/reopen with time choice defaulting to the planned time for past days), Cinder list of events with swipe „Ändern“/„Löschen“, footer „Eintragen“ (EventForm with `default_date`).

- [ ] **Step 1: Failing tests**
  - "default period one week shows rate and per-routine stats".
  - "switching to 2 Monate shows weekly buckets" (contains „KW“).
  - "accident card with previous comparison" („3“ and „Vorher: 6“).
  - "day view ticks off yesterday's 02:00 routine at 02:10" → stats rate updates.
  - "day view deletes an event and the routine becomes missed".
  - "back-dated event from the day view matches that day".
  - "no arrival date shows the profile hint".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add history with statistics and day corrections`.

### Task 12: End-to-end check and documentation

**Files:**
- Modify: `docs/design/DESIGN.md` (decisions 10–12: arrival date, potty tick choice, day view), `README.md` (routines + reminder process, `PuppyLog.Daily.Reminders` config)
- Test: full suite

- [ ] **Step 1:** Render „Heute“, sheet, log sheet, routines, settings, Verlauf and day view at 390×844 with sample data (headless Chrome as in earlier steps) and compare with `Main.dc.html`, `Eintragen.dc.html`, `Verlauf.dc.html`, `entwuerfe/01`, `06`, `07`, `08`, `15`; fix visual deviations.
- [ ] **Step 2:** On the running dev server: create two routines a few minutes ahead, verify a reminder arrives on an iPhone and is replaced by „… erledigt ✓“ after ticking on the other phone (manual, report the result).
- [ ] **Step 3:** Update docs; `mix precommit`.
- [ ] **Step 4:** Commit `Document daily routines and reminders`.
