#!/usr/bin/env python3
"""Exercise the guard against the real simulator app, without a large allocation."""
import subprocess,os,time,csv,json
from pathlib import Path
sim=os.environ.get('PLENARA_SIMULATOR_ID','BB42F29A-928B-4B9E-BD39-160B70249D4F')
bundle='com.plenara.plenaraApp'
launch=['xcrun','simctl','launch',sim,bundle,'--ui-testing','--reset','--demo']
stop=['xcrun','simctl','terminate',sim,bundle]
watch=None
try:
 subprocess.run(launch,check=True,capture_output=True)
 env=os.environ|{'PLENARA_RSS_LIMIT_KIB':'1','PLENARA_MEMORY_TRACE':'.tmp/memory-stop-control.csv'}
 broken=subprocess.run(['python3','tool/watch-memory.py',sim],env=env,capture_output=True,text=True,timeout=15)
 assert broken.returncode==1 and 'Stopped Plenara above 1 KiB RSS' in broken.stderr,broken.stderr
 stopped=subprocess.check_output(['ps','-axo','comm='],text=True)
 assert not any(sim in line and line.endswith('/Plenara.app/Plenara') for line in stopped.splitlines()),'Guard did not stop the app'
 subprocess.run(launch,check=True,capture_output=True)
 env=os.environ|{'PLENARA_MEMORY_TRACE':'.tmp/memory-good-control.csv'}
 watch=subprocess.Popen(['python3','tool/watch-memory.py',sim],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 deadline=time.monotonic()+15;trace=Path('.tmp/memory-good-control.csv')
 while time.monotonic()<deadline:
  assert watch.poll() is None,'Default guard unexpectedly stopped the app'
  if trace.exists() and len(trace.read_text().splitlines())>=4:break
  time.sleep(.2)
 else:raise AssertionError('Guard did not record three live samples')
 rows=list(csv.DictReader(trace.open()));peak=max(int(row['rss_kib']) for row in rows)
 assert 0<peak<524288
 result={'realAppStoppedWithOneKiBLimit':True,'realAppContinuedWithDefault512MiBLimit':True,'goodControlPeakRSSKiB':peak,'proof':'Guard routing and comparison; not a leak or device-resource claim.'}
 Path('verification/memory-guard-calibration.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result))
finally:
 if watch is not None:
  watch.terminate();watch.wait(timeout=10)
 subprocess.run(stop,capture_output=True)
