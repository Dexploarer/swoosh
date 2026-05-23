// Tests/SwooshDoctorTests/DoctorCheckIDTests.swift — 0.9B
//
// Pins down the canonical check-ID catalogue + verifies every built-in
// check's struct id matches the corresponding constant in
// `DoctorCheckID`. A rename in any *Checks.swift file that forgets to
// update DoctorCheckID will fail one of these tests.

import Foundation
import XCTest
@testable import SwooshDoctor

final class DoctorCheckIDTests: XCTestCase {

    func testIDCatalogueExposesEveryBuiltInCheck() async {
        let runner = DoctorRunner()
        let report = await runner.runAll(context: DoctorContext(
            configPath: "/nonexistent/config.json",
            statePath: "/nonexistent",
            logPath: "/nonexistent/logs"
        ))
        let ranIDs = Set(report.checks.map { $0.checkID })
        let catalogue = Set(DoctorCheckID.all)
        XCTAssertEqual(
            ranIDs, catalogue,
            "DoctorCheckID.all must enumerate exactly the IDs the runner emits. Diff: ran-only=\(ranIDs.subtracting(catalogue)), catalogue-only=\(catalogue.subtracting(ranIDs))"
        )
    }

    func testIDsAreStable() {
        // If any of these literals change, downstream consumers (logs,
        // dashboards, recommendation heuristics) break. Pin them.
        XCTAssertEqual(DoctorCheckID.providerKeys, "secrets.providers")
        XCTAssertEqual(DoctorCheckID.modelConfig, "config.model")
        XCTAssertEqual(DoctorCheckID.memory, "perf.memory")
        XCTAssertEqual(DoctorCheckID.runtimeReadiness, "runtime.readiness")
        XCTAssertEqual(DoctorCheckID.logPrivacy, "privacy.logs")
    }

    func testIDsHaveNoDuplicates() {
        XCTAssertEqual(DoctorCheckID.all.count, Set(DoctorCheckID.all).count)
    }
}
