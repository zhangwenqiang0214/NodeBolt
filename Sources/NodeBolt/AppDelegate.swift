import AppKit
import SwiftUI
import Combine
import NodeBoltCore

// 用自定义 NSStatusItem + NSPopover 管理菜单栏(可代码控制开关面板、隐藏图标)。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    private var tempShown = false   // 隐藏模式下被快捷键临时唤出

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)   // 菜单栏程序:无 Dock 图标(从 Xcode 裸跑也生效)

        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(rootView: PanelView())
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        // 观察状态变化,实时刷新菜单栏标题/图标
        cancellable = AppState.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusButton() }
        }
        updateStatusButton()

        Task { await AppState.shared.refresh() }
    }

    // 图标完全隐藏时:重新打开 App → 弹设置(逃生口)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // 供快捷键“打开面板”调用;图标隐藏时临时显示以便定位
    func showPanel() {
        if !(statusItem?.isVisible ?? false) {
            statusItem?.isVisible = true
            tempShown = true
        }
        showPopover()
    }

    func popoverDidClose(_ notification: Notification) {
        if tempShown {
            statusItem?.isVisible = false
            tempShown = false
        }
    }

    func updateStatusButton() {
        guard let item = statusItem, let button = item.button else { return }
        let s = AppState.shared

        if s.menuBarMode == .hidden && !tempShown {
            item.isVisible = false
            return
        }
        item.isVisible = true

        let symbol = s.hasError ? "bolt.slash.fill" : "bolt.fill"
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: "NodeBolt")
        let speed = "↓\(formatBytes(s.proxyDownSpeed))/s ↑\(formatBytes(s.proxyUpSpeed))/s"

        switch s.menuBarMode {
        case .iconOnly:
            button.image = icon; button.title = ""
        case .iconNode:
            button.image = icon; button.title = s.currentNode.isEmpty ? "" : " \(s.currentNode)"
        case .iconSpeed:
            button.image = icon; button.title = " \(speed)"
        case .nodeOnly:
            button.image = nil; button.title = s.currentNode.isEmpty ? "—" : s.currentNode
        case .speedOnly:
            button.image = nil; button.title = speed
        case .hidden:
            button.image = icon; button.title = ""   // tempShown 时
        }
    }
}
