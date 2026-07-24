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
        guard canAcceptDrop else { return }

        let items = urls.filter { Self.isRepairableItem($0) }
        guard let itemURL = items.first else { return }

        if items.count > 1 {
            let info = DiagnosticInfo(
                title: "一次只能处理一个项目",
                message: "检测到 \(items.count) 个可处理文件。Unseal 每次仅处理一个 .app 或 .dmg。",
                command: "拖入 \(items.count) 个项目",
                output: items.map(\.lastPathComponent).joined(separator: "\n"),
                suggestions: [
                    "一次只从访达拖入一个 .app 或 .dmg。",
                    "处理完成后再拖入下一个。"
                ]
            )
            dropStatus = .failure(itemURL, info)
            lastDiagnostic = info
            return
        }

        performRepair(for: itemURL)
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

    static func isRepairableItem(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ext == "app" || ext == "dmg"
    }

    private func resetState() {
        activeRepairID = nil
        dropStatus = .idle
        lastDiagnostic = nil
    }

    private func performRepair(for itemURL: URL) {
        guard canAcceptDrop else { return }

        let repairID = UUID()
        activeRepairID = repairID

        dropStatus = .processing(itemURL)
        lastDiagnostic = nil

        service.repair(appURL: itemURL) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.activeRepairID == repairID else { return }
                self.activeRepairID = nil
                switch result {
                case .success:
                    self.dropStatus = .success(itemURL)
                case let .failure(info):
                    self.dropStatus = .failure(itemURL, info)
                    self.lastDiagnostic = info
                }
            }
        }
    }
}
