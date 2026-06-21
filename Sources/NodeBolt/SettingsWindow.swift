import SwiftUI
import AppKit
import NodeBoltCore

// 独立管理设置窗口的单例,避免依赖 NSApp.delegate(SwiftUI 会用它自己的 AppDelegate 包一层)。
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        nbDebug("SettingsWindowController.show()")
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = .preferredContentSize
            let win = NSWindow(contentViewController: hosting)
            win.title = "NodeBolt 设置"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 420, height: 360))
            win.delegate = self
            win.center()
            window = win
        }
        NSApp.setActivationPolicy(.regular)          // 临时显示 Dock,使窗口可获得焦点
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        nbDebug("settings 窗口已显示")
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)        // 关闭后恢复纯菜单栏
    }
}
