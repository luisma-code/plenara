#!/usr/bin/env python3
"""Reproduce the inherited-search-keyboard fault and restore production source."""
from pathlib import Path
import subprocess,json
p=Path('ios/Plenara/Organization.swift'); original=p.read_bytes()
try:
 text=original.decode(); good='.searchFocused($searchFocused)'; assert good in text
 p.write_text(text.replace(good,'',1))
 run=subprocess.run(['bash','tool/test-native.sh','-only-testing:PlenaraUITests/PlenaraUITests/testOrganizeBulkSelectionCancelUndoAndImportedJournalReopen'],capture_output=True,text=True)
 expected='The search keyboard must close before shared details open'
 assert run.returncode!=0 and expected in Path('.tmp/native-tests.log').read_text(), 'The inherited keyboard was not rejected'
 Path('verification/organize/focus-calibration.json').write_text(json.dumps({'rejected':True,'message':expected,'sourceRestored':True},indent=2)+'\n')
 print('Rejected the original keyboard-focus fault.',flush=True)
finally:
 p.write_bytes(original);print('Restored source. Rebuild before delivery.',flush=True)
