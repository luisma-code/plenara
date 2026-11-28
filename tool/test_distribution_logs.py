#!/usr/bin/env python3
"""Prove a corrupted copy cannot authorize deletion of its original."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('distribution_logs', Path(__file__).with_name('retain-distribution-logs.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DistributionLogTests(unittest.TestCase):
    def test_source_guard_rejects_a_different_parent(self):
        with tempfile.TemporaryDirectory(dir=".tmp") as directory:
            root = Path(directory).resolve(); allowed = root/'system-temp'; allowed.mkdir()
            valid = allowed/'Plenara_completed.xcdistributionlogs'; valid.mkdir()
            unrelated = root/'Plenara_unrelated.xcdistributionlogs'; unrelated.mkdir()
            module.validate_source(valid, allowed)
            with self.assertRaisesRegex(ValueError, 'Unexpected distribution-log source'):
                module.validate_source(unrelated, allowed)
            self.assertTrue(unrelated.is_dir())

    def test_copy_verification_accepts_preservation_and_rejects_corruption(self):
        with tempfile.TemporaryDirectory(dir=".tmp") as directory:
            root = Path(directory); source = root/'source'; copied = root/'copied'
            source.mkdir(); copied.mkdir()
            for folder in [source, copied]:
                (folder/'log').write_bytes(b'completed export\n')
                (folder/'link').symlink_to('log')
            module.verify_copy(source, copied)
            (copied/'log').write_bytes(b'corrupted export\n')
            with self.assertRaisesRegex(ValueError, 'original retained'):
                module.verify_copy(source, copied)
            self.assertEqual((source/'log').read_bytes(), b'completed export\n')

    def test_incomplete_export_cannot_move_logs(self):
        with tempfile.TemporaryDirectory(dir=".tmp") as directory:
            log = Path(directory)/'export.log'; log.write_text('export started')
            with self.assertRaisesRegex(ValueError, 'completed successful'):
                module.retain(log)


if __name__ == '__main__':
    unittest.main()
