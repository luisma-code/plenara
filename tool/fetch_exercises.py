#!/usr/bin/env python3
"""Build the shipped `exercises` reference dataset (Spec 13) from the wger open catalogue.

WHY A CATALOGUE RATHER THAN GENERATED FIGURES: a spike (2026-07-28) established that a model can
author SVG stick figures that pass a strict render-only subset AND tween correctly, but that
lying-down poses are not readable at all — and neither explicit 3/4 projection geometry nor a
render-and-critique vision loop fixed them. Selecting from a real illustrated catalogue removes
figure quality as a per-generation gamble, makes authoring cheaper and deterministic, works
offline forever, and keeps the App Store 2.5.2 story trivial (bundled assets are content).

LICENSING: wger's catalogue is CC BY-SA 4.0 and carries per-record `license_author`, so attribution
is mechanical. We record it per entry and ship an attributions screen. Images are stored UNMODIFIED
— the dark-on-transparent line art is recoloured for the void with a RENDER-TIME filter, never by
writing altered files, so we display the work rather than distribute an adaptation.

COVERAGE IS PARTIAL BY DESIGN: only ~32% of the catalogue has an illustration. A step whose exercise
has no image degrades to text-only, which is first-class in the design — every instruction has to
stand alone for the ear anyway (screen-off runs).

Usage:  tool/fetch_exercises.py [--images] [--limit N]
        --images also downloads the medium (400x400) thumbnails.
"""
import argparse
import json
import os
import re
import sys
import urllib.request

API = "https://wger.de/api/v2"
ENGLISH = 2
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_JSON = os.path.join(ROOT, "v0", "data", "reference", "exercises.json")
OUT_IMGS = os.path.join(ROOT, "app", "assets", "exercises")


def pull(path, cap=40):
    """Follow wger's pagination and return every result row."""
    url = f"{API}/{path}"
    rows, pages = [], 0
    while url and pages < cap:
        with urllib.request.urlopen(url, timeout=120) as r:
            d = json.load(r)
        rows += d["results"]
        url = d.get("next")
        pages += 1
    return rows


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def clean(html):
    """wger descriptions are HTML; the interpreter and TTS both want plain text."""
    txt = re.sub(r"<[^>]+>", " ", html or "")
    txt = (txt.replace("&nbsp;", " ").replace("&amp;", "&")
              .replace("&lt;", "<").replace("&gt;", ">").replace("&#39;", "'")
              .replace("&quot;", '"'))
    return re.sub(r"\s+", " ", txt).strip()


# A routine step must stand alone FOR THE EAR — a run with the screen off or the phone on the floor
# is a first-class case, and the figure is never the sole carrier of the movement. So an exercise the
# app cannot describe out loud is not selectable, and is dropped from the shipped catalogue rather
# than shipped as a step that would say nothing (P2.8: no silent failure).
_VIDEO_ONLY = re.compile(r"^\W*(view|watch|see)\s+(the\s+)?video\b|^\W*video\W*$", re.I)
MIN_INSTRUCTION = 15


def speakable(text):
    t = (text or "").strip()
    if len(t) < MIN_INSTRUCTION:
        return False  # empty, or junk like "."
    if _VIDEO_ONLY.search(t):
        return False  # points at media we do not ship
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", action="store_true", help="also download thumbnails")
    ap.add_argument("--limit", type=int, default=0, help="cap entries (for a smoke run)")
    args = ap.parse_args()

    print("fetching catalogue…", file=sys.stderr)
    cats = {c["id"]: c["name"] for c in pull("exercisecategory/?limit=100&format=json")}
    muscles = {m["id"]: (m.get("name_en") or m.get("name")) for m in pull("muscle/?limit=100&format=json")}
    equip = {e["id"]: e["name"] for e in pull("equipment/?limit=100&format=json")}
    bases = pull("exercise/?limit=200&format=json")
    trans = pull("exercise-translation/?limit=500&format=json")
    images = pull("exerciseimage/?limit=200&format=json")
    print(f"  {len(bases)} exercises · {len(trans)} translations · {len(images)} images", file=sys.stderr)

    # english name + description per exercise (first translation wins)
    en = {}
    for t in trans:
        if t.get("language") != ENGLISH or not t.get("name"):
            continue
        en.setdefault(t["exercise"], t)

    # one image per exercise: prefer the flagged main image, else the first
    img_by_ex = {}
    for im in images:
        ex = im.get("exercise")
        if ex is None:
            continue
        if ex not in img_by_ex or im.get("is_main"):
            img_by_ex[ex] = im

    entries, seen = [], set()
    dropped_unspeakable = 0
    for b in bases:
        t = en.get(b["id"])
        if not t:
            continue  # no English name -> unusable for a spoken catalogue
        name = t["name"].strip()
        key = slug(name)
        if not key or key in seen:
            continue
        if not speakable(clean(t.get("description"))):
            dropped_unspeakable += 1
            continue
        seen.add(key)
        im = img_by_ex.get(b["id"])
        entry = {
            "key": key,
            "name": name,
            "category": cats.get(b.get("category"), ""),
            "muscles": [muscles[m] for m in b.get("muscles", []) if m in muscles],
            "equipment": [equip[e] for e in b.get("equipment", []) if e in equip],
            "instructions": clean(t.get("description")),
            # Absent when the catalogue has no illustration — the step degrades to text-only.
            "image": f"{key}.png" if im else None,
            "imageAuthor": (im.get("license_author") if im else None),
        }
        entries.append(entry)
        if args.limit and len(entries) >= args.limit:
            break

    entries.sort(key=lambda e: e["key"])
    with_img = sum(1 for e in entries if e["image"])
    doc = {
        "dataset": "exercises",
        "version": 1,
        "provenance": "wger.de open exercise catalogue",
        "license": "CC BY-SA 4.0",
        "licenseUrl": "https://creativecommons.org/licenses/by-sa/4.0/",
        "attribution": "Exercise data and illustrations from the wger project (wger.de); "
                       "illustrations largely by Everkinetic. Licensed CC BY-SA 4.0.",
        "note": f"{len(entries)} exercises, {with_img} with an illustration. Images are shipped "
                "UNMODIFIED; the app recolours them for the dark void with a render-time filter "
                "rather than distributing an adaptation. An entry without an image renders "
                "text-only (Spec 16).",
        "entries": entries,
    }
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
    size = os.path.getsize(OUT_JSON)
    print(f"wrote {OUT_JSON} — {len(entries)} entries, {with_img} illustrated, {size//1024} KB "
          f"({dropped_unspeakable} dropped: no usable spoken instruction)", file=sys.stderr)

    # Prune images no longer referenced (an entry dropped by the quality gate, or renamed upstream),
    # so the bundle can never carry assets the catalogue doesn't know about.
    if os.path.isdir(OUT_IMGS):
        keep = {e["image"] for e in entries if e["image"]}
        orphans = [f for f in os.listdir(OUT_IMGS) if f.endswith(".png") and f not in keep]
        for f in orphans:
            os.remove(os.path.join(OUT_IMGS, f))
        if orphans:
            print(f"pruned {len(orphans)} orphan image(s)", file=sys.stderr)

    if args.images:
        os.makedirs(OUT_IMGS, exist_ok=True)
        total = n = 0
        for e in entries:
            if not e["image"]:
                continue
            base = next(b for b in bases if en.get(b["id"], {}).get("name", "").strip() == e["name"])
            im = img_by_ex[base["id"]]
            url = (im.get("thumbnails") or {}).get("medium") or im["image"]
            dst = os.path.join(OUT_IMGS, e["image"])
            try:
                urllib.request.urlretrieve(url, dst)
                total += os.path.getsize(dst)
                n += 1
            except Exception as ex:  # a missing thumbnail must not abort the build
                print(f"  ! {e['key']}: {ex}", file=sys.stderr)
        print(f"downloaded {n} images — {total//1024} KB total ({total//max(n,1)//1024} KB avg)",
              file=sys.stderr)


if __name__ == "__main__":
    main()
