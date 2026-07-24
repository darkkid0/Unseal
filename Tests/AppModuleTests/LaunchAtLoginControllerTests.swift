import Foundation
import ServiceManagement
import XCTest
@testable import AppModule

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testFirstLaunchDoesNotEnableLoginItemByDefault() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        let defaults = makeDefaults()
        let controller = LaunchAtLoginController(manager: manager, defaults: defaults)

        controller.activateIfNeeded()

        XCTAssertEqual(manager.registerCallCount, 0)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: LaunchAtLoginController.preferenceKey))
    }

    func testStoredEnabledPreferenceRegistersOnActivate() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        let defaults = makeDefaults()
        defaults.set(true, forKey: LaunchAtLoginController.preferenceKey)
        let controller = LaunchAtLoginController(manager: manager, defaults: defaults)

        controller.activateIfNeeded()

        XCTAssertEqual(manager.registerCallCount, 1)
        XCTAssertTrue(controller.isEnabled)
    }

    func testStoredDisabledPreferenceIsRespected() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        let defaults = makeDefaults()
        defaults.set(false, forKey: LaunchAtLoginController.preferenceKey)
        let controller = LaunchAtLoginController(manager: manager, defaults: defaults)

        controller.activateIfNeeded()

        XCTAssertEqual(manager.registerCallCount, 0)
        XCTAssertFalse(controller.isEnabled)
    }

    func testSystemApprovalIsNotForcedAndOpensSettings() {
        let manager = FakeLaunchAtLoginManager(status: .requiresApproval)
        let defaults = makeDefaults()
        defaults.set(true, forKey: LaunchAtLoginController.preferenceKey)
        let controller = LaunchAtLoginController(manager: manager, defaults: defaults)

        controller.activateIfNeeded()
        controller.openSystemSettings()

        XCTAssertEqual(manager.registerCallCount, 0)
        XCTAssertTrue(controller.requiresApproval)
        XCTAssertNotNil(controller.statusMessage)
        XCTAssertEqual(manager.openSettingsCallCount, 1)
    }

    func testDisablingLoginItemUnregistersIt() {
        let manager = FakeLaunchAtLoginManager(status: .enabled)
        let defaults = makeDefaults()
        let controller = LaunchAtLoginController(manager: manager, defaults: defaults)

        controller.setEnabled(false)

        XCTAssertEqual(manager.unregisterCallCount, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: LaunchAtLoginController.preferenceKey))
        XCTAssertTrue(defaults.bool(forKey: LaunchAtLoginController.consentKey))
    }

    func testNotFoundMainAppServiceUsesLaunchAgentFallback() throws {
        let fallback = try makeLaunchAgentLoginItem()
        let appService = FakeMainAppLoginItem(status: .notFound)
        let manager = SystemLaunchAtLoginManager(
            appService: appService,
            fallback: fallback
        )

        XCTAssertEqual(manager.status, .disabled)
        try manager.register()

        XCTAssertEqual(manager.status, .enabled)
        XCTAssertEqual(appService.registerCallCount, 0)
        XCTAssertTrue(fallback.isRegistered)

        let data = try Data(contentsOf: fallback.plistURL)
        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(propertyList["Label"] as? String, fallback.label)
        XCTAssertEqual(fallback.label, "io.github.darkkid0.Unseal.login-item")

        try manager.unregister()
        XCTAssertFalse(fallback.plistExists)
    }

    func testRegistrationFailureUsesLaunchAgentFallback() throws {
        let fallback = try makeLaunchAgentLoginItem()
        let appService = FakeMainAppLoginItem(
            status: .notRegistered,
            registrationError: FakeLoginItemError.registrationFailed
        )
        let manager = SystemLaunchAtLoginManager(
            appService: appService,
            fallback: fallback
        )

        try manager.register()

        XCTAssertEqual(appService.registerCallCount, 1)
        XCTAssertTrue(fallback.isRegistered)
        XCTAssertEqual(manager.status, .enabled)
    }

    func testEnabledSMAppServiceMigratesAwayFromLaunchAgent() throws {
        let fallback = try makeLaunchAgentLoginItem()
        try fallback.register()
        XCTAssertTrue(fallback.isRegistered)

        let appService = FakeMainAppLoginItem(status: .enabled)
        let manager = SystemLaunchAtLoginManager(
            appService: appService,
            fallback: fallback
        )

        XCTAssertEqual(manager.status, .enabled)
        XCTAssertFalse(fallback.isRegistered)
    }

    func testLaunchAgentLabelDerivesFromBundleIdentifier() throws {
        let item = try makeLaunchAgentLoginItem(
            bundleIdentifier: "com.example.CustomUnseal"
        )
        try item.register()
        XCTAssertEqual(item.label, "com.example.CustomUnseal.login-item")
        XCTAssertTrue(item.isRegistered)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "LaunchAtLoginControllerTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func makeLaunchAgentLoginItem(
        bundleIdentifier: String = "io.github.darkkid0.Unseal"
    ) throws -> LaunchAgentLoginItem {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchAgentTests-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = rootURL.appendingPathComponent("Unseal.app", isDirectory: true)
        let launchAgentsURL = rootURL.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
        return LaunchAgentLoginItem(
            bundleURL: bundleURL,
            launchAgentsDirectory: launchAgentsURL,
            bundleIdentifier: bundleIdentifier
        )
    }
}

@MainActor
private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginState
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(status: LaunchAtLoginState) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .disabled
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}

private enum FakeLoginItemError: Error {
    case registrationFailed
}

@MainActor
private final class FakeMainAppLoginItem: MainAppLoginItemManaging {
    var status: SMAppService.Status
    private let registrationError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(
        status: SMAppService.Status,
        registrationError: Error? = nil
    ) {
        self.status = status
        self.registrationError = registrationError
    }

    func register() throws {
        registerCallCount += 1
        if let registrationError {
            throw registrationError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}
