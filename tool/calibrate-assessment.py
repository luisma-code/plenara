#!/usr/bin/env python3
"""Reject an ineffective assessment filter through the actual Organize UI."""
from pathlib import Path
import subprocess, json, shutil
view = Path('ios/Plenara/Organization.swift')
original = view.read_bytes()
try:
    good = '? (!needsAssessmentOnly || (missingDetail.map'
    bad = '? (true || !needsAssessmentOnly || (missingDetail.map'
    assert good in original.decode()
    view.write_text(original.decode().replace(good, bad, 1))
    run = subprocess.run(['bash', 'tool/test-native.sh', '-only-testing:PlenaraUITests/PlenaraUITests/testOrganizeNeedsAssessmentFilterBatchUndoAndReopen'], capture_output=True, text=True)
    log = Path('.tmp/native-tests.log').read_text()
    message = 'Fully assessed people must be hidden'
    assert run.returncode != 0 and message in log, 'Known broken assessment filter was not rejected for the intended reason'
    shutil.copyfile('.tmp/native-tests.log', 'verification/assessment/broken-filter.log')
    Path('verification/assessment/calibration.json').write_text(json.dumps({'mutation': 'Together keeps all people while the assessment toggle stays enabled', 'test': 'testOrganizeNeedsAssessmentFilterBatchUndoAndReopen', 'rejected': True, 'failure': message, 'sourcesRestored': True}, indent=2) + '\n')
    print('Rejected ineffective assessment filter.', flush=True)
finally:
    view.write_bytes(original)
    print('Restored production source. Rebuild before delivery.', flush=True)
