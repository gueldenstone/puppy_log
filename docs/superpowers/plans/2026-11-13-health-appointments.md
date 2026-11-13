# Health Entries and Calendar Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manually entered vaccination/preventive-care plan and vet appointments with completion, optional repetition, a „Gesundheit“ overview, and a household-wide iCalendar subscription whose alarms are the reminders.

**Architecture:** One Ash resource `PuppyLog.Puppy.HealthEntry` in the existing `PuppyLog.Puppy` domain; a pure module for entry states; a pure iCalendar renderer plus a token-authenticated controller; LiveViews for the tab, the entry form and the settings card. No push and no changes to the reminder process.

**Tech Stack:** Elixir, Phoenix LiveView 1.2, Ash 3 + AshSqlite, Cinder, tz (Europe/Berlin).

**Spec:** `docs/superpowers/specs/2026-11-13-health-appointments-design.md`

## Global Constraints

- UI German; code, comments, test names, commit messages, URLs English (see AGENTS.md).
- Every created record stores its creator (`relate_actor(:created_by)`); household-wide policies `authorize_if actor_present()`.
- Dates/times local Europe/Berlin via `PuppyLog.Clock` (`now/0`, `today/0`, `local_datetime/2`; tests pin with `PuppyLog.Fixtures.pin_clock/1`).
- No push notifications for health entries; reminders are `VALARM`s in the feed.
- The feed always contains **all** household entries, for every member.
- Migrations only via `mix ash.codegen <name>` + `mix ash.migrate`; PubSub prefix `health_entries`, event `"changed"`.
- UI from `PuppyLogWeb.UI` + core `<.input>`; Ash resource lists via `Cinder.collection layout={:list}`.
- Each task ends with `mix precommit` green (pristine output) and a commit whose message ends with `Co-Authored-By: <model that wrote it> <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01KsLYod5k7ufJq8gXoe1hbS`.

## Review Focus

1. **iCal text escaping and folding:** a title or note with `,` `;` `\` or a newline, and lines longer than 75 octets with umlauts, must produce a valid feed (test in Task 3).
2. **DST in the feed:** a vet appointment on 29 Mar 2026 at 10:00 must appear at 10:00 Berlin time, not shifted by an hour (test in Task 3).
3. **Repeat from a past completion:** entering the breeder's vaccination as done on 2026-09-30 with „alle 4 Wochen“ creates an open successor due 2026-10-28 that shows as overdue (test in Task 2).
4. **Rotated token:** after „Neue Adresse erzeugen“ the old URL returns 404 and the new one works (test in Task 3).
5. **Reopen after the successor was already completed:** the completed successor stays untouched (test in Task 2).

---

### Task 1: HealthEntry resource and household lead time

**Files:**
- Create: `lib/puppy_log/puppy/health_entry.ex`, `lib/puppy_log/puppy/health_status.ex`
- Modify: `lib/puppy_log/puppy.ex` (code interface), `lib/puppy_log/daily/settings.ex` (field + `:save` accept)
- Test: `test/puppy_log/puppy/health_entry_test.exs`, `test/puppy_log/puppy/health_status_test.exs`, `test/puppy_log/daily/settings_test.exs`
- Migration: `mix ash.codegen add_health_entries`

**Interfaces:**
- Produces:
  - `HealthEntry` attributes: `kind` one_of `[:vaccination, :deworming, :flea_tick, :other_care, :vet_visit]`; `title` string 1..80 trim; `due_on :date` required; `due_time :time | nil` (required for `:vet_visit`, must be nil otherwise); `location` string ≤ 120 (vet only); `assignee_id` → `belongs_to :assignee, PuppyLog.Accounts.User` (vet only, nilify on delete); `notes` ≤ 1000; `remind_days_before` integer 0..14 (default from settings on create); `repeat_weeks` integer 1..104 or nil (care kinds only; nil = no repetition); `status` one_of `[:open, :done]` default `:open`; `done_on :date | nil`; `batch` string ≤ 120 (vaccination only); `previous_id` → `belongs_to :previous, HealthEntry` (nilify); `created_by`; timestamps. Validation messages German (e.g. „Bitte eine Uhrzeit angeben“, „Nur für Tierarzttermine“).
  - Actions: `:create`, `:update` (fields above except status/done_on), default `:destroy`, read `:overview` (sorted: open by `due_on`,`due_time`; then done by `done_on` desc).
  - `PuppyLog.Puppy` code interface: `list_health_entries(opts)` (`:overview`), `get_health_entry(id, opts)`, `create_health_entry(attrs, opts)`, `update_health_entry(entry, attrs, opts)`, `delete_health_entry(entry, opts)`.
  - `PuppyLog.Puppy.HealthStatus.state(entry, now :: DateTime.t()) :: :open | :due_soon | :due_today | :overdue | :done` — `:due_soon` when `due_on - today <= remind_days_before` and > 0; `:due_today` on the day (vet: before its time); `:overdue` care after `due_on`, vet after its local date+time.
  - `PuppyLog.Puppy.HealthStatus.days_until(entry, today) :: integer`.
  - `Daily.Settings.health_reminder_days` integer 0..14 default 2, accepted by `:save`.

- [ ] **Step 1: Failing tests**
  - `health_entry_test.exs`: "creates a care item with the household default lead time" (settings saved with `health_reminder_days: 3` → entry `remind_days_before == 3`, `created_by_id` set); "vet visit needs a time, care items reject time/location/assignee"; "repeat only for care kinds"; "overview lists open by due date, then done newest first"; "requires a signed in user"; "broadcasts health_entries:changed".
  - `health_status_test.exs` (now = 2026-11-13 10:00 Berlin): care due 2026-11-15 with lead 2 → `:due_soon`; due 2026-11-20 → `:open`; due today → `:due_today`; due 2026-11-12 → `:overdue`; vet today 09:00 → `:overdue`, vet today 11:00 → `:due_today`; done → `:done`.
  - `settings_test.exs`: "health lead time defaults to 2 and can be saved".
- [ ] **Step 2:** `mix test` on those files → FAIL.
- [ ] **Step 3:** Implement; `mix ash.codegen add_health_entries && mix ash.migrate`.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add health entries`.

### Task 2: Completing, repetition and reopening

**Files:**
- Create: `lib/puppy_log/puppy/changes/complete_health_entry.ex`
- Modify: `lib/puppy_log/puppy/health_entry.ex`, `lib/puppy_log/puppy.ex`
- Test: `test/puppy_log/puppy/health_completion_test.exs`

**Interfaces:**
- Consumes: Task 1 resource.
- Produces:
  - Update `:complete` (args `done_on :date` default `Clock.today()`, not in the future; `batch` optional, vaccination only): only from `:open` (error „Schon erledigt“); sets status/done_on/batch; if `repeat_weeks` → creates the successor (same kind, title, notes, remind_days_before, repeat_weeks, assignee nil, batch nil, `due_on = done_on + 7 * repeat_weeks`, `previous_id` = this entry, created_by = actor) in the same transaction. → `Puppy.complete_health_entry(entry, %{done_on:, batch:}, opts)` returning the completed entry.
  - `:create` accepts `status: :done` + `done_on` to enter past entries directly as done; with `repeat_weeks` it also creates the successor (same change module).
  - Update `:reopen`: back to `:open`, clears done_on/batch; deletes the successor only if it is still `:open` and unchanged since its creation (`updated_at == inserted_at`). → `Puppy.reopen_health_entry(entry, opts)`.
- [ ] **Step 1: Failing tests** (pin 2026-11-13): "complete stores date, batch and who"; "second completion fails with Schon erledigt"; "repeating care item creates the next one from the completion date" (done 2026-11-13, 4 weeks → successor due 2026-12-11, `previous_id`); "entered as done in the past still creates the successor" (2026-09-30 → 2026-10-28, `HealthStatus.state == :overdue`); "no successor without repetition"; "reopen removes an untouched open successor"; "reopen keeps a successor that was already edited or completed"; "future done_on is rejected".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Complete and repeat health entries`.

### Task 3: iCalendar feed with per-person token

**Files:**
- Create: `lib/puppy_log/puppy/calendar.ex` (pure renderer), `lib/puppy_log_web/controllers/calendar_controller.ex`
- Modify: `lib/puppy_log/accounts/user.ex` (attribute + actions), `lib/puppy_log/accounts.ex`, `lib/puppy_log_web/router.ex`
- Test: `test/puppy_log/puppy/calendar_test.exs`, `test/puppy_log_web/controllers/calendar_controller_test.exs`
- Migration: `mix ash.codegen add_calendar_token`

**Interfaces:**
- Consumes: Task 1/2 entries, `HealthStatus`.
- Produces:
  - `User.calendar_token :string | nil` (sensitive, not public in forms); update `:rotate_calendar_token` (sets `Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)`, policy actor_present, only own user — `relates_to_actor_via` / `expr(id == ^actor(:id))`); read `:by_calendar_token` (arg token, get?). `Accounts.rotate_calendar_token(user, opts)`, `Accounts.get_user_by_calendar_token(token, authorize?: false)`.
  - `PuppyLog.Puppy.Calendar.render(entries, opts) :: iodata` — `opts`: `name: "Puppy Log – <puppy name>"`, `users: %{id => name}`. Output: `BEGIN:VCALENDAR`, `VERSION:2.0`, `PRODID:-//Puppy Log//DE`, `CALSCALE:GREGORIAN`, `X-WR-CALNAME`, `REFRESH-INTERVAL;VALUE=DURATION:PT1H`, `X-PUBLISHED-TTL:PT1H`, one `VEVENT` per entry: `UID:<id>@puppy-log`, `DTSTAMP` (UTC), care → `DTSTART;VALUE=DATE` / `DTEND` next day, vet → `DTSTART`/`DTEND` in UTC (60 min, converted from Berlin via `Clock.local_datetime/2`); `SUMMARY` = title (done → `✓ ` prefix); `LOCATION`; `DESCRIPTION` with notes, „Geht hin: <name>“, batch, kind label; alarms only for open entries: care `TRIGGER;RELATED=START:-P1DT15H` for N=2 (generally 09:00 N days before; N=0 → `PT9H`), vet `-P<N>D` (omit when N=0) and `-PT2H`; `ACTION:DISPLAY`, `DESCRIPTION` = title. CRLF line endings, RFC 5545 escaping (`\\`, `\;`, `\,`, `\n`), folding at 75 octets without splitting UTF-8 characters.
  - Route `get "/calendar/:token", CalendarController, :show` in a pipeline without session/CSRF (`plug :accepts, ["ics", "html"]` not required — respond `text/calendar; charset=utf-8`); path param ends with `.ics` (strip it); unknown → 404; entries: all household entries with `due_on >= today - 365` (read with `authorize?: false`).
- [ ] **Step 1: Failing tests**
  - `calendar_test.exs`: "all-day care item with alarm at 09:00 two days before" (`DTSTART;VALUE=DATE:20261120`, `TRIGGER;RELATED=START:-P1DT15H`); "vet appointment in UTC with two alarms" (2026-11-20 10:00 Berlin → `DTSTART:20261120T090000Z`, `TRIGGER:-P2D`, `TRIGGER:-PT2H`, `LOCATION`, „Geht hin: Riv“); "DST: 2026-03-29 10:00 → 080000Z"; "done entries are ticked and have no alarm"; "escapes , ; \ and newlines"; "folds long umlaut lines at 75 octets, CRLF everywhere".
  - `calendar_controller_test.exs`: "feed with valid token contains entries of both members" (one assigned to each user); "unknown token is 404"; "rotated token: old 404, new 200"; "content type text/calendar".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement; `mix ash.codegen add_calendar_token && mix ash.migrate`.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Serve health entries as a subscribable calendar`.

### Task 4: „Gesundheit“ tab: next entry, list, completion sheet

**Files:**
- Modify: `lib/puppy_log_web/live/health_live.ex`, `lib/puppy_log_web/router.ex`
- Create: `lib/puppy_log_web/components/health_row.ex` (`health_row/1`, `health_chip/1`)
- Test: `test/puppy_log_web/live/health_live_test.exs` (extend `tabs_live_test.exs` cases if they assert the old placeholder)

**Interfaces:**
- Consumes: Tasks 1–2 (`list_health_entries`, `complete_health_entry`, `reopen_health_entry`, `HealthStatus`).
- Produces: routes `live "/health", HealthLive, :index`, `live "/health/:id/done", HealthLive, :complete`. Page per `docs/design/Gesundheit.dc.html`: card „Nächster Termin“ (earliest open entry, overdue first; date tile, „in N Tagen“ / „heute“ / „seit N Tagen überfällig“ in danger, title, time · place, „Geht hin: …“; none → „Keine offenen Termine“ + link „Termin eintragen“ → `/health/new`), existing weight card, list „Impfungen und Vorsorge“ (Cinder over `:overview`) with chips: `:done` ok „Erledigt“, `:due_today` warn „Heute“, `:due_soon` warn „In N Tagen“, `:open` neutral „In N Tagen“ / date, `:overdue` bad „Überfällig“; subtitle lines (date, „Zuletzt 01.11. · alle 4 Wochen“, batch). Row swipe actions „Erledigt“ (→ `/health/:id/done`) or „Wieder öffnen“ for done; tapping a row → `/health/:id` (form, Task 5). Completion sheet: „Wann“ date (default today, max today), „Impfstoff/Charge“ for vaccinations, button „Erledigt“; flash „Erledigt.“; when a successor was created, flash „Erledigt. Nächster Termin am <date>.“ Live via `health_entries:changed`.
- [ ] **Step 1: Failing tests:** "next card shows the earliest open entry and overdue first"; "no open entries shows the hint"; "list shows chips (Überfällig, In 2 Tagen, Erledigt)"; "complete via sheet with batch creates the successor and flashes its date"; "reopen from the swipe action"; "live update when the other member adds an entry".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Show health entries on the health tab`.

### Task 5: Entry form (new, edit, delete)

**Files:**
- Create: `lib/puppy_log_web/live/health_form_live.ex`
- Modify: `lib/puppy_log_web/router.ex`
- Test: `test/puppy_log_web/live/health_form_live_test.exs`

**Interfaces:**
- Consumes: Task 1 code interface, `Daily.settings/1` for the default lead time, household members (`Accounts.list_users!`).
- Produces: routes `live "/health/new", HealthFormLive, :new`, `live "/health/:id", HealthFormLive, :edit` (declare `/health/new` before `/health/:id`). Form per `docs/design/entwuerfe/09-termin.html`: kind tiles „Impfung“, „Entwurmung“, „Floh/Zecke“, „Andere Vorsorge“, „Tierarzt“; „Bezeichnung“; „Datum“ (label „Fällig am“ for care, „Datum“ for vet); „Uhrzeit“, „Ort“, „Zuständig“ only for Tierarzt; „Erinnern“ stepper „N Tage vorher“ (0 → „Am Tag selbst“) with hint „Die Erinnerung kommt über euer Kalender-Abo.“; „Wiederholen“ switch + „Alle N Wochen“ stepper (care only); „Impfstoff/Charge“ (vaccination); „Bereits erledigt“ switch on new entries reveals „Erledigt am“ (default today) to enter past items; „Notiz“; footer „Speichern“; edit mode „Eintrag löschen“ with confirm „Diesen Eintrag löschen?“. After save → `/health` with flash „Gespeichert.“. Unknown id → `/health` with „Diesen Eintrag gibt es nicht mehr.“
- [ ] **Step 1: Failing tests:** "creates a vaccination with repetition"; "vet visit requires time and offers place and assignee"; "switching kind hides vet-only fields"; "enter a past vaccination as done creates its successor"; "edit and delete"; "unknown id redirects with flash"; "default lead time comes from settings".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add the health entry form`.

### Task 6: Settings: lead time and calendar subscription

**Files:**
- Modify: `lib/puppy_log_web/live/settings_live.ex`, `assets/js/app.js` only if the existing `puppy:copy` handler needs a label tweak
- Test: `test/puppy_log_web/live/settings_live_test.exs`

**Interfaces:**
- Consumes: `Daily.save_settings/2` (`health_reminder_days`), `Accounts.rotate_calendar_token/2`, `current_user.calendar_token`.
- Produces: Settings section „Gesundheit“: stepper „Termine erinnern: N Tage vorher“ (saves on change). Section „Kalender-Abo“: if no token yet, button „Kalender-Adresse erzeugen“; otherwise the `webcal://<host>/calendar/<token>.ics` URL (host from `PuppyLogWeb.Endpoint.url/0`) in a read-only field, copy button („Kopieren“, reuses `puppy:copy`), link „Im Kalender öffnen“ (`webcal://…`), button „Neue Adresse erzeugen“ with confirm „Die alte Adresse funktioniert danach nicht mehr. Fortfahren?“, and the hint text: „Auf dem iPhone: Einstellungen → Kalender → Accounts → Account hinzufügen → Andere → Kalenderabo hinzufügen, Adresse einfügen und „Alarme entfernen“ ausschalten – sonst kommen keine Erinnerungen. Der Kalender enthält alle Termine des Haushalts.“
- [ ] **Step 1: Failing tests:** "saves the health lead time"; "creates a calendar address and shows the hint"; "rotating changes the address"; "each member sees only their own address".
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass; `mix precommit`.
- [ ] **Step 5:** Commit `Add calendar subscription and health lead time to settings`.

### Task 7: Visual check and docs

**Files:**
- Modify: `docs/design/DESIGN.md` (decisions: health entries, calendar alarms instead of push, household feed), `README.md` (health + calendar section)
- [ ] **Step 1:** Exploratory check in the user's browser through Tidewave (`browser_eval`, sid given by the user, page at http://localhost:4000) at 390×844: `/health`, `/health/new` (all kinds), completion sheet, settings calendar card; fix visual deviations from `docs/design/Gesundheit.dc.html` and `entwuerfe/09`. Create test entries only with title prefix „ZZ “ and delete them afterwards.
- [ ] **Step 2:** Validate the feed: fetch `/calendar/<token>.ics` with curl and check it parses (e.g. `python3 -I -c` with a minimal line/CRLF/fold check); report the manual iPhone subscription steps for the user.
- [ ] **Step 3:** Docs; `mix precommit`.
- [ ] **Step 4:** Commit `Document health entries and calendar feed`.
