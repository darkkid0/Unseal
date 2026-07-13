import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()
    let launchAtLoginController = LaunchAtLoginController()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launchAtLoginController.activateIfNeeded()
        statusItemController = StatusItemController(
            appModel: appModel,
            launchAtLoginController: launchAtLoginController
        )
        statusItemController?.activate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchAtLoginController.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
