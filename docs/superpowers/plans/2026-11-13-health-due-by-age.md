# Health Entries Due at an Age Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Care entries can be due at an age of the puppy ("mit 8 Wochen") instead of a fixed date; the date is derived from the birth date and follows birth-date corrections.

**Architecture:** `HealthEntry` gets `due_age` + `due_age_unit`; a change computes `due_on` from the profile's `birth_date` on create/update. Everything that reads `due_on` (sort, status, next card, iCal) stays unchanged. A profile update that changes `birth_date` recomputes `due_on` of open age-based entries through a dedicated update action (so PubSub fires).

**Tech Stack:** Phoenix LiveView 1.2, Ash 3 + AshSqlite, existing `PuppyLogWeb.UI` components.

**Spec:** `docs/superpowers/specs/2026-11-13-health-due-by-age-design.md` (extends `docs/superpowers/specs/2026-11-13-health-appointments-design.md`)

## Global Constraints

- UI texts German; code, comments, docs, test names, commit messages, URL paths English.
- Age only for care kinds (`:vaccination, :deworming, :flea_tick, :other_care`), never `:vet_visit`.
- Weeks: `due_on = birth_date + 7·N` days, N in 1..104. Months: `Date.shift(birth_date, month: N)` (clamps to month end), N in 1..36.
- Labels exactly: „mit 1 Woche“, „mit N Wochen“, „mit 1 Monat“, „mit N Monaten“.
- Done entries and fixed-date entries never move; only open entries with `due_age` follow a birth-date change.
- Repetition unchanged: successor gets fixed `due_on = done_on + N weeks`, `due_age`/`due_age_unit` nil.
- Without a birth date: age option disabled in the form with hint „Geburtsdatum im Profil eintragen“ linking to `/profile/edit`; server rejects `due_age` with error on `:due_age`: „Erst das Geburtsdatum im Profil eintragen“.
- Migrations via `mix ash.codegen <name>`; new columns nullable.
- `mix precommit` clean at the end of every task.

## Review Focus

1. Birth date removed (set to nil) in the profile → open age entries keep their last `due_on`, no crash.
2. Switching an entry from age to „Datum“ in the form → `due_age`/`due_age_unit` become nil and the typed date is kept (not overwritten by the age).
3. Editing an age entry's age (8 → 9 Wochen) recomputes `due_on`.
4. Birth date 31 Jan + 1 Monat → 28/29 Feb (clamped), not an error.
5. Completing an age entry with repetition → successor has no age, fixed date.

---

### Task 1: Domain — age on entries and birth-date follow-up

**Files:**
- Modify: `lib/puppy_log/puppy/health_entry.ex` (attributes, `@fields`, validations, new update action `:follow_birth_date`)
- Create: `lib/puppy_log/puppy/changes/due_on_from_age.ex`
- Create: `lib/puppy_log/puppy/due_age.ex`
- Modify: `lib/puppy_log/puppy/changes/complete_health_entry.ex` (successor without age)
- Modify: `lib/puppy_log/puppy/profile.ex` (after-action on `:update` when `birth_date` changed)
- Modify: `lib/puppy_log/puppy.ex` (code interface if needed)
- Test: `test/puppy_log/puppy/due_age_test.exs`, `test/puppy_log/puppy/health_entry_test.exs`, `test/puppy_log/puppy/health_completion_test.exs`

**Interfaces:**
- Produces: attributes `due_age :integer` (nullable, public), `due_age_unit :atom` one_of `[:weeks, :months]` (nullable, public); both accepted by `:create` and `:update`.
- Produces: `PuppyLog.Puppy.DueAge.due_on(birth_date :: Date.t(), n :: pos_integer, unit :: :weeks | :months) :: Date.t()`
- Produces: `PuppyLog.Puppy.DueAge.label(n, unit) :: String.t()` („mit 8 Wochen“ …)
- Produces: `PuppyLog.Puppy.DueAge.ranges() :: %{weeks: 1..104, months: 1..36}`

- [ ] **Step 1: Failing tests** in `due_age_test.exs`:

```elixir
test "weeks count days from birth" do
  assert DueAge.due_on(~D[2026-10-07], 8, :weeks) == ~D[2026-12-02]
end

test "months keep the day and clamp to month end" do
  assert DueAge.due_on(~D[2026-10-07], 4, :months) == ~D[2027-02-07]
  assert DueAge.due_on(~D[2027-01-31], 1, :months) == ~D[2027-02-28]
end

test "labels" do
  assert DueAge.label(1, :weeks) == "mit 1 Woche"
  assert DueAge.label(8, :weeks) == "mit 8 Wochen"
  assert DueAge.label(1, :months) == "mit 1 Monat"
  assert DueAge.label(4, :months) == "mit 4 Monaten"
end
```

In `health_entry_test.exs` (profile with `birth_date: ~D[2026-10-07]` created in setup; pin the clock as the file already does):
- `"an age sets the due date from the birth date"`: create vaccination with `due_age: 8, due_age_unit: :weeks` and no `due_on` → `due_on == ~D[2026-12-02]`, `due_age == 8`.
- `"changing the age recomputes the date"`: update `due_age: 9` → `due_on == ~D[2026-12-09]`.
- `"switching to a fixed date drops the age"`: update `%{due_age: nil, due_age_unit: nil, due_on: ~D[2026-12-05]}` → `due_on == ~D[2026-12-05]`, `due_age == nil`.
- `"age needs both number and unit"`: `due_age: 8` without unit → error on `:due_age_unit`.
- `"age is only for care items"`: vet visit with `due_age` → error on `:due_age`.
- `"age needs a birth date"`: profile without birth date → error on `:due_age` „Erst das Geburtsdatum im Profil eintragen“.
- `"age out of range"`: `due_age: 105, :weeks` and `due_age: 37, :months` → error on `:due_age`.
- `"a corrected birth date moves open age entries only"`: entries: open age (8 Wochen), done age, open fixed date; `update_profile(birth_date: ~D[2026-10-01])` → open age entry `due_on == ~D[2026-11-26]`; the other two unchanged; a `health_entries:changed` broadcast is received (subscribe `PuppyLogWeb.Endpoint` to `"health_entries:changed"`).
- `"removing the birth date keeps the dates"`: `update_profile(birth_date: nil)` → open age entry keeps `due_on`, no error.

In `health_completion_test.exs`: `"the successor of an age entry has a fixed date"`: age entry with `repeat_weeks: 4` completed on `~D[2026-12-03]` → successor `due_on == ~D[2026-12-31]`, `due_age == nil`, `due_age_unit == nil`.

- [ ] **Step 2: Run** `mix test test/puppy_log/puppy` → the new tests fail.

- [ ] **Step 3: Implement.**
  - `DueAge` as above (weeks: `Date.add(birth, 7 * n)`; months: `Date.shift(birth, month: n)`).
  - `Changes.DueOnFromAge` (on `:create` and `:update`, before the existing changes in `:create` so `CompleteHealthEntry` sees the final `due_on`): when the changeset's `due_age` and `due_age_unit` are both present, load the profile (`PuppyLog.Puppy.get_profile(authorize?: false)` or equivalent existing reader) and force-set `due_on`; missing birth date → `add_error(field: :due_age, message: "Erst das Geburtsdatum im Profil eintragen")`.
  - Validations: both-or-neither (error on `:due_age_unit` „Bitte Wochen oder Monate wählen“ / on `:due_age` „Bitte ein Alter angeben“); only-for care kinds via existing `Validations.OnlyFor` (as `repeat_weeks`); range per unit, message „Wochen: 1 bis 104, Monate: 1 bis 36“.
  - Update action `:follow_birth_date` (accepts nothing, `require_atomic? false`, runs `DueOnFromAge` with the stored age; add it to `publish_all :update`-style PubSub so the change is broadcast — `publish_all :update` already covers all update actions; verify).
  - `Profile` `:update`: `change after_action` that, only when `birth_date` changed and the new value is not nil, reads open entries with non-nil `due_age` (`authorize?: false`) and runs `:follow_birth_date` on each (same transaction). Keep it in a change module `lib/puppy_log/puppy/changes/move_age_entries.ex`.
  - `CompleteHealthEntry`: successor attrs set `due_age: nil, due_age_unit: nil`.
  - `mix ash.codegen add_health_entry_due_age`, then `mix ash.migrate`.

- [ ] **Step 4: Run** `mix test test/puppy_log` → all pass.

- [ ] **Step 5: Commit** `Let health entries be due at an age`.

---

### Task 2: Form and list — choose „Datum | Alter“, show the age

**Files:**
- Modify: `lib/puppy_log_web/live/health_form_live.ex`
- Modify: `lib/puppy_log_web/components/health_row.ex`
- Modify: `lib/puppy_log_web/live/health_live.ex` (next card detail)
- Test: `test/puppy_log_web/live/health_form_live_test.exs`, `test/puppy_log_web/live/health_live_test.exs`

**Interfaces:**
- Consumes: Task 1 attributes `due_age`, `due_age_unit`; `DueAge.due_on/3`, `DueAge.label/2`, `DueAge.ranges/0`.

- [ ] **Step 1: Failing tests** (profile with `birth_date: ~D[2026-10-07]`, clock pinned to 2026-11-13):
  - `"care kinds offer Datum or Alter"`: `/health/new` (default kind vaccination) has a radiogroup `aria-label="Fällig"` with options „Datum“ and „Alter“; vet kind has no such group.
  - `"entering an age shows the computed date and saves it"`: choose Alter, `due_age=8`, unit `weeks` → page shows „→ Mi, 2. Dez“ (use `Format` helper that matches the app's short weekday date); submit with title „ZZ Impfung“ → entry has `due_age 8`, `due_on ~D[2026-12-02]`.
  - `"editing an age entry starts on Alter; switching to Datum keeps the typed date"`: edit age entry → Alter selected with 8 / Wochen; switch to Datum, set `due_on` 2026-12-05, save → `due_age nil`, `due_on ~D[2026-12-05]`.
  - `"without a birth date Alter is disabled with a profile link"`: profile without birth date → Alter radio `disabled`, link `a[href="/profile/edit"]` „Geburtsdatum im Profil eintragen“.
  - `"switching kind to Tierarzt clears the age"` (carry the existing kind-switch clearing rule to the new fields).
  - In `health_live_test.exs`: `"rows and the next card show the age"`: open age entry → row and next card contain „mit 8 Wochen“.

- [ ] **Step 2: Run** the two test files → fail.

- [ ] **Step 3: Implement.** Form: a `due_mode` assign (`"date" | "age"`, initial from `entry.due_age`), segmented control like the existing kind tiles/radio pattern; Alter shows a number input `due_age` (`inputmode="numeric"`) and unit radio „Wochen | Monate“, plus the live preview line computed with `DueAge.due_on/3` from the loaded profile birth date (no preview while invalid). Normalization: mode date → `due_age`/`due_age_unit` nil; mode age → do not send `due_on` from the date field (server computes). Rows/next card: append `DueAge.label/2` to the date line when `due_age` is set (e.g. „2. Dez · mit 8 Wochen“).

- [ ] **Step 4: Run** the two test files, then `mix precommit` → green.

- [ ] **Step 5: Commit** `Choose a date or an age in the health form`.

---

### Task 3: Calendar, docs, visual check

**Files:**
- Modify: `lib/puppy_log/puppy/calendar.ex` (description gets the age label)
- Modify: `test/puppy_log/puppy/calendar_test.exs`
- Modify: `docs/design/DESIGN.md`, `README.md` (health section: due at an age)

- [ ] **Step 1: Failing test** `"an age entry mentions the age in the description"`: entry with `due_age: 8, due_age_unit: :weeks` → rendered VEVENT `DESCRIPTION` contains `mit 8 Wochen`; title (`SUMMARY`) unchanged.
- [ ] **Step 2: Implement**, run `mix test test/puppy_log/puppy/calendar_test.exs` → pass.
- [ ] **Step 3: Visual check** at 390×844 with headless Chrome against the running dev server (as in the previous plan's Task 7: magic link created via Tidewave `project_eval` inside the running app, not the mix task): `/health/new` in Datum and Alter mode, an edit page of an age entry, `/health`. Test entries only with title prefix „ZZ “, deleted afterwards. Do not change the profile's birth date in the dev DB.
- [ ] **Step 4: Docs**, `mix precommit`.
- [ ] **Step 5: Commit** `Show the age in the calendar and document due ages`.
