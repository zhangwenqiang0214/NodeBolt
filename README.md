# ⚡ NodeBolt

A lightweight, native **macOS menu-bar app** to remotely control **Mihomo / Clash.Meta**
(e.g. **OpenClash** on a router) through its RESTful API — switch nodes, test latency,
manage subscriptions / connections, watch realtime traffic, all from the menu bar.
**No SSH required.**

> 一个轻量的原生 **macOS 菜单栏应用**,通过 RESTful API 远程管理路由器上的
> **Mihomo / OpenClash**:切节点、测延迟、看连接 / 订阅 / 实时流量,全在菜单栏完成,**无需 SSH**。

## 🖥 Requirements / 环境要求

- **系统**:macOS 14 (Sonoma) 或更高
- **CPU**:Universal —— **Apple Silicon(M 系列)与 Intel 均可**
- **内核**:支持 RESTful 外部控制器的 **Mihomo / Clash.Meta**(已在 **v1.19.x** 实测;OpenClash 自带的 Mihomo 内核即可),并已开启外部控制器(API 地址 + Secret)

<!-- 截图占位:docs/ 放入图片后,这里改成 Screenshots 表格 -->

## ✨ Features / 功能

- **节点切换**:菜单栏弹出面板,彩色延迟,点一下即切;搜索 / 收藏置顶 / 排序 / 隐藏超时
- **测速**:整组原生测速(一次请求)、单节点测速、一键切到最快、定时自动测速
- **运行模式**:规则 / 全局 / 直连 一键切换
- **检测页**:GitHub / YouTube / 百度 / QQ 连通性 + 代理出口 IP(ip.sb / ipwho.is / ipapi.is 多源对比,含纯净度/风险)
- **管理窗口**:订阅(更新 / 健康检查)、连接(查看 / 搜索 / 关闭)、**实时监控(流量 / 内存 / 日志)**、DNS 查询、系统维护(GEO / 重启 / 升级)
- **连接档案**:家里 / 公司多套 API 一键切换;配置文件按路径切换
- **系统集成**:可自定义的**全局快捷键**(切最快 / 呼出面板)、开机自启、节点掉线通知、网络变化自动重连
- **菜单栏显示**:仅图标 / 图标+节点名 / 图标+代理网速 / 仅文字 / 完全隐藏

## 📦 Install / 安装

1. Download `NodeBolt.dmg` from the [Releases](../../releases) page.
2. Open it and drag **NodeBolt** into **Applications**.
3. First launch: **right-click the app → Open** (this is an unsigned build, so macOS Gatekeeper needs a one-time bypass).
4. Allow **Local Network** access when prompted (needed to reach your router's API).
5. Click the menu-bar ⚡ → gear → **Settings**, set your **API address** (e.g. `http://192.168.x.x:9090`) and **Secret**.

> 未签名构建,首次打开请**右键 →「打开」**。首次连接路由器会请求「本地网络」权限,允许即可。
> 然后在「设置」里填入你的 API 地址和 Secret。

## 🔧 Build from source / 源码构建

Requires the Swift toolchain (full **Xcode** or just **Command Line Tools**):

```bash
git clone https://github.com/zhangwenqiang0214/NodeBolt.git
cd NodeBolt
./build.sh          # 编译并打包出 dist/NodeBolt.app
./package_dmg.sh    # 生成 dist/NodeBolt.dmg
./run_tests.sh      # 对本地 mock 跑集成测试
```

## 🧪 Tech / 技术

- **SwiftUI + AppKit**, Swift Package Manager
- 仅通过 Mihomo 的 **RESTful API** 通信(不用 SSH)
- 网络层与本地 **mock 服务**做集成测试(`Tests/`)

## 🗺 Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md). 后续迭代:secret 存 Keychain、中英文双语本地化、代码签名+公证分发。

## 📄 License

[MIT](LICENSE) © 2026 zhangwenqiang
