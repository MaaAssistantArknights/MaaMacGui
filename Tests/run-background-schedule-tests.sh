#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d /tmp/maa-background-schedule-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
swiftc -parse-as-library MeoAsstMac/Scheduling/DailyTaskSchedule.swift MeoAsstMac/Scheduling/ScheduleOccurrenceStore.swift MeoAsstMac/Scheduling/BackgroundScheduleSchema.swift MeoAsstMac/Scheduling/BackgroundScheduleCheck.swift MeoAsstMac/Scheduling/ScheduleAgentLocation.swift Tests/BackgroundScheduleTests.swift -o "$build_dir/tests"
"$build_dir/tests"
python3 - "$build_dir/tests" "$build_dir/ledger" <<'PYWORKERS'
import concurrent.futures, pathlib, subprocess, sys
exe,directory=sys.argv[1:]
subprocess.run([exe,'--setup',directory],check=True)
def check(_):
    return subprocess.run([exe,'--race',directory],capture_output=True,text=True,check=True).stdout.strip()
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
    results=list(pool.map(check,range(32)))
assert results.count('delivered') == 1, results
assert results.count('duplicate') == 31, results
assert len(list((pathlib.Path(directory)/'Inbox').glob('*.json'))) == 1
print('PASS: 32 real agent checks publish exactly one intent for the stable batch winner')
def accept(_):
    return subprocess.run([exe,'--accept',directory],capture_output=True,text=True,check=True).stdout.strip()
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
    accepted=list(pool.map(accept,range(32)))
assert accepted.count('accepted') == 1 and accepted.count('duplicate') == 31, accepted
print('PASS: 32 real GUI consumers transfer the helper claim exactly once')
PYWORKERS
