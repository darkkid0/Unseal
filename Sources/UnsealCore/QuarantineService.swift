import Foundation

public protocol CommandRunning {
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

public final class SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(command: String, arguments: [String]) -> CommandResult {
        Self.runSync(command: command, arguments: arguments)
    }

    public static func runSync(command: String, arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return CommandResult(
                terminationStatus: -1,
                standardOutput: "",
                standardError: error.localizedDescription
            )
        }

        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(data: output, encoding: .utf8) ?? "",
            standardError: String(data: errorOutput, encoding: .utf8) ?? ""
        )
    }
}

public enum RepairResult: Sendable {
    case success
    case failure(DiagnosticInfo)
}

public final class QuarantineService {
    private let queue = DispatchQueue(label: "com.example.QuarantineService", qos: .userInitiated)
    private let runner: CommandRunning

    public init(runner: CommandRunning = SystemCommandRunner()) {
        self.runner = runner
    }

    public func repair(appURL: URL, completion: @escaping @Sendable (RepairResult) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }

            let xattrResult = self.runner.run(
                command: "/usr/bin/xattr",
                arguments: ["-cr", appURL.path]
            )

            if !xattrResult.succeeded {
                let info = DiagnosticInfo(
                    title: "移除扩展属性失败",
                    message: "尝试执行 xattr -cr 时出现错误。",
                    command: "xattr -cr \(appURL.path)",
                    output: xattrResult.standardError.ifEmpty(fallback: xattrResult.standardOutput),
                    suggestions: [
                        "确保已为 Unseal 授予完全磁盘访问权限。",
                        "确认应用路径无误。",
                        "尝试重新下载该应用并再次修复。"
                    ]
                )
                completion(.failure(info))
                return
            }

            let assessment = self.assess(appURL: appURL)
            switch assessment.status {
            case .clean:
                completion(.success)
            case .blocked:
                let info = DiagnosticInfo(
                    title: "Gatekeeper 校验失败",
                    message: "系统仍然认为该应用不安全。",
                    command: "spctl --assess --type execute \(appURL.path)",
                    output: assessment.details,
                    suggestions: [
                        "尝试重新下载应用或联系开发者获取新版。",
                        "在系统设置的隐私与安全中允许该应用运行。",
                        "确认下载来源可信，避免运行未知来源应用。"
                    ]
                )
                completion(.failure(info))
            case .unknown:
                let info = DiagnosticInfo(
                    title: "校验状态未知",
                    message: "修复后未能确认应用状态，请手动验证。",
                    command: "spctl --assess --type execute \(appURL.path)",
                    output: assessment.details,
                    suggestions: [
                        "在终端手动运行上述命令确认输出。",
                        "检查系统日志了解更多信息。",
                        "若问题持续，考虑联系苹果支持。"
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
                let assessment = self.assess(appURL: appURL)
                continuation.resume(returning: assessment)
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
}

extension QuarantineService: @unchecked Sendable {}

private extension String {
    func ifEmpty(fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
