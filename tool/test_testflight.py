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

    def test_release_resolves_group_owner_and_existing_assignment_on_later_pages(self):
        apple = AppleBoundary(['VALID', 'VALID'])
        apple.attached = True
        pages = []

        def paginated(method, path, body=None):
            if method == 'GET' and path.endswith(('/betaGroups', '/betaTesters', '/relationships/builds')):
                pages.append(path)
                return {'data': [], 'links': {'next': 'https://api.appstoreconnect.apple.com/v1' + path + '?cursor=next'}}
            if '?cursor=next' in path:
                return apple(method, path.removeprefix('https://api.appstoreconnect.apple.com/v1').split('?')[0], body)
            return apple(method, path, body)

        self.scope['call'] = paginated
        with contextlib.redirect_stdout(io.StringIO()):
            result = self.release('1000')
        self.assertTrue(result['ownerEnrolled'])
        self.assertTrue(result['builds'][0]['inGroup'])
        self.assertEqual(apple.assignments, 0, 'An existing assignment on a later page must not be repeated')
        self.assertTrue(any(p.endswith('/betaTesters') for p in pages))

    def test_pagination_rejects_cycles_and_foreign_hosts(self):
        # These guards must reject before making another authenticated request.
        for next_url in ('https://api.appstoreconnect.apple.com/v1/items', 'https://example.org/items'):
            with self.subTest(next_url=next_url):
                calls = []
                def cycle(method, path, body=None):
                    calls.append(path)
                    return {'data': [], 'links': {'next': next_url}}
                self.scope['call'] = cycle
                with self.assertRaisesRegex(SystemExit, 'pagination'):
                    self.scope['collection']('/items')
                self.assertEqual(calls, ['/items'])

    def test_duplicate_build_number_on_later_page_is_not_distributed(self):
        apple = AppleBoundary(['VALID'])
        def paginated(method, path, body=None):
            if path == 'https://api.appstoreconnect.apple.com/v1/builds?cursor=next':
                return {'data': [{'id': 'other-build', 'attributes': {
                    'version': '1000', 'processingState': 'VALID', 'expired': False}}]}
            response = apple(method, path, body)
            if path.startswith('/builds?'):
                response['links'] = {'next': 'https://api.appstoreconnect.apple.com/v1/builds?cursor=next'}
            return response
        self.scope['call'] = paginated
        with self.assertRaisesRegex(SystemExit, 'Ambiguous build number'):
            self.release('1000')
        self.assertEqual(apple.assignments, 0)


if __name__ == '__main__':
    unittest.main()
