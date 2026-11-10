#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d /tmp/maa-schedule-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
swiftc -parse-as-library MeoAsstMac/Scheduling/DailyTaskSchedule.swift MeoAsstMac/Scheduling/ScheduleOccurrenceStore.swift MeoAsstMac/Scheduling/ScheduleHandoff.swift Tests/ScheduleTests.swift -o "$build_dir/tests"
"$build_dir/tests"
python3 - "$build_dir/tests" "$build_dir/ledger" <<'PYWORKERS'
import concurrent.futures, subprocess, sys, uuid
exe,directory=sys.argv[1:]
identity=str(uuid.uuid4())
def claim(_):
    result=subprocess.run([exe,'--claim',directory,identity],capture_output=True,text=True,check=True)
    return result.stdout.strip()
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
    results=list(pool.map(claim,range(32)))
assert results.count('claimed') == 1, results
assert results.count('duplicate') == 31, results
print('PASS: 32 real processes race for one occurrence; exactly one claim')
PYWORKERS
