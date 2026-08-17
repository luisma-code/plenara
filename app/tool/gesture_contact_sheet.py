import os
import sys

from PIL import Image, ImageDraw, ImageFont

BACKGROUND = (10, 9, 8)
ORDER = [
    "smile", "check", "heart", "wave", "spark", "question", "ellipsis", "sunrise",
    "crescent", "star", "candle", "nod", "ripple", "settle", "quill", "warm-smile",
    "wink", "double-check", "up-arrow", "flag", "rising-bars", "spiral", "orbit",
    "small-check", "up-tick", "leaf", "bell", "seedling", "bridge", "meeting-line",
    "linked-rings", "target", "clock", "hourglass", "enso", "breath-tilde",
    "snooze-arc", "undo-loop", "infinity", "house", "still-flame", "pulse-heart",
    "gift", "laurel", "cake", "teacup", "clasp", "balloon", "open-book",
]
CELL = 150
LBLW = 132
PAD = 4
PERSHEET = 7
ROWH = CELL + PAD


def composite_frame(path, size=(CELL, CELL)):
    """Composite transparent renderer output onto Plenara's real dark ground."""
    with Image.open(path) as source:
        rgba = source.convert("RGBA")
        ground = Image.new("RGBA", rgba.size, BACKGROUND + (255,))
        merged = Image.alpha_composite(ground, rgba).convert("RGB")
        return merged.resize(size, Image.Resampling.LANCZOS)


def _fonts():
    try:
        return (
            ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 15),
            ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 11),
        )
    except Exception:
        fallback = ImageFont.load_default()
        return fallback, fallback


def strip(root, glyph, font, small_font):
    frames = sorted(
        name
        for name in os.listdir(os.path.join(root, glyph))
        if name.endswith(".png")
    )
    width = LBLW + len(frames) * (CELL + PAD)
    row = Image.new("RGB", (width, ROWH), BACKGROUND)
    draw = ImageDraw.Draw(row)
    draw.text((8, CELL // 2 - 10), glyph, font=font, fill=(240, 200, 120))
    for index, filename in enumerate(frames):
        image = composite_frame(os.path.join(root, glyph, filename))
        x = LBLW + index * (CELL + PAD)
        row.paste(image, (x, 0))
        draw.text(
            (x + 3, 2), filename.split("-")[0], font=small_font,
            fill=(150, 140, 130),
        )
    return row


def build_contact_sheets(root, output):
    os.makedirs(output, exist_ok=True)
    directories = [
        name for name in os.listdir(root) if os.path.isdir(os.path.join(root, name))
    ]
    glyphs = [name for name in ORDER if name in directories] + [
        name for name in sorted(directories) if name not in ORDER
    ]
    font, small_font = _fonts()
    sheets = 0
    for start in range(0, len(glyphs), PERSHEET):
        group = glyphs[start : start + PERSHEET]
        rows = [strip(root, glyph, font, small_font) for glyph in group]
        width = max(row.width for row in rows)
        height = sum(row.height for row in rows) + PAD * (len(rows) + 1)
        sheet = Image.new("RGB", (width, height), BACKGROUND)
        y = PAD
        for row in rows:
            sheet.paste(row, (0, y))
            y += row.height + PAD
        sheets += 1
        path = os.path.join(output, f"sheet-{sheets:02d}.png")
        sheet.save(path)
        print(path, "|", ", ".join(group))
    print("TOTAL", sheets, "sheets,", len(glyphs), "glyphs")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: gesture_contact_sheet.py FRAME_ROOT OUTPUT_DIR")
    build_contact_sheets(sys.argv[1], sys.argv[2])
