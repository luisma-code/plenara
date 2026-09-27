# Plenara Flutter app

Plenara helps Luis make space for relationships, follow through on commitments, and build routines that fit his life. Today brings those three goals together; People, Tasks, and Routines provide direct access. Labeled Talk to Plena and Message Plena controls follow roots and detail pages into one resumable conversation.

The optional GPT guide reads relevant planner context and proposes editable, undoable updates. It uses a separate secure OpenAI API key, explicit context consent and a persisted monthly spending limit. Local commands and direct touch actions remain available offline. No recorded relationship update means unknown. Practices support a reason, cue, normal/minimum versions, flexible opportunities, and deliberate skips.

User-selected Calendar/Reminders evidence, pasted text and Shortcuts captures reduce bookkeeping without automatic message surveillance. Calendar entries do not prove attendance. Notifications use private, silent copy and open the relevant conversation. Planner files remain readable JSON in the chosen folder; device history stays local. See [the privacy policy](../PRIVACY.md).

## Local verification

```sh
flutter pub get
flutter analyze lib test integration_test
flutter test
```

Use `../tool/precheck.sh` for the complete repository gate and
`../tool/external_release_gate.sh` for compiled external-artifact inspection.
Automated iPhone verification runs only in a local simulator. A physical phone
is deployment-only and must never be selected by a test or debug harness.
