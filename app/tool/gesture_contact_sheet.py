import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = sys.argv[1]
OUT  = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

# vocabulary order (glyphs.dart): core, extended, emblems
ORDER = ["smile","check","heart","wave","spark","question","ellipsis","sunrise","crescent","star",
"candle","nod","ripple","settle","quill","warm-smile","wink","double-check","up-arrow","flag",
"rising-bars","spiral","orbit","small-check","up-tick","leaf","bell","seedling","bridge","meeting-line",
"linked-rings","target","clock","hourglass","enso","breath-tilde","snooze-arc","undo-loop","infinity",
"house","still-flame","pulse-heart","gift","laurel","cake","teacup","clasp","balloon","open-book"]

dirs = [d for d in os.listdir(ROOT) if os.path.isdir(os.path.join(ROOT, d))]
glyphs = [g for g in ORDER if g in dirs] + [d for d in sorted(dirs) if d not in ORDER]

CELL = 150            # per-frame thumbnail
LBLW = 132            # left label column
PAD  = 4
PERSHEET = 7          # glyphs per contact sheet
ROWH = CELL + PAD
try:
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 15)
    fsm  = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 11)
except Exception:
    font = fsm = ImageFont.load_default()

def strip(g):
    frames = sorted(f for f in os.listdir(os.path.join(ROOT, g)) if f.endswith(".png"))
    w = LBLW + len(frames) * (CELL + PAD)
    row = Image.new("RGB", (w, ROWH), (10, 9, 8))
    d = ImageDraw.Draw(row)
    d.text((8, CELL // 2 - 10), g, font=font, fill=(240, 200, 120))
    for i, f in enumerate(frames):
        im = Image.open(os.path.join(ROOT, g, f)).convert("RGB").resize((CELL, CELL))
        x = LBLW + i * (CELL + PAD)
        row.paste(im, (x, 0))
        d.text((x + 3, 2), f.split("-")[0], font=fsm, fill=(150, 140, 130))
    return row

sheets = 0
for s in range(0, len(glyphs), PERSHEET):
    group = glyphs[s:s + PERSHEET]
    rows = [strip(g) for g in group]
    W = max(r.width for r in rows)
    H = sum(r.height for r in rows) + PAD * (len(rows) + 1)
    sheet = Image.new("RGB", (W, H), (10, 9, 8))
    y = PAD
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height + PAD
    sheets += 1
    path = os.path.join(OUT, f"sheet-{sheets:02d}.png")
    sheet.save(path)
    print(path, "|", ", ".join(group))
print("TOTAL", sheets, "sheets,", len(glyphs), "glyphs")
