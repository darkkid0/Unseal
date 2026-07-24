import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginManaging {
    var status: LaunchAtLoginState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
protocol MainAppLoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
struct SMMainAppLoginItem: MainAppLoginItemManaging {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct LaunchAgentLoginItem {
    /// Historical hard-coded label used by earlier builds.
    static let legacyLabel = "io.github.darkkid0.Unseal.login-item"

    private let bundleURL: URL
    private let launchAgentsDirectory: URL
    private let fileManager: FileManager
    private let primaryLabel: String
    private let knownLabels: [String]

    var label: String { primaryLabel }

    var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(primaryLabel).plist")
    }

    var isAvailable: Bool {
        bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame &&
            fileManager.fileExists(atPath: bundleURL.path)
    }

    var plistExists: Bool {
        knownLabels.contains { label in
            fileManager.fileExists(atPath: plistURL(for: label).path)
        }
    }

    var isRegistered: Bool {
        knownLabels.contains { isRegistered(label: $0) }
    }

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        launchAgentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.bundleURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        self.launchAgentsDirectory = launchAgentsDirectory
        self.fileManager = fileManager

        let resolvedIdentifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let derivedLabel: String
        if let resolvedIdentifier, !resolvedIdentifier.isEmpty {
            derivedLabel = "\(resolvedIdentifier).login-item"
        } else {
            derivedLabel = Self.legacyLabel
        }
        self.primaryLabel = derivedLabel

        var labels = [derivedLabel]
        if derivedLabel != Self.legacyLabel {
            labels.append(Self.legacyLabel)
        }
        self.knownLabels = labels
    }

    func register() throws {
        guard isAvailable else {
            throw LaunchAtLoginError.applicationBundleUnavailable
        }

        // Prefer a single authoritative plist derived from the bundle identifier.
        try removeLegacyPlists(keeping: primaryLabel)

        let propertyList: [String: Any] = [
            "Label": primaryLabel,
            "ProgramArguments": ["/usr/bin/open", "-g", bundleURL.path],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )

        try fileManager.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try data.write(to: plistURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: plistURL.path
        )
    }

    func unregister() throws {
        var firstError: Error?
        for label in knownLabels {
            let url = plistURL(for: label)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    /// Removes LaunchAgent fallback entries once SMAppService owns login registration.
    func migrateAwayIfPresent() {
        try? unregister()
    }

    private func plistURL(for label: String) -> URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    private func isRegistered(label: String) -> Bool {
        guard isAvailable,
              let data = try? Data(contentsOf: plistURL(for: label)),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let dictionary = propertyList as? [String: Any],
              dictionary["Label"] as? String == label,
              dictionary["RunAtLoad"] as? Bool == true,
              let arguments = dictionary["ProgramArguments"] as? [String] else {
            return false
        }

        return arguments == ["/usr/bin/open", "-g", bundleURL.path]
    }

    private func removeLegacyPlists(keeping keepLabel: String) throws {
        for label in knownLabels where label != keepLabel {
            let url = plistURL(for: label)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
    }
}

private enum LaunchAtLoginError: LocalizedError {
    case applicationBundleUnavailable

    var errorDescription: String? {
        "当前运行文件不是完整的 Unseal.app，无法创建登录启动项。"
    }
}

@MainActor
struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    private let appService: any MainAppLoginItemManaging
    private let fallback: LaunchAgentLoginItem

    init(
        appService: any MainAppLoginItemManaging = SMMainAppLoginItem(),
        fallback: LaunchAgentLoginItem = LaunchAgentLoginItem()
    ) {
        self.appService = appService
        self.fallback = fallback
    }

    var status: LaunchAtLoginState {
        switch appService.status {
        case .enabled:
            // SMAppService is authoritative; drop any leftover LaunchAgent.
            fallback.migrateAwayIfPresent()
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            if fallback.isRegistered {
                return .enabled
            }
            return .disabled
        case .notFound:
            if fallback.isRegistered {
                return .enabled
            }
            return fallback.isAvailable ? .disabled : .unavailable
        @unknown default:
            if fallback.isRegistered {
                return .enabled
            }
            return .unavailable
        }
    }

    func register() throws {
        switch appService.status {
        case .enabled:
            fallback.migrateAwayIfPresent()
            return
        case .requiresApproval:
            return
        case .notFound:
            try fallback.register()
        case .notRegistered:
            do {
                try appService.register()
                fallback.migrateAwayIfPresent()
            } catch {
                guard fallback.isAvailable else { throw error }
                try fallback.register()
            }
        @unknown default:
            try fallback.register()
        }
    }

    func unregister() throws {
        var firstError: Error?

        do {
            try fallback.unregister()
        } catch {
            firstError = error
        }

        switch appService.status {
        case .enabled, .requiresApproval:
            do {
                try appService.unregister()
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }

        if let firstError {
            throw firstError
        }
    }

    func openSystemSettings() {
        appService.openSystemSettings()
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState = .disabled
    @Published private(set) var statusMessage: String?

    static let preferenceKey = "LaunchAtLoginEnabled"
    /// Tracks whether the user has made an explicit login-item choice.
    static let consentKey = "LaunchAtLoginConsentRecorded"

    private let manager: any LaunchAtLoginManaging
    private let defaults: UserDefaults

    var isEnabled: Bool {
        state == .enabled
    }

    var requiresApproval: Bool {
        state == .requiresApproval
    }

    init(
        manager: any LaunchAtLoginManaging = SystemLaunchAtLoginManager(),
        defaults: UserDefaults = .standard
    ) {
        self.manager = manager
        self.defaults = defaults
        refresh()
    }

    func activateIfNeeded() {
        // Opt-in: do not register on first launch until the user enables the toggle.
        if defaults.object(forKey: Self.preferenceKey) == nil {
            defaults.set(false, forKey: Self.preferenceKey)
        }

        guard defaults.bool(forKey: Self.preferenceKey) else {
            refresh()
            return
        }

        enableIfPossible()
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.consentKey)
        defaults.set(enabled, forKey: Self.preferenceKey)

        if enabled {
            enableIfPossible()
            return
        }

        do {
            try manager.unregister()
            refresh()
        } catch {
            refresh(errorMessage: "关闭登录启动失败：\(error.localizedDescription)")
        }
    }

    func refresh() {
        refresh(errorMessage: nil)
    }

    func openSystemSettings() {
        manager.openSystemSettings()
    }

    private func enableIfPossible() {
        switch manager.status {
        case .enabled, .requiresApproval, .unavailable:
            refresh()
        case .disabled:
            do {
                try manager.register()
                refresh()
            } catch {
                refresh(errorMessage: "开启登录启动失败：\(error.localizedDescription)")
            }
        }
    }

    private func refresh(errorMessage: String?) {
        state = manager.status

        if let errorMessage {
            statusMessage = errorMessage
            return
        }

        switch state {
        case .disabled, .enabled:
            statusMessage = nil
        case .requiresApproval:
            statusMessage = "macOS 已暂停登录启动，请在“系统设置 > 通用 > 登录项”中允许 Unseal。"
        case .unavailable:
            statusMessage = "请从完整的 Unseal.app 启动，登录启动功能才可用。"
        }
    }
}
