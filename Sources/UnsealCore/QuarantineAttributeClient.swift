import Foundation

/// Typed result of probing `com.apple.quarantine` on an application bundle.
public enum QuarantineAttributeProbe: Sendable, Equatable {
    case present(value: String)
    case absent
    case failed(CommandResult)
}

/// Reads, removes, and restores only the `com.apple.quarantine` extended attribute.
public struct QuarantineAttributeClient: Sendable {
    public static let attributeName = "com.apple.quarantine"

    private let runner: any CommandRunning

    public init(runner: any CommandRunning) {
        self.runner = runner
    }

    public func probe(appURL: URL) -> QuarantineAttributeProbe {
        let result = runner.run(
            command: "/usr/bin/xattr",
            arguments: ["-p", Self.attributeName, appURL.path]
        )

        if result.succeeded {
            let value = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return .present(value: value)
        }

        if Self.isMissingAttribute(result: result) {
            return .absent
        }

        return .failed(result)
    }

    public func remove(appURL: URL) -> CommandResult {
        runner.run(
            command: "/usr/bin/xattr",
            arguments: ["-dr", Self.attributeName, appURL.path]
        )
    }

    /// Scans the bundle tree for any `com.apple.quarantine` entries.
    public func hasQuarantineAnywhere(appURL: URL) -> Bool {
        let result = runner.run(
            command: "/usr/bin/xattr",
            arguments: ["-lr", appURL.path]
        )
        let output = result.standardOutput + "\n" + result.standardError
        return output.contains(Self.attributeName)
    }

    /// Restores the top-level quarantine attribute (kept for tests / recovery tools).
    public func restore(appURL: URL, value: String) -> CommandResult {
        runner.run(
            command: "/usr/bin/xattr",
            arguments: ["-w", Self.attributeName, value, appURL.path]
        )
    }

    static func isMissingAttribute(result: CommandResult) -> Bool {
        let output = (result.standardError + "\n" + result.standardOutput)
            .lowercased()
        let markers = [
            "no such xattr",
            "no such attribute",
            "attribute not found",
            "找不到",
            "不存在"
        ]
        return markers.contains { output.contains($0) }
    }
}
