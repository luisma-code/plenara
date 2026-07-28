# Session Handoff — Plenara

_Written 2026-07-16 for the next session. Point-in-time snapshot; the continuously-updated
working memory is [`WORK-CAPSULE.md`](WORK-CAPSULE.md) — read that too._

---

## TL;DR — where things stand

- **Everything is committed + pushed to `origin/main`.** Tree clean. Tests green: **v0 1718, app 80**,
  both `analyze` clean, seed assets in sync.
- Two features shipped this session (**G-49**) and put through a **4-lens Fable code review** — all
  confirmed defects fixed + regression-tested.
- **One thing is blocked on you (Luis):** the TestFlight one-time Apple-account setup (see below).
  Nothing else is blocked.
- Latest commits (newest first): `c774c94` (G-49 review fixes) · `3b82691` (TestFlight plumbing) ·
  `193a932` (Feature 2) · `10d0aaf` (Feature 1).

---

## What shipped this session (G-49)

Both features were designed with Fable first, then implemented, then Fable-reviewed and fixed.

### 1. Numbered-list corrections (engine, `v0/`)
The problem: a misheard item ("Zpack my clothes") was nearly impossible to re-target by text.
Now **every list Plena reads back is numbered** ("1. …, 2. …") and you reference an item by the
number spoken:
- **"delete 2"**, **"complete 1"**, **"correct 3"** (two-turn re-speak) / **"change 2 to X"** (one-turn).
- Resolves by recordId against exactly what was read back (no drift, no fuzzy match). All journaled,
  so **"undo that"** reverses them.
- Works across **every domain** — tasks, reminders, knowledge/facts, relations, interactions, meals,
  journal, mood (~18 list skills converted).
- Two new closed-vocab DSL ops: **`enumerate`** (flat lists) + **`ref_mark`** (captures a ref from
  inside a `foreach` for rich/conditional/joined readbacks). Session `_enumCtx` context +
  reference-by-number handlers. Recognition is offline regex (free, deterministic).

### 2. Editable "Your data" view (app, `app/lib/data_view.dart`)
The read-only archetype browser behind the "…" menu is now an editable fallback:
- **Per-value tap-to-edit** (Spec 07 §5.5 — not a form): text/number inline, boolean toggle,
  date/datetime pickers. **Delete-with-undo-snackbar** (targeted undo). A **"Learned phrases"** card
  showing what Plena learned to recognize from how you talk (humanized templates), each **forgettable**.
- Six Session facade methods (`editField`, `deleteRecord`, `undoLast`, `undoById`, `learnedFlows`,
  `forgetLearnedFlow`, `restoreLearnedFlow`) + `Router.restore`. Edits ride the **one** journal, so a
  spoken "undo that" reverses a manual edit.

### The Fable review (4 lenses) — all confirmed defects fixed
Two were data-corruption paths (executed repros): (1) a **mixed-type readback** wrote a junk field on
the wrong type → fixed with a **per-item** `{id, typeId, labelField}` reference channel; (2) a
**manual edit between a spoken write and a voice "no, I meant…"** reversed the wrong journal entry →
manual writes clear the spoken-correction context + the snackbar uses a **targeted `undoById`**. Plus:
a date-picker **crash** on dates >5y old (birthdays) → clamped; edit-failure was invisible behind the
modal sheet → inline `errorText`; ref-commands guarded mid-slot-fill; Tour kept alive; var-closure
scans `id`/`label`; learned-flow forget/restore hardened. Specs 02/03/07 synced + gap-register row.
(Feature was renamed G-47 → **G-49**; G-47 was already taken by the gap register.)

### Verified live with the real cloud
Using the test key, confirmed end-to-end: the numbered-corrections flow, **and G-46's gift
suggestion** ("suggest a gift for Elena" → recognized by the cloud, grounded in her real facts) — the
dogfood miss that started G-46, never before tested with a real key.

---

## NEXT STEPS

### 🔴 Blocked on Luis — TestFlight (deploy-from-anywhere)
Remote deploy across networks is impossible today (the phone shows `unavailable` to the Mac when off
its LAN — that's exactly what TestFlight fixes). All Mac-side plumbing is done and needs no Apple
login. **Your one-time batch (≈5 min, any browser — full steps in [`TESTFLIGHT.md`](TESTFLIGHT.md)):**
1. Create the App Store Connect **app record** for bundle id `com.plenara.plenaraApp` (name "Plenara").
2. Generate an App Store Connect **API key** with **Admin** access → download the `.p8` once, note the
   **Key ID** + **Issuer ID**. Drop all three into gitignored `tool/.testflight.env`.
3. Add yourself as an internal tester + install the TestFlight app on the phone.

Then the next session runs `cd app && flutter build ipa --release && ../tool/testflight-upload.sh` —
one command — and the build (G-46 + G-49) lands in TestFlight over cellular. The script auto-creates
the distribution cert via the API key (`xcodebuild -allowProvisioningUpdates`).

### 🟢 Unblocked / candidate work (next session's pick)
- **On-device dogfood of G-49** once TestFlight (or same-WiFi) lands — numbered corrections + editable
  data view on the real phone.
- **Deferred, device-test-gated** (don't do blind — they touch the one subsystem that works only on
  device): `flutter_tts` shared-handler refactor; Impeller-safe comet trail. See capsule "Open threads".
- **Lower-value cleanups** Fable flagged but didn't block: `read_related` has no ordering (numbering in
  join-based lists can shuffle across restarts); the tag/list comma-editor can't hold commas-in-values;
  a successful tap-edit updates in place but doesn't emit a Stream "act-then-describe" line (accepted
  v0 posture, noted in Spec 07 §5.5).

---

## Key facts & commands (grab these)

- **Build env evals (prefix Bash build cmds):**
  `eval "$(/opt/homebrew/bin/brew shellenv)"; export LANG=en_US.UTF-8; export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- **Run v0 tests:** from `v0/` → `dart test` (1718 green). **App tests:** from `app/` → `flutter test` (80).
- **iPhone:** "Aluminum Monster", id `00008140-000645442862201C`, iOS 26.5.2, bundle
  `com.plenara.plenaraApp`, team `7V63BZ39HU`, deployment target 26.0.
- **Wireless deploy (only on the SAME WiFi as the Mac + phone unlocked):** from `app/` →
  `flutter run --release --dart-define=PLENARA_DEBUG=true -d 00008140-000645442862201C`.
- **After changing `v0/data/` skills/types:** run `bash tool/sync_seed.sh` (the app bundles a copy);
  `--check` gates drift.
- **API key for live testing:** Luis provided one this session (passed via `ANTHROPIC_API_KEY` env; not
  committed). Ask him again if needed — don't persist it.
- **Keep the Mac awake all session:** `pgrep -x caffeinate || nohup caffeinate -dimsu >/dev/null 2>&1 &`
  (standing rule — kill only at true session end).

## Working mode reminder
Default = **short interactive turns** (Luis at the keyboard). **Agentic/uninterrupted mode only when
he explicitly says so** ("working mode" / "agentic mode" = he's left the machine). This session's
review-and-fix work was done agentically at his direction.

## Doc map
- [`WORK-CAPSULE.md`](WORK-CAPSULE.md) — living working memory (read first).
- [`TESTFLIGHT.md`](TESTFLIGHT.md) — the TestFlight setup + per-release commands.
- [`CLAUDE.md`](CLAUDE.md) — project context + working rules.
- `planning/specs/` — design specs (02 DSL, 03 NLU §2.3a, 07 UI §5.5 updated this session);
  `planning/specs/05b-gap-register.md` — the G-49 row.
- `HANDOFF.md` — older full history (deep background, if needed).
