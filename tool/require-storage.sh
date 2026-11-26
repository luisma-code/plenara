#!/usr/bin/env bash
# Source after changing to the repository root. Never recreate a missing mount.
PLENARA_VOLUME_UUID=$(/usr/sbin/diskutil info -plist /Volumes/MacExt 2>/dev/null | python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read()).get("VolumeUUID", ""))') || { echo 'Plenara requires the mounted MacExt development drive.' >&2; return 1; }
if [ "$PLENARA_VOLUME_UUID" != '2B4972AC-6571-4862-9042-46B7AB6006A2' ]; then
  echo 'Plenara development drive UUID does not match MacExt.' >&2
  return 1
fi
python3 - <<'PY'
from pathlib import Path
base = Path('/Volumes/MacExt/DeveloperData/projects/plenara')
for name, leaf in [('.build', 'build'), ('.tmp', 'tmp')]:
    link = Path(name)
    if not link.is_symlink() or link.resolve() != base / leaf or not link.is_dir():
        raise SystemExit(f'Plenara output must use the external {name} link to {base / leaf}')
PY
if [ "$?" != 0 ]; then return 1; fi
export TMPDIR="$(cd .tmp && pwd -P)/system-tmp"
export PYTHONPYCACHEPREFIX="$(cd .tmp && pwd -P)/python-cache"
mkdir -p "$TMPDIR" "$PYTHONPYCACHEPREFIX"
