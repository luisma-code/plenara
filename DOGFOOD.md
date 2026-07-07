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

## What to try (25 skills — ask **"what can you do"** any time)

- **Tasks:** "add call the plumber to my list" · "add pay rent due friday" · "list my
  tasks" · "what's due" / "anything overdue" · "move pay rent to next week" · "mark
  call the plumber done" · "delete call the plumber from my list".
- **Reminders:** "remind me to call mom on thursday at 5pm" · "what are my reminders" ·
  "snooze the reminder to call mom to friday at 9am" · "mark the reminder to call mom
  done" · "cancel the reminder to call mom". Past-due ones and birthdays within a week
  greet you as nudges on open.
- **Running / mood:** "log a 3k run" · "how much have I run this week" · "I'm feeling
  great" · "how have I been feeling".
- **People:** "remember that Mia is Sarah Mitchell's daughter" · "what do I know about
  Mia" · "forget that Mia likes chess" · "talked to Sam about the trip" · "when did I
  last talk to Sam" · "what have I logged with Sam" · "who is Sarah related to".
- **Birthdays:** "Sarah's birthday is july 16" · "when is Sarah's birthday" · "whose
  birthday is coming up".
- **System:** "undo that" · "no, I meant to …" · "start tracking my water intake"
  (authors a brand-new capability). Partial names work — "what do I know about Sam"
  finds "Sam Rivera", and asks which one if there are two.

## The instrument

Every turn appends to `<dataDir>/turnlog.jsonl`:
`{at, utterance, source, skill, cloud?}` — `source` ∈ `corpus | cloud | undo |
correction | authored | help | clarify | error`, and `cloud` records cloud health
(`ok | offline | badKey | rateLimited | …`) whenever the cloud was consulted. Run
**`cd v0 && <dart> run bin/turnlog_report.dart`** any time for the source mix, cloud
health, top skills, and the make-or-break **clarify rate**.

## Known rough edges (this phase, deliberately)

- **Reminders fire in-app only for now** — past-due reminders surface as on-open
  nudges; the real Windows toast is built + tested behind a fake, blocked on the ATL
  install (see "Tonight"). Cloud-routed reminder times are normalized so a novel
  phrasing can't arm a midnight reminder or silently drop one.
- Undo is in-memory (dies on app restart); the persisted journal is deferred (Spec 04
  §3.11's window is 5 min anyway — see the handoff).
- Single-device only; the multi-device merge is P2.

## Tonight (after the reconfiguration window)

1. **Rotate the two exposed credentials** (GitHub PAT + Anthropic BYOK key).
2. **ATL → native toast:** in an ADMIN shell,
   `& '…\Installer\setup.exe' modify --installPath '…\2019\BuildTools' --add Microsoft.VisualStudio.Component.VC.ATL --quiet --norestart`,
   then re-add `flutter_local_notifications`, write the real `NotificationScheduler`
   over it, inject it in `app/lib/main.dart` `buildSession()`, `flutter build windows`,
   and smoke one real toast. All logic is already tested against `FakeScheduler`.
3. **Voice spike** (Fable's top v1 lever, locked principle #1) — behind
   `SpeechInput`/`SpeechOutput` seams; start with Windows STT to de-risk the
   interaction model cheaply.
