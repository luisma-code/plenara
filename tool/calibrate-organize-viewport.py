#!/usr/bin/env python3
"""Prove the two repaired viewport journeys fail when their real actions stop."""
from pathlib import Path
import json,subprocess
p=Path('ios/Plenara/HomeView.swift'); original=p.read_bytes()
controls=[
 ('Button("Clear") { filter = PeopleFilter() }','Button("Clear") { }','PlenaraUITests/PlenaraUITests/testExistingImportSurvivesUpgradeAndIndependentChoices','Clearing filters must restore the complete imported list'),
 ('ActionButton(title: "Import from Contacts", icon: "person.badge.plus", primary: false) { importing = true }','ActionButton(title: "Import from Contacts", icon: "person.badge.plus", primary: false) { }','PlenaraUITests/PlenaraUITests/testNativeContactPickerImportAndRepeat','The visible import action must open the native import flow'),
]
records=[]
try:
 for good,bad,test,message in controls:
  text=original.decode();assert good in text;p.write_text(text.replace(good,bad,1))
  run=subprocess.run(['bash','tool/test-native.sh','-only-testing:'+test],capture_output=True,text=True)
  assert run.returncode!=0 and message in Path('.tmp/native-tests.log').read_text(),message+' was not detected'
  records.append({'test':test,'rejected':True,'message':message});p.write_bytes(original)
  print('Rejected: '+message,flush=True)
 Path('verification/organize/viewport-calibration.json').write_text(json.dumps({'controls':records,'sourceRestored':True},indent=2)+'\n')
finally:
 p.write_bytes(original);print('Restored source. Rebuild for the final gate.',flush=True)
