#!/usr/bin/env python3
"""Bounded simulator RSS samples; stop the owned app if it grows dangerously."""
import subprocess,time,sys,csv,os
sim=sys.argv[1]
limit=int(os.environ.get("PLENARA_RSS_LIMIT_KIB", "524288"))
with open(os.environ.get('PLENARA_MEMORY_TRACE', '.tmp/native-memory.csv'),'w',buffering=1) as f:
 out=csv.writer(f);out.writerow(['time','pid','rss_kib'])
 while True:
  rows=subprocess.check_output(['ps','-axo','pid=,rss=,comm='],text=True).splitlines()
  for row in rows:
   parts=row.strip().split(None,2)
   if len(parts)==3 and sim in parts[2] and parts[2].endswith('/Plenara.app/Plenara'):
    pid,rss=int(parts[0]),int(parts[1]);out.writerow([time.time(),pid,rss])
    if rss>limit:
     subprocess.run(['xcrun','simctl','terminate',sim,'com.plenara.plenaraApp'])
     sys.exit(f'Stopped Plenara above {limit} KiB RSS; inspect the trace before proceeding.')
  time.sleep(2)
