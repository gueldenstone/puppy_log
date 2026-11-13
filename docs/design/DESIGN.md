# Puppy Log – Design Spec

Reference for the LiveView implementation. The six files in `design/` are clickable HTML mockups
("Design Component" format, not HEEx). They are a **visual template**: adopt layout, colors,
spacing and behavior, do not copy the code. All data in them is sample data.

UI texts are German; quoted labels below („Heute“, „Überspringen“, …) are the exact UI strings.

## Basics
- Mobile-first for iPhone (mockup: 390×844), used as a PWA from the home screen. UI language: German.
- Bottom tab bar (72 px): „Heute“, „Verlauf“, „Gesundheit“, „Lernen“. Active tab in the accent color, `aria-current="page"`.
- Touch targets at least 44 px. Real `<button>`, `<a>`, `<input>` with `<label>`.
- Never convey state by color alone: always add text or an icon (pee/poo, outside/inside, status chips).

## Colors
| Purpose | Value |
|---|---|
| Background | #F3F5F2 |
| Card | #FFFFFF, border #DDE3DE, dividers #E6EBE7 |
| Text / muted | #14201B / #55645D |
| Accent (actions, done) | #0E6B52, tint #D7EDE4, dark #0B4F3D |
| Pee („Pipi“) | #1D5FA8, tint #E3EEF9 |
| Poo („Kaka“) | #7A4A1E, tint #F3E7DA |
| Neutral tint (icons, tracks) | #E4EAE6 |
| Overdue / accident | #A32A1C, tint #FBE4E0, light #F0C6C0 |
| Warning / due soon | #8A5200, tint #FDF0D5 |
| Unchecked border | #6B7B73 |
| Input border | #C5CEC8 (replaced, see technical requirements) |

## Typography
- Headings and large numbers: Space Grotesk 600 (page title 26/30, key figures 28/34).
- Body text: Inter 400/500/600. Default 15/20, meta 12.5–13, tab labels 12.

## Shape and spacing
- Page margin 16, gap between cards 12, card padding 16, card radius 16.
- Tiles 14, inputs and buttons 12–14, chips 10. Primary button 52 high, accent with white text.
- Progress bar 8 px high, radius 4, track #E4EAE6.
- Icons: 2 px stroke, rounded, 24 px grid (droplet = pee, three stacked pills = poo, bowl = meal).

## Screens and behavior
1. **Today** („Heute“, `Main.dc.html`): header with name, age, weight, household avatars. Card „Routinen heute“
   (x of y, percentage, bar). List of routines with a check button; states: done (time, who),
   open, overdue (red, „Seit N Min fällig“). Below, four quick buttons (pee, poo, meal, walk).
   Checking updates counter and bar immediately, live on both phones (PubSub).
2. **Log an event** („Eintragen“, `Eintragen.dc.html`): type grid (pee, poo, meal, walk, sleep, play, vomiting, other).
   For pee/poo a „Wo?“ choice appears (outside/inside); inside = accident, with a hint, does not fulfil a routine.
   When (default: now) and who. If a due routine matches, there is a checkbox „Routine gleich abhaken“
   (one operation). Note field, button „Eintragen“.
3. **History** („Verlauf“, `Verlauf.dc.html`): routine adherence per day of the week (today highlighted,
   future days dashed), outside/inside ratio for pee and poo, frequently skipped routines,
   today's events.
4. **Health** („Gesundheit“, `Gesundheit.dc.html`): next appointment card, weight curve by weeks of life,
   list of vaccinations and preventive care with a status chip (done / in N days). Users enter appointments
   themselves (see decisions 13–16).
5. **Learning** („Lernen“, `Lernen.dc.html`): toggle socialization/commands. Socialization: overall progress,
   categories (people, animals, noises, surfaces, places), recently rated with a reaction from 1 to 5.
   Commands: weekly stats, learning stage per command in four levels („Neu“, „Übt“, „Sicher“, „Unter Ablenkung“).
6. **Setup** („Einrichten“, `Einrichten.dc.html`): steps sign-in via link, home screen hint,
   push permission, test notification (only active after permission). Order changed, see decision 9.

## Implementation notes
- All values are inline in the mockups; in Phoenix define them once as Tailwind theme values or CSS variables,
  not repeated everywhere.
- Recurring building blocks as function components: card, chip, progress bar, check button,
  type tile, tab bar.

## Decisions (2026-11-12, mockups approved)
Supplementary mockups in the same style live in `entwuerfe/` (overview: `entwuerfe/index.html`,
regenerate with `python3 entwuerfe/generator/build.py entwuerfe`).

1. **Profile and settings without their own tab:** tapping photo/name in the header of „Heute“ opens the profile
   (`02`, `03`), tapping the household avatars opens „Haushalt & Mitteilungen“ (`08`). From there: manage
   routines (`06`, `07`), export (`13`), test notification.
2. **Skip by swiping:** swiping a routine to the left reveals „Überspringen“ (`01`). Skipped routines are grey
   with icon and text and do not count towards the rate. Weight entries: swipe to edit/delete (`04`).
   A long press shows the same actions (alternative to the gesture); keyboard/VoiceOver users can focus them.
3. **Done on the other phone:** iOS requires a visible notification for every push. The reminder is therefore
   replaced by a "done" notification with the same tag, e.g. „Pipi-Runde erledigt ✓ · Riv“ (`16`).
4. **User-defined goals:** socialization has no template; you set a goal per category yourself (`10`).
   Health appointments can optionally have a user-defined repetition („alle 4 Wochen“);
   completing one creates the next appointment (`09`). (confirmed)
5. **No dark mode.** Light theme only.
6. **Routines:** no repetition within a day; every round is its own routine.
   A routine can be linked to training: a training session checks it off.
7. **Commands:** after 3 sessions with more than 80 % success the app suggests „Sicher“.
8. **No "who" field** in forms: we store who made the entry (also applies to `Eintragen.dc.html`).
9. **Setup order corrected** (`14`): first the home screen, then sign in inside the app (paste the link),
   then allow notifications, then test. The home screen app has its own cookies.

## Decisions (2026-11-13, routines and events)
Full rules: `docs/superpowers/specs/2026-11-12-alltag-routines-events-design.md`. Where older mockups
disagree with that spec, the spec wins.

10. **Arrival date gates everything that counts:** the puppy profile has an arrival date („Einzug“).
    Routines can be created and edited before it (`/routines`), but occurrences, reminders and
    statistics start on that day. A routine created during the day starts today only if its time
    is still ahead. Without an arrival date „Heute“ and „Verlauf“ ask for it; when it lies in the future
    „Heute“ shows „Bald geht es los“ with a link „Tagesablauf vorbereiten“.
11. **Ticking a potty routine asks what happened:** the check button of a „Lösen“ routine opens the
    choice „Pipi · Kaka · beides · nichts“ (outside) and creates that potty event, so the house-training
    numbers stay complete. All other kinds tick off with one tap. Tapping the row opens a sheet with the
    time quick select („Jetzt“, „vor 15 Min“, „vor 20 Min“, „vor 30 Min“, „Uhrzeit“): punctuality uses the
    entered time. In „Eintragen“ the routine link is a choice (auto-selected within ±15 minutes,
    otherwise the day's open matching routines closest first, or „Keine“) instead of the checkbox
    „Routine gleich abhaken“ in `Eintragen.dc.html`. The „Eintragen“ button stays pinned at the bottom
    of the sheet while it scrolls.
12. **„Verlauf“ with a day view for corrections:** period chips (1, 2, 4 weeks; 2, 4, 6 months; 1 year),
    adherence bars per day (per week for long periods; today highlighted, days without counted
    routines dashed; daily bars open that day), accidents inside compared with the previous period,
    outside/inside split for pee and poo, and per-routine stats with problem routines first (replaces
    „Oft ausgelassen“). The day view (`/history/:date`) lists that day's routines and events: past
    routines can be ticked off with their real time, skipped or reopened, events added, edited or
    deleted, e.g. the 02:00 night outing logged the next morning.

## Decisions (2026-11-13, health entries and calendar)
Full rules: `docs/superpowers/specs/2026-11-13-health-appointments-design.md`.

13. **Health entries are entered by hand:** no built-in vaccination or deworming plan. One kind of
    record (`HealthEntry`) covers care items („Impfung“, „Entwurmung“, „Floh/Zecke“, „Andere
    Vorsorge“: a due date, optionally „alle N Wochen“) and vet appointments („Tierarzt“: date, time,
    place, „Zuständig“). The form (`09`) shows five kind tiles (three over two) instead of the
    mockup's four. Entries from before the arrival can be entered directly as „Bereits erledigt“.
14. **Status chips:** „Erledigt“ (accent), „Heute“ and „In N Tagen“ within the entry's lead time
    (warning), „In N Tagen“ later (neutral), „Überfällig“ (red; also in the „Nächster Termin“ card
    as „seit N Tagen überfällig“). Open entries come first by due date, done ones below, newest
    first. As in the other Cinder lists, the section label „Impfungen und Vorsorge“ with
    „Termin eintragen“ sits above the card, not inside it as in `Gesundheit.dc.html`.
    Swipe left: „Erledigt“ opens a sheet with „Wann“ (and „Impfstoff/Charge“ for vaccinations);
    a done entry offers „Wieder öffnen“. Completing a repeating item creates the next one
    from the completion date.
15. **Calendar alarms instead of push:** health entries send no Web Push. Reminders are `VALARM`s
    in the calendar subscription: care items at 09:00 N days before (household default „Termine
    erinnern“ in `/settings`, editable per entry, 0 = on the day), vet appointments N days and
    2 hours before. Done entries stay in the calendar with „✓“ and without alarms. The steppers
    show the value as text next to them („2 Tage vorher“, „Alle 4 Wochen“), not inside as in `09`.
16. **One household calendar:** every member has their own secret feed address
    (`/calendar/<token>.ics`, card „Kalender-Abo“ in `/settings`, `webcal://` link plus the
    https address to copy), but each feed contains all household entries, whoever goes to the
    appointment („Geht hin: …“ in the description). „Neue Adresse erzeugen“ invalidates the old
    address. The card explains that on the iPhone „Alarme entfernen“ must be switched off.
17. **Due at an age:** a health entry is either due on a date or „mit N Wochen/Monaten“, chosen in
    the form via „Fällig: Datum | Alter“ (age needs the profile's birth date; the form shows the
    resulting date as „→ Mi, 2. Dez“). Weeks = birth date + 7·N days, months = same day N months
    later, clamped to the month's end. The stored date is derived: open age entries are recomputed
    when the birth date is corrected, done entries and fixed-date entries never move. The successor
    of a repeating entry gets a fixed date. The list shows „02.12. · mit 8 Wochen“, the calendar
    event keeps its title and mentions the age in the description.

**URLs are English** (UI texts stay German): `/`, `/routine/:id`, `/log?type=pee|poo|meal|walk`,
`/history`, `/history/:date`, `/health`, `/health/new`, `/health/:id`, `/health/:id/done`,
`/learn`, `/profile`, `/profile/edit`, `/weight`, `/weight/new`, `/weight/:id`, `/settings`,
`/routines`, `/routines/new`, `/routines/:id`; calendar feed `/calendar/:token.ics`.

## Technical requirements
- Serve the fonts (Inter, Space Grotesk, both OFL) ourselves instead of Google Fonts (AGENTS.md: no external links).
- Input border `#84918A` instead of `#C5CEC8` (3.3:1 instead of 1.6:1 contrast, WCAG 1.4.11).
- Pages scroll; tab bar 72 px plus `env(safe-area-inset-bottom)`.
- Lists of Ash resources use Cinder with a custom theme in these colors (no daisyUI theme).
- App icon in green.
- Weight: input in kg with a decimal comma (`inputmode="decimal"`), stored in grams.
