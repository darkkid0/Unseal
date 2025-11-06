import Foundation

public struct DiagnosticInfo: Equatable, Sendable {
    public let title: String
    public let message: String
    public let command: String
    public let output: String
    public let suggestions: [String]

    public init(
        title: String,
        message: String,
        command: String,
        output: String,
        suggestions: [String]
    ) {
        self.title = title
        self.message = message
        self.command = command
        self.output = output
        self.suggestions = suggestions
    }
}

public struct QuarantineAssessment: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case clean
        case blocked
        case unknown
    }

    public let status: Status
    public let details: String

    public init(status: Status, details: String) {
        self.status = status
        self.details = details
    }
}
