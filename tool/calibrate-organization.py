#!/usr/bin/env python3
"""Exclusive known-broken checks for organizing; always restore all sources."""
from pathlib import Path
import subprocess,json
store=Path('ios/Plenara/JournalStore.swift'); view=Path('ios/Plenara/Organization.swift')
original={p:p.read_bytes() for p in [store,view]}
controls=[
 (store,'for i in candidate.people.indices where ids.contains(candidate.people[i].id)', 'for i in candidate.people.indices',
  'PlenaraTests/JournalTests/testOrganizationOnlyChangesChosenPeopleAndFieldsAndUndoPreservesNewNotes', 'Organizing must preserve unselected people, imported fields, notes, moments, and rhythms'),
 (store,'guard receipt.changes.allSatisfy({ edit in', 'guard true || receipt.changes.allSatisfy({ edit in',
  'PlenaraTests/JournalTests/testOrganizationUndoRejectsNewerChoicesAndRestoresNoDeletedPeople', 'Undo must refuse to overwrite a newer choice'),
 (store,'guard update({ $0 = candidate }) else { return nil }', '_ = update({ $0 = candidate }); journal = candidate',
  'PlenaraTests/JournalTests/testOrganizationFailedSaveIsAtomicAndKeepsUndoAvailable', 'A failed batch must not publish any partial edits'),
 (view,'store.organize([p.id], changes: [field: choice])', 'store.organize([p.id], changes: [field: field.value(p)])',
  'PlenaraUITests/PlenaraUITests/testOrganizeQuickSortUnsetSkipUndoAndSave', 'Setting a value must remove it from the Not set only view'),
]
records=[]
try:
 for path,good,bad,test,message in controls:
  content=original[path].decode();assert good in content
  path.write_text(content.replace(good,bad,1))
  run=subprocess.run(['bash','tool/test-native.sh','-only-testing:'+test],capture_output=True,text=True)
  log=Path('.tmp/native-tests.log').read_text()
  assert run.returncode!=0 and message in log, 'Known-broken state was not rejected for: '+message
  records.append({'test':test,'rejected':True,'message':message})
  path.write_bytes(original[path]); print('Rejected: '+message,flush=True)
 Path('verification/organize/calibration.json').write_text(json.dumps({'controls':records,'sourcesRestored':True},indent=2)+'\n')
finally:
 for p,data in original.items():p.write_bytes(data)
 print('Restored sources. Rebuild and run full precheck before delivery.',flush=True)
