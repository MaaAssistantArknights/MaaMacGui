import XCTest

@testable import MAA

final class InfrastTimeRotationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func time(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2026, month: 9, day: 7,
                hour: hour, minute: minute, second: second))!
    }

    private func configuration(_ plans: String) throws -> MAAInfrast {
        try JSONDecoder().decode(MAAInfrast.self, from: Data("{\"plans\":\(plans)}".utf8))
    }

    func testMatchesFirstOverlappingPlanAndAnyPeriodWithinAPlan() throws {
        let config = try configuration(
            #"[{"period":[["6:00","13:59"],["18:00","20:00"]]},{"period":[["12:00","22:00"]]}]"#)
        XCTAssertEqual(try config.select(-1, at: time(13), calendar: calendar).index, 0)
        XCTAssertEqual(try config.select(-1, at: time(15), calendar: calendar).index, 1)
        let evening = try config.select(-1, at: time(19), calendar: calendar)
        XCTAssertEqual(evening.index, 0)
        XCTAssertFalse(evening.usedFallback)
    }

    func testEndpointsAreInclusiveButEndMinuteDoesNotIncludeLaterSeconds() throws {
        let config = try configuration(#"[{"period":[["6:00","13:59"]]},{"period":[["14:00","21:59"]]}]"#)
        for date in [time(6), time(13, 59), time(14), time(21, 59)] {
            XCTAssertFalse(try config.select(-1, at: date, calendar: calendar).usedFallback)
        }
        for date in [time(5, 59, 59), time(13, 59, 1), time(13, 59, 30), time(21, 59, 1)] {
            let selection = try config.select(-1, at: date, calendar: calendar)
            XCTAssertEqual(selection.index, 0)
            XCTAssertTrue(selection.usedFallback)
        }
    }

    func testCrossMidnightRequiresSeparatePeriods() throws {
        let unsplit = try configuration(#"[{"period":[["22:00","06:00"]]}]"#)
        let split = try configuration(#"[{"period":[["22:00","23:59"],["00:00","06:00"]]}]"#)
        for date in [time(23), time(0), time(5)] {
            XCTAssertTrue(try unsplit.select(-1, at: date, calendar: calendar).usedFallback)
            XCTAssertFalse(try split.select(-1, at: date, calendar: calendar).usedFallback)
        }
    }

    func testMissingNullAndEmptyPeriodsAllowManualSelection() throws {
        let config = try configuration(#"[{},{"period":null},{"period":[]}]"#)
        XCTAssertFalse(config.hasPeriods)
        XCTAssertFalse(config.hasMixedPeriods)
        XCTAssertEqual(config.defaultSelection, 0)
        let manual = try config.select(2, at: time(12), calendar: calendar)
        XCTAssertEqual(manual.index, 2)
        XCTAssertFalse(manual.usedFallback)
        XCTAssertTrue(try config.select(-1, at: time(12), calendar: calendar).usedFallback)
        XCTAssertThrowsError(try config.select(3, at: time(12), calendar: calendar))
        XCTAssertThrowsError(try config.select(-2, at: time(12), calendar: calendar))
    }

    func testMixedPeriodsDefaultToRotationAndSkipUnscheduledPlans() throws {
        let config = try configuration(#"[{},{"period":[["00:00","23:59"]]}]"#)
        XCTAssertTrue(config.hasPeriods)
        XCTAssertTrue(config.hasMixedPeriods)
        XCTAssertEqual(config.defaultSelection, -1)
        XCTAssertEqual(try config.select(-1, at: time(12), calendar: calendar).index, 1)
    }

    func testEmptyPlansUseWindowsRotationFallback() throws {
        let config = try configuration("[]")
        XCTAssertFalse(config.hasPeriods)
        XCTAssertFalse(config.hasMixedPeriods)
        let selection = try config.select(-1, at: time(12), calendar: calendar)
        XCTAssertEqual(selection.index, 0)
        XCTAssertTrue(selection.usedFallback)
        XCTAssertThrowsError(try config.select(0, at: time(12), calendar: calendar))
        XCTAssertEqual(config.refreshedSelection(0), -1)
        XCTAssertNil(config.nextSelection(after: 0))
    }

    func testInvalidPeriodsFailDecoding() {
        for period in [
            #"[["06:00"]]"#, #"[["06:00","12:00","18:00"]]"#,
            #"[["24:00","06:00"]]"#, #"[["06:60","12:00"]]"#,
            #"[["invalid","12:00"]]"#, #"[[null,"12:00"]]"#,
        ] {
            XCTAssertThrowsError(try configuration("[{\"period\":\(period)}]"), period)
        }
    }

    func testMissingPlansAreEmptyButExplicitNullIsAnError() throws {
        let missing = try JSONDecoder().decode(MAAInfrast.self, from: Data("{}".utf8))
        XCTAssertTrue(missing.plans.isEmpty)
        XCTAssertThrowsError(try configuration("null"))
    }

    func testRefreshPreservesAvailableChoicesAndUsesWindowsInvalidSelection() throws {
        let scheduled = try configuration(#"[{"period":[["06:00","18:00"]]},{}]"#)
        XCTAssertEqual(scheduled.refreshedSelection(-1), -1)
        XCTAssertEqual(scheduled.refreshedSelection(1), 1)
        XCTAssertEqual(scheduled.refreshedSelection(2), -1)
        let manual = try configuration("[{}]")
        XCTAssertEqual(manual.refreshedSelection(0), 0)
        XCTAssertEqual(manual.refreshedSelection(1), -1)
        XCTAssertEqual(manual.refreshedSelection(-1), -1)
    }

    func testOnlyValidManualChoicesAdvanceAndWrap() throws {
        let config = try configuration(#"[{"period":[["06:00","18:00"]]},{}]"#)
        XCTAssertEqual(config.nextSelection(after: 0), 1)
        XCTAssertEqual(config.nextSelection(after: 1), 0)
        XCTAssertNil(config.nextSelection(after: -1))
        XCTAssertNil(config.nextSelection(after: 2))
        XCTAssertEqual(try configuration("[{}]").nextSelection(after: 0), 0)
    }

    func testMatchingUsesSuppliedLocalCalendar() throws {
        let config = try configuration(#"[{"period":[["06:00","07:00"]]}]"#)
        var local = calendar
        local.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = time(22, 30)
        XCTAssertTrue(try config.select(-1, at: date, calendar: calendar).usedFallback)
        XCTAssertFalse(try config.select(-1, at: date, calendar: local).usedFallback)
    }
}

extension InfrastTimeRotationTests {
    private func withPlanFile(_ plans: String, body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePlans(plans, to: url)
        try body(url)
    }

    private func writePlans(_ plans: String, to url: URL) throws {
        try Data("{\"plans\":\(plans)}".utf8).write(to: url)
    }

    private func taskConfiguration(file: URL, selection: Int = -1) throws -> InfrastConfiguration {
        let data = try JSONSerialization.data(withJSONObject: [
            "mode": 10000, "filename": file.path, "plan_index": selection,
        ])
        return try JSONDecoder().decode(InfrastConfiguration.self, from: data)
    }

    private func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    func testExecutionResolvesIndexWithoutChangingPersistedRotation() throws {
        try withPlanFile(#"[{"period":[["06:00","13:59"]]},{"period":[["14:00","21:59"]]}]"#) { url in
            let config = try taskConfiguration(file: url)
            let execution = try config.execution(at: time(15), calendar: calendar)
            XCTAssertEqual(execution.configuration.plan_index, 1)
            XCTAssertEqual(execution.selection?.index, 1)
            XCTAssertEqual(execution.selection?.usedFallback, false)
            XCTAssertEqual(config.plan_index, -1)
            let persisted = try encodedObject(config)
            XCTAssertEqual(persisted["plan_index"] as? Int, -1)
            XCTAssertNil(persisted["customPlan"])
            XCTAssertNil(persisted["customPlanError"])
        }
    }

    func testCoreParamsResolveRotationIncludingEmptyPlans() throws {
        try withPlanFile(#"[{"period":[["00:00","23:59"]]}]"#) { url in
            let config = try taskConfiguration(file: url)
            XCTAssertEqual(try encodedObject(config.params)["plan_index"] as? Int, 0)
            XCTAssertEqual(config.plan_index, -1)
        }
        try withPlanFile("[]") { url in
            let config = try taskConfiguration(file: url)
            XCTAssertEqual(try encodedObject(config.params)["plan_index"] as? Int, 0)
            XCTAssertEqual(config.plan_index, -1)
        }
    }

    func testPlistReopenPreservesManualAndRotationSelections() throws {
        try withPlanFile(#"[{"period":[["06:00","13:59"]]},{"period":[["14:00","21:59"]]}]"#) { url in
            for selection in [-1, 0, 1] {
                let original = try taskConfiguration(file: url, selection: selection)
                let data = try PropertyListEncoder().encode(original)
                let reopened = try PropertyListDecoder().decode(InfrastConfiguration.self, from: data)
                XCTAssertEqual(reopened.plan_index, selection)
                XCTAssertEqual(reopened.filename, url.path)
                XCTAssertTrue(reopened.customPlan.hasPeriods)
                XCTAssertNil(reopened.customPlanError)
            }
        }
    }

    func testFileSwitchDefaultsAndReloadRetainsOnlyAvailableChoices() throws {
        try withPlanFile(#"[{"period":[["06:00","18:00"]]},{}]"#) { scheduledURL in
            try withPlanFile("[{}]") { manualURL in
                var config = try taskConfiguration(file: manualURL, selection: 0)
                config.filename = scheduledURL.path
                config.reloadCustomPlan(resetSelection: true)
                XCTAssertEqual(config.plan_index, -1)
                config.plan_index = 1
                config.reloadCustomPlan()
                XCTAssertEqual(config.plan_index, 1)
                config.filename = manualURL.path
                config.reloadCustomPlan(resetSelection: true)
                XCTAssertEqual(config.plan_index, 0)
                config.plan_index = 1
                config.reloadCustomPlan()
                XCTAssertEqual(config.plan_index, -1)
                config.refreshCustomPlanSelection()
                XCTAssertEqual(config.plan_index, -1)
            }
        }
    }

    func testExecutionUsesCachedPlansUntilExplicitReload() throws {
        try withPlanFile(#"[{"period":[["06:00","13:59"]]},{"period":[["14:00","21:59"]]}]"#) { url in
            var config = try taskConfiguration(file: url)
            XCTAssertEqual(try config.execution(at: time(15), calendar: calendar).configuration.plan_index, 1)
            try writePlans(#"[{"period":[["14:00","21:59"]]},{"period":[["06:00","13:59"]]}]"#, to: url)
            config.refreshCustomPlanSelection()
            XCTAssertEqual(try config.execution(at: time(15), calendar: calendar).configuration.plan_index, 1)
            config.reloadCustomPlan()
            XCTAssertEqual(try config.execution(at: time(15), calendar: calendar).configuration.plan_index, 0)
            XCTAssertEqual(config.plan_index, -1)
        }
    }

    func testReopenDistinguishesMissingAndMalformedFilesLikeWindows() throws {
        try withPlanFile("[]") { url in
            try Data("broken JSON".utf8).write(to: url)
            var malformed = try taskConfiguration(file: url)
            XCTAssertEqual(malformed.plan_index, 0)
            XCTAssertNotNil(malformed.customPlanError)
            XCTAssertThrowsError(try JSONEncoder().encode(malformed.params))
            // Opening the settings refreshes the absent item to -1, as Windows does.
            malformed.refreshCustomPlanSelection()
            XCTAssertEqual(malformed.plan_index, -1)
            XCTAssertEqual(try encodedObject(malformed.params)["plan_index"] as? Int, 0)

            try FileManager.default.removeItem(at: url)
            let missing = try taskConfiguration(file: url)
            XCTAssertEqual(missing.plan_index, -1)
            XCTAssertNil(missing.customPlanError)
            XCTAssertEqual(try encodedObject(missing.params)["plan_index"] as? Int, 0)
        }
    }

    func testRestoringDirectlyConstructedConfigurationLoadsCachedPlan() throws {
        try withPlanFile("[{},{}]") { url in
            var config = InfrastConfiguration()
            config.mode = .custom
            config.filename = url.path
            config.plan_index = 1
            config.restoreCustomPlan()
            XCTAssertEqual(config.customPlan.plans.count, 2)
            XCTAssertEqual(config.plan_index, 1)
            XCTAssertEqual(try encodedObject(config.params)["plan_index"] as? Int, 1)
        }
    }

    func testCompletionOnlyAdvancesManualCustomMode() throws {
        try withPlanFile(#"[{"period":[["06:00","18:00"]]},{}]"#) { url in
            var config = try taskConfiguration(file: url)
            config.advanceCustomPlan()
            XCTAssertEqual(config.plan_index, -1)
            config.plan_index = 0
            config.advanceCustomPlan()
            XCTAssertEqual(config.plan_index, 1)
            config.advanceCustomPlan()
            XCTAssertEqual(config.plan_index, 0)
            for mode in [InfrastConfiguration.Mode.default, .rotation] {
                config.mode = mode
                config.advanceCustomPlan()
                XCTAssertEqual(config.plan_index, 0)
                XCTAssertNil(try config.execution(at: time(15), calendar: calendar).selection)
            }
        }
    }
}
