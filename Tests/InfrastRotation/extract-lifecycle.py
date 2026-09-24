"""Compile the exact production integration methods against a fake Core, without Xcode.
This does not replace the full GUI target build or its real callback dispatcher.
"""
from pathlib import Path
import sys
repo = Path(__file__).resolve().parents[2]
text = (repo / 'MeoAsstMac/Model/MAAViewModel.swift').read_text()
start = text.index('        var submitted = false', text.index('private func startTasks'))
end = text.index('    private func initScheduledDailyTaskTimer()', start)
submission = text[start:end]
helpers = text[text.index('// MARK: - Custom infrastructure execution history'):]
Path(sys.argv[1]).write_text('import Foundation\nextension MAAViewModel {\n    func submitForTest() async throws {\n' + submission + '}\n' + helpers)
