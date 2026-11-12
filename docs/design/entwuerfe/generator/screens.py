from base import icon, tabbar

def photo(size, icon_size=None):
    return f'<div class="photo" style="width:{size}px;height:{size}px">{icon("paw", icon_size or size//2, "#fff")}</div>'

def back(title, right=""):
    return f'<header class="bar-head"><a class="icon-btn" href="#" aria-label="Zurück">{icon("left")}</a><h1>{title}</h1>{right}</header>'

def close(title, right=""):
    return f'<header class="bar-head"><a class="icon-btn" href="#" aria-label="Schließen">{icon("x")}</a><h1>{title}</h1>{right}</header>'

S = {}

# 01 Heute mit Wischen ---------------------------------------------------------
def routine(state, title, meta, time, who=None):
    box = {"done": f'<span class="check done">{icon("check",16,"#fff",3)}</span>',
           "open": '<span class="check"></span>',
           "late": '<span class="check late"></span>',
           "skipped": f'<span class="check skipped">{icon("skip",14,"#55645D",2.5)}</span>'}[state]
    meta_style = ' style="color:var(--bad);font-weight:600"' if state=="late" else ""
    title_style = ' style="color:var(--muted)"' if state=="skipped" else ""
    return f'''<div class="row" style="padding-left:16px">
<button class="check-btn" aria-label="Abhaken: {title}">{box}</button>
<div class="grow"><div class="t"{title_style}>{title}</div><div class="m"{meta_style}>{meta}</div></div>
<div class="m mono">{time}</div></div>'''

swiped = f'''<div class="swipe-wrap">
<div class="swipe-action">
<button style="background:var(--warn)">{icon("skip",20,"#fff")}Überspringen</button>
</div>
<div class="row swipe-front" style="border-top:0;padding-left:16px">
<button class="check-btn" aria-label="Abhaken: Mittagsschlaf"><span class="check"></span></button>
<div class="grow"><div class="t">Mittagsschlaf in der Box</div><div class="m">12:30 bis 14:00</div></div>
<div class="m mono">12:30</div></div></div>'''

S["01-heute.html"] = ("Today (swipe, skip)", f'''
<main class="scroll">
<a href="02-profil.html" class="page-head" aria-label="Profil von Bruno öffnen">
{photo(48, 24)}
<div style="flex:1;min-width:0"><h1>Bruno</h1><div class="sub">14 Wochen · 7,8 kg · Do, 12. Nov</div></div>
</a>
<section class="card">
<div style="display:flex;justify-content:space-between"><span class="label">Routinen heute</span><span class="label mono">67 %</span></div>
<div class="big" style="margin-top:2px">4 von 6</div>
<div class="progress" style="margin-top:10px"><i style="width:67%"></i></div>
<div class="m" style="margin-top:8px;font-size:12.5px;color:var(--muted)">1 übersprungen zählt nicht mit</div>
</section>
<section class="card flush" style="padding-top:4px">
{routine("done","Pipi-Runde nach dem Aufwachen","Erledigt 07:05 · Du","07:00")}
{routine("done","Frühstück","Erledigt 07:42 · Riv","07:30")}
{routine("skipped","Training, 5 Minuten","Übersprungen · Du","09:00")}
{routine("late","Pipi-Runde","Seit 20 Min fällig","10:00")}
{swiped}
{routine("open","Mittagessen","Um 13:00","13:00")}
</section>
<p class="hint" style="text-align:center">Nach links wischen: überspringen · Antippen: abhaken</p>
<section>
<div class="section-label" style="padding-bottom:8px">Schnell eintragen</div>
<div class="tiles">
<a class="tile" style="color:var(--pipi);height:84px"><span style="width:36px;height:36px;border-radius:18px;background:var(--pipi-t);display:flex;align-items:center;justify-content:center">{icon("pipi",20,"#1D5FA8")}</span>Pipi</a>
<a class="tile" style="color:var(--kaka);height:84px"><span style="width:36px;height:36px;border-radius:18px;background:var(--kaka-t);display:flex;align-items:center;justify-content:center">{icon("kaka",20,"#7A4A1E")}</span>Kaka</a>
<a class="tile" style="height:84px"><span style="width:36px;height:36px;border-radius:18px;background:var(--neu);display:flex;align-items:center;justify-content:center">{icon("bowl",20)}</span>Mahlzeit</a>
<a class="tile" style="height:84px"><span style="width:36px;height:36px;border-radius:18px;background:var(--neu);display:flex;align-items:center;justify-content:center">{icon("gassi",20)}</span>Gassi</a>
</div></section>
</main>
<a href="08-einstellungen.html" aria-label="Haushalt und Mitteilungen" style="position:absolute;top:32px;right:20px;display:flex">
<span class="avatar" style="background:var(--acc)">Du</span><span class="avatar" style="background:var(--pipi);margin-left:-8px">R</span></a>
{tabbar("Heute")}''',
 "Tapping photo/name opens the profile, tapping the avatars opens household & notifications. Swiping left reveals „Überspringen“ (skip). Skipped routines are grey with an icon and do not count towards the rate.")

# 02 Profil --------------------------------------------------------------------
S["02-profil.html"] = ("Profile", f'''
<main class="scroll">
{back("Profil", f'<a class="link-btn" href="03-profil-bearbeiten.html">{icon("edit",18)}Bearbeiten</a>')}
<section style="display:flex;flex-direction:column;align-items:center;gap:8px;padding:8px 0 4px">
{photo(128, 56)}
<div class="title" style="margin-top:6px">Bruno</div>
<div class="sub">14 Wochen alt · geboren am 6. August 2026</div>
</section>
<section class="card flush">
<div class="row"><div class="grow"><div class="m">Rasse</div><div class="t">Labrador Retriever</div></div></div>
<div class="row"><div class="grow"><div class="m">Chipnummer</div><div class="t mono">276 098 106 543 210</div></div>
<button class="icon-btn" aria-label="Chipnummer kopieren" style="color:var(--acc)">{icon("copy",20)}</button></div>
<div class="row"><div class="grow"><div class="m">Geburtsdatum</div><div class="t">6. August 2026</div></div></div>
</section>
<a class="card" href="04-gewicht.html" style="display:flex;align-items:center;gap:12px">
<span style="width:40px;height:40px;border-radius:20px;background:var(--acc-t);display:flex;align-items:center;justify-content:center;color:var(--acc)">{icon("scale",22)}</span>
<div style="flex:1"><div class="label">Gewicht</div><div style="font-weight:600">7,8 kg · +0,6 kg seit letzter Woche</div></div>
<span class="chev">{icon("right",20)}</span></a>
<a class="card" href="13-export.html" style="display:flex;align-items:center;gap:12px">
<span style="width:40px;height:40px;border-radius:20px;background:var(--neu);display:flex;align-items:center;justify-content:center">{icon("download",22)}</span>
<div style="flex:1"><div style="font-weight:600">Für den Tierarzt exportieren</div><div class="m" style="font-size:12.5px;color:var(--muted)">PDF oder CSV</div></div>
<span class="chev">{icon("right",20)}</span></a>
<p class="hint" style="text-align:center">Zuletzt geändert von Riv am 10. November</p>
</main>''',
 "Reached via photo/name on „Heute“. Shows all master data; the chip number is grouped for reading and can be copied. Weight and export are reachable from here.")

# 03 Profil bearbeiten ---------------------------------------------------------
S["03-profil-bearbeiten.html"] = ("Edit profile", f'''
<main class="scroll" style="gap:16px">
{close("Profil bearbeiten")}
<section style="display:flex;flex-direction:column;align-items:center;gap:10px">
<div style="position:relative">{photo(112, 48)}
<span style="position:absolute;right:0;bottom:0;width:40px;height:40px;border-radius:20px;background:var(--acc);border:3px solid var(--bg);display:flex;align-items:center;justify-content:center">{icon("camera",18,"#fff")}</span></div>
<button class="link-btn">Foto ändern</button>
</section>
<div class="field"><label for="n">Name</label><input id="n" class="input" value="Bruno"></div>
<div class="field"><label for="b">Geburtsdatum</label><input id="b" class="input" value="06.08.2026"></div>
<div class="field"><label for="r">Rasse</label><input id="r" class="input" value="Labrador Retriever"></div>
<div class="field"><label for="c">Chipnummer</label><input id="c" class="input invalid mono" inputmode="numeric" value="2760981065432">
<div class="err">Die Chipnummer hat 15 Ziffern, hier sind es 13.</div></div>
<div style="flex:1"></div>
<button class="btn primary">Speichern</button>
</main>''',
 "Photo from camera or library. Errors appear right at the field, in words and not only in red. Chip number with a numeric keyboard.")

# 04 Gewicht -------------------------------------------------------------------
pts=[(28,106),(75,91),(123,73),(171,58),(218,41),(266,27),(314,16)]
poly=" ".join(f"{x},{y}" for x,y in pts)
chart=f'''<svg viewBox="0 0 330 136" width="100%" role="img" aria-label="Gewichtskurve: von 4,1 kg in Woche 8 auf 7,8 kg in Woche 14">
<g stroke="#DDE3DE" stroke-dasharray="3 3"><line x1="22" y1="12" x2="326" y2="12"/><line x1="22" y1="50" x2="326" y2="50"/><line x1="22" y1="89" x2="326" y2="89"/></g>
<g font-size="11" fill="#55645D"><text x="0" y="16">8</text><text x="0" y="54">6</text><text x="0" y="93">4</text></g>
<polyline points="{poly}" fill="none" stroke="#0E6B52" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
{''.join(f'<circle cx="{x}" cy="{y}" r="3.5" fill="#0E6B52"/>' for x,y in pts[:-1])}
<circle cx="314" cy="16" r="5" fill="#0E6B52" stroke="#fff" stroke-width="2"/>
<g font-size="11" fill="#55645D" text-anchor="middle">{''.join(f'<text x="{x}" y="128">{w}</text>' for (x,_),w in zip(pts[:-1],range(8,14)))}<text x="314" y="128" font-weight="600" fill="#14201B">14 W.</text></g></svg>'''
def wrow(date, kg, delta, who, note=None):
    n = f' · {note}' if note else ''
    return f'<div class="row"><div class="grow"><div class="t">{date}</div><div class="m">{who}{n}</div></div><div style="text-align:right"><div class="t mono">{kg} kg</div><div class="m mono">{delta}</div></div></div>'
S["04-gewicht.html"] = ("Weight", f'''
<main class="scroll">
{back("Gewicht")}
<section class="card">
<div style="display:flex;align-items:baseline;gap:8px"><div class="big">7,8 kg</div><div class="label">+0,6 kg seit letzter Woche</div></div>
<div style="margin-top:8px">{chart}</div>
<div class="seg" style="grid-template-columns:repeat(3,1fr);margin-top:8px"><button aria-pressed="true">Lebenswochen</button><button>3 Monate</button><button>Alles</button></div>
</section>
<div class="section-label">Einträge</div>
<section class="card flush">
{wrow("Do, 12. Nov","7,8","+600 g","Du")}
<div class="swipe-wrap"><div class="swipe-action"><button style="background:var(--acc)">{icon("edit",20,"#fff")}Ändern</button><button style="background:var(--bad)">{icon("trash",20,"#fff")}Löschen</button></div>
<div class="row swipe-front" style="border-top:0"><div class="grow"><div class="t">Do, 5. Nov</div><div class="m">Riv · nach dem Fressen</div></div><div style="text-align:right"><div class="t mono">7,2 kg</div><div class="m mono">+550 g</div></div></div></div>
{wrow("Do, 29. Okt","6,65","+700 g","Du")}
{wrow("Do, 22. Okt","5,95","+650 g","Riv")}
</section>
</main>
<div style="position:absolute;left:16px;right:16px;bottom:24px"><button class="btn primary">{icon("plus",20,"#fff")}Wiegen eintragen</button></div>''',
 "Curve by weeks of life (needs the birth date, otherwise by date). List via Cinder in our colors; swipe left (or long-press) to edit/delete. Difference to the previous entry in grams.")

# 05 Wiegen eintragen (Sheet) --------------------------------------------------
S["05-wiegen.html"] = ("Log a weighing", f'''
<main class="scroll" style="filter:none">{back("Gewicht")}<section class="card" style="height:220px"></section><section class="card" style="height:240px"></section></main>
<div class="sheet-backdrop"></div>
<section class="sheet" role="dialog" aria-label="Wiegen eintragen">
<div class="grabber"></div>
<div style="display:flex;align-items:center"><h2 style="margin:0;flex:1;font-family:var(--display);font-size:22px">Wiegen eintragen</h2><button class="icon-btn" aria-label="Schließen">{icon("x")}</button></div>
<div class="field"><label for="kg">Gewicht in kg</label><input id="kg" class="input big-num mono" inputmode="decimal" value="8,15">
<div class="hint" style="text-align:center">+350 g seit dem letzten Mal (vor 3 Tagen)</div></div>
<div class="field"><label for="d">Datum</label><input id="d" class="input" value="Heute"></div>
<div class="field"><label for="no">Notiz</label><input id="no" class="input" placeholder="Optional, zum Beispiel vor dem Fressen"></div>
<button class="btn primary">Speichern</button>
</section>''',
 "Bottom sheet over the weight page. Large number, decimal comma keyboard (inputmode=decimal), date defaults to today. Shows the change since the last entry right away.")

# 06 Routinen ------------------------------------------------------------------
def rr(ic, color, bg, title, when, days, reminder=True):
    bell = icon("bell",16,"#55645D") if reminder else '<span class="m">aus</span>'
    return f'''<a class="row" href="07-routine.html"><span style="width:36px;height:36px;border-radius:18px;background:{bg};display:flex;align-items:center;justify-content:center;color:{color}">{icon(ic,18)}</span>
<div class="grow"><div class="t">{title}</div><div class="m">{when} · {days}</div></div>{bell}<span class="chev">{icon("right",18)}</span></a>'''
S["06-routinen.html"] = ("Routines", f'''
<main class="scroll">
{back("Routinen")}
<p class="sub" style="margin:0;padding:0 4px">Wiederkehrende Aufgaben für Bruno. Sie erscheinen auf „Heute“ und erinnern euch.</p>
<div class="section-label">Morgens</div>
<section class="card flush">
{rr("pipi","#1D5FA8","var(--pipi-t)","Pipi-Runde nach dem Aufwachen","07:00","täglich")}
{rr("bowl","#14201B","var(--neu)","Frühstück","07:30","täglich")}
{rr("target","#14201B","var(--neu)","Training, 5 Minuten","09:00 bis 11:00","Mo–Fr")}
</section>
<div class="section-label">Mittags</div>
<section class="card flush">
{rr("pipi","#1D5FA8","var(--pipi-t)","Pipi-Runde","10:00","täglich")}
{rr("pipi","#1D5FA8","var(--pipi-t)","Pipi-Runde","12:00","täglich")}
{rr("moon","#14201B","var(--neu)","Mittagsschlaf in der Box","12:30 bis 14:00","täglich", False)}
{rr("bowl","#14201B","var(--neu)","Mittagessen","13:00","täglich")}
</section>
</main>
<div style="position:absolute;left:16px;right:16px;bottom:24px"><button class="btn primary">{icon("plus",20,"#fff")}Neue Routine</button></div>''',
 "Reached via settings (and later „Bearbeiten“ on today). Grouped by time of day; the bell shows whether a reminder is sent. Several rounds per day are separate routines.")

# 07 Routine bearbeiten --------------------------------------------------------
S["07-routine.html"] = ("Edit routine", f'''
<main class="scroll" style="gap:16px">
{close("Routine bearbeiten")}
<div class="field"><label for="t">Name</label><input id="t" class="input" value="Training, 5 Minuten"></div>
<section>
<div class="label" style="padding:0 2px 8px">Wird erledigt durch</div>
<div class="tiles">
<button class="tile">{icon("pipi")}Pipi</button><button class="tile">{icon("kaka")}Kaka</button><button class="tile">{icon("bowl")}Mahlzeit</button><button class="tile">{icon("gassi")}Gassi</button>
<button class="tile">{icon("moon")}Schlaf</button><button class="tile">{icon("ball")}Spiel</button><button class="tile" aria-pressed="true">{icon("target")}Training</button><button class="tile">{icon("check")}Nur abhaken</button>
</div>
<div class="hint" style="padding-top:8px">Trägt jemand ein passendes Ereignis ein, wird die Routine automatisch abgehakt.</div>
</section>
<section style="display:flex;flex-direction:column;gap:8px">
<div class="label" style="padding:0 2px">Wann</div>
<div class="seg" style="grid-template-columns:1fr 1fr"><button>Feste Uhrzeit</button><button aria-pressed="true">Zeitfenster</button></div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
<div class="field"><label for="f">Von</label><input id="f" class="input" value="09:00"></div>
<div class="field"><label for="u">Bis</label><input id="u" class="input" value="11:00"></div></div>
</section>
<section style="display:flex;flex-direction:column;gap:8px">
<div class="label" style="padding:0 2px">An diesen Tagen</div>
<div class="daychips">{''.join(f'<button aria-pressed="{str(d not in ("Sa","So")).lower()}">{d}</button>' for d in ["Mo","Di","Mi","Do","Fr","Sa","So"])}</div>
</section>
<section class="card flush">
<div class="row"><div class="grow"><div class="t">Erinnern</div><div class="m">Zu Beginn des Zeitfensters</div></div><button class="toggle" role="switch" aria-checked="true" aria-label="Erinnern"></button></div>
<div class="row"><div class="grow"><div class="t">Nachfragen, wenn offen</div><div class="m">Nach 30 Minuten</div></div><button class="toggle" role="switch" aria-checked="true" aria-label="Nachfragen"></button></div>
</section>
<button class="btn primary">Speichern</button>
<button class="btn ghost-danger">Routine löschen</button>
</main>''',
 "Fixed time or time window, weekdays as chips. „Wird erledigt durch“ links the routine to an event type – the basis for \"event fulfils routine\". Reminder and follow-up per routine.")

# 08 Einstellungen -------------------------------------------------------------
S["08-einstellungen.html"] = ("Household & notifications", f'''
<main class="scroll">
{back("Haushalt & Mitteilungen")}
<div class="section-label">Haushalt</div>
<section class="card flush">
<div class="row"><span class="avatar" style="background:var(--acc);border:0">Du</span><div class="grow"><div class="t">Lukas</div><div class="m">Dieses iPhone · Mitteilungen aktiv</div></div><button class="toggle" role="switch" aria-checked="true" aria-label="Lukas bekommt Erinnerungen"></button></div>
<div class="row"><span class="avatar" style="background:var(--pipi);border:0">R</span><div class="grow"><div class="t">Riv</div><div class="m">1 iPhone · Mitteilungen aktiv</div></div><button class="toggle" role="switch" aria-checked="true" aria-label="Riv bekommt Erinnerungen"></button></div>
</section>
<p class="hint">Der Schalter legt fest, wer Routine-Erinnerungen bekommt. Erledigt jemand eine Routine, ersetzt eine kurze Mitteilung die Erinnerung auf dem anderen Handy.</p>
<div class="section-label">Ruhezeiten</div>
<section class="card flush">
<div class="row"><div class="grow"><div class="t">Nachts nicht stören</div><div class="m">Erinnerungen werden morgens nachgeholt</div></div><button class="toggle" role="switch" aria-checked="true" aria-label="Ruhezeiten"></button></div>
<div class="row"><div class="grow"><div class="t">Von</div></div><span class="t mono">22:00</span></div>
<div class="row"><div class="grow"><div class="t">Bis</div></div><span class="t mono">06:30</span></div>
</section>
<div class="section-label">Gesundheit</div>
<section class="card flush">
<div class="row"><div class="grow"><div class="t">Termine erinnern</div><div class="m">Standard für neue Termine</div></div><span class="t">2 Tage vorher</span></div>
</section>
<div class="section-label">Mehr</div>
<section class="card flush">
<a class="row" href="06-routinen.html">{icon("repeat",20)}<div class="grow t">Routinen verwalten</div><span class="chev">{icon("right",18)}</span></a>
<a class="row" href="13-export.html">{icon("download",20)}<div class="grow t">Export für den Tierarzt</div><span class="chev">{icon("right",18)}</span></a>
<a class="row" href="16-mitteilungen.html">{icon("bell",20)}<div class="grow t">Test-Benachrichtigung senden</div><span class="chev">{icon("right",18)}</span></a>
<a class="row" href="#" style="color:var(--bad)">{icon("logout",20)}<div class="grow t">Auf diesem Gerät abmelden</div></a>
</section>
</main>''',
 "Reached via the avatars at the top right of „Heute“. Who gets reminders, quiet hours, default lead time for health appointments, plus routines, export and test.")

# 09 Termin eintragen ----------------------------------------------------------
S["09-termin.html"] = ("Add a health appointment", f'''
<main class="scroll" style="gap:16px">
{close("Termin eintragen")}
<section><div class="label" style="padding:0 2px 8px">Art</div>
<div class="tiles" style="grid-template-columns:repeat(4,minmax(0,1fr))">
<button class="tile">{icon("syringe")}Impfung</button><button class="tile" aria-pressed="true">{icon("pill")}Entwurmung</button><button class="tile">{icon("bug")}Floh/Zecke</button><button class="tile">{icon("steth")}Tierarzt</button>
</div></section>
<div class="field"><label for="t">Bezeichnung</label><input id="t" class="input" value="Entwurmung (Milbemax)"></div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
<div class="field"><label for="d">Datum</label><input id="d" class="input" value="29.11.2026"></div>
<div class="field"><label for="z">Uhrzeit</label><input id="z" class="input" placeholder="optional"></div></div>
<div class="field"><label for="o">Ort</label><input id="o" class="input" placeholder="Optional, zum Beispiel Praxis Dr. Berg"></div>
<section class="card flush">
<div class="row"><div class="grow"><div class="t">Erinnern</div><div class="m">Tage vorher</div></div><div class="stepper" style="width:140px"><button aria-label="weniger">−</button><span>2</span><button aria-label="mehr">+</button></div></div>
<div class="row"><div class="grow"><div class="t">Wiederholen</div><div class="m">Nach Erledigen kommt der nächste Termin</div></div><button class="toggle" role="switch" aria-checked="true" aria-label="Wiederholen"></button></div>
<div class="row"><div class="grow"><div class="t">Alle</div></div><div class="stepper" style="width:140px"><button aria-label="weniger">−</button><span>4 Wo.</span><button aria-label="mehr">+</button></div></div>
</section>
<div class="field"><label for="n">Notiz</label><input id="n" class="input" placeholder="Optional"></div>
<button class="btn primary">Speichern</button>
</main>''',
 "No template, but you can set a repetition yourself. Checking it off creates the next appointment. Reminder X days before, per appointment.")

# 10 Sozialisierung Kategorie --------------------------------------------------
def srow(name, who, rating):
    dots = "".join(f'<span class="{"on" if i<rating else ""}"></span>' for i in range(5)) if rating else ""
    meta = who if rating else "Noch nicht erlebt"
    right = f'<div class="dots" role="img" aria-label="Reaktion {rating} von 5">{dots}</div>' if rating else f'<span class="chip neu">offen</span>'
    return f'<a class="row" href="11-bewerten.html"><div class="grow"><div class="t">{name}</div><div class="m">{meta}</div></div>{right}</a>'
S["10-sozialisierung.html"] = ("Socialization: category", f'''
<main class="scroll">
{back("Geräusche", f'<button class="icon-btn" aria-label="Eintrag hinzufügen">{icon("plus")}</button>')}
<section class="card">
<div style="display:flex;justify-content:space-between"><span class="label">Erlebt und bewertet</span><button class="link-btn" style="padding:0;min-height:0">{icon("target",16)}Ziel: 20</button></div>
<div class="big" style="margin-top:2px">8 von 20</div>
<div class="progress" style="margin-top:10px"><i style="width:40%"></i></div>
<div class="hint" style="margin-top:8px;padding:0">Das Ziel legt ihr selbst fest. 10 Einträge habt ihr angelegt, 12 fehlen noch bis zum Ziel.</div>
</section>
<section class="card flush">
{srow("Staubsauger","Riv · gestern",3)}
{srow("Straßenbahn","Du · Dienstag",4)}
{srow("Türklingel","Du · 8. Nov",5)}
{srow("Feuerwerk (Video)","Riv · 6. Nov",2)}
{srow("Föhn","",0)}
{srow("Rasenmäher","",0)}
</section>
</main>
{tabbar("Lernen")}''',
 "Set a goal per category yourself (tap „Ziel“). You create the entries yourself (+). Rated = at least one rating; the dots show the latest reaction, with text for screen readers.")

# 11 Bewerten ------------------------------------------------------------------
labels=[("1","ängstlich"),("2","unsicher"),("3","neutral"),("4","neugierig"),("5","entspannt")]
S["11-bewerten.html"] = ("Rate an experience", f'''
<main class="scroll">{back("Geräusche")}<section class="card" style="height:160px"></section><section class="card" style="height:300px"></section></main>
<div class="sheet-backdrop"></div>
<section class="sheet" role="dialog" aria-label="Staubsauger bewerten">
<div class="grabber"></div>
<div style="display:flex;align-items:center"><div style="flex:1"><div class="label">Geräusche</div><h2 style="margin:0;font-family:var(--display);font-size:22px">Staubsauger</h2></div><button class="icon-btn" aria-label="Schließen">{icon("x")}</button></div>
<div><div class="label" style="padding:0 2px 8px">Wie hat Bruno reagiert?</div>
<div class="rating">{''.join(f'<button aria-pressed="{str(n=="4").lower()}"><b>{n}</b>{l}</button>' for n,l in labels)}</div></div>
<div class="field"><label for="d">Wann</label><input id="d" class="input" value="Heute"></div>
<div class="field"><label for="n">Notiz</label><input id="n" class="input" value="Erst gebellt, dann neugierig geschnuppert"></div>
<button class="btn primary">Speichern</button>
<p class="hint" style="text-align:center;margin:0">Bisher: 3 Bewertungen, zuletzt 3 (neutral)</p>
</section>''',
 "Reaction 1 to 5 with words, not just numbers. Several ratings per entry so you can see progress.")

# 12 Übungseinheit -------------------------------------------------------------
S["12-uebung.html"] = ("Log a training session", f'''
<main class="scroll" style="gap:16px">
{close("Übungseinheit")}
<section><div class="label" style="padding:0 2px 8px">Kommando</div>
<div style="display:flex;flex-wrap:wrap;gap:8px">{''.join(f'<button class="chip {"sel" if c=="Platz" else "neu"}" style="height:40px;padding:0 14px;font-size:14px;border:0;cursor:pointer" aria-pressed="{str(c=="Platz").lower()}">{c}</button>' for c in ["Name hören","Sitz","Platz","Komm","Bleib"])}
<button class="chip neu" style="height:40px;padding:0 14px;font-size:14px;border:0">{icon("plus",14)}Neu</button></div></section>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
<div class="field"><label>Dauer</label><div class="stepper"><button aria-label="weniger">−</button><span>5 Min</span><button aria-label="mehr">+</button></div></div>
<div class="field"><label>Wann</label><div class="input" style="display:flex;align-items:center">Jetzt, 10:22</div></div></div>
<section class="card">
<div class="label">Wie oft hat es geklappt?</div>
<div style="display:grid;grid-template-columns:1fr auto 1fr;gap:8px;align-items:end;margin-top:8px">
<div class="field"><label>Geklappt</label><div class="stepper"><button>−</button><span>8</span><button>+</button></div></div>
<div style="padding-bottom:14px;color:var(--muted)">von</div>
<div class="field"><label>Versuche</label><div class="stepper"><button>−</button><span>10</span><button>+</button></div></div></div>
<div style="margin-top:12px;display:flex;align-items:baseline;gap:8px"><span class="big">80 %</span><span class="label">Erfolg</span></div>
</section>
<section><div class="label" style="padding:0 2px 8px">Lernstand „Platz“</div>
<div class="seg" style="grid-template-columns:repeat(4,1fr)"><button>Neu</button><button aria-pressed="true">Übt</button><button>Sicher</button><button style="font-size:12px">Ablenkung</button></div>
<div class="hint" style="padding-top:8px">Bei 3 Einheiten über 80 % schlagen wir „Sicher“ vor.</div></section>
<button class="btn primary">Speichern</button>
</main>''',
 "Success as \"succeeded out of attempts\" – this gives the percentage on the learning tab. Learning stage adjustable right here. Suggests „Sicher“ after 3 sessions above 80 %.")

# 13 Export --------------------------------------------------------------------
def opt(label, sub, on=True):
    return f'<div class="row"><div class="grow"><div class="t">{label}</div><div class="m">{sub}</div></div><button class="toggle" role="switch" aria-checked="{str(on).lower()}" aria-label="{label}"></button></div>'
S["13-export.html"] = ("Export for the vet", f'''
<main class="scroll" style="gap:16px">
{back("Export")}
<section style="display:flex;flex-direction:column;gap:8px"><div class="label" style="padding:0 2px">Zeitraum</div>
<div class="seg" style="grid-template-columns:repeat(3,1fr)"><button>4 Wochen</button><button>3 Monate</button><button aria-pressed="true">Seit Geburt</button></div></section>
<section class="card flush">
{opt("Stammdaten","Name, Rasse, Chip, Geburtsdatum")}
{opt("Impfungen und Vorsorge","Erledigte und geplante Termine")}
{opt("Gewicht","Kurve und Tabelle")}
{opt("Auffälligkeiten","Erbrechen und Unfälle drinnen")}
{opt("Alle Ereignisse","Pipi, Kaka, Mahlzeiten …", False)}
</section>
<div style="flex:1"></div>
<button class="btn primary">{icon("doc",20,"#fff")}PDF für den Tierarzt</button>
<button class="btn secondary">{icon("download",20)}CSV-Dateien</button>
<p class="hint" style="text-align:center;margin:0">Öffnet das Teilen-Menü, z. B. für Mail oder AirDrop.</p>
</main>''',
 "PDF for the vet appointment, CSV for your own analysis. Choose what goes in.")

# 14 Einrichten (korrigierte Reihenfolge) --------------------------------------
def step(n, state, title, text, extra=""):
    badge = (f'<span style="width:32px;height:32px;border-radius:16px;background:var(--acc);display:flex;align-items:center;justify-content:center;flex:none">{icon("check",16,"#fff",3)}</span>' if state=="done"
             else f'<span style="width:32px;height:32px;border-radius:16px;background:{"var(--acc-t)" if state=="now" else "var(--neu)"};color:{"var(--acc)" if state=="now" else "var(--muted)"};font-weight:700;display:flex;align-items:center;justify-content:center;flex:none">{n}</span>')
    op = ' style="opacity:.6"' if state=="later" else ""
    return f'<section class="card" style="display:flex;gap:12px"{"" if not op else ""}>{badge}<div style="flex:1"{op}><h2 style="margin:0;font-size:16px;line-height:22px">{title}</h2><div class="sub" style="font-size:14px;margin-top:2px">{text}</div>{extra}</div></section>'
S["14-einrichten.html"] = ("Setup (new order)", f'''
<main class="scroll">
<header style="padding:0 4px"><h1 class="title">Willkommen bei Bruno</h1><div class="sub" style="margin-top:4px">Einmal einrichten, danach läuft alles auf euren beiden Handys.</div></header>
{step(1,"done","Zum Home-Bildschirm hinzugefügt","Puppy Log läuft als App. Nur so kann iOS Erinnerungen zustellen.")}
{step(2,"now","Anmelden","Füge den Login-Link aus deiner Nachricht ein. Dieses Gerät bleibt danach angemeldet.",
 '<div class="field" style="margin-top:10px"><label for="l" style="padding:0">Login-Link</label><input id="l" class="input" placeholder="https://…/magic_link/…"></div><button class="btn primary sm" style="margin-top:10px">Anmelden</button>')}
{step(3,"later","Erinnerungen erlauben","Damit sich Bruno meldet, wenn eine Routine fällig ist.")}
{step(4,"later","Testen","Schickt eine Nachricht an alle Geräte im Haushalt.")}
</main>''',
 "Order corrected: home screen first, then sign in inside the app – otherwise you are not signed in there (separate cookies). Opened in Safari, step 1 shows the „Teilen → Zum Home-Bildschirm“ instructions.")

# 15 Eintragen: Anderes, Wann, Wer ---------------------------------------------
types=[("pipi","Pipi"),("kaka","Kaka"),("bowl","Mahlzeit"),("gassi","Gassi"),("moon","Schlaf"),("ball","Spiel"),("vomit","Erbrechen"),("plus","Anderes")]
S["15-eintragen-anderes.html"] = ("Log: other, when", f'''
<main class="scroll" style="gap:16px">
{close("Ereignis eintragen")}
<section><div class="label" style="padding:0 2px 8px">Was ist passiert?</div>
<div class="tiles">{''.join(f'<button class="tile" aria-pressed="{str(l=="Anderes").lower()}">{icon(i)}{l}</button>' for i,l in types)}</div></section>
<div class="field"><label for="w">Was genau?</label><input id="w" class="input" value="Zähne geputzt">
<div class="hint">Zuletzt benutzt: <button class="chip neu" style="border:0">Krallen geschnitten</button> <button class="chip neu" style="border:0">Baden</button></div></div>
<section style="display:flex;flex-direction:column;gap:8px"><div class="label" style="padding:0 2px">Wann</div>
<div class="seg" style="grid-template-columns:repeat(4,1fr)"><button aria-pressed="true">Jetzt</button><button>−15 Min</button><button>−30 Min</button><button>Andere</button></div></section>
<p class="hint" style="margin:0">Gespeichert wird, wer den Eintrag gemacht hat (du).</p>
<div class="field"><label for="n">Notiz</label><input id="n" class="input" placeholder="Optional"></div>
<div style="flex:1"></div>
<button class="btn primary">Eintragen</button>
</main>''',
 "Extends the existing log mockup: „Anderes“ with a name field and recently used names, „Wann“ with quick time offsets. No \"who\" field: we store who made the entry.")

# 16 Mitteilungen auf dem Sperrbildschirm --------------------------------------
def notif(title, body, when):
    return f'<div class="notif"><span class="app">{icon("paw",22,"#fff")}</span><div style="flex:1"><div class="h">Puppy Log<span>{when}</span></div><div class="b"><b>{title}</b><br>{body}</div></div></div>'
S["16-mitteilungen.html"] = ("Notifications on the lock screen", f'''
<div class="lock" style="flex:1;padding:70px 12px 24px;display:flex;flex-direction:column;gap:10px">
<div style="text-align:center;color:#fff"><div style="font-size:18px;font-weight:600;opacity:.85">Donnerstag, 12. November</div><div style="font-family:var(--display);font-size:84px;line-height:90px;font-weight:600">10:31</div></div>
<div style="color:#fff;font-size:12.5px;opacity:.7;padding:8px 6px 0">1 · Erinnerung zur Soll-Zeit</div>
{notif("Pipi-Runde ist fällig","Seit 10:00. Tippen zum Abhaken.","10:00")}
<div style="color:#fff;font-size:12.5px;opacity:.7;padding:8px 6px 0">2 · Nachfrage nach 30 Min, falls noch offen</div>
{notif("Pipi-Runde noch offen","Seit 30 Minuten fällig.","10:30")}
<div style="color:#fff;font-size:12.5px;opacity:.7;padding:8px 6px 0">3 · Riv hakt ab: ersetzt 1 und 2 auf deinem Handy</div>
{notif("Pipi-Runde erledigt ✓","Riv, 10:31 · draußen","jetzt")}
</div>''',
 "What \"done on the other phone\" looks like: the reminder is replaced by a short done notification with the same tag, so iOS shows only one. Quiet hours move reminders to the end of the quiet period.")
