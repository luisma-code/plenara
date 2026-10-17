#!/usr/bin/env python3
"""Save captures and build provenance from the completed Release precheck."""
from pathlib import Path
import hashlib, json, shutil, subprocess
result = Path('.tmp/latest-full-native-result.txt').read_text().strip()
dest = Path('verification/quick-log'); dest.mkdir(exist_ok=True)
attachments = Path('.tmp/quick-log-attachments')
if attachments.exists(): shutil.rmtree(attachments)
subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', result, '--output-path', str(attachments)], check=True, stdout=subprocess.DEVNULL)
labels = {'Stay close': 'home', 'Quick person chooser': 'chooser', 'Quick moment editor': 'editor', 'Quick moment history': 'history', 'Dark quick moment': 'dark', 'Large quick moment': 'large'}
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
shutil.copyfile('.tmp/full-native-memory.csv', dest / 'memory.csv')
print('Exported six current native captures and Release verification evidence.')
