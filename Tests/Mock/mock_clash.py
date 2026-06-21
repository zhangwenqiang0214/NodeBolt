#!/usr/bin/env python3
# 模拟 Mihomo (Clash.Meta) 外部控制器 API,用于测试 clash.sh。
# 用法: python3 mock_clash.py [port]    (默认 9090, secret 取 MOCK_SECRET 或 123456)
import json, os, sys, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote, parse_qs

SECRET = os.environ.get("MOCK_SECRET", "123456")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9090
STREAM_N = int(os.environ.get("MOCK_STREAM_N", "5"))   # 流式接口推送多少条后关闭

# ---- 可变状态 ----
GROUP_NOW = {"主代理": "自动选择", "国外媒体": "JP-UDP-199"}

GROUPS = {
    "主代理": {"type": "Selector",
             "all": ["自动选择", "JP-UDP-199", "JP-UDP-216", "JP-TCP-199", "JP-TCP-216", "DIRECT"]},
    "自动选择": {"type": "URLTest",
              "all": ["JP-UDP-199", "JP-UDP-216", "JP-TCP-199"]},
    "国外媒体": {"type": "Selector",
              "all": ["JP-UDP-199", "JP-TCP-216", "DIRECT"]},
}
PLAIN_PROXIES = ["JP-UDP-199", "JP-UDP-216", "JP-TCP-199", "JP-TCP-216", "DIRECT"]

def node_delay(name):
    # 模拟:TCP 节点全部超时(返回 0/失败),UDP 正常
    if "TCP" in name:
        return None
    if name == "DIRECT":
        return None
    return 100 + (sum(ord(c) for c in name) % 60)

def build_proxies():
    p = {}
    for n in PLAIN_PROXIES:
        p[n] = {"name": n, "type": ("Direct" if n == "DIRECT" else "Shadowsocks"),
                "history": [], "udp": True}
    for g, info in GROUPS.items():
        p[g] = {"name": g, "type": info["type"], "all": info["all"],
                "now": GROUP_NOW.get(g, info["all"][0]), "history": []}
    return {"proxies": p}

CONFIGS = {
    "port": 7890, "socks-port": 7891, "mixed-port": 7892, "redir-port": 0,
    "tproxy-port": 0, "mode": "rule", "log-level": "info", "allow-lan": False,
    "tun": {"enable": True}
}

CONNECTIONS = {
    "downloadTotal": 1234567890, "uploadTotal": 12345678,
    "connections": [
        {"id": "conn-aaa-111", "upload": 2048, "download": 884736,
         "chains": ["JP-UDP-199", "主代理"], "rule": "DomainSuffix",
         "rulePayload": "youtube.com",
         "metadata": {"network": "tcp", "host": "www.youtube.com",
                      "destinationIP": "142.250.0.1", "destinationPort": "443",
                      "sourceIP": "192.168.6.100", "process": "Safari"}},
        {"id": "conn-bbb-222", "upload": 512, "download": 102400,
         "chains": ["DIRECT"], "rule": "GeoIP", "rulePayload": "CN",
         "metadata": {"network": "tcp", "host": "",
                      "destinationIP": "120.0.0.5", "destinationPort": "80",
                      "sourceIP": "192.168.6.101", "process": "WeChat"}},
        {"id": "conn-ccc-333", "upload": 8192, "download": 4096,
         "chains": ["JP-TCP-199", "主代理"], "rule": "Match", "rulePayload": "",
         "metadata": {"network": "udp", "host": "api.github.com",
                      "destinationIP": "140.82.0.6", "destinationPort": "443",
                      "sourceIP": "192.168.6.100", "process": "git"}},
    ]
}

RULES = {"rules": [
    {"type": "DomainSuffix", "payload": "google.com", "proxy": "主代理"},
    {"type": "DomainSuffix", "payload": "youtube.com", "proxy": "国外媒体"},
    {"type": "GeoIP", "payload": "CN", "proxy": "DIRECT"},
    {"type": "DomainKeyword", "payload": "github", "proxy": "主代理"},
    {"type": "Match", "payload": "", "proxy": "主代理"},
]}

PROXY_PROVIDERS = {"providers": {
    "default": {"name": "default", "type": "Proxy", "vehicleType": "Compatible",
                "proxies": [{"name": n} for n in PLAIN_PROXIES]},
    "我的机场": {"name": "我的机场", "type": "Proxy", "vehicleType": "HTTP",
              "proxies": [{"name": n} for n in PLAIN_PROXIES],
              "updatedAt": "2026-06-21T10:00:00.000Z",
              "subscriptionInfo": {"Upload": 1073741824, "Download": 53687091200,
                                   "Total": 107374182400, "Expire": 1782000000}},
}}

RULE_PROVIDERS = {"providers": {
    "reject": {"name": "reject", "type": "Rule", "vehicleType": "HTTP",
               "behavior": "domain", "format": "yaml", "ruleCount": 12000,
               "updatedAt": "2026-06-20T08:00:00.000Z"},
    "cncidr": {"name": "cncidr", "type": "Rule", "vehicleType": "File",
               "behavior": "ipcidr", "format": "text", "ruleCount": 9000,
               "updatedAt": "2026-06-19T08:00:00.000Z"},
}}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"   # 支持 chunked 流式 + keep-alive

    def log_message(self, fmt, *args):
        if os.environ.get("MOCK_LOG"):
            sys.stderr.write("[mock] " + (fmt % args) + "\n")
            sys.stderr.flush()

    def _auth_ok(self):
        return self.headers.get("Authorization", "") == "Bearer " + SECRET

    def _send(self, code, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _stream(self, make_line, n=None, interval=0.25):
        if n is None:
            n = STREAM_N
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        try:
            for i in range(n):
                line = (json.dumps(make_line(i)) + "\n").encode("utf-8")
                chunk = ("%X\r\n" % len(line)).encode() + line + b"\r\n"
                self.wfile.write(chunk)
                self.wfile.flush()
                time.sleep(interval)
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _read_body(self):
        ln = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(ln) if ln else b""
        try:
            return json.loads(raw.decode("utf-8")) if raw else {}
        except Exception:
            return {}

    # -------- GET --------
    def do_GET(self):
        if not self._auth_ok():
            return self._send(401, {"message": "unauthorized"})
        u = urlparse(self.path)
        path = unquote(u.path)
        q = parse_qs(u.query)

        if path == "/" :
            return self._send(200, {"hello": "clash.meta"})
        if path == "/version":
            return self._send(200, {"version": "v1.18.0-mock", "meta": True})
        if path == "/configs":
            return self._send(200, CONFIGS)
        if path == "/proxies":
            return self._send(200, build_proxies())
        if path == "/connections":
            # 每次请求让流量增长,便于验证速率计算
            for c in CONNECTIONS["connections"]:
                c["download"] += 120000
                c["upload"] += 8000
            return self._send(200, CONNECTIONS)
        if path == "/rules":
            return self._send(200, RULES)
        if path == "/providers/proxies":
            return self._send(200, PROXY_PROVIDERS)
        if path == "/providers/rules":
            return self._send(200, RULE_PROVIDERS)
        if path == "/dns/query":
            name = (q.get("name", [""])[0])
            return self._send(200, {"Status": 0,
                "Answer": [{"name": name, "type": 1, "TTL": 300, "data": "142.250.72.14"},
                           {"name": name, "type": 1, "TTL": 300, "data": "142.250.72.15"}]})
        if path == "/traffic":
            return self._stream(lambda i: {"up": 1024*(i+1), "down": 1048576*(i+1)})
        if path == "/memory":
            return self._stream(lambda i: {"inuse": 52428800 + i*1048576, "oslimit": 0})
        if path == "/logs":
            lv = ["info", "warning", "info", "error", "debug"]
            return self._stream(lambda i: {"type": lv[i % 5], "payload": "log message #%d" % i})

        # /proxies/{name}/delay
        if path.endswith("/delay") and path.startswith("/proxies/"):
            name = path[len("/proxies/"):-len("/delay")]
            d = node_delay(name)
            if d is None:
                return self._send(503, {"message": "An error occurred in the delay test"})
            return self._send(200, {"delay": d})
        # /group/{name}/delay
        if path.endswith("/delay") and path.startswith("/group/"):
            name = path[len("/group/"):-len("/delay")]
            g = GROUPS.get(name)
            if not g:
                return self._send(404, {"message": "Group not found"})
            res = {}
            for n in g["all"]:
                d = node_delay(n)
                res[n] = d if d is not None else 0
            return self._send(200, res)
        # /proxies/{name}
        if path.startswith("/proxies/"):
            name = path[len("/proxies/"):]
            if name in GROUPS:
                info = GROUPS[name]
                return self._send(200, {"name": name, "type": info["type"],
                                        "all": info["all"], "now": GROUP_NOW.get(name, info["all"][0]),
                                        "history": []})
            if name in PLAIN_PROXIES:
                return self._send(200, {"name": name, "type": "Shadowsocks", "history": []})
            return self._send(404, {"message": "Proxy not found"})
        # /providers/proxies/{name}/healthcheck
        if path.startswith("/providers/proxies/") and path.endswith("/healthcheck"):
            return self._send(204)
        if path.startswith("/providers/proxies/"):
            name = path[len("/providers/proxies/"):]
            pv = PROXY_PROVIDERS["providers"].get(name)
            return self._send(200, pv) if pv else self._send(404, {"message": "not found"})

        return self._send(404, {"message": "not found: " + path})

    # -------- PUT --------
    def do_PUT(self):
        if not self._auth_ok():
            return self._send(401, {"message": "unauthorized"})
        u = urlparse(self.path)
        path = unquote(u.path)
        body = self._read_body()
        if path == "/configs":
            return self._send(204)
        if path.startswith("/proxies/"):
            name = path[len("/proxies/"):]
            if name in GROUPS and "name" in body:
                if body["name"] in GROUPS[name]["all"]:
                    GROUP_NOW[name] = body["name"]
                    return self._send(204)
                return self._send(400, {"message": "node not in group"})
            return self._send(404, {"message": "Proxy not found"})
        if path.startswith("/providers/proxies/"):
            return self._send(204)
        if path.startswith("/providers/rules/"):
            return self._send(204)
        return self._send(404, {"message": "not found"})

    # -------- PATCH --------
    def do_PATCH(self):
        if not self._auth_ok():
            return self._send(401, {"message": "unauthorized"})
        path = unquote(urlparse(self.path).path)
        body = self._read_body()
        if path == "/configs":
            for k in ("mode", "log-level", "allow-lan"):
                if k in body:
                    CONFIGS[k] = body[k]
            return self._send(204)
        return self._send(404, {"message": "not found"})

    # -------- POST --------
    def do_POST(self):
        if not self._auth_ok():
            return self._send(401, {"message": "unauthorized"})
        path = unquote(urlparse(self.path).path)
        if path in ("/cache/fakeip/flush", "/configs/geo", "/restart",
                    "/upgrade", "/upgrade/ui"):
            return self._send(204)
        return self._send(404, {"message": "not found"})

    # -------- DELETE --------
    def do_DELETE(self):
        if not self._auth_ok():
            return self._send(401, {"message": "unauthorized"})
        path = unquote(urlparse(self.path).path)
        if path == "/connections":
            return self._send(204)
        if path.startswith("/connections/"):
            return self._send(204)
        return self._send(404, {"message": "not found"})


if __name__ == "__main__":
    srv = ThreadingHTTPServer((os.environ.get("MOCK_HOST", "127.0.0.1"), PORT), H)
    print("mock clash api on 127.0.0.1:%d (secret=%s)" % (PORT, SECRET), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
