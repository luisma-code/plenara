# Plenara — fresh start

Plenara is an iPhone app for caring for personal relationships: staying in touch,
choosing relationships to deepen, and remembering the people in your life.

Luis's October 16, 2026 reset replaces the previous planner product and its
project instructions, skills, designs, code, and operational assumptions.
Everything under `archive/` is historical material, never active guidance.
Do not restore old features or architecture by default.

Luis approved the design and requested implementation on October 16, 2026.
`design/relationship-app.md` owns the product design; `ios/` is the native
SwiftUI app. The HTML prototype is retained as a visual reference, with
fictional browser-local data. Do not confuse it with the shipped native app.

The native journal is local and atomic; failed saves must not publish changes.
Contacts import is explicit selection, never background address-book reading.
Verification uses a dedicated simulator. Physical devices are install-only.
Build and test in Release; keep logging useful without logging personal content.
`ios/README.md` records build, verification, signing, deployment, and data paths.

Run `bash tool/precheck.sh` before reporting repository work complete.
Global user preferences continue to apply; no old project-local skill is active.
