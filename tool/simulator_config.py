"""One configuration for Plenara's dedicated external verification simulator."""
import os
from pathlib import Path
import shlex

DEFAULT_ID = '24BF69CD-E43A-4D88-80ED-BBCFD6798C32'
DEFAULT_SET = '/Volumes/MacExt/DeveloperData/projects/plenara/simulators'


def settings():
    return (os.environ.get('PLENARA_SIMULATOR_ID', DEFAULT_ID),
            Path(os.environ.get('PLENARA_SIMULATOR_SET', DEFAULT_SET)))


def command(*arguments):
    return ['xcrun', 'simctl', '--set', str(settings()[1]), *arguments]


if __name__ == '__main__':
    device, device_set = settings()
    print('SIMULATOR_ID=' + shlex.quote(device))
    print('SIMULATOR_SET=' + shlex.quote(str(device_set)))
