import Foundation

// UserDefaults 键名集中管理
public enum SettingsKeys {
    public static let apiBase   = "apiBase"     // String  例: http://192.168.6.1:9090
    public static let secret    = "apiSecret"   // String  Bearer 认证用
    public static let group     = "groupName"   // String  留空则自动选第一个 Selector 组
    public static let testURL   = "testURL"     // String  延迟测试目标
    public static let timeout   = "timeoutMs"   // Int     测速超时(毫秒)
    public static let autoTest    = "autoTest"    // Bool    打开面板时自动测速
    public static let favorites   = "favorites"   // [String] 收藏的节点名
    public static let menuBarMode = "menuBarMode" // String  状态栏显示方式
    public static let filterInfoNodes = "filterInfoNodes" // Bool   过滤机场信息节点
    public static let filterRules     = "filterRules"     // String 过滤关键词(逗号分隔)
    public static let notifyNodeDown  = "notifyNodeDown"  // Bool   节点掉线通知
    public static let hotkeyEnabled   = "hotkeyEnabled"   // Bool   全局快捷键(切最快)
    public static let sortMode        = "sortMode"        // String default/delay/name
    public static let hideTimeout     = "hideTimeout"     // Bool   隐藏超时节点
    public static let hotkeyKeyCode   = "hotkeyKeyCode"   // Int    虚拟键码
    public static let hotkeyModifiers = "hotkeyModifiers" // Int    Carbon 修饰键
    public static let hotkeyDisplay   = "hotkeyDisplay"   // String 显示用文本
    public static let hotkeyAction    = "hotkeyAction"    // String fastest/panel
    public static let configProfiles  = "configProfiles"  // Data   [ConfigProfile] JSON
    public static let connProfiles    = "connProfiles"    // Data   [ConnectionProfile] JSON
    public static let autoTestMinutes = "autoTestMinutes" // Int    定时自动测速(分钟,0=关)

    public static let defaults: [String: Any] = [
        apiBase: "http://127.0.0.1:9090",
        secret:  "",
        group:   "",
        testURL: "http://www.gstatic.com/generate_204",
        timeout: 5000,
        autoTest: false,
        menuBarMode: MenuBarMode.iconNode.rawValue,
        filterInfoNodes: false,
        filterRules: defaultFilterRules,
        notifyNodeDown: false,
        hotkeyEnabled: false,
        sortMode: "default",
        hideTimeout: false,
        hotkeyKeyCode: 3,        // kVK_ANSI_F
        hotkeyModifiers: 6144,   // controlKey(4096) | optionKey(2048) = ⌃⌥
        hotkeyDisplay: "⌃⌥F",
        hotkeyAction: HotKeyAction.fastest.rawValue,
        autoTestMinutes: 0
    ]
}
