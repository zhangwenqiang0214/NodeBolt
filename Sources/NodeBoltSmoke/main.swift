import Foundation
import NodeBoltCore

// NodeBolt 网络层集成测试:对本地 mock(Tests/Mock/mock_clash.py)跑真实 API。
// 用环境变量 MOCK_BASE 指定地址(默认 127.0.0.1:19090),secret 固定 123456。
// 不依赖 XCTest,命令行工具链即可运行:  swift run NodeBoltSmoke

let base = ProcessInfo.processInfo.environment["MOCK_BASE"] ?? "http://127.0.0.1:19090"
let secret = "123456"

var failed = 0
var total = 0
func ok(_ cond: Bool, _ name: String) {
    total += 1
    if cond { print("  PASS  \(name)") }
    else    { print("  FAIL  \(name)"); failed += 1 }
}
func fail(_ name: String) { total += 1; print("  FAIL  \(name)"); failed += 1 }

print("== NodeBoltCore 集成测试 (base=\(base)) ==")

let c = MihomoClient(base: base, secret: secret)

// 1) 取代理 + 中文组解析
do {
    let px = try await c.proxies()
    ok(px.proxies["主代理"] != nil, "包含中文策略组「主代理」")
    ok(px.proxies["主代理"]?.type == "Selector", "主代理 类型为 Selector")
    ok((px.proxies["主代理"]?.all ?? []).contains("JP-UDP-199"), "组内含 JP-UDP-199")
    let groupCount = px.proxies.values.filter { $0.all != nil }.count
    ok(groupCount >= 3, "识别出多个策略组(\(groupCount) 个)")
} catch {
    fail("取代理失败: \(error)")
}

// 2) 切换节点 + 回读
do {
    try await c.switchProxy(group: "主代理", to: "JP-UDP-199")
    let px = try await c.proxies()
    ok(px.proxies["主代理"]?.now == "JP-UDP-199", "切换后当前节点更新为 JP-UDP-199")
} catch {
    fail("切换节点失败: \(error)")
}

// 3) UDP 节点测速成功
do {
    let d = try await c.delay("JP-UDP-199", timeout: 5000, url: "http://www.gstatic.com/generate_204")
    ok(d > 0, "UDP 节点返回有效延迟(\(d) ms)")
} catch {
    fail("UDP 测速异常: \(error)")
}

// 4) TCP 节点判定为超时
do {
    _ = try await c.delay("JP-TCP-199", timeout: 5000, url: "http://x")
    fail("TCP 节点应超时,却成功了")
} catch MihomoClient.APIError.timeout {
    ok(true, "TCP 节点正确判定为超时")
} catch {
    fail("TCP 测速错误类型: \(error)")
}

// 5) 错误 secret -> 401
do {
    _ = try await MihomoClient(base: base, secret: "wrong").proxies()
    fail("错误 secret 应 401")
} catch MihomoClient.APIError.unauthorized {
    ok(true, "错误 secret 正确判定为认证失败")
} catch {
    fail("401 错误类型: \(error)")
}

// 5b) 读取/切换运行模式
do {
    let cfg = try await c.config()
    ok(["rule", "global", "direct"].contains(cfg.mode), "读取到运行模式(\(cfg.mode))")
    try await c.setMode("global")
    let cfg2 = try await c.config()
    ok(cfg2.mode == "global", "切换模式生效(global)")
} catch {
    fail("配置接口异常: \(error)")
}

// 5c) 连接列表 + 代理流量统计
do {
    let snap = try await c.connections()
    ok(!snap.connections.isEmpty, "拉取到活动连接(\(snap.connections.count) 条)")
    let t = proxiedTotals(snap)
    ok(t.down > 0, "代理流量统计可计算(累计下行 \(t.down))")
} catch {
    fail("连接接口异常: \(error)")
}

// 5c-2) 连接解析容错:connections=null → 空数组(修复无连接时一直转圈)
if let d = "{\"downloadTotal\":1,\"uploadTotal\":2,\"connections\":null}".data(using: .utf8),
   let snapNull = try? JSONDecoder().decode(ConnectionsSnapshot.self, from: d) {
    ok(snapNull.connections.isEmpty, "connections=null 容错为空数组")
} else {
    fail("connections=null 解析失败")
}

// 5d) 订阅信息(providers)
do {
    let pv = try await c.providers()
    let withSub = pv.providers.values.filter { $0.subscriptionInfo != nil }
    ok(!withSub.isEmpty, "读取到带订阅信息的 provider(\(withSub.count) 个)")
    if let s = withSub.first?.subscriptionInfo { ok(s.total > 0, "订阅总量可读(\(s.total))") }
} catch {
    fail("providers 接口异常: \(error)")
}

// 5e) 信息节点识别(纯函数)
let rules = parseFilterRules(defaultFilterRules)
ok(isInfoNode("剩余流量:100GB", rules: rules), "信息节点识别(剩余流量)")
ok(!isInfoNode("JP-UDP-199", rules: rules), "真节点不被误判")

// 5f) 管理类接口(订阅更新/健康检查/关连接/DNS/版本/GEO)
do {
    try await c.updateProvider("我的机场")
    try await c.healthCheck("default")
    try await c.closeAllConnections()
    let dns = try await c.dnsQuery(name: "google.com", type: "A")
    ok((dns.Answer?.count ?? 0) > 0, "DNS 查询返回结果(\(dns.Answer?.count ?? 0) 条)")
    let v = try await c.version()
    ok(!v.version.isEmpty, "读取内核版本(\(v.version))")
    try await c.updateGeo()
    try await c.loadConfig(path: "/tmp/x.yaml")
    ok(true, "管理接口(更新订阅/健康检查/关连接/GEO/切配置)均通过")
} catch {
    fail("管理接口异常: \(error)")
}

// 5g-2) 整组原生测速
do {
    let m = try await c.groupDelay("主代理", timeout: 5000, url: "http://www.gstatic.com/generate_204")
    ok(m["JP-UDP-199"] != nil, "整组原生测速返回延迟(\(m.count) 项)")
} catch {
    fail("整组测速异常: \(error)")
}

// 5h) 流式 /traffic 至少收到一条
do {
    let bytes = try await c.streamBytes("/traffic")
    var got = false
    for try await line in bytes.lines { if line.contains("up") { got = true; break } }
    ok(got, "流式 /traffic 收到数据")
} catch {
    fail("流式接口异常: \(error)")
}

// 6) 连不上 -> connection
do {
    _ = try await MihomoClient(base: "http://127.0.0.1:9", secret: secret).proxies()
    fail("不可达地址应报连接错误")
} catch MihomoClient.APIError.connection {
    ok(true, "不可达地址正确判定为连接失败")
} catch {
    fail("连接错误类型: \(error)")
}

print("== 结果:通过 \(total - failed)/\(total),失败 \(failed) ==")
if failed == 0 { print("全部通过 ✅") } else { print("存在失败 ❌") }
exit(failed == 0 ? 0 : 1)
