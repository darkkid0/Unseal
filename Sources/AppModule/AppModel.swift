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

    @Published var dropStatus: DropStatus = .idle
    @Published var lastDiagnostic: DiagnosticInfo?

    private let service: QuarantineService

    init(service: QuarantineService = .init()) {
        self.service = service
    }

    func handleDrop(urls: [URL]) {
        guard let appURL = urls.first else { return }
        performRepair(for: appURL)
    }

    func retryLastFailure() {
        if case let .failure(url, _) = dropStatus {
            performRepair(for: url, allowReuse: true)
        }
    }

    func clearState() {
        dropStatus = .idle
        lastDiagnostic = nil
    }

    private func performRepair(for appURL: URL, allowReuse: Bool = false) {
        if !allowReuse, case .processing = dropStatus {
            return
        }

        dropStatus = .processing(appURL)
        lastDiagnostic = nil

        service.repair(appURL: appURL) { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
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
