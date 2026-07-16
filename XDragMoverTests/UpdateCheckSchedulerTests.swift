import XCTest
@testable import XDragMover

/// Immediately/synchronously invokes its stored result, so tests never
/// need to wait on real async network behavior — mirrors this codebase's
/// existing fake-over-mock convention (e.g. `WindowListProviding` fakes).
private final class FakeUpdateChecker: UpdateChecking {
    var result: Result<String, Error> = .success("0.0.0")

    func fetchLatestVersion(completion: @escaping (Result<String, Error>) -> Void) {
        completion(result)
    }
}

private struct FakeError: Error {}

final class UpdateCheckSchedulerTests: XCTestCase {

    func test_performCheck_newerVersionAvailable_firesOnUpdateAvailable() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .success("3.2.0")
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { "3.1.2" })
        var observedVersions: [String] = []
        let expectation = expectation(description: "onUpdateAvailable fires")
        scheduler.onUpdateAvailable = {
            observedVersions.append($0)
            expectation.fulfill()
        }

        scheduler.performCheck()

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(observedVersions, ["3.2.0"])
    }

    func test_performCheck_sameVersion_doesNotFireOnUpdateAvailable() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .success("3.1.2")
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { "3.1.2" })
        var fired = false
        scheduler.onUpdateAvailable = { _ in fired = true }

        scheduler.performCheck()

        XCTAssertFalse(fired)
    }

    func test_performCheck_olderVersion_doesNotFireOnUpdateAvailable() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .success("3.0.0")
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { "3.1.2" })
        var fired = false
        scheduler.onUpdateAvailable = { _ in fired = true }

        scheduler.performCheck()

        XCTAssertFalse(fired)
    }

    func test_performCheck_fetchFails_doesNotFireOrCrash() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .failure(FakeError())
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { "3.1.2" })
        var fired = false
        scheduler.onUpdateAvailable = { _ in fired = true }

        scheduler.performCheck()

        XCTAssertFalse(fired)
    }

    func test_performCheck_noCurrentVersionAvailable_doesNotFetchOrFire() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .success("99.0.0")
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { nil })
        var fired = false
        scheduler.onUpdateAvailable = { _ in fired = true }

        scheduler.performCheck()

        XCTAssertFalse(fired)
    }

    // MARK: - US-22: checkNow (user-initiated, always reports an outcome)

    func test_checkNow_newerVersionAvailable_reportsUpdateAvailable() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .success("3.2.0")
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { "3.1.2" })
        let expectation = expectation(description: "checkNow completes")
        var observedResult: UpdateCheckResult?

        scheduler.checkNow { result in
            observedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        guard case .updateAvailable(let version) = observedResult else {
            return XCTFail("expected .updateAvailable, got \(String(describing: observedResult))")
        }
        XCTAssertEqual(version, "3.2.0")
    }

    func test_checkNow_sameVersion_reportsUpToDate() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .success("3.1.2")
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { "3.1.2" })
        let expectation = expectation(description: "checkNow completes")
        var observedResult: UpdateCheckResult?

        scheduler.checkNow { result in
            observedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        guard case .upToDate = observedResult else {
            return XCTFail("expected .upToDate, got \(String(describing: observedResult))")
        }
    }

    func test_checkNow_olderVersion_reportsUpToDate() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .success("3.0.0")
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { "3.1.2" })
        let expectation = expectation(description: "checkNow completes")
        var observedResult: UpdateCheckResult?

        scheduler.checkNow { result in
            observedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        guard case .upToDate = observedResult else {
            return XCTFail("expected .upToDate, got \(String(describing: observedResult))")
        }
    }

    func test_checkNow_fetchFails_reportsFailed() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .failure(FakeError())
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { "3.1.2" })
        let expectation = expectation(description: "checkNow completes")
        var observedResult: UpdateCheckResult?

        scheduler.checkNow { result in
            observedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        guard case .failed = observedResult else {
            return XCTFail("expected .failed, got \(String(describing: observedResult))")
        }
    }

    func test_checkNow_noCurrentVersionAvailable_doesNotCallCompletion() {
        let fakeChecker = FakeUpdateChecker()
        fakeChecker.result = .success("99.0.0")
        let scheduler = UpdateCheckScheduler(updateChecker: fakeChecker, currentVersionProvider: { nil })
        var called = false

        scheduler.checkNow { _ in called = true }

        XCTAssertFalse(called)
    }
}
