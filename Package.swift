// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NodeBolt",
    platforms: [
        .macOS(.v14)   // MenuBarExtra 需 13+;SettingsLink 需 14+
    ],
    targets: [
        // 纯网络/模型层(无 UI)
        .target(name: "NodeBoltCore"),
        // 菜单栏 App(UI)
        .executableTarget(
            name: "NodeBolt",
            dependencies: ["NodeBoltCore"],
            path: "Sources/NodeBolt"
        ),
        // 集成测试程序(对本地 mock 跑真实 API;不依赖 XCTest,命令行工具即可运行)
        .executableTarget(
            name: "NodeBoltSmoke",
            dependencies: ["NodeBoltCore"],
            path: "Sources/NodeBoltSmoke"
        )
    ]
)
