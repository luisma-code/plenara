#!/usr/bin/env python3
"""Retain Xcode's completed Foundation-temp logs on MacExt after export exits."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def inventory(root):
    result = {}
    for path in sorted(root.rglob('*')):
        name = str(path.relative_to(root))
        if path.is_symlink():
            result[name] = ['link', os.readlink(path)]
        elif path.is_file():
            result[name] = ['file', path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest()]
        elif path.is_dir():
            result[name] = ['directory']
        else:
            raise ValueError('Unsupported distribution-log entry')
    return result


def verify_copy(source, destination):
    if inventory(source) != inventory(destination):
        raise ValueError('Distribution-log copy differs; original retained')


def validate_source(source, system_temp):
    if (source.is_symlink() or source.resolve().parent != system_temp or
            not source.name.startswith('Plenara_') or not source.is_dir() or
            source.stat().st_uid != os.getuid()):
        raise ValueError('Unexpected distribution-log source; nothing moved')


def retain(log):
    text = Path(log).read_text()
    if '** EXPORT SUCCEEDED **' not in text:
        raise ValueError('Only completed successful exports may consolidate logs')
    paths = set(re.findall(r'Created bundle at path "([^"]+\.xcdistributionlogs)"', text))
    if len(paths) != 1:
        raise ValueError('Expected one completed Plenara distribution-log bundle')
    source = Path(paths.pop())
    # Python does not expose Darwin's symbolic confstr alias; use the verified
    # system getconf query, which agrees with Foundation's temporary directory.
    system_temp = Path(subprocess.check_output(
        ['/usr/bin/getconf', 'DARWIN_USER_TEMP_DIR'], text=True).strip()).resolve()
    validate_source(source, system_temp)
    external = Path('/Volumes/MacExt/DeveloperData/projects/plenara/tmp')
    if not Path('.tmp').is_symlink() or not Path('.tmp').is_dir() or Path('.tmp').resolve() != external:
        raise ValueError('MacExt temporary storage is required')
    destination = external / 'testflight/distribution-logs'
    candidate = destination.with_name('distribution-logs-candidate')
    previous = destination.with_name('distribution-logs-previous')
    if candidate.exists() or previous.exists():
        raise ValueError('An unfinished log replacement needs inspection')
    shutil.copytree(source, candidate, symlinks=True)
    verify_copy(source, candidate)
    entries = inventory(candidate)
    if destination.exists():
        destination.rename(previous)
    candidate.rename(destination)
    # The export process has exited, and every copied entry was verified.
    shutil.rmtree(source)
    if previous.exists():
        shutil.rmtree(previous)
    return {'source': str(source), 'destination': str(destination),
            'verifiedFiles': sum(v[0] == 'file' for v in entries.values()),
            'verifiedBytes': sum(v[1] for v in entries.values() if v[0] == 'file'),
            'internalOriginalRemoved': not source.exists()}


if __name__ == '__main__':
    # Reuse the authoritative UUID/link checks, including after a long export.
    subprocess.run(['/bin/bash', '-c', 'source tool/require-storage.sh'], check=True)
    print(json.dumps(retain(sys.argv[1]), indent=2))
