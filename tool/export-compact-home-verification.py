#!/usr/bin/env python3
"""Retain selected full-device captures and the final Release receipts."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

result = Path('.tmp/latest-full-native-result.txt').read_text().strip()
dest = Path('verification/compact-home')
dest.mkdir(exist_ok=True)
scratch = Path('.tmp/compact-final-attachments')
if scratch.exists():
    shutil.rmtree(scratch)
subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', result, '--output-path', str(scratch)], check=True, stdout=subprocess.DEVNULL)
labels = {
    'Compact Home': 'home', 'Family Home': 'family', 'Home filters': 'filters',
    'Filtered Home': 'filtered', 'Home person actions': 'actions',
    'Home no reminders': 'empty', 'Home due reminders': 'due',
    'Dark compact Home': 'dark-home', 'Large Home filters': 'large-filters',
    'Large Home log contact': 'large-log', 'Ranked compact Home': 'ranked-home',
    'Complete compact ranked list': 'ranked-complete', 'Compact ranked Home after snooze': 'after-snooze',
}
found = set()
for test in json.loads((scratch / 'manifest.json').read_text()):
    for item in test['attachments']:
        label = item['suggestedHumanReadableName'].split('_0_')[0]
        if label in labels and item['exportedFileName'].endswith('.png'):
            shutil.copyfile(scratch / item['exportedFileName'], dest / (labels[label] + '.png'))
            found.add(label)
assert found == set(labels), 'Missing current captures: ' + str(set(labels) - found)
for name, receipt in [('native-tests.json', '.tmp/latest-full-native-result.txt'), ('contacts-denied.json', '.tmp/latest-denied-native-result.txt')]:
    bundle = Path(receipt).read_text().strip()
    summary = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', bundle])
    parsed = json.loads(summary)
    assert parsed['result'] == 'Passed' and parsed['failedTests'] == 0 and parsed['passedTests'] > 0
    (dest / name).write_bytes(summary)
paths = list(Path('ios/Plenara').rglob('*')) + list(Path('ios/PlenaraTests').rglob('*.swift')) + list(Path('ios/PlenaraUITests').glob('*.swift')) + [Path('ios/project.yml')]
(dest / 'source-hashes.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths) if p.is_file()}, indent=2) + '\n')
shutil.copyfile('.tmp/full-native-memory.csv', dest / 'memory.csv')
shutil.copyfile('.tmp/native-memory.csv', dest / 'contacts-denied-memory.csv')
shutil.rmtree(scratch)
print('Retained 13 native captures, final summaries, memory samples and source hashes.')
