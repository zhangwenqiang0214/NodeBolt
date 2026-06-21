import SwiftUI
import AppKit
import NodeBoltCore

// 按当前设置构造一个 API 客户端
func nbClient() -> MihomoClient {
    let d = UserDefaults.standard
    var base = d.string(forKey: SettingsKeys.apiBase) ?? ""
    while base.hasSuffix("/") { base.removeLast() }
    return MihomoClient(base: base, secret: d.string(forKey: SettingsKeys.secret) ?? "")
}

// 错误转中文
func nbErr(_ e: Error) -> String {
    if let a = e as? MihomoClient.APIError {
        switch a {
        case .unauthorized:        return "认证失败"
        case .connection, .badURL: return "无法连接"
        case .notFound:            return "未找到"
        case .timeout:             return "超时"
        case .http(let c):         return "HTTP \(c)"
        }
    }
    return e.localizedDescription
}

// ISO8601(UTC)→ 本地可读时间;零值/无效时间返回 nil(不显示)
func nbFormatDate(_ s: String) -> String? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = iso.date(from: s)
    if date == nil {
        iso.formatOptions = [.withInternetDateTime]
        date = iso.date(from: s)
    }
    guard let d = date else { return nil }
    if Calendar.current.component(.year, from: d) < 2000 { return nil }   // 过滤 0001 等零值时间
    let out = DateFormatter()
    out.dateFormat = "yyyy-MM-dd HH:mm"
    return out.string(from: d)
}

struct ManagementView: View {
    var body: some View {
        TabView {
            ProvidersTab().tabItem { Label("订阅", systemImage: "arrow.down.circle") }
            ConnectionsTab().tabItem { Label("连接", systemImage: "link") }
            MonitorTab().tabItem { Label("监控", systemImage: "waveform.path.ecg") }
            DNSTab().tabItem { Label("DNS", systemImage: "magnifyingglass") }
            SystemTab().tabItem { Label("系统", systemImage: "gearshape.2") }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}

// 状态行:转圈 + 结果
private struct StatusRow: View {
    let busy: Bool
    let msg: String
    var body: some View {
        HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.small) }
            Text(msg).font(.caption).foregroundStyle(msg.hasPrefix("✗") ? .red : .secondary)
        }
    }
}

// 配置文件档案的本地存储
enum ProfileStore {
    static func load() -> [ConfigProfile] {
        guard let d = UserDefaults.standard.data(forKey: SettingsKeys.configProfiles),
              let a = try? JSONDecoder().decode([ConfigProfile].self, from: d) else { return [] }
        return a
    }
    static func save(_ p: [ConfigProfile]) {
        if let d = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(d, forKey: SettingsKeys.configProfiles)
        }
    }
}

// ===== 订阅 =====
struct ProvidersTab: View {
    @State private var providers: [ProxyProvider] = []
    @State private var busy = false
    @State private var msg = ""
    @State private var profiles: [ConfigProfile] = ProfileStore.load()
    @State private var newName = ""
    @State private var newPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 配置文件切换
            Text("配置文件切换").font(.headline)
            Text("通过 API 重新加载路由器上指定的配置文件(用于切换订阅/配置)。填写文件在路由器上的路径。")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(profiles) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(.caption.bold())
                        Text(p.path).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("切换") { run("切换到「\(p.name)」") { try await nbClient().loadConfig(path: p.path) } }
                        .disabled(busy)
                    Button { remove(p) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("名称", text: $newName).textFieldStyle(.roundedBorder).frame(width: 90)
                TextField("配置文件路径(如 /etc/openclash/config/xxx.yaml)", text: $newPath)
                    .textFieldStyle(.roundedBorder)
                Button("添加") { addProfile() }
            }
            Divider()

            HStack {
                Text("订阅 / 代理集合").font(.headline)
                Spacer()
                Button("刷新") { Task { await load() } }.disabled(busy)
            }
            if !providers.isEmpty && !providers.contains(where: { $0.subscriptionInfo != nil }) {
                Text("当前订阅未通过 provider 提供流量/到期信息。若机场把这些放在节点名里,见 面板 → 🌐检测 → 机场信息。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            List(providers, id: \.name) { p in
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.body.bold())
                    Text("类型 \(p.vehicleType)").font(.caption).foregroundStyle(.secondary)
                    if let u = p.updatedAt, let formatted = nbFormatDate(u) {
                        Text("更新于 \(formatted)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let s = p.subscriptionInfo, s.total > 0 {
                        Text("剩余 \(formatBytes(max(0, s.total - s.upload - s.download))) / 总 \(formatBytes(s.total))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("更新") { run("更新订阅「\(p.name)」", reload: true) { try await nbClient().updateProvider(p.name) } }
                        Button("健康检查") { run("健康检查「\(p.name)」") { try await nbClient().healthCheck(p.name) } }
                    }.font(.caption).disabled(busy)
                }.padding(.vertical, 2)
            }
            StatusRow(busy: busy, msg: msg)
        }
        .padding()
        .task { await load() }
    }

    private func load() async {
        if let pv = try? await nbClient().providers() {
            providers = pv.providers.values.sorted { $0.name < $1.name }
        }
    }

    private func run(_ label: String, reload: Bool = false, _ op: @escaping () async throws -> Void) {
        busy = true; msg = ""
        Task {
            do { try await op(); msg = "✓ \(label)成功"; if reload { await load() } }
            catch { msg = "✗ \(label)失败:\(nbErr(error))" }
            busy = false
        }
    }

    private func addProfile() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        let p = newPath.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !p.isEmpty else { return }
        profiles.append(ConfigProfile(name: n, path: p))
        ProfileStore.save(profiles)
        newName = ""; newPath = ""
    }

    private func remove(_ profile: ConfigProfile) {
        profiles.removeAll { $0.id == profile.id }
        ProfileStore.save(profiles)
    }
}

// ===== 连接(每秒自动刷新)=====
struct ConnectionsTab: View {
    @State private var snap: ConnectionsSnapshot?
    @State private var query = ""
    @State private var showCloseAll = false
    @State private var busy = false
    @State private var msg = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("活动连接").font(.headline)
                Text("(每秒刷新)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("关闭全部") { showCloseAll = true }.foregroundStyle(.red).disabled(busy)
            }
            TextField("搜索(域名/IP/规则/节点)", text: $query).textFieldStyle(.roundedBorder)
            if let s = snap {
                Text("累计 ↓\(formatBytes(s.downloadTotal)) ↑\(formatBytes(s.uploadTotal))   共 \(s.connections.count) 条")
                    .font(.caption).foregroundStyle(.secondary)
                List(filtered(s), id: \.id) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host(c)).font(.caption.bold())
                        Text("\(c.chains.reversed().joined(separator: " → "))   [\(c.rule ?? "")]")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Text("↓\(formatBytes(c.download)) ↑\(formatBytes(c.upload))").font(.caption2)
                            Spacer()
                            Button("关闭") { run("关闭连接") { try await nbClient().closeConnection(c.id) } }
                                .font(.caption2).disabled(busy)
                        }
                    }.padding(.vertical, 1)
                }
            } else {
                ProgressView()
            }
            if busy || !msg.isEmpty { StatusRow(busy: busy, msg: msg) }
        }
        .padding()
        .task { await poll() }
        .confirmationDialog("关闭所有连接?", isPresented: $showCloseAll) {
            Button("关闭全部", role: .destructive) { run("关闭全部连接") { try await nbClient().closeAllConnections() } }
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            snap = try? await nbClient().connections()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func host(_ c: ConnectionsSnapshot.Conn) -> String {
        let h = c.metadata?.host ?? ""
        let ip = c.metadata?.destinationIP ?? ""
        let port = c.metadata?.destinationPort ?? ""
        let base = h.isEmpty ? ip : h
        return port.isEmpty ? base : "\(base):\(port)"
    }
    private func filtered(_ s: ConnectionsSnapshot) -> [ConnectionsSnapshot.Conn] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return s.connections }
        return s.connections.filter {
            (host($0) + ($0.rule ?? "") + $0.chains.joined()).localizedCaseInsensitiveContains(q)
        }
    }
    private func run(_ label: String, _ op: @escaping () async throws -> Void) {
        busy = true; msg = ""
        Task {
            do { try await op(); msg = "✓ \(label)成功" } catch { msg = "✗ \(label)失败:\(nbErr(error))" }
            busy = false
        }
    }
}

// ===== DNS =====
struct DNSTab: View {
    @State private var domain = ""
    @State private var type = "A"
    @State private var answers: [String] = []
    @State private var msg = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DNS 查询").font(.headline)
            HStack {
                TextField("域名", text: $domain).textFieldStyle(.roundedBorder)
                Picker("", selection: $type) {
                    ForEach(["A", "AAAA", "CNAME", "MX", "TXT"], id: \.self) { Text($0).tag($0) }
                }.frame(width: 90).labelsHidden()
                Button("查询") { query() }.disabled(busy)
            }
            Text("查询某域名经内核 DNS 的解析结果,用于排查分流是否生效 / 是否被 DNS 污染(看它解析到哪些 IP)。")
                .font(.caption2).foregroundStyle(.secondary)
            if busy {
                StatusRow(busy: true, msg: "查询中…")
            } else if !answers.isEmpty {
                List(answers, id: \.self) { Text($0).font(.body.monospaced()) }
            } else {
                Text(msg).font(.caption).foregroundStyle(msg.hasPrefix("✗") ? .red : .secondary)
                Spacer()
            }
        }
        .padding()
    }

    private func query() {
        let d = domain.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty else { return }
        busy = true; answers = []; msg = ""
        Task {
            do {
                let r = try await nbClient().dnsQuery(name: d, type: type)
                answers = (r.Answer ?? []).compactMap { $0.data }
                msg = answers.isEmpty ? "无解析结果" : ""
            } catch {
                msg = "✗ 查询失败:\(nbErr(error))"
            }
            busy = false
        }
    }
}

// ===== 实时监控(流式)=====
struct MonitorTab: View {
    @State private var up = 0
    @State private var down = 0
    @State private var inuse = 0
    @State private var logs: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("实时监控").font(.headline)
            HStack(spacing: 24) {
                metric("下行", "\(formatBytes(down))/s", .green)
                metric("上行", "\(formatBytes(up))/s", .blue)
                metric("内存", formatBytes(inuse), .primary)
            }
            Divider()
            Text("实时日志").font(.subheadline.bold())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .task {
            async let t: Void = streamTraffic()
            async let m: Void = streamMemory()
            async let l: Void = streamLogs()
            _ = await (t, m, l)
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit()).foregroundStyle(color)
        }
    }

    @MainActor private func streamTraffic() async {
        guard let bytes = try? await nbClient().streamBytes("/traffic") else { return }
        do {
            for try await line in bytes.lines {
                if let d = line.data(using: .utf8),
                   let s = try? JSONDecoder().decode(TrafficSample.self, from: d) {
                    up = s.up; down = s.down
                }
            }
        } catch { }
    }
    @MainActor private func streamMemory() async {
        guard let bytes = try? await nbClient().streamBytes("/memory") else { return }
        do {
            for try await line in bytes.lines {
                if let d = line.data(using: .utf8),
                   let s = try? JSONDecoder().decode(MemorySample.self, from: d) {
                    inuse = s.inuse
                }
            }
        } catch { }
    }
    @MainActor private func streamLogs() async {
        guard let bytes = try? await nbClient().streamBytes("/logs") else { return }
        do {
            for try await line in bytes.lines {
                if let d = line.data(using: .utf8),
                   let s = try? JSONDecoder().decode(LogLine.self, from: d) {
                    logs.append("[\(s.type)] \(s.payload)")
                    if logs.count > 300 { logs.removeFirst(logs.count - 300) }
                }
            }
        } catch { }
    }
}

// ===== 系统 =====
struct SystemTab: View {
    @State private var version = "—"
    @State private var busy = false
    @State private var msg = ""
    @State private var danger: Danger?

    enum Danger: String, Identifiable {
        case restart, upgrade, upgradeUI
        var id: String { rawValue }
        var title: String {
            switch self {
            case .restart:   return "重启内核?"
            case .upgrade:   return "升级内核?"
            case .upgradeUI: return "升级面板 UI?"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("系统与维护").font(.headline)
            Text("内核版本:\(version)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("更新 GEO 数据库") { run("更新 GEO") { try await nbClient().updateGeo() } }
                Button("清空 FakeIP 缓存") { run("清空 FakeIP") { try await nbClient().flushFakeIP() } }
            }.disabled(busy)
            Divider()
            Text("高危操作").font(.caption).foregroundStyle(.red)
            HStack {
                Button("重启内核") { danger = .restart }
                Button("升级内核") { danger = .upgrade }
                Button("升级面板") { danger = .upgradeUI }
            }.foregroundStyle(.red).disabled(busy)
            StatusRow(busy: busy, msg: msg)
            Spacer()
        }
        .padding()
        .task { if let v = try? await nbClient().version() { version = v.version } }
        .confirmationDialog(danger?.title ?? "", isPresented: Binding(
            get: { danger != nil },
            set: { if !$0 { danger = nil } }
        ), presenting: danger) { act in
            Button(act.title, role: .destructive) {
                switch act {
                case .restart:   run("重启内核") { try await nbClient().restartCore() }
                case .upgrade:   run("升级内核") { try await nbClient().upgradeCore() }
                case .upgradeUI: run("升级面板") { try await nbClient().upgradeUI() }
                }
            }
        } message: { _ in Text("该操作会影响内核运行,请确认。") }
    }

    private func run(_ label: String, _ op: @escaping () async throws -> Void) {
        busy = true; msg = ""
        Task {
            do { try await op(); msg = "✓ \(label)成功" } catch { msg = "✗ \(label)失败:\(nbErr(error))" }
            busy = false
        }
    }
}
