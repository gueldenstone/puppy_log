import os, sys, html
sys.path.insert(0, os.path.dirname(__file__))
from base import page, CSS
from screens import S

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for name, (title, body, caption) in S.items():
    with open(os.path.join(out, name), "w") as f:
        f.write(page(title, body))

cards = "".join(f'''<figure>
<iframe src="{name}" title="{html.escape(title)}" loading="lazy"></iframe>
<figcaption><a href="{name}"><b>{name[:2]} · {html.escape(title)}</b></a><span>{html.escape(caption)}</span></figcaption>
</figure>''' for name, (title, _b, caption) in S.items())

index = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Puppy Log · supplementary mockups</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<style>
body{{margin:0;background:#E9ECE8;color:#14201B;font-family:Inter,system-ui,sans-serif}}
header{{max-width:1240px;margin:0 auto;padding:32px 16px 8px}}
h1{{font-family:'Space Grotesk',sans-serif;font-size:30px;margin:0 0 6px}}
header p{{margin:0;color:#55645D;max-width:760px;line-height:1.5}}
.grid{{max-width:1240px;margin:0 auto;padding:16px;display:grid;grid-template-columns:repeat(auto-fill,minmax(400px,1fr));gap:28px 20px}}
figure{{margin:0;display:flex;flex-direction:column;align-items:center;gap:10px}}
iframe{{width:390px;height:844px;border:0;border-radius:36px;box-shadow:0 0 0 10px #14201B,0 18px 40px rgba(0,0,0,.25);background:#F3F5F2;transform-origin:top center}}
figcaption{{width:390px;display:flex;flex-direction:column;gap:4px;font-size:13.5px;line-height:1.45;color:#55645D;margin-top:10px}}
figcaption b{{color:#14201B;font-size:15px}}
@media (max-width:440px){{iframe{{width:100%;max-width:390px}} figcaption{{width:100%}} .grid{{grid-template-columns:1fr}}}}
</style></head><body>
<header><h1>Supplementary mockups</h1>
<p>Additions to the existing mockups (Heute, Eintragen, Verlauf, Gesundheit, Lernen, Einrichten) in the same style.
The screens themselves show the German UI. Click a title to open a screen on its own. All data is sample data.</p></header>
<main class="grid">{cards}</main>
</body></html>"""
with open(os.path.join(out, "index.html"), "w") as f:
    f.write(index)
print(f"{len(S)} screens -> {out}")
