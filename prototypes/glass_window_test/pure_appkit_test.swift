import AppKit

/// Attempt 7: SwiftUIを一切介さない純粋AppKitでのNSVisualEffectView単体テスト。
/// これでもブラーがかからなければ、原因はSwiftUI側ではなくAppKit/システム側にあると確定できる。

final class PlainWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PlainWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = PlainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear

        let effectView = NSVisualEffectView(frame: window.contentView!.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 20
        effectView.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "Pure AppKit NSVisualEffectView Test")
        label.font = .boldSystemFont(ofSize: 16)
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 150, width: 340, height: 40)
        label.autoresizingMask = [.width]

        effectView.addSubview(label)
        window.contentView = effectView

        if let targetScreen = NSScreen.screens.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            let screenFrame = targetScreen.frame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
