import Darwin
import Foundation

public protocol CommandRunning: Sendable {
    func run(command: String, arguments: [String]) -> CommandResult
}

public struct CommandResult: Sendable {
    public let terminationStatus: Int32
    public let standardOutput: String
    public let standardError: String

    public init(
        terminationStatus: Int32,
        standardOutput: String,
        standardError: String
    ) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool {
        terminationStatus == 0
    }
}

public final class SystemCommandRunner: CommandRunning, @unchecked Sendable {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    public func run(command: String, arguments: [String]) -> CommandResult {
        Self.runSync(command: command, arguments: arguments, timeout: timeout)
    }

    public static func runSync(
        command: String,
        arguments: [String],
        timeout: TimeInterval = 30
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

        let output = readOutput(at: standardOutputURL)
        let errorOutput = readOutput(at: standardErrorURL)

        if didTimeOut {
            let timeoutMessage = "命令执行超过 \(effectiveTimeout.formatted()) 秒，已终止。"
            let combinedError = errorOutput.isEmpty
                ? timeoutMessage
                : "\(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))\n\(timeoutMessage)"
            return CommandResult(
                terminationStatus: 124,
                standardOutput: output,
                standardError: combinedError
            )
        }

        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: output,
            standardError: errorOutput
        )
    }

    private static func readOutput(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum RepairResult: Sendable {
    case success
    case failure(DiagnosticInfo)
}

public protocol QuarantineRepairing: Sendable {
    func repair(appURL: URL, completion: @escaping @Sendable (RepairResult) -> Void)
}

public final class QuarantineService: QuarantineRepairing, @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "io.github.darkkid0.Unseal.QuarantineService",
        qos: .userInitiated
    )
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = SystemCommandRunner()) {
        self.runner = runner
    }

    public func repair(appURL: URL, completion: @escaping @Sendable (RepairResult) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }

            if let validationFailure = self.validationFailure(for: appURL) {
                completion(.failure(validationFailure))
                return
            }

            let hadQuarantineAttribute = self.hasQuarantineAttribute(appURL: appURL)
            if hadQuarantineAttribute {
                let xattrResult = self.runner.run(
                    command: "/usr/bin/xattr",
                    arguments: ["-dr", "com.apple.quarantine", appURL.path]
                )

                if !xattrResult.succeeded {
                    let info = DiagnosticInfo(
                        title: "移除隔离标记失败",
                        message: "仅删除 com.apple.quarantine 时出现错误，其他扩展属性未被修改。",
                        command: "xattr -dr com.apple.quarantine \(appURL.path.shellQuoted)",
                        output: xattrResult.standardError.ifEmpty(
                            fallback: xattrResult.standardOutput
                        ),
                        suggestions: [
                            "确认应用包未被其他进程占用。",
                            "检查应用所在目录是否允许当前用户修改。",
                            "重新下载可信来源的应用后再次尝试。"
                        ]
                    )
                    completion(.failure(info))
                    return
                }
            }

            let assessment = self.assess(appURL: appURL)
            switch assessment.status {
            case .clean:
                completion(.success)
            case .blocked:
                let info = DiagnosticInfo(
                    title: "Gatekeeper 仍然阻止此应用",
                    message: "隔离标记未能完全移除，系统仍拒绝运行此应用。",
                    command: "spctl --assess --type execute \(appURL.path.shellQuoted)",
                    output: assessment.details,
                    suggestions: [
                        "确认应用来自可信来源后重新下载。",
                        "在“系统设置 > 隐私与安全”中查看系统给出的具体原因。",
                        "不要继续运行签名损坏或来源不明的应用。"
                    ]
                )
                completion(.failure(info))
            case .unknown:
                let message = hadQuarantineAttribute
                    ? "隔离标记已处理，但 Gatekeeper 仍未接受此应用，可能存在签名或完整性问题。"
                    : "未检测到可移除的隔离标记，Gatekeeper 拒绝可能由签名或完整性问题导致。"
                let info = DiagnosticInfo(
                    title: "无法解除应用限制",
                    message: message,
                    command: "spctl --assess --type execute \(appURL.path.shellQuoted)",
                    output: assessment.details,
                    suggestions: [
                        "优先从开发者官网或 App Store 重新下载。",
                        "核对开发者签名与下载来源。",
                        "不要通过关闭系统安全功能来强行运行。"
                    ]
                )
                completion(.failure(info))
            }
        }
    }

    public func assess(appURL: URL) async -> QuarantineAssessment {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(
                        returning: QuarantineAssessment(status: .unknown, details: "服务已释放")
                    )
                    return
                }
                continuation.resume(returning: self.assess(appURL: appURL))
            }
        }
    }

    private func assess(appURL: URL) -> QuarantineAssessment {
        let command = "/usr/sbin/spctl"
        let arguments = ["--assess", "--type", "execute", appURL.path]
        let result = runner.run(command: command, arguments: arguments)

        if result.succeeded {
            return QuarantineAssessment(status: .clean, details: result.standardOutput)
        }

        let errorMessage = result.standardError.ifEmpty(fallback: result.standardOutput)
        if hasQuarantineAttribute(appURL: appURL) {
            return QuarantineAssessment(status: .blocked, details: errorMessage)
        }

        return QuarantineAssessment(status: .unknown, details: errorMessage)
    }

    private func hasQuarantineAttribute(appURL: URL) -> Bool {
        let result = runner.run(
            command: "/usr/bin/xattr",
            arguments: ["-p", "com.apple.quarantine", appURL.path]
        )
        return result.succeeded
    }

    private func validationFailure(for appURL: URL) -> DiagnosticInfo? {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: appURL.path,
            isDirectory: &isDirectory
        )
        let values = try? appURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        let isApplication = appURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame

        guard appURL.isFileURL,
              exists,
              isDirectory.boolValue,
              isApplication,
              values?.isSymbolicLink != true else {
            return DiagnosticInfo(
                title: "无效的应用包",
                message: "Unseal 仅处理本机文件系统中真实存在且不是符号链接的 .app 应用包。",
                command: "检查 \(appURL.path.shellQuoted)",
                output: appURL.path,
                suggestions: [
                    "请直接从访达拖入完整的 .app 应用包。",
                    "不要拖入应用内部文件、快捷方式或符号链接。"
                ]
            )
        }

        return nil
    }
}

private extension String {
    func ifEmpty(fallback: String) -> String {
        isEmpty ? fallback : self
    }

    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
