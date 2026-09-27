# Plenara Privacy Policy

Effective September 26, 2026

Plenara is a personal, voice-first planner. It has no Plenara account, advertising,
tracking, analytics service, or Plenara-operated server.

## Data stored by the app

Your plans, contacts, notes, routines, and other records are stored as readable JSON
files in the folder you choose. Early versions do not encrypt those record files. If
you choose an iCloud Drive, OneDrive, Google Drive, or another synchronized folder,
that provider receives and stores the files under your account and its privacy terms.

Your Anthropic and OpenAI API keys are stored in the operating system's secure credential store.
Device-local execution history and diagnostics are not placed in your synchronized
data folder.

## Voice

Plenara opens the microphone only after you start a voice turn and visibly shows the
listening state. Speech recognition is required to run on the device; if the device
cannot provide on-device recognition, Plenara falls back to text entry instead of a
server recognizer. Raw audio is not written to disk, synchronized, logged, included in
diagnostic exports, or sent to Anthropic by Plenara. Dictation initiated from the
operating system keyboard is an operating-system feature and follows that provider's
privacy terms.

## Anthropic cloud features

Cloud features are optional and use the Anthropic API key you provide. A novel request
may send that request's final text to Anthropic for routing. Features you explicitly
request—such as a briefing, gift ideas, or a weekly reflection—send the request and
only the record categories disclosed for that feature in Plenara's Settings. Current
features exclude journal entries. Anthropic processes those requests under its API
terms and bills your Anthropic account. Offline mode makes no Anthropic requests.

## GPT guide and selected sources

The optional Plena guide uses your separate OpenAI API key and monthly spending limit. Sending a conversation sends recent guide dialogue and relevant people, facts, interactions, tasks, reminders, practices and guided routines. Journal and mood records, contact phone/email/system identifiers, and diagnostics are excluded from guide tools. A user-written note or pasted text can still contain sensitive information. OpenAI bills your API account separately from ChatGPT/Codex. Requests use `store:false`; provider abuse-monitoring retention can still apply. Zero budget or Disconnect pauses requests.

Calendar and Reminders browsing needs separate iOS permission. Browsing stays local; only an item you select and then send is included in a conversation. Nothing is automatically imported, written back, or assumed completed. Paste selected text or use Capture with Plenara in Shortcuts; the pending Shortcut draft uses this device’s unlock-only keychain. Plenara does not read blanket Messages history or iPhone call logs. Revoke source permission in iOS Settings.

The device-local conversation ledger retains up to 250 turns as readable JSON under the existing local storage model. Guide turns omit input/reply/record content from diagnostic turn traces. Internal native speech hypotheses have the separately disclosed diagnostic boundary below. Notifications omit names and private reminder text on the lock screen and are silent by default.

## Diagnostics

Development and single-user internal builds keep content-bearing diagnostic logs on
the device so failures can be reproduced. Those logs can contain final conversation
text, record values, exception details, and stacks. They are never uploaded
automatically and leave the device only after the user opens a precise payload preview
and chooses the operating system share sheet. Credentials and raw audio are always excluded.
Internal diagnostic traces may include interim recognizer hypotheses because they are needed to
reconstruct a native capture that displayed words but never produced a final result.

External builds do not capture interim hypotheses or other raw diagnostic content, create raw
diagnostic logs, or expose raw-log export. They also
remove raw logs left by an earlier internal build. Plenara has no automatic telemetry,
remote crash-reporting service, or analytics endpoint.

## Deletion and control

You can disconnect OpenAI and Anthropic in Settings, choose a different data folder, delete the
JSON files in your chosen folder, and uninstall Plenara to remove its device-local
state. Copies held by a synchronization provider must be managed through that
provider. A diagnostics share draft is controlled by the destination you select in
the operating system share sheet.

## Contact

Questions and privacy requests can be filed through the public
[Plenara support tracker](https://github.com/luisma-code/plenara/issues).
