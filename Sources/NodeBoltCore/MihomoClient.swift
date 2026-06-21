import Foundation

// 与 Mihomo (Clash.Meta) 外部控制器 API 通信。无状态值类型,可安全跨任务并发使用。
public struct MihomoClient: Sendable {
    public let base: String      // 例: http://192.168.6.1:9090(末尾斜杠应已去除)
    public let secret: String
    private let session: URLSession = .shared

    public init(base: String, secret: String) {
        self.base = base
        self.secret = secret
    }

    public enum APIError: Error, Sendable {
        case badURL
        case connection      // 连不上 / 超时 / 被拒
        case unauthorized    // 401 / 403
        case notFound        // 404
        case timeout         // 延迟测试失败
        case http(Int)
    }

    // 把节点名 / 组名安全地放进 URL 路径(正确处理中文)
    private func encodePath(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func check(_ resp: URLResponse) throws {
        guard let h = resp as? HTTPURLResponse else { throw APIError.connection }
        switch h.statusCode {
        case 200..<300: return
        case 401, 403:  throw APIError.unauthorized
        case 404:       throw APIError.notFound
        default:        throw APIError.http(h.statusCode)
        }
    }

    private func makeRequest(_ path: String, method: String = "GET") throws -> URLRequest {
        guard let url = URL(string: base + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        if !secret.isEmpty {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        nbDebug("→ \(req.httpMethod ?? "GET") \(req.url?.absoluteString ?? "?")")
        do {
            let (data, resp) = try await session.data(for: req)
            try check(resp)
            return data
        } catch let e as APIError {
            nbDebug("✗ APIError: \(e)")
            throw e
        } catch {
            nbDebug("✗ 传输错误: \(error)")
            throw APIError.connection
        }
    }

    // ===== 具体接口 =====

    public func proxies() async throws -> ProxiesResponse {
        let data = try await send(try makeRequest("/proxies"))
        return try JSONDecoder().decode(ProxiesResponse.self, from: data)
    }

    public func switchProxy(group: String, to name: String) async throws {
        var req = try makeRequest("/proxies/\(encodePath(group))", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["name": name])
        _ = try await send(req)
    }

    public func delay(_ name: String, timeout: Int, url: String) async throws -> Int {
        let encURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let path = "/proxies/\(encodePath(name))/delay?timeout=\(timeout)&url=\(encURL)"
        do {
            let data = try await send(try makeRequest(path))
            return try JSONDecoder().decode(DelayResponse.self, from: data).delay
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch APIError.connection {
            throw APIError.connection
        } catch {
            // 503 / 404 / 解码失败等,对测速来说都视为“不可用”
            throw APIError.timeout
        }
    }

    public func config() async throws -> ConfigInfo {
        let data = try await send(try makeRequest("/configs"))
        return try JSONDecoder().decode(ConfigInfo.self, from: data)
    }

    public func setMode(_ mode: String) async throws {
        var req = try makeRequest("/configs", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["mode": mode])
        _ = try await send(req)
    }

    // 整组原生测速(一次请求测整组,返回 节点名→延迟ms)
    public func groupDelay(_ group: String, timeout: Int, url: String) async throws -> [String: Int] {
        let u = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let data = try await send(try makeRequest("/group/\(encodePath(group))/delay?timeout=\(timeout)&url=\(u)"))
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    public func connections() async throws -> ConnectionsSnapshot {
        let data = try await send(try makeRequest("/connections"))
        return try JSONDecoder().decode(ConnectionsSnapshot.self, from: data)
    }

    public func providers() async throws -> ProxyProvidersResponse {
        let data = try await send(try makeRequest("/providers/proxies"))
        return try JSONDecoder().decode(ProxyProvidersResponse.self, from: data)
    }

    // 订阅管理
    public func updateProvider(_ name: String) async throws {
        _ = try await send(try makeRequest("/providers/proxies/\(encodePath(name))", method: "PUT"))
    }
    public func healthCheck(_ name: String) async throws {
        _ = try await send(try makeRequest("/providers/proxies/\(encodePath(name))/healthcheck"))
    }

    // 连接管理
    public func closeConnection(_ id: String) async throws {
        _ = try await send(try makeRequest("/connections/\(encodePath(id))", method: "DELETE"))
    }
    public func closeAllConnections() async throws {
        _ = try await send(try makeRequest("/connections", method: "DELETE"))
    }

    // DNS
    public func dnsQuery(name: String, type: String) async throws -> DNSResult {
        let n = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let t = type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? type
        let data = try await send(try makeRequest("/dns/query?name=\(n)&type=\(t)"))
        return try JSONDecoder().decode(DNSResult.self, from: data)
    }

    // 系统维护
    public func version() async throws -> VersionInfo {
        let data = try await send(try makeRequest("/version"))
        return try JSONDecoder().decode(VersionInfo.self, from: data)
    }
    // 按路径重新加载配置文件(切换订阅/配置)
    public func loadConfig(path: String) async throws {
        var req = try makeRequest("/configs?force=true", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["path": path])
        _ = try await send(req)
    }

    public func updateGeo()    async throws { _ = try await send(try makeRequest("/configs/geo", method: "POST")) }
    public func flushFakeIP()  async throws { _ = try await send(try makeRequest("/cache/fakeip/flush", method: "POST")) }
    public func restartCore()  async throws { _ = try await send(try makeRequest("/restart", method: "POST")) }
    public func upgradeCore()  async throws { _ = try await send(try makeRequest("/upgrade", method: "POST")) }
    public func upgradeUI()    async throws { _ = try await send(try makeRequest("/upgrade/ui", method: "POST")) }

    // 流式:返回字节序列,调用方按行解析(/traffic /memory /logs)
    public func streamBytes(_ path: String) async throws -> URLSession.AsyncBytes {
        guard let url = URL(string: base + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 86400
        if !secret.isEmpty { req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        let (bytes, resp) = try await session.bytes(for: req)
        try check(resp)
        return bytes
    }
}
