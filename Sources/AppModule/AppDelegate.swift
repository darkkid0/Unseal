import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(appModel: appModel)
        statusItemController?.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel.clearState()
    }
}
