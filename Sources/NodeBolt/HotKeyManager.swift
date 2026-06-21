import Carbon.HIToolbox
import SwiftUI

// 用 Carbon RegisterEventHotKey 注册系统级全局快捷键(无需辅助功能权限)。
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onTrigger: (() -> Void)?

    // 默认 ⌃⌥F
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_F),
                  modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        var handlerRef: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            if let userData = userData {
                let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                mgr.onTrigger?()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        eventHandler = handlerRef

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E424C54), id: 1) // 'NBLT'
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }
}

// 快捷键录制控件:捕获用户按下的组合键
struct KeyRecorder: NSViewRepresentable {
    var onCapture: (UInt32, UInt32, String) -> Void   // keyCode, carbonModifiers, display

    func makeNSView(context: Context) -> RecorderNSView {
        let v = RecorderNSView()
        v.onCapture = onCapture
        return v
    }
    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

final class RecorderNSView: NSView {
    var onCapture: ((UInt32, UInt32, String) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        var disp = ""
        if flags.contains(.control) { disp += "⌃" }
        if flags.contains(.option)  { disp += "⌥" }
        if flags.contains(.shift)   { disp += "⇧" }
        if flags.contains(.command) { disp += "⌘" }
        disp += (event.charactersIgnoringModifiers?.uppercased() ?? "")
        onCapture?(UInt32(event.keyCode), carbon, disp)
    }
}
