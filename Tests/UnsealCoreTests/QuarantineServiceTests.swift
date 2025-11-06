import Foundation
import XCTest
@testable import UnsealCore

final class QuarantineServiceTests: XCTestCase {
    func testRepairSucceedsWhenCommandsSucceed() {
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: ""), // xattr
            CommandResult(terminationStatus: 0, standardOutput: "accepted", standardError: "") // spctl
        ])
        let service = QuarantineService(runner: runner)
        let expectation = expectation(description: "repair completion")

        service.repair(appURL: URL(fileURLWithPath: "/Applications/Foo.app")) { result in
            switch result {
            case .success:
                break
            case .failure:
                XCTFail("Expected success")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testRepairFailsWhenXattrFails() {
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "Permission denied")
        ])
        let service = QuarantineService(runner: runner)
        let expectation = expectation(description: "repair completion")

        service.repair(appURL: URL(fileURLWithPath: "/Applications/Foo.app")) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case let .failure(info):
                XCTAssert(info.command.contains("xattr"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testRepairReturnsBlockedWhenAssessmentFails() {
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: ""), // xattr
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "rejected"), // spctl
            CommandResult(terminationStatus: 0, standardOutput: "0081;00000000;Gatekeeper;...", standardError: "") // xattr -p
        ])
        let service = QuarantineService(runner: runner)
        let expectation = expectation(description: "repair completion")

        service.repair(appURL: URL(fileURLWithPath: "/Applications/Foo.app")) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case let .failure(info):
                XCTAssert(info.title.contains("Gatekeeper"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}

private final class QueueCommandRunner: CommandRunning {
    private var results: [CommandResult]
    private let lock = NSLock()

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(command: String, arguments: [String]) -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        guard !results.isEmpty else {
            return CommandResult(terminationStatus: 1, standardOutput: "", standardError: "No mock value")
        }
        return results.removeFirst()
    }
}
