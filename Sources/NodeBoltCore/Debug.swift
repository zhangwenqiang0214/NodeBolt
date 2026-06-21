import Foundation

// 设置环境变量 NODEBOLT_DEBUG=1 时,把诊断信息打到标准错误(终端可见)。
public func nbDebug(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["NODEBOLT_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data(("‹NodeBolt› " + message() + "\n").utf8))
}
