#!/usr/bin/env python3
from pathlib import Path
import subprocess,json
paths=[Path('ios/Plenara')/name for name in ['Models.swift','HomeView.swift']]
original={p:p.read_bytes() for p in paths}
try:
 p=paths[0];s=p.read_text();needle='for p in people.filter({ !$0.paused }).sorted';assert needle in s;p.write_text(s.replace(needle,'for p in people.filter({ _ in true }).sorted',1))
 p=paths[1];s=p.read_text();needle='j.people[i].notes[n].followUp = nil';assert needle in s;p.write_text(s.replace(needle,'j.people[i].notes.remove(at: n)',1))
 run=subprocess.run(['bash','tool/test-native.sh','-only-testing:PlenaraTests/JournalTests/testDatedRemindersHaveVisiblePersonContext','-only-testing:PlenaraUITests/PlenaraUITests/testDatedReminderContext'],capture_output=True,text=True)
 log=Path('.tmp/native-tests.log').read_text()
 expected=['Pausing a person hides their dated reminders','Completing a dated reminder must keep the memory']
 assert run.returncode!=0
 for message in expected:assert message in log,message
 Path('verification/dated-reminder-calibration.json').write_text(json.dumps({'rejectedBrokenControls':expected,'sourcesRestored':True},indent=2)+'\n')
 print('Both dated-reminder checks rejected their intended broken states.')
finally:
 for p,content in original.items():p.write_bytes(content)
 print('Restored sources. Rebuild the delivery candidate.')
