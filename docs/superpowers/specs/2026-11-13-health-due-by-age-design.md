# Health entries due at an age — short design

Status: approved by the user · 2026-11-13 · extends `2026-11-13-health-appointments-design.md`

## Intent

Vaccination (and deworming) plans state *when* in terms of the puppy's age ("mit 8 Wochen",
"mit 4 Monaten"), counted from birth. The household wants to enter the plan in those terms and
let the app work out the calendar date, while still being able to override it with a fixed date
when the vet names one.

## Goals

- Care entries (vaccination, deworming, flea_tick, other_care) can be due either on a date or at
  an age: a number plus unit (weeks or months), counted from the profile's `birth_date`.
- The age stays on the entry and is shown next to the date in the list, the „Nächster Termin“
  card and the calendar event („mit 8 Wochen“).
- Switching an entry from age to a fixed date (and back) is a normal edit.
- Correcting the birth date in the profile moves every **open** entry that is due at an age.

## Non-goals / anti-goals

- No built-in plan templates (still manual, as before).
- Done entries never move; entries with a fixed date never move.
- Vet visits stay date + time only.

## Approaches

1. **Store the age and the derived `due_on`** (chosen): the entry keeps `due_age` + `due_age_unit`
   and `due_on` is computed from them; sorting, status, the next card and the iCal feed keep using
   `due_on` unchanged. A birth-date change recomputes `due_on` of open age-based entries.
2. Compute `due_on` on the fly from the age — rejected: every consumer of `due_on` (sort, status,
   overview, calendar) would need the profile and special handling, for no user-visible gain.
3. Age only as an input helper (no stored age) — rejected by the user: the plan should stay
   readable in the vet's terms and follow birth-date corrections.

## Decided with the user

- Age is stored on the entry; the date can be corrected by switching to a fixed date.
- Applies to all care kinds; not to vet visits.

## My calls (builder may revise with care)

- Arithmetic: "N Wochen" = `birth_date + 7·N days` (8 Wochen alt = day 56). "N Monate" = same
  day of month N months later, clamped to the month's last day (`Date.shift(birth, month: N)`).
- Ranges: weeks 1–104, months 1–36.
- Form: under „Fällig“ a two-way switch „Datum | Alter“. Alter shows a number input (or stepper)
  plus unit „Wochen | Monate“ and below it the computed date („→ Mi, 2. Dez“), live. Without a
  birth date the Alter option is disabled with the hint „Geburtsdatum im Profil eintragen“ linking
  to `/profile/edit`.
- Server side: when `due_age` is set, the create/update action computes `due_on` from the
  profile's birth date (error on `due_age` if no birth date); `due_age` and `due_age_unit` are
  both set or both nil; only for care kinds (same only-for rule as `repeat_weeks`).
- Profile update: when `birth_date` changes, recompute `due_on` of all open entries with `due_age`
  (in the same transaction, after-action) and publish the health PubSub change.
- Labels: „mit 8 Wochen“, „mit 1 Woche“, „mit 4 Monaten“, „mit 1 Monat“. Calendar: appended to the
  event description (title unchanged so it stays short).
- Repetition unchanged: the successor is created with a fixed `due_on = done_on + N weeks` and
  no age. Completing, reopening keep the age on the entry.
- „Bereits erledigt“ with an age: allowed (date derived), as before.

## Left to the builder

- Migration/snapshot details, exact component markup within the design system.
