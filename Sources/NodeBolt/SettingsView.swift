import SwiftUI
import NodeBoltCore
import ServiceManagement

// 连接档案本地存储
enum ConnProfileStore {
    static func load() -> [ConnectionProfile] {
        guard let d = UserDefaults.standard.data(forKey: SettingsKeys.connProfiles),
              let a = try? JSONDecoder().decode([ConnectionProfile].self, from: d) else { return [] }
        return a
    }
    static func save(_ p: [ConnectionProfile]) {
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: SettingsKeys.connProfiles) }
    }
}

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared

    @AppStorage(SettingsKeys.apiBase) private var apiBase = "http://127.0.0.1:9090"
    @AppStorage(SettingsKeys.secret)  private var secret  = ""
    @AppStorage(SettingsKeys.group)   private var group   = ""
    @AppStorage(SettingsKeys.testURL) private var testURL = "http://www.gstatic.com/generate_204"
    @AppStorage(SettingsKeys.timeout) private var timeout = 5000
    @AppStorage(SettingsKeys.autoTest) private var autoTest = false
    @AppStorage(SettingsKeys.filterInfoNodes) private var filterInfoNodes = false
    @AppStorage(SettingsKeys.filterRules) private var filterRules = defaultFilterRules
    @AppStorage(SettingsKeys.notifyNodeDown) private var notifyNodeDown = false
    @AppStorage(SettingsKeys.hotkeyEnabled) private var hotkeyEnabled = false
    @AppStorage(SettingsKeys.hotkeyAction) private var hotkeyAction = "fastest"
    @AppStorage(SettingsKeys.hotkeyDisplay) private var hotkeyDisplay = "⌃⌥F"
    @AppStorage(SettingsKeys.hotkeyKeyCode) private var hotkeyKeyCode = 3
    @AppStorage(SettingsKeys.hotkeyModifiers) private var hotkeyModifiers = 6144
    @AppStorage(SettingsKeys.autoTestMinutes) private var autoTestMinutes = 0
    @State private var recording = false

    @State private var testResult = ""
    @State private var launchAtLogin = false
    @State private var connProfiles: [ConnectionProfile] = ConnProfileStore.load()
    @State private var newProfileName = ""

    var body: some View {
        Form {
            Section("连接") {
                TextField("API 地址", text: $apiBase)
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret", text: $secret)
                    .textFieldStyle(.roundedBorder)
                TextField("策略组(留空=自动选择)", text: $group)
                    .textFieldStyle(.roundedBorder)
            }
            Section("连接档案(家里/公司)") {
                ForEach(connProfiles) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.caption.bold())
                            Text(p.apiBase).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("切换") { applyProfile(p) }
                        Button { removeProfile(p) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("档案名", text: $newProfileName).textFieldStyle(.roundedBorder).frame(width: 100)
                    Button("保存当前为档案") { saveCurrentProfile() }
                }
            }
            Section("测速") {
                TextField("测试 URL", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                TextField("超时(毫秒)", value: $timeout, format: .number)
                    .textFieldStyle(.roundedBorder)
                Toggle("打开面板时自动测速", isOn: $autoTest)
                Picker("定时自动测速", selection: Binding(
                    get: { autoTestMinutes },
                    set: { autoTestMinutes = $0; state.updateAutoTest() }
                )) {
                    Text("关闭").tag(0)
                    Text("每 5 分钟").tag(5)
                    Text("每 10 分钟").tag(10)
                    Text("每 30 分钟").tag(30)
                }
            }
            Section("通用") {
                Toggle("开机自启", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = newValue
                        } catch {
                            // 失败:回到真实状态
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
                ))
            }
            Section("状态栏") {
                Picker("显示方式", selection: Binding(
                    get: { state.menuBarMode },
                    set: { state.setMenuBarMode($0) }
                )) {
                    ForEach(MenuBarMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
            }
            Section("节点") {
                Toggle("过滤机场信息节点", isOn: $filterInfoNodes)
                if filterInfoNodes {
                    TextField("过滤关键词(逗号分隔)", text: $filterRules)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Section("通知") {
                Toggle("节点掉线时通知", isOn: $notifyNodeDown)
                    .onChange(of: notifyNodeDown) { _, v in
                        if v { state.requestNotifyAuth() }
                        state.updateNodeMonitor()
                    }
            }
            Section("全局快捷键") {
                Toggle("启用全局快捷键", isOn: $hotkeyEnabled)
                    .onChange(of: hotkeyEnabled) { _, v in
                        if v { state.requestNotifyAuth() }
                        state.updateHotKey()
                    }
                if hotkeyEnabled {
                    Picker("功能", selection: Binding(
                        get: { HotKeyAction(rawValue: hotkeyAction) ?? .fastest },
                        set: { hotkeyAction = $0.rawValue; state.updateHotKey() }
                    )) {
                        ForEach(HotKeyAction.allCases, id: \.self) { a in Text(a.label).tag(a) }
                    }
                    HStack {
                        Text("快捷键")
                        Spacer()
                        if recording {
                            Text("按下组合键…").foregroundStyle(.secondary)
                            KeyRecorder { keyCode, mods, disp in
                                hotkeyKeyCode = Int(keyCode)
                                hotkeyModifiers = Int(mods)
                                hotkeyDisplay = disp
                                recording = false
                                state.updateHotKey()
                            }
                            .frame(width: 1, height: 16)
                        } else {
                            Button(hotkeyDisplay.isEmpty ? "未设置" : hotkeyDisplay) { recording = true }
                        }
                    }
                }
            }
            Section {
                HStack {
                    Button("测试连接并刷新") {
                        Task {
                            await state.refresh()
                            testResult = state.hasError
                                ? "✗ \(state.statusText)"
                                : "✓ 已连接,组「\(state.activeGroup)」共 \(state.nodes.count) 个节点"
                        }
                    }
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 760)
        .onAppear { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
    }

    private func applyProfile(_ p: ConnectionProfile) {
        apiBase = p.apiBase; secret = p.secret; group = p.group
        Task { await state.refresh() }
    }
    private func saveCurrentProfile() {
        let n = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        connProfiles.append(ConnectionProfile(name: n, apiBase: apiBase, secret: secret, group: group))
        ConnProfileStore.save(connProfiles)
        newProfileName = ""
    }
    private func removeProfile(_ p: ConnectionProfile) {
        connProfiles.removeAll { $0.id == p.id }
        ConnProfileStore.save(connProfiles)
    }
}
