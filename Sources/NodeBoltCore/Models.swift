import Foundation

// ===== Mihomo API 响应模型 =====

public struct ProxiesResponse: Decodable {
    public let proxies: [String: ProxyInfo]
}

public struct ProxyInfo: Decodable {
    public let name: String
    public let type: String
    public let now: String?      // 策略组当前选中的节点
    public let all: [String]?    // 策略组下所有可选项(普通节点没有此字段)
}

struct DelayResponse: Decodable {
    let delay: Int
}

public struct ConfigInfo: Decodable {
    public let mode: String
}

// ===== 连接 =====
public struct ConnectionsSnapshot: Decodable {
    public let downloadTotal: Int
    public let uploadTotal: Int
    public let connections: [Conn]

    enum CodingKeys: String, CodingKey { case downloadTotal, uploadTotal, connections }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        downloadTotal = (try? c.decode(Int.self, forKey: .downloadTotal)) ?? 0
        uploadTotal   = (try? c.decode(Int.self, forKey: .uploadTotal)) ?? 0
        connections   = (try? c.decode([Conn].self, forKey: .connections)) ?? []   // 容错:null/缺失 → []
    }

    public struct Conn: Decodable {
        public let id: String
        public let upload: Int
        public let download: Int
        public let chains: [String]
        public let rule: String?
        public let rulePayload: String?
        public let metadata: Metadata?
        public struct Metadata: Decodable {
            public let host: String?
            public let destinationIP: String?
            public let destinationPort: String?
            public let network: String?
            public let process: String?
        }
    }
}

// 统计“走代理(非 DIRECT/REJECT)”的连接累计上下行
public func proxiedTotals(_ snap: ConnectionsSnapshot) -> (up: Int, down: Int) {
    var up = 0, down = 0
    for c in snap.connections {
        let out = c.chains.first ?? "DIRECT"
        if out != "DIRECT" && !out.hasPrefix("REJECT") {
            up += c.upload; down += c.download
        }
    }
    return (up, down)
}

// ===== 菜单栏显示模式 =====
public enum MenuBarMode: String, CaseIterable, Sendable {
    case iconOnly, iconNode, iconSpeed, nodeOnly, speedOnly, hidden
    public var label: String {
        switch self {
        case .iconOnly:  return "仅图标"
        case .iconNode:  return "图标 + 节点名"
        case .iconSpeed: return "图标 + 代理网速"
        case .nodeOnly:  return "仅节点名"
        case .speedOnly: return "仅代理网速"
        case .hidden:    return "完全隐藏图标"
        }
    }
    public var needsSpeed: Bool { self == .iconSpeed || self == .speedOnly }
}

// 人类可读字节
public func formatBytes(_ b: Int) -> String {
    let x = Double(max(0, b))
    if x < 1024 { return "\(Int(x))B" }
    if x < 1_048_576 { return String(format: "%.0fK", x / 1024) }
    if x < 1_073_741_824 { return String(format: "%.1fM", x / 1_048_576) }
    return String(format: "%.2fG", x / 1_073_741_824)
}

// ===== 订阅(proxy providers)=====
public struct ProxyProvidersResponse: Decodable {
    public let providers: [String: ProxyProvider]
}
public struct ProxyProvider: Decodable {
    public let name: String
    public let vehicleType: String
    public let updatedAt: String?
    public let subscriptionInfo: SubscriptionInfo?
}
public struct SubscriptionInfo: Decodable {
    public let upload: Int
    public let download: Int
    public let total: Int
    public let expire: Int
    enum CodingKeys: String, CodingKey {
        case upload = "Upload", download = "Download", total = "Total", expire = "Expire"
    }
}
// 给 UI 用的订阅摘要
public struct SubInfo: Identifiable, Sendable {
    public let name: String
    public let used: Int
    public let total: Int
    public let expire: Int   // unix 秒;0=无
    public var id: String { name }
    public var remaining: Int { max(0, total - used) }
    public init(name: String, used: Int, total: Int, expire: Int) {
        self.name = name; self.used = used; self.total = total; self.expire = expire
    }
}

// ===== 机场“信息节点”过滤 =====
public let defaultFilterRules = "剩余流量,到期,过期,重置,官网,套餐,电报,群组,Expire,距离下次,订阅,客服"

public func parseFilterRules(_ s: String) -> [String] {
    s.split(whereSeparator: { $0 == "," || $0 == "," || $0 == "\n" })
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

public func isInfoNode(_ name: String, rules: [String]) -> Bool {
    let lower = name.lowercased()
    return rules.contains { lower.contains($0.lowercased()) }
}

// ===== 系统 / DNS =====
public struct VersionInfo: Decodable {
    public let version: String
    public let meta: Bool?
}
public struct DNSAnswer: Decodable {
    public let data: String?
    public let TTL: Int?
    public let type: Int?
}
public struct DNSResult: Decodable {
    public let Answer: [DNSAnswer]?
}

// 流式监控样本
public struct TrafficSample: Decodable { public let up: Int; public let down: Int }
public struct MemorySample: Decodable { public let inuse: Int }
public struct LogLine: Decodable { public let type: String; public let payload: String }

// API 连接档案(家里/公司)
public struct ConnectionProfile: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var apiBase: String
    public var secret: String
    public var group: String
    public init(id: String = UUID().uuidString, name: String, apiBase: String, secret: String, group: String) {
        self.id = id; self.name = name; self.apiBase = apiBase; self.secret = secret; self.group = group
    }
}

// 配置文件档案(用于切换配置 / 订阅)
public struct ConfigProfile: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public init(id: String = UUID().uuidString, name: String, path: String) {
        self.id = id; self.name = name; self.path = path
    }
}

// ===== 全局快捷键功能 =====
public enum HotKeyAction: String, CaseIterable, Sendable {
    case fastest, panel
    public var label: String {
        switch self {
        case .fastest: return "连接最快的节点"
        case .panel:   return "打开软件面板"
        }
    }
}

// ===== 菜单里用的节点行模型 =====

public struct NodeItem: Identifiable, Hashable, Sendable {
    public let name: String
    public var delay: Int?       // 毫秒;nil = 尚未测速
    public var failed: Bool      // 测过但超时/不可用
    public var isCurrent: Bool   // 是否为当前选中
    public var testing: Bool     // 正在测速(显示转圈)
    public var id: String { name }

    public init(name: String, delay: Int? = nil, failed: Bool = false,
                isCurrent: Bool = false, testing: Bool = false) {
        self.name = name
        self.delay = delay
        self.failed = failed
        self.isCurrent = isCurrent
        self.testing = testing
    }
}
