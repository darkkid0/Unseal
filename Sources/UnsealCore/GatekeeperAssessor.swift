import Foundation

/// Runs Gatekeeper assessment via `/usr/sbin/spctl`.
public struct GatekeeperAssessor: Sendable {
    private let runner: any CommandRunning
    private let attributeClient: QuarantineAttributeClient

    public init(runner: any CommandRunning) {
        self.runner = runner
        self.attributeClient = QuarantineAttributeClient(runner: runner)
    }

    public func assess(appURL: URL) -> QuarantineAssessment {
        let result = runner.run(
            command: "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "execute", appURL.path]
        )

        if result.succeeded {
            return QuarantineAssessment(status: .clean, details: result.standardOutput)
        }

        let errorMessage = result.combinedOutput
        switch attributeClient.probe(appURL: appURL) {
        case .present:
            return QuarantineAssessment(status: .blocked, details: errorMessage)
        case .absent:
            return QuarantineAssessment(status: .unknown, details: errorMessage)
        case let .failed(probeResult):
            let details = [
                errorMessage,
                "隔离标记探测失败：\(probeResult.combinedOutput)"
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            return QuarantineAssessment(status: .unknown, details: details)
        }
    }
}
