#!/usr/bin/env python3
"""Verify the stop-log oracle catches a missing log even with earlier diagnostics.
Only temporary copies are mutated. The production worktree is never edited.
"""
from pathlib import Path
import subprocess
import tempfile
import re

root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
baseline = 'c4dae149f83d652c73affecb8abacb118ec37d56'
paths = [
    'Tests/run-task-operation-tests.py', 'Tests/TaskOperationTestSupport.swift',
    'MeoAsstMac/Model/MAAViewModel.swift', 'MeoAsstMac/Model/NewViewModel.swift',
    'MeoAsstMac/Model/MAAError.swift', 'MeoAsstMac/Views/TaskButtons.swift',
    'MeoAsstMac/Utils/TaskTimerManager.swift',
]
old_test = subprocess.check_output(
    ['git', 'show', baseline + ':Tests/TaskOperationTests.swift'], cwd=root, text=True)
marker = '            var stopRejected = false\n'
assert marker in old_test
old_test = old_test.replace(marker, '            model.errors.append("Earlier unrelated diagnostic")\n' + marker, 1)
new_test = (root / 'Tests/TaskOperationTests.swift').read_text()
log = 'if logsConflict { logError("当前正在启动或停止任务，请稍后重试。") }'
with tempfile.TemporaryDirectory(prefix='maa-stop-log-mutation-') as tmp:
    for name, test, expected in [('old-oracle', old_test, 0), ('fixed-oracle', new_test, 1)]:
        snapshot = Path(tmp) / name
        for rel in paths:
            dest = snapshot / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            source = (root / rel).read_text()
            if rel == 'MeoAsstMac/Model/MAAViewModel.swift':
                assert source.count(log) == 1
                # Keep logging for conflicting starts, suppress it only for stop.
                source = source.replace(
                    log, 'if logsConflict, requiresIdle { logError("当前正在启动或停止任务，请稍后重试。") }', 1)
            dest.write_text(source)
        (snapshot / 'Tests/TaskOperationTests.swift').write_text(test)
        result = subprocess.run(
            ['python3', 'Tests/run-task-operation-tests.py'],
            cwd=snapshot, shell=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (out / (name + '.log')).write_text(result.stdout)
        print(name + ': exit=' + str(result.returncode) + '\n' + result.stdout)
        assert result.returncode == expected, 'Unexpected mutation verdict: ' + name
        if name == 'fixed-oracle':
            assert 'FAIL: stop rejection appends its own busy log' in result.stdout
            assert re.search(r'^\d+ assertions; 1 failures$', result.stdout, re.M)
        else:
            assert '242 assertions; 0 failures' in result.stdout
print('PASS: old oracle masks the missing stop log; fixed oracle detects it.')
