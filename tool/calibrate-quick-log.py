#!/usr/bin/env python3
"""Run exclusive negative controls; always restore source before a release build."""
from pathlib import Path
import json, subprocess
source = Path('ios/Plenara/Editors.swift')
original = source.read_bytes()
controls = [
    ('channel selection', 'Button { moment.channel = channel } label:', 'Button { } label:', 'A one-tap channel choice must actually select Messages'),
    ('saved note', 'moment.note = moment.note.trimmingCharacters(in: .whitespacesAndNewlines); if store.save(moment, completingHandoff: handoffID)', 'moment.note = ""; if store.save(moment, completingHandoff: handoffID)', 'The saved Messages and its note must survive reopening'),
]
home = Path('ios/Plenara/HomeView.swift')
home_original = home.read_bytes()
records = []
try:
    for name, good, bad, expected in controls:
        text = original.decode(); assert good in text
        source.write_text(text.replace(good, bad, 1))
        Path('.tmp/native-tests.log').unlink(missing_ok=True)
        run = subprocess.run(['bash', 'tool/test-native.sh', '-only-testing:PlenaraUITests/PlenaraUITests/testQuickLogCallsTextsVisitsAndNotesSurviveReopen'], capture_output=True, text=True)
        log = Path('.tmp/native-tests.log').read_text()
        assert run.returncode != 0 and expected in log, name + ' was not rejected for its intended reason'
        records.append({'control': name, 'rejected': True, 'message': expected})
        source.write_bytes(original)
        print('Rejected: ' + name, flush=True)
    text = home_original.decode()
    start = text.index('                if !store.journal.people.isEmpty {')
    end = text.index('                PageHeading', start)
    early = text[start:end]
    actions = early.removeprefix('                if !store.journal.people.isEmpty {\n').removesuffix('                }\n')
    assert 'accessibilityIdentifier("quick-log")' in actions
    destination = '                } else {\n                    if !store.journal.datedReminders()'
    assert destination in text
    text = text.replace(early, '', 1).replace(destination, '                } else {\n' + actions + '                    if !store.journal.datedReminders()', 1)
    home.write_text(text)
    Path('.tmp/native-tests.log').unlink(missing_ok=True)
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
