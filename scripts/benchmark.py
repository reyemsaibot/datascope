#!/usr/bin/env python3
"""Run once; record process peak RSS (macOS bytes) and end-to-end wall time."""
from pathlib import Path
import json, platform, resource, subprocess, time
root = Path(__file__).resolve().parent.parent
start = time.monotonic()
run = subprocess.run([str(root / '.build/release/profile'), str(root / 'Fixtures/million.csv')], capture_output=True, text=True, check=True)
wall = time.monotonic() - start
max_rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
profile = json.loads(run.stdout)
assert profile['rows'] == 1_000_000
assert len(profile['columns']) == 8
assert profile['columns'][0]['distinct'] == 1_000_000
assert profile['columns'][3]['nulls'] == 100_000
assert len(profile['preview']) == 100
hardware = {}
try:
    data = json.loads(subprocess.check_output(['/usr/sbin/system_profiler','SPHardwareDataType','-json'], text=True))['SPHardwareDataType'][0]
    hardware = {k: data[k] for k in ('machine_name', 'machine_model', 'chip_type', 'physical_memory', 'number_processors') if k in data}
except (subprocess.CalledProcessError, KeyError):
    pass
result = dict(hardware=hardware, architecture=platform.machine(), macOS=platform.mac_ver()[0],
              fileBytes=profile['fileBytes'], rows=profile['rows'], columns=len(profile['columns']),
              importSeconds=profile['importSeconds'], analysisTotalSeconds=profile['totalSeconds'],
              wallSeconds=wall, maxRSSBytes=max_rss,
              engine=profile['engineVersion'], checks='row count, distinct IDs, missing emails, preview limit passed',
              caveat='Single synthetic run; OS cache not flushed; RSS includes runtime, not just DuckDB buffer manager.')
(root / 'docs/benchmark.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
