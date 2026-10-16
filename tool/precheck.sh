#!/usr/bin/env bash
# Quality gate for native Plenara and its retained design reference.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 - <<'PY'
import tarfile, hashlib, json
from pathlib import Path
base=Path('archive/2026-10-16-reset')
manifest=json.loads((base/'manifest.json').read_text())
assert len(manifest)==926, 'Archive manifest must contain all 926 original tracked files'
with tarfile.open(base/'plenara-before-reset.tar.gz') as src:
    assert set(src.getnames())=={item['path'] for item in manifest}, 'Archive membership mismatch'
    for item in manifest:
        assert hashlib.sha256(src.extractfile(item['path']).read()).hexdigest()==item['sha256'], 'Archive bytes changed: '+item['path']
for retired in ['app','v0','planning','.agents','.codex','.github','WORK-CAPSULE.md']:
    assert not Path(retired).exists(), 'Retired project content active at root: '+retired
print('PASS: 926 archived files verified; old app, CI, and project guidance inert')
PY
RUNTIME="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies"
if command -v node >/dev/null 2>&1; then
  NODE="$(command -v node)"
else
  NODE="$RUNTIME/node/bin/node"
fi
export PATH="$(dirname "$NODE"):$PATH"
export NODE_PATH="${NODE_PATH:-$RUNTIME/node/node_modules}"
"$NODE" tool/check-design.cjs "$@"
python3 tool/test_testflight.py
bash tool/test-native.sh
cp .tmp/latest-native-result.txt .tmp/latest-full-native-result.txt
cp .tmp/native-memory.csv .tmp/full-native-memory.csv
PLENARA_CONTACTS_DENIED=1 bash tool/test-native.sh -only-testing:PlenaraUITests/PlenaraUITests/testNativeContactPickerImportAndRepeat
cp .tmp/latest-native-result.txt .tmp/latest-denied-native-result.txt
