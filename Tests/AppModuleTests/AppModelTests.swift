import Foundation
import XCTest
@testable import AppModule
import UnsealCore

@MainActor
final class AppModelTests: XCTestCase {
    func testSecondDropIsIgnoredWhileRepairIsRunning() async {
        let service = ControlledRepairService()
        let model = AppModel(service: service)
        let firstURL = URL(fileURLWithPath: "/Applications/First.app")
        let secondURL = URL(fileURLWithPath: "/Applications/Second.app")

        model.handleDrop(urls: [firstURL])
        model.handleDrop(urls: [secondURL])

        XCTAssertEqual(service.requestedURLs, [firstURL])
        XCTAssertTrue(model.isProcessing)
        XCTAssertFalse(model.canClearRecords)

        service.completeNext(with: .success)
        await Task.yield()

        XCTAssertEqual(model.dropStatus, .success(firstURL))
    }

    func testMultipleAppsInOneDropAreRejectedWithoutRepair() {
        let service = ControlledRepairService()
        let model = AppModel(service: service)
        let firstURL = URL(fileURLWithPath: "/Applications/First.app")
        let secondURL = URL(fileURLWithPath: "/Applications/Second.app")

        model.handleDrop(urls: [firstURL, secondURL])

        XCTAssertTrue(service.requestedURLs.isEmpty)
        guard case let .failure(url, info) = model.dropStatus else {
            return XCTFail("Expected multi-drop failure")
        }
        XCTAssertEqual(url, firstURL)
        XCTAssertEqual(info.title, "一次只能处理一个项目")
        XCTAssertTrue(model.canClearRecords)
        XCTAssertNotNil(model.lastDiagnostic)
    }

    func testDiskImageDropIsAccepted() async {
        let service = ControlledRepairService()
        let model = AppModel(service: service)
        let dmgURL = URL(fileURLWithPath: "/Users/test/Downloads/Kooky.dmg")

        model.handleDrop(urls: [dmgURL])
        XCTAssertEqual(service.requestedURLs, [dmgURL])
        XCTAssertTrue(model.isProcessing)

        service.completeNext(with: .success)
        await Task.yield()
        XCTAssertEqual(model.dropStatus, .success(dmgURL))
    }

    func testClearIsDisabledDuringRepairAndEnabledAfterCompletion() async {
        let service = ControlledRepairService()
        let model = AppModel(service: service)
        let appURL = URL(fileURLWithPath: "/Applications/Example.app")
        let diagnostic = DiagnosticInfo(
            title: "失败",
            message: "测试",
            command: "test",
            output: "",
            suggestions: []
        )

        model.handleDrop(urls: [appURL])
        model.clearState()
        XCTAssertEqual(model.dropStatus, .processing(appURL))

        service.completeNext(with: .failure(diagnostic))
        await Task.yield()
        XCTAssertTrue(model.canClearRecords)

        model.clearState()
        XCTAssertEqual(model.dropStatus, .idle)
        XCTAssertNil(model.lastDiagnostic)
    }

    func testLateCompletionIsIgnoredAfterTerminationReset() async {
        let service = ControlledRepairService()
        let model = AppModel(service: service)
        let appURL = URL(fileURLWithPath: "/Applications/Example.app")

        model.handleDrop(urls: [appURL])
        model.prepareForTermination()
        service.completeNext(with: .success)
        await Task.yield()

        XCTAssertEqual(model.dropStatus, .idle)
    }
}

private final class ControlledRepairService: QuarantineRepairing, @unchecked Sendable {
    private struct Request {
        let url: URL
        let completion: @Sendable (RepairResult) -> Void
    }

    private let lock = NSLock()
    private var requests: [Request] = []

    var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requests.map(\.url)
    }

    func repair(appURL: URL, completion: @escaping @Sendable (RepairResult) -> Void) {
        lock.lock()
        requests.append(Request(url: appURL, completion: completion))
        lock.unlock()
    }

    func completeNext(with result: RepairResult) {
        lock.lock()
        let completion = requests.removeFirst().completion
        lock.unlock()
        completion(result)
    }
}
