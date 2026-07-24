import Darwin
import Foundation

public protocol CommandRunning: Sendable {
    func run(command: String, arguments: [String]) -> CommandResult
}

public struct CommandResult: Sendable, Equatable {
    public let terminationStatus: Int32
    public let standardOutput: String
    public let standardError: String
    public let outputTruncated: Bool

    public init(
        terminationStatus: Int32,
        standardOutput: String,
        standardError: String,
        outputTruncated: Bool = false
    ) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.outputTruncated = outputTruncated
    }

    public var succeeded: Bool {
        terminationStatus == 0
    }

    public var combinedOutput: String {
        standardError.ifEmpty(fallback: standardOutput)
    }
}

/// Executes absolute-path tools without a shell, capturing output with a size cap.
public final class SystemCommandRunner: CommandRunning, @unchecked Sendable {
    public static let defaultMaxCaptureBytes = 256 * 1024

    private let timeout: TimeInterval
    private let maxCaptureBytes: Int

    public init(
        timeout: TimeInterval = 30,
        maxCaptureBytes: Int = SystemCommandRunner.defaultMaxCaptureBytes
    ) {
        self.timeout = timeout
        self.maxCaptureBytes = max(1, maxCaptureBytes)
    }

    public func run(command: String, arguments: [String]) -> CommandResult {
        Self.runSync(
            command: command,
            arguments: arguments,
            timeout: timeout,
            maxCaptureBytes: maxCaptureBytes
        )
    }

    public static func runSync(
        command: String,
        arguments: [String],
        timeout: TimeInterval = 30,
        maxCaptureBytes: Int = SystemCommandRunner.defaultMaxCaptureBytes
    ) -> CommandResult {
        let fileManager = FileManager.default
        let captureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Unseal-\(UUID().uuidString)", isDirectory: true)
        let standardOutputURL = captureDirectory.appendingPathComponent("stdout")
        let standardErrorURL = captureDirectory.appendingPathComponent("stderr")

        do {
            try fileManager.createDirectory(
                at: captureDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return CommandResult(
                terminationStatus: -1,
                standardOutput: "",
                standardError: "无法创建命令输出目录：\(error.localizedDescription)"
            )
        }
        defer { try? fileManager.removeItem(at: captureDirectory) }

        let privateFileAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        guard fileManager.createFile(
            atPath: standardOutputURL.path,
            contents: nil,
            attributes: privateFileAttributes
        ), fileManager.createFile(
            atPath: standardErrorURL.path,
            contents: nil,
            attributes: privateFileAttributes
        ) else {
            return CommandResult(
                terminationStatus: -1,
                standardOutput: "",
                standardError: "无法创建命令输出文件。"
            )
        }

        let standardOutputHandle: FileHandle
        let standardErrorHandle: FileHandle
        do {
            standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
            standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
        } catch {
            return CommandResult(
                terminationStatus: -1,
                standardOutput: "",
                standardError: "无法打开命令输出文件：\(error.localizedDescription)"
            )
        }
        defer {
            try? standardOutputHandle.close()
            try? standardErrorHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = standardOutputHandle
        process.standardError = standardErrorHandle

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return CommandResult(
                terminationStatus: -1,
                standardOutput: "",
                standardError: error.localizedDescription
            )
        }

        let effectiveTimeout = max(timeout, 0.1)
        let didTimeOut = finished.wait(timeout: .now() + effectiveTimeout) == .timedOut
        if didTimeOut, process.isRunning {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }

        try? standardOutputHandle.synchronize()
        try? standardErrorHandle.synchronize()
        try? standardOutputHandle.close()
        try? standardErrorHandle.close()

        let (output, outputTruncated) = readOutput(
            at: standardOutputURL,
            maxBytes: maxCaptureBytes
        )
        let (errorOutput, errorTruncated) = readOutput(
            at: standardErrorURL,
            maxBytes: maxCaptureBytes
        )
        let truncated = outputTruncated || errorTruncated

        if didTimeOut {
            let timeoutMessage = "命令执行超过 \(effectiveTimeout.formatted()) 秒，已终止。"
            let combinedError = errorOutput.isEmpty
                ? timeoutMessage
                : "\(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))\n\(timeoutMessage)"
            return CommandResult(
                terminationStatus: 124,
                standardOutput: output,
                standardError: combinedError,
                outputTruncated: truncated
            )
        }

        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: output,
            standardError: errorOutput,
            outputTruncated: truncated
        )
    }

    private static func readOutput(at url: URL, maxBytes: Int) -> (String, Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ("", false)
        }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maxBytes + 1)
        let truncated = data.count > maxBytes
        let limited = truncated ? data.prefix(maxBytes) : data
        let text = String(data: limited, encoding: .utf8) ?? ""
        if truncated {
            return (text + "\n…（输出已截断）", true)
        }
        return (text, false)
    }
}

extension String {
    func ifEmpty(fallback: String) -> String {
        isEmpty ? fallback : self
    }

    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
