import Foundation
import UnsealCore

@MainActor
final class AppModel: ObservableObject {
    enum DropStatus: Equatable {
        case idle
        case processing(URL)
        case success(URL)
        case failure(URL, DiagnosticInfo)
    }

    @Published private(set) var dropStatus: DropStatus = .idle
    @Published private(set) var lastDiagnostic: DiagnosticInfo?

    private let service: any QuarantineRepairing
    private var activeRepairID: UUID?

    var isProcessing: Bool {
        if case .processing = dropStatus { return true }
        return false
    }

    var canAcceptDrop: Bool {
        !isProcessing
    }

    var canClearRecords: Bool {
        switch dropStatus {
        case .success, .failure:
            return true
        case .idle, .processing:
            return false
        }
    }

    init(service: any QuarantineRepairing = QuarantineService()) {
        self.service = service
    }

    func handleDrop(urls: [URL]) {
        guard canAcceptDrop,
              let appURL = urls.first(where: {
                  $0.isFileURL &&
                      $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame
              }) else { return }
        performRepair(for: appURL)
    }

    func retryLastFailure() {
        if case let .failure(url, _) = dropStatus {
            performRepair(for: url)
        }
    }

    func clearState() {
        guard canClearRecords else { return }
        resetState()
    }

    func prepareForTermination() {
        resetState()
    }

    private func resetState() {
        activeRepairID = nil
        dropStatus = .idle
        lastDiagnostic = nil
    }

    private func performRepair(for appURL: URL) {
        guard canAcceptDrop else { return }

        let repairID = UUID()
        activeRepairID = repairID

        dropStatus = .processing(appURL)
        lastDiagnostic = nil

        service.repair(appURL: appURL) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.activeRepairID == repairID else { return }
                self.activeRepairID = nil
                switch result {
                case .success:
                    self.dropStatus = .success(appURL)
                case let .failure(info):
                    self.dropStatus = .failure(appURL, info)
                    self.lastDiagnostic = info
                }
            }
        }
    }
}
