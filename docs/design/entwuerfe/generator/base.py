CSS = r"""
:root{
  --bg:#F3F5F2;--card:#FFFFFF;--line:#DDE3DE;--div:#E6EBE7;
  --text:#14201B;--muted:#55645D;
  --acc:#0E6B52;--acc-t:#D7EDE4;--acc-d:#0B4F3D;--acc-c:#BFE3D5;
  --pipi:#1D5FA8;--pipi-t:#E3EEF9;--kaka:#7A4A1E;--kaka-t:#F3E7DA;
  --neu:#E4EAE6;--bad:#A32A1C;--bad-t:#FBE4E0;--bad-l:#F0C6C0;
  --warn:#8A5200;--warn-t:#FDF0D5;--unchk:#6B7B73;--input:#84918A;
  --display:'Space Grotesk',system-ui,sans-serif;--body:Inter,system-ui,sans-serif;
}
*{box-sizing:border-box}
html,body{margin:0;background:#E9ECE8}
body{font-family:var(--body);color:var(--text);font-size:15px;line-height:20px}
button,input,select,textarea{font-family:inherit;font-size:inherit;color:inherit}
a{color:inherit;text-decoration:none}
.phone{width:390px;height:844px;margin:0 auto;background:var(--bg);display:flex;flex-direction:column;position:relative;overflow:hidden}
.scroll{flex:1;min-height:0;overflow-y:auto;padding:24px 16px 24px;display:flex;flex-direction:column;gap:12px}
.scroll>*{flex-shrink:0}
.note-ann{position:absolute;left:8px;right:8px;bottom:84px;background:#14201B;color:#fff;border-radius:12px;padding:10px 12px;font-size:12.5px;line-height:17px;z-index:30;box-shadow:0 6px 20px rgba(0,0,0,.25)}
.note-ann b{color:#BFE3D5}
.page-head{display:flex;align-items:center;gap:12px;padding:0 4px}
.page-head h1,.title{margin:0;font-family:var(--display);font-size:26px;line-height:30px;font-weight:600}
.sub{font-size:14px;line-height:20px;color:var(--muted)}
.bar-head{display:flex;align-items:center;gap:4px;margin:0 -8px}
.bar-head h1{margin:0;font-family:var(--display);font-size:22px;line-height:28px;font-weight:600;flex:1}
.icon-btn{width:44px;height:44px;display:flex;align-items:center;justify-content:center;border:0;background:none;border-radius:22px;cursor:pointer;color:var(--text)}
.link-btn{font-size:14px;font-weight:600;color:var(--acc);background:none;border:0;padding:10px 4px;min-height:44px;display:inline-flex;align-items:center;gap:4px;cursor:pointer}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px}
.card.flush{padding:0;overflow:hidden}
.label{font-size:13px;line-height:18px;color:var(--muted);font-weight:500}
.section-label{font-size:13px;line-height:18px;color:var(--muted);font-weight:500;padding:4px 4px 0}
.big{font-family:var(--display);font-size:28px;line-height:34px;font-weight:600}
.row{display:flex;align-items:center;gap:12px;min-height:56px;padding:8px 16px;border-top:1px solid var(--div)}
.row:first-child{border-top:0}
.row .grow{flex:1;min-width:0}
.row .t{font-size:15px;line-height:20px;font-weight:500}
.row .m{font-size:12.5px;line-height:17px;color:var(--muted)}
.chev{color:var(--muted)}
.chip{font-size:12px;font-weight:600;border-radius:10px;padding:3px 10px;white-space:nowrap;display:inline-flex;align-items:center;gap:4px}
.chip.ok{color:var(--acc);background:var(--acc-t)}
.chip.warn{color:var(--warn);background:var(--warn-t)}
.chip.bad{color:var(--bad);background:var(--bad-t)}
.chip.neu{color:var(--muted);background:var(--neu)}
.chip.sel{color:#fff;background:var(--acc)}
.chip.pipi{color:var(--pipi);background:var(--pipi-t)}
.chip.kaka{color:var(--kaka);background:var(--kaka-t)}
.progress{height:8px;border-radius:4px;background:var(--neu);overflow:hidden}
.progress>i{display:block;height:100%;border-radius:4px;background:var(--acc)}
.btn{height:52px;border-radius:14px;border:0;font-size:16px;font-weight:600;display:flex;align-items:center;justify-content:center;gap:8px;width:100%;cursor:pointer}
.btn.primary{background:var(--acc);color:#fff}
.btn.secondary{background:#fff;color:var(--acc);border:2px solid var(--acc)}
.btn.ghost-danger{background:none;color:var(--bad);height:48px;font-size:15px}
.btn.sm{height:44px;font-size:15px;border-radius:12px;width:auto;padding:0 18px}
.field{display:flex;flex-direction:column;gap:6px}
.field label{font-size:13px;line-height:18px;color:var(--muted);font-weight:500;padding:0 2px}
.input{height:48px;border:1px solid var(--input);border-radius:12px;padding:0 14px;background:#fff;font-size:16px;width:100%}
.input.big-num{height:72px;font-family:var(--display);font-size:40px;font-weight:600;text-align:center;letter-spacing:.5px}
.hint{font-size:12.5px;line-height:17px;color:var(--muted);padding:0 2px}
.err{font-size:12.5px;line-height:17px;color:var(--bad);font-weight:600;padding:0 2px}
.input.invalid{border:2px solid var(--bad)}
.seg{display:grid;gap:4px;background:var(--neu);border-radius:12px;padding:4px}
.seg button{height:40px;border:0;border-radius:9px;background:transparent;font-size:14px;font-weight:600;color:var(--muted);cursor:pointer}
.seg button[aria-pressed=true]{background:#fff;color:var(--acc);box-shadow:0 1px 2px rgba(20,32,27,.15)}
.tiles{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}
.tile{height:76px;border-radius:14px;border:2px solid var(--line);background:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;font-size:12px;font-weight:600;cursor:pointer;padding:0}
.tile[aria-pressed=true]{border-color:var(--acc);background:var(--acc-t);color:var(--acc)}
.tile.pipi[aria-pressed=true]{border-color:var(--pipi);background:var(--pipi-t);color:var(--pipi)}
.daychips{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:6px}
.daychips button{height:44px;border-radius:22px;border:2px solid var(--line);background:#fff;font-size:13px;font-weight:600;cursor:pointer}
.daychips button[aria-pressed=true]{background:var(--acc);border-color:var(--acc);color:#fff}
.toggle{width:51px;height:31px;border-radius:16px;background:var(--neu);border:0;position:relative;flex:none;cursor:pointer}
.toggle::after{content:"";position:absolute;top:2px;left:2px;width:27px;height:27px;border-radius:14px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.25);transition:left .15s}
.toggle[aria-checked=true]{background:var(--acc)}
.toggle[aria-checked=true]::after{left:22px}
.stepper{display:flex;align-items:center;border:1px solid var(--input);border-radius:12px;height:48px;background:#fff;overflow:hidden}
.stepper button{width:48px;height:100%;border:0;background:none;font-size:22px;color:var(--acc);cursor:pointer}
.stepper span{flex:1;text-align:center;font-weight:600;font-variant-numeric:tabular-nums}
.check{width:28px;height:28px;border-radius:14px;border:2px solid var(--unchk);background:#fff;display:flex;align-items:center;justify-content:center;flex:none}
.check.done{background:var(--acc);border-color:var(--acc);color:#fff}
.check.late{border-color:var(--bad)}
.check.skipped{background:var(--neu);border-color:var(--neu);color:var(--muted)}
.check-btn{width:44px;height:44px;display:flex;align-items:center;justify-content:center;border:0;background:none;padding:0;margin-left:-10px;cursor:pointer}
.avatar{width:32px;height:32px;border-radius:16px;color:#fff;font-size:12px;font-weight:600;display:flex;align-items:center;justify-content:center;border:2px solid var(--bg)}
.photo{border-radius:50%;background:radial-gradient(circle at 35% 30%,#E9C79A,#B9855A 60%,#8E5F3B);display:flex;align-items:center;justify-content:center;color:#fff;flex:none;position:relative}
.photo svg{opacity:.9}
.tabbar{height:calc(72px + 0px);background:#fff;border-top:1px solid var(--line);display:grid;grid-template-columns:repeat(4,minmax(0,1fr));flex:none}
.tabbar a{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;color:var(--muted);font-size:12px;font-weight:500}
.tabbar a[aria-current=page]{color:var(--acc);font-weight:600}
.sheet-backdrop{position:absolute;inset:0;background:rgba(20,32,27,.38);z-index:10}
.sheet{position:absolute;left:0;right:0;bottom:0;background:var(--bg);border-radius:20px 20px 0 0;padding:8px 16px 24px;z-index:11;display:flex;flex-direction:column;gap:14px;box-shadow:0 -8px 30px rgba(0,0,0,.18)}
.grabber{width:36px;height:5px;border-radius:3px;background:#C5CEC8;margin:0 auto 4px}
.dots{display:flex;gap:4px}.dots span{width:10px;height:10px;border-radius:5px;background:var(--line)}.dots span.on{background:var(--acc)}
.rating{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:6px}
.rating button{height:64px;border-radius:12px;border:2px solid var(--line);background:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;cursor:pointer;font-size:11px;font-weight:600;color:var(--muted)}
.rating button b{font-family:var(--display);font-size:20px;color:var(--text)}
.rating button[aria-pressed=true]{border-color:var(--acc);background:var(--acc-t);color:var(--acc)}
.rating button[aria-pressed=true] b{color:var(--acc)}
.swipe-wrap{position:relative;border-top:1px solid var(--div);overflow:hidden}
.swipe-action{position:absolute;inset:0 0 0 auto;width:132px;display:flex}
.swipe-action button{flex:1;border:0;color:#fff;font-size:13px;font-weight:600;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px}
.swipe-front{background:#fff;transform:translateX(-132px)}
.stat3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;text-align:left}
.stat3 .v{font-family:var(--display);font-size:22px;line-height:28px;font-weight:600}
.lock{background:linear-gradient(160deg,#2C4A3F,#14201B 70%);}
.notif{background:rgba(255,255,255,.82);backdrop-filter:blur(20px);border-radius:18px;padding:12px 14px;display:flex;gap:10px;align-items:flex-start}
.notif .app{width:38px;height:38px;border-radius:9px;background:var(--acc);display:flex;align-items:center;justify-content:center;flex:none}
.notif .h{display:flex;justify-content:space-between;font-size:14px;font-weight:600}
.notif .h span{font-weight:400;color:#55645D;font-size:13px}
.notif .b{font-size:14px;line-height:19px}
.mono{font-variant-numeric:tabular-nums;letter-spacing:.3px}
.dl{display:grid;grid-template-columns:auto 1fr;gap:0}
"""

ICONS = {
 "home":'<path d="M3 10.5L12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
 "chart":'<path d="M6 20v-8M12 20V4M18 20V9"/>',
 "heart":'<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21l7.8-7.5 1-1.1a5.5 5.5 0 0 0 0-7.8z"/>',
 "book":'<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20V3H6.5A2.5 2.5 0 0 0 4 5.5z"/><path d="M4 19.5A2.5 2.5 0 0 0 6.5 22H20v-5"/>',
 "pipi":'<path d="M12 2.7l5.7 5.7a8 8 0 1 1-11.4 0z"/>',
 "kaka":'<path d="M8 20h8a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4z M9 15h6a2 2 0 0 0 0-4H9a2 2 0 0 0 0 4z M11 10h2a2 2 0 0 0 0-4h-2a2 2 0 0 0 0 4z"/>',
 "bowl":'<path d="M3 11h18a9 9 0 0 1-18 0z"/>',
 "gassi":'<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2"/>',
 "moon":'<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
 "ball":'<circle cx="12" cy="12" r="9"/><path d="M4 8c5 1 11 1 16 0M4 16c5-1 11-1 16 0"/>',
 "vomit":'<path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
 "plus":'<path d="M12 5v14M5 12h14"/>',
 "check":'<path d="M20 6L9 17l-5-5"/>',
 "x":'<path d="M6 6l12 12M18 6L6 18"/>',
 "right":'<path d="M9 6l6 6-6 6"/>',
 "left":'<path d="M15 6l-6 6 6 6"/>',
 "bell":'<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>',
 "clock":'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
 "camera":'<path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/>',
 "skip":'<path d="M5 4l10 8-10 8z"/><path d="M19 5v14"/>',
 "trash":'<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>',
 "edit":'<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
 "users":'<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
 "download":'<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5M12 15V3"/>',
 "share":'<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><path d="M16 6l-4-4-4 4M12 2v13"/>',
 "scale":'<path d="M9 7a3 3 0 1 1 6 0"/><path d="M6.5 9h11l2 11h-15z"/>',
 "copy":'<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
 "syringe":'<path d="M18 2l4 4M17 7l3-3M19 9l-8.7 8.7a2 2 0 0 1-2.8 0l-1.2-1.2a2 2 0 0 1 0-2.8L15 5M9 11l4 4M5 19l-3 3M14 4l6 6"/>',
 "pill":'<path d="M10.5 20.5a5 5 0 0 1-7-7l10-10a5 5 0 0 1 7 7z"/><path d="M8.5 8.5l7 7"/>',
 "bug":'<circle cx="12" cy="13" r="5"/><path d="M12 8V5M9 5l-2-2M15 5l2-2M7 13H3M21 13h-4M8 17l-3 3M16 17l3 3"/>',
 "steth":'<path d="M6 3v6a4 4 0 0 0 8 0V3"/><path d="M10 13v3a5 5 0 0 0 10 0v-2"/><circle cx="20" cy="12" r="2"/>',
 "cal":'<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
 "paw":'<circle cx="6" cy="10" r="2"/><circle cx="10" cy="6" r="2"/><circle cx="14" cy="6" r="2"/><circle cx="18" cy="10" r="2"/><path d="M12 12c-3 0-5 3-5 5.5 0 1.5 1.2 2.5 2.7 2.5 1 0 1.5-.5 2.3-.5s1.3.5 2.3.5c1.5 0 2.7-1 2.7-2.5C17 15 15 12 12 12z"/>',
 "doc":'<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h5"/>',
 "repeat":'<path d="M17 1l4 4-4 4"/><path d="M3 11V9a4 4 0 0 1 4-4h14M7 23l-4-4 4-4"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>',
 "moonclock":'<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
 "phone":'<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/>',
 "link":'<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
 "target":'<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
 "sound":'<path d="M11 5L6 9H2v6h4l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14"/>',
 "logout":'<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
}

def icon(name, size=24, stroke="currentColor", width=2, extra=""):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{stroke}" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" {extra}>{ICONS[name]}</svg>')

def tabbar(active):
    tabs=[("Heute","home","../Main.dc.html"),("Verlauf","chart","../Verlauf.dc.html"),("Gesundheit","heart","../Gesundheit.dc.html"),("Lernen","book","../Lernen.dc.html")]
    out='<nav class="tabbar" aria-label="Hauptnavigation">'
    for label,ic,href in tabs:
        cur=' aria-current="page"' if label==active else ''
        out+=f'<a href="{href}"{cur}>{icon(ic)}{label}</a>'
    return out+'</nav>'

def page(title, body, note=None):
    ann=f'<div class="note-ann">{note}</div>' if note else ''
    return f"""<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Puppy Log mockup</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<style>{CSS}</style>
</head>
<body>
<div class="phone">
{body}
{ann}
</div>
</body>
</html>
"""
