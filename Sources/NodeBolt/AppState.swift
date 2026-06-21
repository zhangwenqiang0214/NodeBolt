import SwiftUI
import NodeBoltCore
import Network
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var groups: [String] = []        // 所有策略组名
    @Published var activeGroup: String = ""      // 当前操作的组
    @Published var nodes: [NodeItem] = []        // 当前组下的节点
    @Published var currentNode: String = ""      // 当前选中节点
    @Published var statusText: String = "正在连接…"
    @Published var hasError: Bool = false
    @Published var isTesting: Bool = false
    @Published var favorites: Set<String> = []   // 收藏的节点名(置顶)
    @Published var mode: String = ""             // 运行模式 rule/global/direct
    @Published var modeSwitching: Bool = false   // 模式切换中(显示转圈)
    @Published var menuBarMode: MenuBarMode = .iconNode
    @Published var proxyUpSpeed: Int = 0
    @Published var proxyDownSpeed: Int = 0
    @Published var probes: [ProbeResult] = ProbeService.sites.map { ProbeResult(name: $0.name, url: $0.url) }
    @Published var ipResults: [IPSource: IPInfo] = [:]
    @Published var ipSource: IPSource = .ipapi
    @Published var ipChecking: Bool = false
    @Published var subInfos: [SubInfo] = []

    private var lastConnBytes: [String: (up: Int, down: Int)] = [:]
    private var lastPollTime: Date?
    private var speedTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var lastNetSatisfied = true
    private var nodeMonitorTask: Task<Void, Never>?
    private var lastNodeHealthy = true
    private let hotKey = HotKeyManager()
    private var autoTestTask: Task<Void, Never>?

    // 当前实际使用的 API 地址(给错误界面显示,便于排查)
    var currentBaseDisplay: String {
        UserDefaults.standard.string(forKey: SettingsKeys.apiBase) ?? "(未设置)"
    }

    init() {
        UserDefaults.standard.register(defaults: SettingsKeys.defaults)
        favorites = Set(UserDefaults.standard.stringArray(forKey: SettingsKeys.favorites) ?? [])
        let raw = UserDefaults.standard.string(forKey: SettingsKeys.menuBarMode) ?? MenuBarMode.iconNode.rawValue
        menuBarMode = MenuBarMode(rawValue: raw) ?? .iconNode
        Task { await refresh() }
        updateSpeedPolling()
        startPathMonitor()
        updateNodeMonitor()
        updateHotKey()
        updateAutoTest()
    }

    // ===== 配置读取 =====
    private func client() -> MihomoClient {
        let d = UserDefaults.standard
        var base = d.string(forKey: SettingsKeys.apiBase) ?? ""
        while base.hasSuffix("/") { base.removeLast() }
        return MihomoClient(base: base, secret: d.string(forKey: SettingsKeys.secret) ?? "")
    }
    private var testURL: String {
        UserDefaults.standard.string(forKey: SettingsKeys.testURL) ?? "http://www.gstatic.com/generate_204"
    }
    private var timeoutMs: Int {
        let v = UserDefaults.standard.integer(forKey: SettingsKeys.timeout)
        return v <= 0 ? 5000 : v
    }

    // ===== 操作 =====

    func refresh() async {
        statusText = "连接中…"
        let c = client()
        nbDebug("refresh: base=\(c.base) secretSet=\(!c.secret.isEmpty)")
        do {
            let px = try await c.proxies()
            let groupInfos = px.proxies.values.filter { $0.all != nil }
            self.groups = groupInfos.map { $0.name }.sorted()

            // 解析活动组:优先用户设置,否则自动选第一个 Selector
            var ag = UserDefaults.standard.string(forKey: SettingsKeys.group) ?? ""
            if ag.isEmpty || !groups.contains(ag) {
                ag = px.proxies.values.first(where: { $0.type == "Selector" })?.name
                    ?? groups.first ?? ""
            }
            self.activeGroup = ag

            if let g = px.proxies[ag], let all = g.all {
                self.currentNode = g.now ?? ""
                // 保留上次测速结果(按节点名合并)
                let old = Dictionary(nodes.map { ($0.name, ($0.delay, $0.failed)) },
                                     uniquingKeysWith: { a, _ in a })
                self.nodes = all.map { name in
                    let prev = old[name]
                    return NodeItem(name: name,
                                    delay: prev?.0 ?? nil,
                                    failed: prev?.1 ?? false,
                                    isCurrent: name == g.now)
                }
            } else {
                self.nodes = []
                self.currentNode = ""
            }
            self.hasError = false
            self.statusText = "已连接"
            if let cfg = try? await c.config() { self.mode = cfg.mode }
            if let pv = try? await c.providers() {
                subInfos = pv.providers.values.compactMap { p in
                    guard let s = p.subscriptionInfo, s.total > 0 else { return nil }
                    return SubInfo(name: p.name, used: s.upload + s.download, total: s.total, expire: s.expire)
                }.sorted { $0.name < $1.name }
            }
        } catch {
            nbDebug("refresh failed: \(error)")
            self.hasError = true
            self.statusText = Self.describe(error)
        }
    }

    func setActiveGroup(_ name: String) {
        UserDefaults.standard.set(name, forKey: SettingsKeys.group)
        activeGroup = name
        Task { await refresh() }
    }

    func switchTo(_ name: String) async {
        statusText = "切换中…"
        do {
            try await client().switchProxy(group: activeGroup, to: name)
            await refresh()
            statusText = "已切换到 \(name)"
        } catch {
            hasError = true
            statusText = Self.describe(error)
        }
    }

    func testAll() async {
        guard !isTesting, !nodes.isEmpty else { return }
        isTesting = true
        for i in nodes.indices { nodes[i].testing = true }     // 全部标记“测速中”
        defer {
            isTesting = false
            for i in nodes.indices { nodes[i].testing = false }
        }
        let c = client(); let url = testURL; let to = timeoutMs

        // 优先整组原生测速(一次请求,更快)
        if let map = try? await c.groupDelay(activeGroup, timeout: to, url: url), !map.isEmpty {
            for i in nodes.indices {
                if let d = map[nodes[i].name], d > 0 {
                    nodes[i].delay = d; nodes[i].failed = false
                } else {
                    nodes[i].delay = nil; nodes[i].failed = true
                }
                nodes[i].testing = false
            }
            statusText = "测速完成"
            return
        }

        // 回退:逐节点并发
        let names = nodes.map { $0.name }
        await withTaskGroup(of: (String, Int?).self) { group in
            for n in names {
                group.addTask {
                    let d = try? await c.delay(n, timeout: to, url: url)
                    return (n, d)
                }
            }
            for await (n, d) in group {
                if let i = nodes.firstIndex(where: { $0.name == n }) {
                    nodes[i].delay = d
                    nodes[i].failed = (d == nil)
                    nodes[i].testing = false                    // 出结果即停转圈
                }
            }
        }
        statusText = "测速完成"
    }

    func switchFastest() async {
        if !nodes.contains(where: { $0.delay != nil }) {
            await testAll()
        }
        let best = nodes
            .filter { !$0.failed && $0.delay != nil }
            .min(by: { ($0.delay ?? .max) < ($1.delay ?? .max) })
        guard let b = best else {
            hasError = true
            statusText = "无可用节点(全部超时)"
            return
        }
        await switchTo(b.name)
    }

    // 单节点测速
    func testOne(_ name: String) async {
        if let i = nodes.firstIndex(where: { $0.name == name }) { nodes[i].testing = true }
        let c = client(); let url = testURL; let to = timeoutMs
        let d = try? await c.delay(name, timeout: to, url: url)
        if let i = nodes.firstIndex(where: { $0.name == name }) {
            nodes[i].delay = d
            nodes[i].failed = (d == nil)
            nodes[i].testing = false
        }
    }

    func isFavorite(_ name: String) -> Bool { favorites.contains(name) }

    func toggleFavorite(_ name: String) {
        if favorites.contains(name) { favorites.remove(name) } else { favorites.insert(name) }
        UserDefaults.standard.set(Array(favorites), forKey: SettingsKeys.favorites)
    }

    // 切换运行模式 rule/global/direct(乐观更新,避免分段控件回弹)
    func setMode(_ m: String) async {
        guard m != mode else { return }
        let previous = mode
        mode = m                 // 立即更新 UI
        modeSwitching = true
        defer { modeSwitching = false }
        do {
            try await client().setMode(m)
        } catch {
            mode = previous      // 失败回滚
            hasError = true
            statusText = Self.describe(error)
        }
    }

    // ===== 状态栏显示 / 代理网速 =====
    func setMenuBarMode(_ m: MenuBarMode) {
        menuBarMode = m
        UserDefaults.standard.set(m.rawValue, forKey: SettingsKeys.menuBarMode)
        updateSpeedPolling()
    }

    private func updateSpeedPolling() {
        speedTask?.cancel()
        guard menuBarMode.needsSpeed else {
            proxyUpSpeed = 0; proxyDownSpeed = 0
            lastConnBytes = [:]; lastPollTime = nil
            return
        }
        speedTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollProxySpeed()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pollProxySpeed() async {
        guard let snap = try? await client().connections() else { return }
        let now = Date()
        var newMap: [String: (up: Int, down: Int)] = [:]
        var dUp = 0, dDown = 0
        for c in snap.connections {
            let out = c.chains.first ?? "DIRECT"
            guard out != "DIRECT" && !out.hasPrefix("REJECT") else { continue }
            newMap[c.id] = (c.upload, c.download)
            if let prev = lastConnBytes[c.id] {
                dUp += max(0, c.upload - prev.up)
                dDown += max(0, c.download - prev.down)
            }
        }
        if let t = lastPollTime {
            let dt = now.timeIntervalSince(t)
            if dt > 0 {
                proxyUpSpeed = Int(Double(dUp) / dt)
                proxyDownSpeed = Int(Double(dDown) / dt)
            }
        }
        lastConnBytes = newMap
        lastPollTime = now
    }

    // ===== 检测页 =====
    func runConnectivity() async {
        let probe = ProbeService()
        for i in probes.indices { probes[i].testing = true; probes[i].done = false; probes[i].delay = nil }
        await withTaskGroup(of: (String, Int?).self) { group in
            for p in probes {
                let url = p.url, name = p.name
                group.addTask { (name, await probe.ping(url)) }
            }
            for await (name, d) in group {
                if let i = probes.firstIndex(where: { $0.name == name }) {
                    probes[i].delay = d
                    probes[i].testing = false
                    probes[i].done = true
                }
            }
        }
    }

    func runIPCheck() async {
        ipChecking = true
        defer { ipChecking = false }
        ipResults = [:]
        let probe = ProbeService()
        await withTaskGroup(of: (IPSource, IPInfo?).self) { group in
            for s in IPSource.allCases {
                group.addTask { (s, await probe.queryIP(s)) }
            }
            for await (s, info) in group {
                if let info = info { ipResults[s] = info }
            }
        }
    }

    // ===== Phase 8:网络监控 / 掉线通知 / 全局快捷键 =====
    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let became = satisfied && !self.lastNetSatisfied
                self.lastNetSatisfied = satisfied
                if satisfied {
                    await self.refresh()
                    if became && UserDefaults.standard.bool(forKey: SettingsKeys.autoTest) {
                        await self.testAll()
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    func updateNodeMonitor() {
        nodeMonitorTask?.cancel()
        guard UserDefaults.standard.bool(forKey: SettingsKeys.notifyNodeDown) else { return }
        lastNodeHealthy = true
        nodeMonitorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)   // 等首次拉取完成,currentNode 就绪
            while !Task.isCancelled {
                await self?.checkCurrentNode()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func checkCurrentNode() async {
        guard !currentNode.isEmpty else { return }
        let c = client()
        let d = try? await c.delay(currentNode, timeout: timeoutMs, url: testURL)
        let healthy = (d != nil)
        if lastNodeHealthy && !healthy {
            postNotification(title: "节点掉线", body: "当前节点「\(currentNode)」不可用")
        }
        lastNodeHealthy = healthy
    }

    func updateHotKey() {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.hotkeyEnabled) else {
            hotKey.unregister(); return
        }
        let d = UserDefaults.standard
        let keyCode = UInt32(d.integer(forKey: SettingsKeys.hotkeyKeyCode))
        let mods = UInt32(d.integer(forKey: SettingsKeys.hotkeyModifiers))
        let action = HotKeyAction(rawValue: d.string(forKey: SettingsKeys.hotkeyAction) ?? "fastest") ?? .fastest
        hotKey.onTrigger = {
            Task { @MainActor in
                switch action {
                case .fastest:
                    await AppState.shared.switchFastest()
                    AppState.shared.postNotification(title: "NodeBolt",
                        body: "已切到最快:\(AppState.shared.currentNode)")
                case .panel:
                    AppDelegate.shared?.showPanel()
                }
            }
        }
        hotKey.register(keyCode: keyCode == 0 ? 3 : keyCode,
                        modifiers: mods == 0 ? 6144 : mods)
    }

    func requestNotifyAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // 定时自动测速(分钟,0=关)
    func updateAutoTest() {
        autoTestTask?.cancel()
        let mins = UserDefaults.standard.integer(forKey: SettingsKeys.autoTestMinutes)
        guard mins > 0 else { return }
        autoTestTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(mins) * 60_000_000_000)
                await self?.testAll()
            }
        }
    }

    // ===== 工具 =====
    static func describe(_ e: Error) -> String {
        if let a = e as? MihomoClient.APIError {
            switch a {
            case .unauthorized:        return "认证失败,请检查 Secret"
            case .connection, .badURL: return "无法连接 API,请检查地址/网络"
            case .notFound:            return "未找到,请检查策略组名"
            case .timeout:             return "请求超时"
            case .http(let code):      return "请求失败(HTTP \(code))"
            }
        }
        return "出错:\(e.localizedDescription)"
    }
}
