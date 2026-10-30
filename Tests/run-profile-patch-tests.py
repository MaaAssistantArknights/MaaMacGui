#!/usr/bin/env python3
"""Compile actual callback field patching and configuration decoding with Core/UI-only boundaries removed."""
from pathlib import Path
import subprocess,tempfile,re
root=Path(__file__).resolve().parent.parent

def declaration(source, pattern):
    match=re.search(pattern,source,re.M)
    assert match,pattern
    start=source.index('{',match.start());depth=1;end=start+1
    while depth:
        if source[end]=='{':depth+=1
        elif source[end]=='}':depth-=1
        end+=1
    return source[match.start():end]

support='''import Foundation
protocol MAATaskConfiguration: Codable, Hashable, Sendable { associatedtype Params: Encodable; var params: Params { get } }
extension MAATaskConfiguration { init() { self = try! JSONDecoder().decode(Self.self, from: Data("{}".utf8)) } }
enum MAATaskType { case Infrast, Mall; var description: String { "fixture" } }
enum MAATask: Codable, Equatable { case infrast(InfrastConfiguration), mall(MallConfiguration) }
struct MAAInfrast { var title: String?; var plans: [Plan] = []; struct Plan { var name: String? }; init(path: String) throws {} }
'''
protocol=(root/'MeoAsstMac/Task Configurations/MAATaskConfiguration.swift').read_text()
support+=protocol[protocol.index('extension KeyedDecodingContainer'):]
tasks=(root/'MeoAsstMac/Model/MAATask.swift').read_text()
support+=declaration(tasks,r'^struct DailyTask:')
model=(root/'MeoAsstMac/Model/MAAViewModel.swift').read_text()
support+='''
@MainActor final class MAAViewModel {
 let dailyRunCoordinator = DailyRunCoordinator()
 var dailyRunTasks: [DailyTask]?
 var taskIDMap: [Int32: UUID] = [:]
 var tasks: [DailyTask] = []
 var dailyTaskProfile = "B"
 let tasksDirectory: URL
 var isApplyingDailyCallbackPatch = false
 var errors = [String]()
 init(directory: URL) { tasksDirectory = directory }
 func logWarn(_ value: String) { errors.append(value) }
 func logError(verbatim value: String) { errors.append(value) }
 func logError(_ resource: LocalizedStringResource) { logError(verbatim: .init(localized: resource)) }
'''+declaration(model,r'^    func applyDailyTaskCallback\(')+'\n}\n'
mall=(root/'MeoAsstMac/Task Configurations/MallConfiguration.swift').read_text().replace('import JBird','')
# Only the unrelated Core JSON result builder is replaced; all saved fields,
# Codable migration, and production patch/store/wrapper code compile verbatim.
params=declaration(mall,r'^    @JSON.Builder var params:')
mall=mall.replace(params,'    var params: Self { self }')
with tempfile.TemporaryDirectory(prefix='maa-profile-patch-tests-') as temporary:
    tmp=Path(temporary)
    (tmp/'Support.swift').write_text(support)
    (tmp/'MallConfiguration.swift').write_text(mall)
    binary=tmp/'tests'
    subprocess.run(['xcrun','swiftc','-parse-as-library',str(tmp/'Support.swift'),
        str(root/'MeoAsstMac/Task Configurations/InfrastConfiguration.swift'),str(tmp/'MallConfiguration.swift'),
        str(root/'MeoAsstMac/RunHooks/RunContext.swift'),str(root/'MeoAsstMac/RunHooks/DailyRunProfilePatch.swift'),
        str(root/'Tests/RunProfilePatchTests.swift'),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
