import Foundation
import XCTest
@testable import UnsealCore

final class QuarantineServiceTests: XCTestCase {
    func testRepairRemovesOnlyQuarantineAttributeAndSucceeds() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: "0081", standardError: ""),
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: ""),
            CommandResult(terminationStatus: 0, standardOutput: "accepted", standardError: "")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case .success = result else {
            return XCTFail("Expected success")
        }

        XCTAssertEqual(runner.invocations, [
            Invocation(
                command: "/usr/bin/xattr",
                arguments: ["-p", "com.apple.quarantine", appURL.path]
            ),
            Invocation(
                command: "/usr/bin/xattr",
                arguments: ["-dr", "com.apple.quarantine", appURL.path]
            ),
            Invocation(
                command: "/usr/sbin/spctl",
                arguments: ["--assess", "--type", "execute", appURL.path]
            )
        ])
    }

    func testRepairDoesNotModifyAppWithoutQuarantineWhenAssessmentSucceeds() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "No such xattr"),
            CommandResult(terminationStatus: 0, standardOutput: "accepted", standardError: "")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case .success = result else {
            return XCTFail("Expected success")
        }
        XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("-dr") })
    }

    func testRepairFailsWhenRemovingQuarantineFails() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: "0081", standardError: ""),
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "Permission denied")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case let .failure(info) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertTrue(info.title.contains("隔离标记"))
        XCTAssertTrue(info.command.contains("xattr -dr com.apple.quarantine"))
    }

    func testRepairReturnsBlockedWhenQuarantineRemains() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: "0081", standardError: ""),
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: ""),
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "rejected"),
            CommandResult(terminationStatus: 0, standardOutput: "0081", standardError: "")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case let .failure(info) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertTrue(info.title.contains("Gatekeeper"))
    }

    func testRepairReturnsSignatureDiagnosticAfterQuarantineWasRemoved() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: "0081", standardError: ""),
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: ""),
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "invalid signature"),
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "No such xattr")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case let .failure(info) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(info.title, "无法解除应用限制")
        XCTAssertTrue(info.message.contains("签名"))
    }

    func testRepairRejectsInvalidApplicationBeforeRunningCommands() {
        let runner = QueueCommandRunner(results: [])
        let service = QuarantineService(runner: runner)
        let invalidURL = URL(fileURLWithPath: "/tmp/not-an-application.txt")
        let result = repairResult(using: service, appURL: invalidURL)

        guard case let .failure(info) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(info.title, "无效的应用包")
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testSystemCommandRunnerCapturesOutput() {
        let result = SystemCommandRunner(timeout: 2).run(
            command: "/bin/echo",
            arguments: ["hello"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput, "hello\n")
    }

    func testSystemCommandRunnerTimesOut() {
        let result = SystemCommandRunner(timeout: 0.1).run(
            command: "/bin/sleep",
            arguments: ["2"]
        )

        XCTAssertEqual(result.terminationStatus, 124)
        XCTAssertTrue(result.standardError.contains("已终止"))
    }

    private func makeTemporaryApp() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnsealTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
        return appURL
    }

    private func repairResult(
        using service: QuarantineService,
        appURL: URL
    ) -> RepairResult {
        let expectation = expectation(description: "repair completion")
        let resultBox = RepairResultBox()

        service.repair(appURL: appURL) { result in
            resultBox.store(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        guard let result = resultBox.value else {
            fatalError("Repair did not return a result")
        }
        return result
    }
}

private struct Invocation: Equatable, Sendable {
    let command: String
    let arguments: [String]
}

private final class QueueCommandRunner: CommandRunning, @unchecked Sendable {
    private var results: [CommandResult]
    private var recordedInvocations: [Invocation] = []
    private let lock = NSLock()

    var invocations: [Invocation] {
        lock.lock()
        defer { lock.unlock() }
        return recordedInvocations
    }

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(command: String, arguments: [String]) -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        recordedInvocations.append(Invocation(command: command, arguments: arguments))
        guard !results.isEmpty else {
            return CommandResult(
                terminationStatus: 1,
                standardOutput: "",
                standardError: "No mock value"
            )
        }
        return results.removeFirst()
    }
}

private final class RepairResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: RepairResult?

    var value: RepairResult? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func store(_ value: RepairResult) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}
