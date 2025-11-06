import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let appModel: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false

        clearMenuItem = NSMenuItem(
            title: "清空记录",
            action: #selector(clearRecords(_:)),
            keyEquivalent: ""
        )
        clearMenuItem?.target = self
        clearMenuItem?.image = NSImage(
            systemSymbolName: "trash.fill",
            accessibilityDescription: "清空记录"
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        clearMenuItem?.image?.isTemplate = true
        menu.addItem(clearMenuItem!)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出软件",
            action: #selector(quitApplication(_:)),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.image = NSImage(
            systemSymbolName: "power.circle.fill",
            accessibilityDescription: "退出软件"
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        quitItem.image?.isTemplate = true
        menu.addItem(quitItem)

        return menu
    }()
    private var clearMenuItem: NSMenuItem?
    private var dropStatusIsActive: Bool {
        if case .idle = appModel.dropStatus {
            return false
        }
        return true
    }

    init(appModel: AppModel) {
        self.appModel = appModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
        updateContextMenuItems()
    }

    func activate() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if let event = NSApp.currentEvent {
            let isRightClick = event.type == .rightMouseUp ||
                (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
            if isRightClick {
                showContextMenu()
                return
            }
        }

        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let frame = button.bounds
        popover.show(relativeTo: frame, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hidePopover() {
        popover.performClose(nil)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "shield.lefthalf.fill",
            accessibilityDescription: "Unseal"
        )
        button.imagePosition = .imageOnly
        button.appearsDisabled = false
        button.focusRingType = .none
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.contentViewController = HostingController(appModel: appModel)
    }

    private func showContextMenu() {
        if popover.isShown {
            hidePopover()
        }
        updateContextMenuItems()
        if let button = statusItem.button {
            contextMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height),
                in: button
            )
        }
    }

    private func updateContextMenuItems() {
        clearMenuItem?.isEnabled = dropStatusIsActive
    }

    @objc
    private func clearRecords(_ sender: Any?) {
        appModel.clearState()
        updateContextMenuItems()
    }

    @objc
    private func quitApplication(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class HostingController: NSHostingController<MenuContainerView> {
    init(appModel: AppModel) {
        super.init(rootView: MenuContainerView(model: appModel))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct MenuContainerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        MenuContent()
            .environmentObject(model)
            .frame(width: 300)
            .padding()
    }
}
