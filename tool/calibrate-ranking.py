#!/usr/bin/env python3
"""Exclusive failure controls; restore sources before rebuilding the delivery candidate."""
from pathlib import Path
import subprocess, json, shutil
model = Path('ios/Plenara/Models.swift')
view = Path('ios/Plenara/HomeFollowUpViews.swift')
queue = Path('ios/Plenara/FollowUpQueue.swift')
originals = {p: p.read_bytes() for p in [model, view, queue]}
controls = [
    (model, 'return l.closeness == "Inner circle"', 'return r.closeness == "Inner circle"',
     'PlenaraTests/RankingTests/testInnerCircleCannotBeDisplacedByGrowthOrCalendarRotation',
     'A due inner-circle person must lead even when Close has growth intent and a longer relative gap', 'priority'),
    (model, '!(p.snoozeUntil.map { $0 > now } ?? false)', 'true',
     'PlenaraTests/FollowUpTests/testRecentContactSharedEventsPauseSnoozeAndOutreachSuppressOptionalInvitations',
     'Recent shared contact must cool down every attendee', 'suppression'),
    (queue, 'selection.people.includes(person),', 'true,',
     'PlenaraTests/FollowUpTests/testFamilyAndIndependentFiltersCombineWithoutChangingJournal',
     'Every selected filter must apply together', 'filters'),
    (view, '.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)', '.frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)',
     'PlenaraUITests/CompactHomeUITests/testColdStartCompactFamilyAndCombinedFiltersSurviveReopen',
     'Normal person rows must stay compact', 'density'),
    (view, 'Text(reminderContext)', 'Text("Reminder details unavailable")',
     'PlenaraUITests/PlenaraUITests/testHomeRankingFullListLogSnoozeAndReopen',
     'Expanded reasons must explain the chosen rhythm', 'explanation'),
]
records = []
try:
    for path, good, bad, test, message, name in controls:
        content = originals[path].decode(); assert good in content
        path.write_text(content.replace(good, bad, 1))
        logpath = Path('.tmp/native-tests.log'); logpath.unlink(missing_ok=True)
        run = subprocess.run(['bash', 'tool/test-native.sh', '-only-testing:' + test], capture_output=True, text=True)
        log = logpath.read_text() if logpath.exists() else ''
        assert run.returncode != 0 and message in log and '** TEST EXECUTE FAILED **' in log, 'Broken control not rejected for expected reason: ' + name
        shutil.copyfile(logpath, 'verification/compact-home/broken-' + name + '.log')
        records.append({'control': name, 'test': test, 'rejected': True, 'message': message})
        path.write_bytes(originals[path]); print('Rejected: ' + name, flush=True)
    Path('verification/compact-home/calibration.json').write_text(json.dumps({'controls': records, 'sourcesRestored': True}, indent=2) + '\n')
finally:
    for path, data in originals.items(): path.write_bytes(data)
    print('Restored all production source; rebuild and run precheck before delivery.', flush=True)
