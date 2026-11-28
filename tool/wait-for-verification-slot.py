"""Wait for observed Xcode workload exits before resource-guarded testing."""
import subprocess,select
while True:
 rows=subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines()
 pids=[int(r.strip().split(None,1)[0]) for r in rows if r.strip().endswith('/xcodebuild')]
 if not pids:break
 pid=pids[0];print('Waiting for active Xcode workload PID',pid,flush=True)
 queue=select.kqueue()
 try:
  queue.control([select.kevent(pid,filter=select.KQ_FILTER_PROC,flags=select.KQ_EV_ADD|select.KQ_EV_ONESHOT,fflags=select.KQ_NOTE_EXIT)],1,None)
 except ProcessLookupError:pass
 finally:queue.close()
 print('Observed process exit; rechecking workload inventory.',flush=True)
print('No competing Xcode workload. Starting Release precheck.',flush=True)
