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
    static let label = "io.github.darkkid0.Unseal.login-item"

    private let bundleURL: URL
    private let launchAgentsDirectory: URL
    private let fileManager: FileManager

    var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
    }

    var isAvailable: Bool {
        bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame &&
            fileManager.fileExists(atPath: bundleURL.path)
    }

    var plistExists: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    var isRegistered: Bool {
        guard isAvailable,
              let data = try? Data(contentsOf: plistURL),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let dictionary = propertyList as? [String: Any],
              dictionary["Label"] as? String == Self.label,
              dictionary["RunAtLoad"] as? Bool == true,
              let arguments = dictionary["ProgramArguments"] as? [String] else {
            return false
        }

        return arguments == ["/usr/bin/open", "-g", bundleURL.path]
    }

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        launchAgentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.bundleURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        self.launchAgentsDirectory = launchAgentsDirectory
        self.fileManager = fileManager
    }

    func register() throws {
        guard isAvailable else {
            throw LaunchAtLoginError.applicationBundleUnavailable
        }

        let propertyList: [String: Any] = [
            "Label": Self.label,
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
        guard plistExists else { return }
        try fileManager.removeItem(at: plistURL)
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
        if fallback.isRegistered {
            return .enabled
        }

        switch appService.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return fallback.isAvailable ? .disabled : .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func register() throws {
        switch appService.status {
        case .enabled:
            return
        case .requiresApproval:
            return
        case .notFound:
            try fallback.register()
        case .notRegistered:
            do {
                try appService.register()
            } catch {
                guard fallback.isAvailable else { throw error }
                try fallback.register()
            }
        @unknown default:
            try fallback.register()
        }
    }

    func unregister() throws {
        try fallback.unregister()

        switch appService.status {
        case .enabled, .requiresApproval:
            try appService.unregister()
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
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
        if defaults.object(forKey: Self.preferenceKey) == nil {
            defaults.set(true, forKey: Self.preferenceKey)
        }

        guard defaults.bool(forKey: Self.preferenceKey) else {
            refresh()
            return
        }

        enableIfPossible()
    }

    func setEnabled(_ enabled: Bool) {
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
