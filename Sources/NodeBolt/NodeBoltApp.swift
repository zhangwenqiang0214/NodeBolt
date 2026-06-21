import SwiftUI

// NodeBolt —— 菜单栏由 AppDelegate 的 NSStatusItem 管理;App 本体仅提供一个空 Settings 场景。
@main
struct NodeBoltApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
