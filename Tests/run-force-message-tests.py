#!/usr/bin/env python3
"""Exercise production recovery callback parsing against JSON-shaped messages."""
from pathlib import Path
import re, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
message=(root/'MeoAsstMac/Core/MaaMessage.swift').read_text()
schedule=(root/'MeoAsstMac/Scheduling/ScheduleHandoff.swift').read_text()
def declaration(source, pattern):
 m=re.search(pattern,source,re.M); assert m, pattern
 start=source.index('{',m.start()); depth,end=1,start+1
 while depth: depth+=(source[end]=='{')-(source[end]=='}'); end+=1
 return source[m.start():end]
parser=declaration(message,r'^    private func processForcedRecoveryMessage\b').replace('private func','func',1)
state=declaration(schedule,r'^struct ForcedGameRecovery\b')
pre='''import Foundation
struct JSON {
 let raw: Any
 func value(forSubscript key: String) throws -> JSON { guard let d=raw as? [String:Any], let v=d[key] else { throw NSError(domain:"JSON",code:1) }; return JSON(raw:v) }
 subscript<T>(_ key: String, as type: T.Type = T.self) -> T { get throws {
  guard let d=raw as? [String:Any], let v=d[key] else { throw NSError(domain:"JSON",code:1) }
  if T.self == JSON.self { return JSON(raw:v) as! T }
  if T.self == Int32.self, let n=v as? Int { return Int32(n) as! T }
  if T.self == [Int32].self, let a=v as? [Int] { return a.map(Int32.init) as! T }
  guard let t=v as? T else { throw NSError(domain:"JSON",code:2) }; return t
 } }
}
struct MaaMessage { let code:Int; let details:JSON }
extension Int {
 static let AllTasksCompleted=3, TaskChainError=10000, TaskChainStart=10001, TaskChainCompleted=10002, TaskChainStopped=10004
 static let SubTaskError=20000, SubTaskStart=20001, SubTaskStopped=20004
}
'''+state+'''\nfinal class Probe { var forceRecoveryInFlight = true; var forceRecovery: ForcedGameRecovery?\n'''+parser+'''\n}\n'''
main='''
func msg(_ code:Int,_ obj:[String:Any])->MaaMessage { .init(code:code,details:JSON(raw:obj)) }
@main struct Main {
 static func main() {
  let p=Probe()
  precondition(p.processForcedRecoveryMessage(msg(.AllTasksCompleted,["finished_tasks":[99]])), "stale callback before recovery task start is consumed")
  p.forceRecoveryInFlight = false
  precondition(!p.processForcedRecoveryMessage(msg(.AllTasksCompleted,["finished_tasks":[99]])), "normal callback routing resumes after recovery")
  p.forceRecoveryInFlight = true
  p.forceRecovery = .init(taskID:42,chain:"Custom",requiresHome:true)
  precondition(p.processForcedRecoveryMessage(msg(.AllTasksCompleted,["finished_tasks":[99]])))
  precondition(p.forceRecovery?.allCompleted == false)
  precondition(p.processForcedRecoveryMessage(msg(.SubTaskStart,["taskchain":"Custom","taskid":0,"subtask":"ProcessTask","details":["task":"Home","algorithm":"MatchTemplate"]])))
  precondition(p.processForcedRecoveryMessage(msg(.TaskChainStart,["taskchain":"Custom","taskid":42])))
  precondition(p.processForcedRecoveryMessage(msg(.SubTaskStart,["taskchain":"Custom","taskid":91,"subtask":"ProcessTask","details":["task":"Home","algorithm":"MatchTemplate"]])))
  precondition(p.processForcedRecoveryMessage(msg(.SubTaskStart,["taskchain":"Custom","taskid":0,"subtask":"ProcessTask","details":["task":"Home","algorithm":"MatchTemplate"]])))
  precondition(p.processForcedRecoveryMessage(msg(.TaskChainCompleted,["taskchain":"Custom","taskid":42])))
  precondition(p.processForcedRecoveryMessage(msg(.AllTasksCompleted,["finished_tasks":[42]])))
  precondition(p.forceRecovery?.verified == true)
  p.forceRecovery = .init(taskID:43,chain:"StartUp",requiresHome:false)
  precondition(p.processForcedRecoveryMessage(msg(.TaskChainStart,["taskchain":"StartUp","taskid":43])))
  precondition(p.processForcedRecoveryMessage(msg(.TaskChainError,["taskchain":"StartUp","taskid":43])))
  precondition(p.forceRecovery?.failed == true)
  print("PASS: production recovery JSON parser scopes nested task, chain, terminal and stale completion")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='maa-force-message-') as d:
 p=Path(d); (p/'main.swift').write_text(pre+main); Path('/private/tmp/maa-force-message-debug.swift').write_text(pre+main)
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-module-cache-path',str(p/'cache'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=10)
