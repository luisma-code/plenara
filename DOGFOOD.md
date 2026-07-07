# Dogfooding Plenara (Windows, this box)

The goal of this phase: **actually use it daily**, so the make-or-break metrics
(how fast it learns your phrasings, how often it clarifies, how emergent-types
holds up) get measured against real data instead of fixtures.

## One-time setup

1. **Build + launch** the desktop app:
   ```
   cd app
   Z:/code/plenara/.tools/flutter/bin/flutter run -d windows
   # or run the built exe: app/build/windows/x64/runner/Debug/plenara_app.exe
   ```
   The first launch scaffolds `C:\Users\<you>\.plenara\config.json`.

2. **Edit that config** — point it at your synced folder and paste your key:
   ```json
   {
     "dataDir": "C:/Users/<you>/OneDrive/Plenara",
     "apiKey": "sk-ant-…"
   }
   ```
   (Env `PLENARA_DATA` / `ANTHROPIC_API_KEY` override these if you prefer.)

3. **Re-launch.** On first run against an empty folder it copies the built-in
   capabilities (types/skills/corpus) in. From then on your **records, learned
   phrasings, and any capabilities you author live in that OneDrive folder** — they
   sync and survive device loss.

Optional: the retrieval fallback wants a local embed server on `:8091`
(`scripts/…` / a llama-server with bge-small). It degrades gracefully if absent —
you just don't get cold-start "did you mean" suggestions.

## What to try

"add call the plumber to my list" · "log a 3k run" · "how many km have I run this
week" · "remember that Mia is Sarah Mitchell's daughter" · "what do I know about
Mia" · "mark call the plumber done" · "undo that" · "no, I meant to …" · "start
tracking my water intake".

## The instrument

Every turn appends to `<dataDir>/turnlog.jsonl`:
`{at, utterance, source, skill}` where `source` ∈ `corpus | cloud | undo |
correction | authored | clarify`. That file is the measurement — after a couple
weeks it answers the real questions: what's the clarify rate, how cloud-dependent
is it, how often do you correct a misroute, and is the corpus-learning ratchet
actually driving those down over time.

## Known rough edges (this phase, deliberately)

- No reminders yet — the retention hook (F2) is the next build.
- Undo is in-memory (dies on app restart); the persisted journal is later.
- Single-device only; the multi-device merge is P2.
