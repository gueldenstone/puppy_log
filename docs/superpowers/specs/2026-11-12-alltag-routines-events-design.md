# Alltag: routines and events — design

Status: reviewed, awaiting approval · 2026-11-12

## Intent

The puppy has not arrived yet. From day one it will live by a **fixed daily schedule** (go out,
breakfast, short training or play, sleep, go out, …) so it gets used to a rhythm. The household
(two people, two iPhones) wants to:

1. **see** that schedule for today and tick it off as it happens, and
2. **see afterwards whether it was kept**: which routines work, which slip, and whether house
   training is improving (few accidents inside).

The app is the shared memory of "did we do it, and when". Being late is not a failure to punish;
the point is to notice patterns.

## Goals

- Self-made routines that repeat on chosen weekdays at a fixed time or within a time window.
- "Heute" shows today's routines with live state on both phones; ticking off takes one tap.
- Logging what happened (events) is fast and, where it fits, ticks off the matching routine in the
  same step.
- Punctuality is measured precisely in the background (minutes early/late) while the UI stays
  forgiving (±15 minutes counts as kept).
- Reminders at the planned time, optional follow-up, silenced during quiet hours.
- A history ("Verlauf") over selectable periods that shows adherence per day/week, per routine,
  and house-training progress.

## Non-goals (for this step)

- Durations of sleep or walks — only points in time are recorded.
- Alarms. A web app cannot set iPhone alarms; night outings are covered by the couple's own alarms.
- Per-person quiet hours or per-routine notification recipients.
- One-off tasks / to-dos (the assignee concept below should be reusable later, e.g. for vet visits).
- Training sessions and commands ("Lernen") — built later; until then training routines are ticked
  off by hand.
- Offline use.

## Anti-goals (would make it a failure even if it works)

- Waking or nagging people at night through app notifications.
- History that silently changes when a routine is edited later (past days must keep the plan they had).
- Ticking off forcing a time that is wrong: if someone ticks off late, the recorded time must be the
  real one they enter, otherwise the statistics lie.
- Having to log the same outing twice (pee and poo in one go must be one entry).

## Constraints

- Existing stack and conventions: Phoenix LiveView, Ash with AshSqlite, Ash domains/resources with
  policies (`actor_present()` household-wide), code interfaces, PubSub notifiers for live updates,
  Cinder for listing Ash resources, design tokens and components from `PuppyLogWeb.UI`,
  `docs/design/DESIGN.md` and the approved mockups (`Main.dc.html`, `Eintragen.dc.html`,
  `Verlauf.dc.html`, `entwuerfe/01`, `06`, `07`, `08`, `15`, `16`).
- UI in German, code/comments/commits in English.
- Every record stores who created it (the actor). There is no separate "who" field in forms.
- Times are local wall-clock times in Europe/Berlin (`PuppyLog.Clock`), including DST.
- Exactly one household, one puppy, two users; SQLite.
- Push goes through the existing `PuppyLog.Notifications.Push`. iOS requires every push to show a
  visible notification.
- Tests for resources and LiveViews, `mix precommit` green.

## Concepts and rules (decided with the user)

### Routines
- A routine has a name, a **kind** (what fulfils it), a schedule, the weekdays it applies to,
  an optional **assignee** (one household member), reminder settings.
- Kinds ("Wird erledigt durch"): **Lösen** (potty break), **Mahlzeit**, **Gassi**, **Schlaf**,
  **Spiel**, **Training**, **Nur abhaken** (manual only).
- Schedule: either a **fixed time** (07:30) or a **time window** (12:30–14:00).
- No repetition within a day: every round is its own routine.
- The assignee is shown in the list; reminders still go to everybody.

### States of a routine on a given day
- **open** → **done** (with actual time and who), **skipped** (with who), or **missed** (the day
  ended without done/skipped).
- **Kept** ("eingehalten") = done within **15 minutes before or after** the planned time
  (for a window: inside the window, extended by 15 minutes on both sides).
- The exact deviation in minutes is always stored (early negative, late positive; for a window,
  distance to the nearest edge, 0 inside).
- **Overdue** (red, „Seit N Min fällig“): still open after the planned time (window end) + 15 min.
- A forgotten routine can be ticked off any time later (it then counts as late) or skipped.

### Start: the puppy's arrival date
- The puppy profile gets an **arrival date** („Einzug“). Routines can be set up before that, but
  occurrences, reminders and statistics only start on the arrival date. Without an arrival date
  nothing counts yet (the plan can still be viewed and edited).

### Ticking off with the real time
- A routine can be ticked off as **now** or with the actual time via quick select
  **„vor 15 Min“, „vor 20 Min“, „vor 30 Min“** or an exact time. Punctuality is computed from
  the entered time, not from when the button was pressed.
- Ticking off a **Lösen** routine always records what happened: the check button opens a small
  choice **„Pipi · Kaka · beides · nichts“** (outside) and creates the matching Lösen event, which
  fulfils the routine. One tap more than other routines, but the house-training numbers stay
  complete. All other routine kinds tick off with a single tap.
- Skipping: swipe left (or long-press) → „Überspringen“. Skipped routines are grey with icon and
  text and are excluded from the adherence rate.

### Events
- Types: **Lösen**, **Mahlzeit**, **Gassi**, **Schlaf**, **Spiel**, **Erbrechen**, **Anderes**
  (free name), each with optional note and a point in time (same time picker as above).
- **Lösen** is one entry with **Pipi**, **Kaka** (one or both) or **nichts gemacht**, plus
  **draußen/drinnen**. Inside = accident. „Nichts gemacht“ only makes sense outside.
  Pee and poo are counted separately in the statistics.
- On "Heute" the quick buttons **Pipi** and **Kaka** open the same Lösen entry with that box
  pre-ticked; the other can be added with one tap.

### Event ↔ routine matching
- An event can fulfil an open routine of the same kind on the same day (Lösen event ↔ Lösen
  routine, Mahlzeit ↔ Mahlzeit, …).
- A Lösen event fulfils a routine if it happened **outside**, including „nichts gemacht“.
  An accident inside never fulfils a routine.
- If the event lies **within ±15 minutes** of an open matching routine, it is matched
  automatically; if several qualify, the **closest** one wins.
- If it lies **outside** that range, the form **offers a choice** among the open matching routines
  of that day, or „keine“.
- If a routine is fulfilled by an event, the routine's actual time is the event's time.
- When an outing produces pee and poo, it is one Lösen entry, so this never double-fulfils.

### Reminders
- At the planned time (window start) a push goes to every household member with notifications
  switched on.
- Optional follow-up after N minutes if the routine is still open.
- When someone ticks off or skips a routine, the other phones' reminder is replaced by a short
  notification with the same tag, e.g. „Pipi-Runde erledigt ✓ · Riv“ (see `entwuerfe/16`).
- **Quiet hours** (household-wide, on/off, from–to): no reminders and no catch-up afterwards.
  Night routines can still exist in the plan and be ticked off.
- Scheduling stays simple: one process checks due reminders every minute.

### History („Verlauf“)
- Period selector: **1, 2, 4 weeks; 2, 4, 6 months; 1 year**. Short periods per day, long periods
  per week.
- Adherence over time (bars). The current day is highlighted.
- **Accidents inside** as a number with comparison to the previous period of the same length.
- Outside/inside ratio for **pee** and **poo**, and the number of „nichts gemacht“ outings.
- **Per routine:** kept x of y, average deviation (e.g. "on average 12 min late"), skipped and
  missed counts; problem routines first.
- Events of a day (today by default), editable.

## My calls (not discussed; the builder may revise with care)

- The 15-minute tolerance is one global value, not per routine.
- Adherence rate = kept ÷ (all routine occurrences − skipped). Late-but-done counts as done but
  not as kept. Missed counts against the rate.
- Overdue starts after the tolerance (e.g. 10:16 for a 10:00 routine).
- **History must not change when routines change:** each day keeps the routine plan it had
  (planned time/window, kind, assignee). Editing or deleting a routine affects today (if still open)
  and the future only. Deleting a routine archives it; its history stays.
- A routine created during the day counts today only if its planned time is still ahead;
  otherwise it starts tomorrow.
- Windows do not cross midnight.
- Past days can be corrected: in „Verlauf“ a day view lists that day's routines with tick off,
  skip and reopen (e.g. the 02:00 night outing logged the next morning). Back-dated events match
  that day's routines with the same ±15 rule; "missed" is therefore not final at midnight.
- If a matching event arrives for a routine already ticked off by hand (non-Lösen kinds), it is
  linked to that routine; the routine keeps its recorded time.
- An accident inside with pee and poo counts as **one accident**; the pee and poo inside counts
  are still kept separately for the ratios.
- Where older mockups disagree with this document (separate Pipi/Kaka routine kinds in
  `entwuerfe/07`, "Erinnerungen werden morgens nachgeholt" in `entwuerfe/08`, the opt-in
  „Routine gleich abhaken“ checkbox in `Eintragen.dc.html`), this document wins.
- On "Heute": the round check button ticks off **now** (fast path; for Lösen see above); tapping the row opens a sheet
  with the time quick select (Jetzt, vor 15/20/30 Min, Uhrzeit) and actions (abhaken,
  überspringen, wieder öffnen). Tapping a done check asks to reopen.
- Matching outside the ±15 range: nothing is pre-selected; the open routines are listed closest
  first.
- Editing an event's time or type re-evaluates its routine link; deleting an event that fulfilled a
  routine puts the routine back to open (or missed for a past day). Unticking a routine that was
  fulfilled by an event keeps the event.
- Events can be back-dated (also to earlier days) via the exact time/date option.
- A "done/skipped" replacement notification is only sent to devices that actually got a reminder
  for that routine occurrence.
- Who gets reminders: a per-member switch in „Haushalt & Mitteilungen“ (as in `entwuerfe/08`).
- Quick buttons on "Heute": Pipi, Kaka, Mahlzeit, Gassi; a button „Eintragen“ opens the full form
  with all types. Weighing stays reachable via „Gesundheit“.
- Statistics periods are rolling, ending today.

## Left to the builder

- Data model (e.g. whether daily routine occurrences are materialised or derived from versioned
  routines), as long as the history rule above holds and statistics stay fast enough for a year
  of data on SQLite.
- Reminder process details: idempotency (never send twice), behaviour after a restart, how late a
  missed minute may still be sent.
- Chart rendering (server-side SVG like the weight chart is fine), aggregation queries, exact copy.
- Which lists use Cinder and how (AGENTS.md: Cinder at least as the base for Ash resource lists).
