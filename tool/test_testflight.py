#!/usr/bin/env python3
"""Release orchestration: only Apple-confirmed group availability is success."""
import contextlib
import io
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch


class AppleBoundary:
    def __init__(self, states):
        self.states = iter(states)
        self.state = None
        self.attached = False
        self.assignments = 0

    def __call__(self, method, path, body=None):
        if path == '/apps/6795650460':
            return {'data': {'id': 'app', 'attributes': {'bundleId': 'com.plenara.plenaraApp'}}}
        if path.endswith('/betaGroups'):
            return {'data': [{'id': 'group', 'attributes': {'name': 'Internal', 'isInternalGroup': True}}]}
        if path.endswith('/betaTesters'):
            return {'data': [{'attributes': {'email': 'luisma.webaccounts@gmail.com'}}]}
        if path.startswith('/builds?'):
            self.state = next(self.states)
            return {'data': [] if self.state == 'ABSENT' else [{'id': 'build', 'attributes': {
                'version': '1000', 'processingState': self.state, 'expired': False}}]}
        if path.endswith('/preReleaseVersion'):
            return {'data': {'attributes': {'version': '1.0.0', 'platform': 'IOS'}}}
        if path.endswith('/relationships/builds'):
            if method == 'POST':
                if self.state != 'VALID':
                    raise AssertionError('Distributed before processing completed')
                self.attached = True
                self.assignments += 1
            return {'data': [{'id': 'build'}] if self.attached else []}
        if path.endswith('/buildBetaDetail'):
            return {'data': {'attributes': {'internalBuildState':
                    'IN_BETA_TESTING' if self.attached else 'READY_FOR_BETA_TESTING'}}}
        raise AssertionError((method, path))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(Path(__file__).with_name('testflight.py')))
        self.release = self.module['release']
        self.scope = self.release.__globals__

    def test_waits_for_processing_and_confirms_distribution(self):
        apple = AppleBoundary(['ABSENT', 'PROCESSING', 'VALID', 'VALID'])
        self.scope['call'] = apple
        with patch.object(self.scope['time'], 'sleep') as sleep, contextlib.redirect_stdout(io.StringIO()):
            result = self.release('1000')
        self.assertEqual(apple.assignments, 1, 'Release must assign the processed build automatically')
        self.assertEqual(sleep.call_count, 2, 'Absence/processing must wait for fresh Apple state')
        self.assertTrue(result['builds'][0]['inGroup'])
        self.assertEqual(result['builds'][0]['betaDetail']['internalBuildState'], 'IN_BETA_TESTING')

    def test_rejection_is_not_delivery(self):
        apple = AppleBoundary(['INVALID'])
        self.scope['call'] = apple
        with self.assertRaisesRegex(SystemExit, 'rejected or expired'):
            self.release('1000')
        self.assertEqual(apple.assignments, 0)

    def test_timeout_is_not_delivery(self):
        apple = AppleBoundary(['ABSENT'])
        self.scope['call'] = apple
        with patch.object(self.scope['time'], 'monotonic', side_effect=[0, 2]):
            with self.assertRaisesRegex(SystemExit, 'not confirmed TestFlight availability'):
                self.release('1000', timeout=1)
        self.assertEqual(apple.assignments, 0)


if __name__ == '__main__':
    unittest.main()
