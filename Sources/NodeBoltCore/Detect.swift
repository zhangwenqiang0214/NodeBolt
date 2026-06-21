import Foundation

// IP 数据源
public enum IPSource: String, CaseIterable, Sendable {
    case ipsb  = "ip.sb"
    case ipwho = "ipwho.is"
    case ipapi = "ipapi.is"
}

// 单条附加信息(各源特有字段)
public struct IPDetail: Identifiable, Sendable {
    public let label: String
    public let value: String
    public var id: String { label }
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

// 代理出口 IP 信息
public struct IPInfo: Sendable {
    public var source: String
    public var ip: String
    public var country: String
    public var city: String
    public var isp: String
    public var details: [IPDetail]
    public init(source: String, ip: String, country: String = "", city: String = "",
                isp: String = "", details: [IPDetail] = []) {
        self.source = source; self.ip = ip; self.country = country
        self.city = city; self.isp = isp; self.details = details
    }
}

// 网络连通性检测的单项结果
public struct ProbeResult: Identifiable, Sendable {
    public let name: String
    public let url: String
    public var delay: Int?
    public var testing: Bool
    public var done: Bool
    public var id: String { name }
    public init(name: String, url: String, delay: Int? = nil, testing: Bool = false, done: Bool = false) {
        self.name = name; self.url = url; self.delay = delay; self.testing = testing; self.done = done
    }
}

// 网络/IP 检测服务(从本机直接发起,反映当前实际出网路径)
public struct ProbeService: Sendable {
    public init() {}

    public static let sites: [(name: String, url: String)] = [
        ("GitHub",  "https://github.com"),
        ("YouTube", "https://www.youtube.com"),
        ("百度",    "https://www.baidu.com"),
        ("QQ",      "https://www.qq.com"),
    ]

    // 连通性 + 延迟
    public func ping(_ urlStr: String, timeout: TimeInterval = 8) async -> Int? {
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let start = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let h = resp as? HTTPURLResponse, h.statusCode < 500 else { return nil }
            return Int(Date().timeIntervalSince(start) * 1000)
        } catch {
            return nil
        }
    }

    // 查询指定数据源
    public func queryIP(_ source: IPSource) async -> IPInfo? {
        switch source {
        case .ipsb:  return await ipSB()
        case .ipwho: return await ipWho()
        case .ipapi: return await ipAPI()
        }
    }

    private func fetchJSON(_ urlStr: String) async -> [String: Any]? {
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("NodeBolt", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private func ipSB() async -> IPInfo? {
        guard let j = await fetchJSON("https://api.ip.sb/geoip"),
              let ip = j["ip"] as? String else { return nil }
        var d: [IPDetail] = []
        if let asn = j["asn"] {
            d.append(IPDetail("ASN", "AS\(asn) \((j["asn_organization"] as? String) ?? "")"))
        }
        if let region = j["region"] as? String, !region.isEmpty { d.append(IPDetail("地区", region)) }
        if let org = j["organization"] as? String, !org.isEmpty { d.append(IPDetail("组织", org)) }
        return IPInfo(source: "ip.sb", ip: ip,
                      country: (j["country"] as? String) ?? "",
                      city: (j["city"] as? String) ?? "",
                      isp: (j["isp"] as? String) ?? "", details: d)
    }

    private func ipWho() async -> IPInfo? {
        guard let j = await fetchJSON("https://ipwho.is/"),
              let ip = j["ip"] as? String else { return nil }
        let conn = j["connection"] as? [String: Any]
        var d: [IPDetail] = []
        if let asn = conn?["asn"] {
            d.append(IPDetail("ASN", "AS\(asn) \((conn?["org"] as? String) ?? "")"))
        }
        if let region = j["region"] as? String, !region.isEmpty { d.append(IPDetail("地区", region)) }
        if let tz = (j["timezone"] as? [String: Any])?["id"] as? String { d.append(IPDetail("时区", tz)) }
        return IPInfo(source: "ipwho.is", ip: ip,
                      country: (j["country"] as? String) ?? "",
                      city: (j["city"] as? String) ?? "",
                      isp: (conn?["isp"] as? String) ?? (conn?["org"] as? String ?? ""), details: d)
    }

    private func ipAPI() async -> IPInfo? {
        guard let j = await fetchJSON("https://api.ipapi.is/"),
              let ip = j["ip"] as? String else { return nil }
        let loc = j["location"] as? [String: Any]
        let asn = j["asn"] as? [String: Any]
        let company = j["company"] as? [String: Any]
        func yn(_ k: String) -> String { (j[k] as? Bool) == true ? "是" : "否" }
        var d: [IPDetail] = []
        if let a = asn?["asn"] { d.append(IPDetail("ASN", "AS\(a) \((asn?["org"] as? String) ?? "")")) }
        if let t = company?["type"] as? String { d.append(IPDetail("类型", t)) }
        // 纯净度 / 风险(ipapi.is 独有)
        d.append(IPDetail("数据中心", yn("is_datacenter")))
        d.append(IPDetail("VPN", yn("is_vpn")))
        d.append(IPDetail("代理", yn("is_proxy")))
        d.append(IPDetail("Tor", yn("is_tor")))
        d.append(IPDetail("滥用", yn("is_abuser")))
        return IPInfo(source: "ipapi.is", ip: ip,
                      country: (loc?["country"] as? String) ?? "",
                      city: (loc?["city"] as? String) ?? "",
                      isp: (asn?["org"] as? String) ?? (company?["name"] as? String ?? ""), details: d)
    }
}
