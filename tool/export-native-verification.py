#!/usr/bin/env python3
from pathlib import Path
import subprocess,json,shutil,sys,hashlib,csv
result=Path(sys.argv[1])
out=Path('.tmp/final-native-attachments')
if out.exists(): shutil.rmtree(out)
out.mkdir()
subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(out)],check=True,stdout=subprocess.DEVNULL)
summary=subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result),'--format','json'])
Path('verification/native-test-summary.json').write_bytes(summary)
labels={'Stay close':'stay-close','People':'people','Person':'person','Person notes':'person-notes','Moments':'moments','Settings':'settings','Backup export':'backup-export','Dark Stay close':'dark-home','Dark person':'dark-person','Large text People':'large-text-people','Large text person':'large-text-person','Repeat import review':'repeat-import','Reminder settings':'reminder-settings','Dated reminders':'dated-reminders'}
found=set()
for test in json.loads((out/'manifest.json').read_text()):
 for a in test['attachments']:
  name=a['suggestedHumanReadableName'].split('_0_')[0]
  if name in labels and a['exportedFileName'].endswith('.png'):
   shutil.copyfile(out/a['exportedFileName'],Path('verification')/(labels[name]+'.png'));found.add(name)
assert found==set(labels),'Missing screenshots: '+str(set(labels)-found)
shutil.copyfile('.tmp/full-native-memory.csv' if Path('.tmp/full-native-memory.csv').exists() else '.tmp/native-memory.csv','verification/native-memory.csv')
memory=Path('verification/native-memory.csv')
memory.write_bytes(memory.read_bytes().replace(b'\r\n',b'\n'))
files=list(Path('ios/Plenara').rglob('*'))+[Path('ios/project.yml')]
Path('verification/native-source-hashes.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files) if p.is_file()},indent=2)+'\n')
print('Exported '+str(len(found))+' native screenshots and verification metadata.')
