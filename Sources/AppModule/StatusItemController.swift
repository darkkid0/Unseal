import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let appModel: AppModel
    private let launchAtLoginController: LaunchAtLoginController
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let contextMenu: NSMenu
    private let clearMenuItem: NSMenuItem
    private var cancellables = Set<AnyCancellable>()

    init(
        appModel: AppModel,
        launchAtLoginController: LaunchAtLoginController
    ) {
        self.appModel = appModel
        self.launchAtLoginController = launchAtLoginController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()

        let menu = NSMenu()
        menu.autoenablesItems = false
        let clearItem = NSMenuItem(
            title: "清空记录",
            action: #selector(clearRecords(_:)),
            keyEquivalent: ""
        )
        clearItem.image = NSImage(
            systemSymbolName: "trash.fill",
            accessibilityDescription: "清空记录"
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        clearItem.image?.isTemplate = true
        menu.addItem(clearItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出软件",
            action: #selector(quitApplication(_:)),
            keyEquivalent: ""
        )
        quitItem.image = NSImage(
            systemSymbolName: "power.circle.fill",
            accessibilityDescription: "退出软件"
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        quitItem.image?.isTemplate = true
        menu.addItem(quitItem)

        contextMenu = menu
        clearMenuItem = clearItem
        super.init()

        clearMenuItem.target = self
        quitItem.target = self
        clearMenuItem.isEnabled = false

        configureStatusItem()
        configurePopover()
        observeModelState()
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
        updatePopoverSize()
        popover.contentViewController = HostingController(
            appModel: appModel,
            launchAtLoginController: launchAtLoginController
        )
    }

    private func observeModelState() {
        appModel.$lastDiagnostic
            .combineLatest(
                launchAtLoginController.$statusMessage,
                appModel.$dropStatus
            )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updatePopoverSize()
                self?.updateContextMenuItems()
            }
            .store(in: &cancellables)
    }

    private func updatePopoverSize() {
        popover.contentSize = NSSize(
            width: MenuLayout.width,
            height: MenuLayout.height(
                hasDiagnostic: appModel.lastDiagnostic != nil,
                hasStatusMessage: launchAtLoginController.statusMessage != nil
            )
        )
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
        clearMenuItem.isEnabled = appModel.canClearRecords
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
    init(
        appModel: AppModel,
        launchAtLoginController: LaunchAtLoginController
    ) {
        super.init(
            rootView: MenuContainerView(
                model: appModel,
                launchAtLoginController: launchAtLoginController
            )
        )
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct MenuContainerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    var body: some View {
        ScrollView {
            MenuContent()
                .environmentObject(model)
                .environmentObject(launchAtLoginController)
                .frame(width: 328)
                .padding()
        }
        .frame(
            width: MenuLayout.width,
            height: MenuLayout.height(
                hasDiagnostic: model.lastDiagnostic != nil,
                hasStatusMessage: launchAtLoginController.statusMessage != nil
            )
        )
    }
}

enum MenuLayout {
    static let width: CGFloat = 360

    static func height(
        hasDiagnostic: Bool,
        hasStatusMessage: Bool
    ) -> CGFloat {
        if hasDiagnostic { return 500 }
        if hasStatusMessage { return 350 }
        return 300
    }
}
