#!/usr/bin/env python3
"""Export reviewed screenshots and provenance from the complete native gate."""
from pathlib import Path
import subprocess,json,hashlib,shutil
result=Path('.tmp/latest-full-native-result.txt').read_text().strip()
dest=Path('verification/relationships');dest.mkdir(exist_ok=True)
out=Path('.tmp/final-relationship-attachments')
if out.exists():shutil.rmtree(out)
subprocess.run(['xcrun','xcresulttool','export','attachments','--path',result,'--output-path',str(out)],check=True,stdout=subprocess.DEVNULL)
labels={'Stay close':'home','People':'people','Person':'person','Migrated imported person':'migrated-person','Independent relationship choices':'choices','About your relationship':'about','Updated relationship profile':'profile','Combined relationship filters':'combined-filters','All relationship filters':'filters','Dark relationship choices':'dark-choices','Large text relationship choices':'large-choices'}
found=set()
for test in json.loads((out/'manifest.json').read_text()):
 for a in test['attachments']:
  label=a['suggestedHumanReadableName'].split('_0_')[0]
  if label in labels and a['exportedFileName'].endswith('.png'):
   shutil.copyfile(out/a['exportedFileName'],dest/(labels[label]+'.png'));found.add(label)
assert found==set(labels),set(labels)-found
for filename,where in [('native-tests.json',result),('contacts-denied.json',Path('.tmp/latest-denied-native-result.txt').read_text().strip())]:
 (dest/filename).write_bytes(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',where,'--format','json']))
files=list(Path('ios/Plenara').rglob('*'))+[Path('ios/project.yml')]
(dest/'source-hashes.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files) if p.is_file()},indent=2)+'\n')
(dest/'memory.csv').write_text(Path('.tmp/full-native-memory.csv').read_text())
print('Exported all '+str(len(found))+' relationship captures and verification metadata.')
