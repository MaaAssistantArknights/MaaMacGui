#!/usr/bin/env python3
"""Compile the production callback case against the real JBird module."""
from pathlib import Path
import json, subprocess, sys, tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'MeoAsstMac/Core/MaaMessage.swift').read_text()
start=source.index('        case "BlackFlowStartRun":')
end=source.index('\n        case ', start+1)
case=source[start:end]
catalog=json.loads((root/'Resources/Localizable.xcstrings').read_text())
packet=json.loads((root/'Tests/Fixtures/BlackFlowStartRunFailure.json').read_text())
assert packet['what']=='BlackFlowStartRun' and packet['taskchain']=='Roguelike' and packet['details']['status']=='reward_recognition_failed'
localizations=catalog['strings']['BlackFlowStartRunRecognitionFailed']['localizations']
for locale in ('zh-Hans', 'en', 'ko'):
    assert localizations[locale]['stringUnit']['value'], locale
derived=Path(sys.argv[1]); packages=Path(sys.argv[2]); products=derived/'Build/Products/Debug'
probe='''import Foundation
import JBird
struct Info { let details: JSON }
var warnings: [String] = []
func logWarn(verbatim text: String) { warnings.append(text) }
func handle(_ status: String) throws {
 let info = Info(details: try JSON(JSONSerialization.data(withJSONObject: ["status": status])))
 switch "BlackFlowStartRun" {
'''+case+'''
 default: break
 }
}
for status in ["reward_recognition_failed", "reward_page_missing", "reward_unrecognized"] { try handle(status) }
precondition(warnings.count == 3, "all terminal recognition failures must be visible")
let captured = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let details = captured["details"] as! [String: Any]
try handle(details["status"] as! String)
precondition(warnings.count == 4, "captured callback must produce a warning")
try handle("preparing"); try handle("completed")
precondition(warnings.count == 4, "progress and completion are not failures")
print("PASS 6 BlackFlow start-run callback checks")
'''
with tempfile.TemporaryDirectory(prefix='maa-blackflow-status-') as d:
 p=Path(d); (p/'main.swift').write_text(probe)
 command=['xcrun','swiftc','-I',str(products),'-Xcc',f'-fmodule-map-file={packages}/checkouts/JBird/Sources/JBirdParser/include/module.modulemap','-load-plugin-executable',f'{products}/JBirdMacrosCompilerPlugin#JBirdMacrosCompilerPlugin']+[str(x) for x in products.glob('JBird*.o')]+[str(p/'main.swift'),'-lc++','-o',str(p/'probe')]
 subprocess.run(command,check=True); subprocess.run([str(p/'probe'),str(root/'Tests/Fixtures/BlackFlowStartRunFailure.json')],check=True)
