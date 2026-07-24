import Foundation
import XCTest
@testable import UnsealCore

final class QuarantineServiceTests: XCTestCase {
    func testRepairRemovesOnlyQuarantineAttributeAndSucceedsWithoutRequiringSpctl() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: "0081", standardError: ""),
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
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
            )
        ])
        XCTAssertFalse(runner.invocations.contains { $0.command.contains("spctl") })
    }

    func testRepairSucceedsWhenQuarantineRemovedEvenIfGatekeeperWouldReject() throws {
        let appURL = try makeTemporaryApp()
        // Only probe + remove are needed; spctl must not gate success after removal.
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: "0081", standardError: ""),
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case .success = result else {
            return XCTFail("Expected success after quarantine removal")
        }
        XCTAssertFalse(runner.invocations.contains {
            $0.command == "/usr/bin/xattr" && $0.arguments.first == "-w"
        })
    }

    func testRepairDoesNotModifyAppWithoutQuarantineWhenAssessmentSucceeds() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "No such xattr"),
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: ""),
            CommandResult(terminationStatus: 0, standardOutput: "accepted", standardError: "")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case .success = result else {
            return XCTFail("Expected success")
        }
        XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("-dr") })
    }

    func testRepairRemovesNestedQuarantineWhenRootProbeIsAbsent() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "No such xattr"),
            CommandResult(
                terminationStatus: 0,
                standardOutput: "\(appURL.path)/Contents/MacOS/App: com.apple.quarantine: 0081\n",
                standardError: ""
            ),
            CommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case .success = result else {
            return XCTFail("Expected success for nested quarantine")
        }
        XCTAssertTrue(runner.invocations.contains {
            $0.arguments == ["-lr", appURL.path]
        })
        XCTAssertTrue(runner.invocations.contains {
            $0.arguments == ["-dr", "com.apple.quarantine", appURL.path]
        })
    }

    func testRepairFailsWhenProbeCannotReadAttribute() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "Permission denied")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case let .failure(info) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(info.title, "无法读取隔离标记")
        XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("-dr") })
        XCTAssertFalse(runner.invocations.contains { $0.command.contains("spctl") })
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

    func testRepairFailsClearlyWhenNoQuarantineAndGatekeeperRejects() throws {
        let appURL = try makeTemporaryApp()
        let runner = QueueCommandRunner(results: [
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "No such xattr"),
            CommandResult(terminationStatus: 0, standardOutput: "com.apple.macl: data\n", standardError: ""),
            CommandResult(terminationStatus: 1, standardOutput: "", standardError: "rejected")
        ])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case let .failure(info) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(info.title, "不是隔离标记问题")
        XCTAssertTrue(info.message.contains("签名"))
        XCTAssertFalse(runner.invocations.contains { $0.arguments.contains("-dr") })
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

    func testRepairRejectsDirectoryWithoutInfoPlist() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnsealTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Fake.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }

        let runner = QueueCommandRunner(results: [])
        let result = repairResult(using: QuarantineService(runner: runner), appURL: appURL)

        guard case let .failure(info) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(info.title, "无效的应用包")
        XCTAssertTrue(info.message.contains("Info.plist"))
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testProbeClassifiesMissingAttributeAndPermissionFailure() {
        let client = QuarantineAttributeClient(
            runner: QueueCommandRunner(results: [
                CommandResult(terminationStatus: 1, standardOutput: "", standardError: "No such xattr: com.apple.quarantine"),
                CommandResult(terminationStatus: 1, standardOutput: "", standardError: "Permission denied")
            ])
        )
        let appURL = URL(fileURLWithPath: "/Applications/Example.app")

        XCTAssertEqual(client.probe(appURL: appURL), .absent)
        guard case .failed = client.probe(appURL: appURL) else {
            return XCTFail("Expected failed probe")
        }
    }

    func testSystemCommandRunnerCapturesOutput() {
        let result = SystemCommandRunner(timeout: 2).run(
            command: "/bin/echo",
            arguments: ["hello"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput, "hello\n")
        XCTAssertFalse(result.outputTruncated)
    }

    func testSystemCommandRunnerTimesOut() {
        let result = SystemCommandRunner(timeout: 0.1).run(
            command: "/bin/sleep",
            arguments: ["2"]
        )

        XCTAssertEqual(result.terminationStatus, 124)
        XCTAssertTrue(result.standardError.contains("已终止"))
    }

    func testSystemCommandRunnerTruncatesLargeOutput() {
        let result = SystemCommandRunner(timeout: 2, maxCaptureBytes: 16).run(
            command: "/bin/echo",
            arguments: ["abcdefghijklmnopqrstuvwxyz"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.outputTruncated)
        XCTAssertTrue(result.standardOutput.contains("输出已截断"))
    }

    private func makeTemporaryApp() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnsealTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Example.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.example.UnsealTest</string>
            <key>CFBundleName</key>
            <string>Example</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
        </dict>
        </plist>
        """
        try infoPlist.write(
            to: contentsURL.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
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
