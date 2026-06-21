import SwiftUI
import AppKit

// 管理窗口(订阅/连接/DNS/系统),可调整大小。
final class ManagementWindowController: NSObject, NSWindowDelegate {
    static let shared = ManagementWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: ManagementView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "NodeBolt 管理"
            win.styleMask = [.titled, .closable, .resizable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 540, height: 500))
            win.delegate = self
            win.center()
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = nil   // 销毁视图树,停止连接页的每秒轮询
    }
}
