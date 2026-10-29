#!/usr/bin/env python3
"""Compile the production MAAHandle preview methods against a controllable native boundary."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / "MeoAsstMac/Core/Maa.swift").read_text()
methods = source[source.index("    func getImage() throws"):source.index("\nenum MAATaskType:")]
resume = source[source.index("    private func resumeCall("):source.index("    private func waitFor(")]
preamble = (root / "Tests/PeepCoreTests.swift").read_text()
actor = """
actor MAAHandle {
    let handle = 1
    var previewCallID: Int32?
    var previewToken: UUID?
    var previewWaiter: CheckedContinuation<Void, Error>?
    var previewTimeout: Task<Void, Never>?
    var pendingCalls = [Int32: CheckedContinuation<JSON, Error>]()
    func deliver(_ id: Int32, success: Bool) { resumeCall(for: id, info: JSON(ret: success)) }
    func cancelStale(_ token: UUID) { cancelPreviewWaiter(token: token, error: CancellationError()) }
""" + resume + methods
with tempfile.TemporaryDirectory(prefix="maa-peep-core-") as directory:
    main = Path(directory) / "Core.swift"
    main.write_text(preamble + actor)
    binary = Path(directory) / "tests"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(root / "MeoAsstMac/Core/PreviewImageBuffer.swift"), str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
