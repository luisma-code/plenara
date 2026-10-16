#!/usr/bin/env python3
"""Exclusive negative controls for upgrade preservation and independent axes."""
from pathlib import Path
import subprocess,json
paths=[Path('ios/Plenara/JournalStore.swift'),Path('ios/Plenara/Models.swift')]
original={p:p.read_bytes() for p in paths}
checks=[]
def run(arguments, messages):
 r=subprocess.run(['bash','tool/test-native.sh']+arguments,capture_output=True,text=True)
 log=Path('.tmp/native-tests.log').read_text()
 assert r.returncode != 0,'Broken relationship control passed'
 for message in messages: assert message in log,'Expected regression was not detected: '+message
 checks.extend(messages)
try:
 p=paths[0];s=p.read_text();needle='        loaded.migrateRelationshipFields()';assert needle in s;p.write_text(s.replace(needle,'        // negative control: skip old-journal migration',1))
 run(['-only-testing:PlenaraTests/JournalTests/testUpgradePreservesImportedJournalAndOriginalFile','-only-testing:PlenaraUITests/PlenaraUITests/testExistingImportSurvivesUpgradeAndIndependentChoices'],['A build 1001 import must remain readable after upgrade','The previous-version import must open without reimporting'])
 for p,b in original.items():p.write_bytes(b)
 p=paths[0];s=p.read_text();needle='try old.write(to: beforeRelationshipUpdate';assert needle in s;p.write_text(s.replace(needle,'try Data().write(to: beforeRelationshipUpdate',1))
 p=paths[1];s=p.read_text();needle='guard p.cadence > 0, !p.paused,';assert needle in s;s=s.replace(needle,'if p.feelingChoice == "Needs care" { return true }; '+needle,1)
 a=s.index('struct PeopleFilter:');s=s[:a]+s[a:].replace(' &&\n',' ||\n',1);p.write_text(s)
 run(['-only-testing:PlenaraTests/JournalTests/testUpgradePreservesImportedJournalAndOriginalFile','-only-testing:PlenaraTests/JournalTests/testIndependentClassificationAndCombinedFilters','-only-testing:PlenaraTests/JournalTests/testFeelingsAndIntentionsNeverCreateOrAlterReminderRhythms'],['Keep a complete before-update recovery copy','Combined filters must require every dimension','A wish to grow or need for care must not start a reminder'])
 Path('verification/relationships/calibration.json').write_text(json.dumps({'rejectedControls':checks,'nativeSourcesRestored':True},indent=2)+'\n')
 print('All relationship upgrade, filtering, and reminder controls rejected.')
finally:
 for p,b in original.items():p.write_bytes(b)
 print('Restored native sources; rebuild the final candidate.')
