#!/usr/bin/env python3
"""Exercise interruption with a fake runner in an isolated temporary repository."""
import ast, json, os, signal, subprocess, sys, tempfile, time, unittest
from pathlib import Path

class CalibrationInterruptionTests(unittest.TestCase):
    def test_interrupt_restores_sources_and_reaps_owned_runner(self):
        script = Path('tool/calibrate-workflows.py').read_text()
        tree = ast.parse(script)
        faults = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'faults' for t in n.targets))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/'tool').mkdir(); (root/'ios/Plenara').mkdir(parents=True)
            (root/'tool/calibrate-workflows.py').write_text(script)
            originals = {}
            for filename, good, _ in faults['unit']:
                p = root/'ios/Plenara'/filename
                originals[p] = originals.get(p, '') + good + '\n'
            for p, text in originals.items(): p.write_text(text)
            fake = "import pathlib,os,time; pathlib.Path('ready').write_text(str(os.getpid())); time.sleep(60)"
            (root/'tool/test-native.sh').write_text('exec '+sys.executable+" -c '"+fake.replace("'", "'\\''")+"'\n")
            process = subprocess.Popen([sys.executable, 'tool/calibrate-workflows.py', 'unit'], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic()+10
                while not (root/'ready').exists() and time.monotonic()<deadline:
                    self.assertIsNone(process.poll()); time.sleep(.05)
                self.assertTrue((root/'ready').exists(), 'Fake runner must acknowledge startup before interruption')
                child = int((root/'ready').read_text()); process.send_signal(signal.SIGTERM)
                output = process.communicate(timeout=15)[0].decode()
                self.assertIn('Restored all source bytes', output)
                for p,text in originals.items(): self.assertEqual(p.read_text(),text)
                with self.assertRaises(ProcessLookupError): os.kill(child,0)
            finally:
                if process.poll() is None: process.kill(); process.communicate()

    def test_build_failure_cannot_reuse_an_old_red_test_log(self):
        for filename in ['calibrate-workflows.py', 'calibrate-quick-log.py']:
            with self.subTest(runner=filename), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); (root/'tool').mkdir(); (root/'ios/Plenara').mkdir(parents=True); (root/'.tmp').mkdir(); (root/'verification/workflows').mkdir(parents=True); (root/'verification/quick-log').mkdir(parents=True)
                script = Path('tool', filename).read_text(); (root/'tool'/filename).write_text(script)
                tree = ast.parse(script)
                literals = {n.targets[0].id: ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and len(n.targets)==1 and isinstance(n.targets[0],ast.Name) and n.targets[0].id in ['faults','controls','expected']}
                originals = {}
                if filename == 'calibrate-workflows.py':
                    for name, good, _ in literals['faults']['unit']: originals[name] = originals.get(name,'') + good + '\n'
                    old = '\n'.join('error: '+item for item in literals['expected']['unit'])
                    args = ['unit']
                else:
                    originals = {'Editors.swift': '\n'.join(c[1] for c in literals['controls']), 'HomeView.swift': 'untouched home'}
                    old = '\n'.join(c[3] for c in literals['controls']); args = []
                for name,text in originals.items(): (root/'ios/Plenara'/name).write_text(text)
                (root/'.tmp/native-tests.log').write_text(old)
                (root/'tool/test-native.sh').write_text('exit 42\n')
                result = subprocess.run([sys.executable,'tool/'+filename]+args,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=10)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('FileNotFoundError',result.stdout.decode(), 'A build failure must never be accepted using an earlier test log')
                self.assertFalse((root/'.tmp/native-tests.log').exists())
                for name,text in originals.items(): self.assertEqual((root/'ios/Plenara'/name).read_text(),text)

if __name__ == '__main__': unittest.main()
