#!/usr/bin/env python3
"""Export final assessment UI and Release evidence, replacing scratch exports."""
from pathlib import Path
import hashlib, json, shutil, subprocess
result = Path('.tmp/latest-full-native-result.txt').read_text().strip()
dest = Path('verification/assessment')
attachments = Path('.tmp/assessment-final-attachments')
if attachments.exists(): shutil.rmtree(attachments)
subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', result, '--output-path', str(attachments)], check=True, stdout=subprocess.DEVNULL)
labels = {'Assessment remaining': 'assessment-remaining', 'Assessment specific detail': 'assessment-specific-detail', 'Assessment complete': 'assessment-complete', 'Dark organizer assessment': 'dark-organizer-assessment', 'Large text organizer assessment': 'large-text-organizer-assessment'}
found = set()
for test in json.loads((attachments / 'manifest.json').read_text()):
    for item in test['attachments']:
        label = item['suggestedHumanReadableName'].split('_0_')[0]
        if label in labels and item['exportedFileName'].endswith('.png'):
            shutil.copyfile(attachments / item['exportedFileName'], dest / (labels[label] + '.png')); found.add(label)
assert found == set(labels), set(labels) - found
for name, path in [('native-tests.json', result), ('contacts-denied.json', Path('.tmp/latest-denied-native-result.txt').read_text().strip())]:
    (dest / name).write_bytes(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', path, '--format', 'json']))
files = list(Path('ios/Plenara').rglob('*')) + [Path('ios/project.yml')]
(dest / 'source-hashes.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files) if p.is_file()}, indent=2) + '\n')
(dest / 'memory.csv').write_text(Path('.tmp/full-native-memory.csv').read_text())
print('Exported five native assessment captures and Release evidence.')
