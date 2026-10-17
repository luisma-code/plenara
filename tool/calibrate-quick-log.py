#!/usr/bin/env python3
"""Run exclusive negative controls; always restore source before a release build."""
from pathlib import Path
import json, subprocess
source = Path('ios/Plenara/Editors.swift')
original = source.read_bytes()
controls = [
    ('channel selection', 'Button { moment.channel = channel } label:', 'Button { } label:', 'A one-tap channel choice must actually select Messages'),
    ('saved note', 'moment.note = moment.note.trimmingCharacters(in: .whitespacesAndNewlines); if store.save(moment)', 'moment.note = ""; if store.save(moment)', 'The saved Messages and its note must survive reopening'),
]
home = Path('ios/Plenara/HomeView.swift')
home_original = home.read_bytes()
records = []
try:
    for name, good, bad, expected in controls:
        text = original.decode(); assert good in text
        source.write_text(text.replace(good, bad, 1))
        run = subprocess.run(['bash', 'tool/test-native.sh', '-only-testing:PlenaraUITests/PlenaraUITests/testQuickLogCallsTextsVisitsAndNotesSurviveReopen'], capture_output=True, text=True)
        log = Path('.tmp/native-tests.log').read_text()
        assert run.returncode != 0 and expected in log, name + ' was not rejected for its intended reason'
        records.append({'control': name, 'rejected': True, 'message': expected})
        source.write_bytes(original)
        print('Rejected: ' + name, flush=True)
    actions = '                    ActionButton(title: "Log a moment", icon: "square.and.pencil") { quickLogging = true }\n                        .accessibilityIdentifier("quick-log")\n'
    early = '                if !store.journal.people.isEmpty {\n' + actions + '                }\n'
    text = home_original.decode(); assert early in text
    text = text.replace(early, '', 1).replace('                } else {\n                    if !store.journal.datedReminders()', '                } else {\n' + actions + '                    if !store.journal.datedReminders()', 1)
    home.write_text(text)
    run = subprocess.run(['bash', 'tool/test-native.sh', '-only-testing:PlenaraUITests/PlenaraUITests/testQuickLogDarkAndLargeText'], capture_output=True, text=True)
    expected = 'Quick logging must stay visible above the introduction at the largest text size'
    assert run.returncode != 0 and expected in Path('.tmp/native-tests.log').read_text(), 'Offscreen quick logging was not rejected'
    records.append({'control': 'large text entry', 'rejected': True, 'message': expected})
    home.write_bytes(home_original)
    print('Rejected: large text entry', flush=True)
    Path('verification/quick-log/calibration.json').write_text(json.dumps({'controls': records, 'sourceRestored': True}, indent=2) + '\n')
finally:
    source.write_bytes(original)
    home.write_bytes(home_original)
    print('Restored source. Rebuild and run precheck before delivery.', flush=True)
