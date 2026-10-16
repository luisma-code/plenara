#!/usr/bin/env python3
"""Exclusive negative controls for appearance, recovery, and neutral import."""
from pathlib import Path
import subprocess,json
changes=[
 ('PlenaraApp.swift','.preferredColorScheme(simulatorAppearance)', '.preferredColorScheme(nil)'),
 ('JournalStore.swift','if !locked && FileManager.default.fileExists(atPath: file.path)', 'if FileManager.default.fileExists(atPath: file.path)'),
 ('Models.swift','var relationship = "Not set"','var relationship = "Friend"')]
original={Path('ios/Plenara')/name:(Path('ios/Plenara')/name).read_bytes() for name,_,_ in changes}
try:
 for name,good,bad in changes:
  p=Path('ios/Plenara')/name;s=p.read_text();assert good in s;p.write_text(s.replace(good,bad,1))
 run=subprocess.run(['bash','tool/test-native.sh','-only-testing:PlenaraTests/JournalTests/testCorruptJournalIsNotOverwritten','-only-testing:PlenaraTests/JournalTests/testImportDeduplicatesPreservesJournalAndCanLinkManualPerson','-only-testing:PlenaraUITests/PlenaraUITests/testDarkAndLargeTextNavigation'],capture_output=True,text=True)
 log=Path('.tmp/native-tests.log').read_text()
 expected=['Recovery must not overwrite a good previous save','Import must not assume that a family member is a friend','Dark mode must render a dark canvas']
 assert run.returncode != 0
 for message in expected:assert message in log,message+' was not detected'
 Path('verification/final-fix-calibration.json').write_text(json.dumps({'rejectedBrokenControls':expected,'sourcesRestored':True},indent=2)+'\n')
 print('All three focused broken controls were rejected with their intended messages.')
finally:
 for p,content in original.items():p.write_bytes(content)
 print('Restored native sources; rebuild for final verification and delivery.')
