import AppKit
import SwiftUI

/// ヘッダー下のウィンドウ内ブラー検証。
/// カラフルな縞模様の上にヘッダーを重ね、ヘッダー越しに縞がぼけて見えるかを
/// スクリーンショットで判定する。複数の方式を同時に並べて一発で比較する。

final class TestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 方式A: NSVisualEffectView .withinWindow (.hudWindow)
struct WithinWindowBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .withinWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct StripeContent: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<40, id: \.self) { i in
                Rectangle()
                    .fill([Color.red, .yellow, .green, .cyan, .white][i % 5])
                    .frame(height: 12)
            }
        }
    }
}

struct TestView: View {
    var body: some View {
        HStack(spacing: 8) {
            // 各方式: 縞の上に高さ60のヘッダー候補を重ねる
            testColumn(label: "A:.hudWindow") {
                AnyView(WithinWindowBlur(material: .hudWindow))
            }
            testColumn(label: "B:.popover") {
                AnyView(WithinWindowBlur(material: .popover))
            }
            testColumn(label: "C:ultraThin") {
                AnyView(Rectangle().fill(.ultraThinMaterial))
            }
            testColumn(label: "D:glassEffect") {
                AnyView(Color.clear.glassEffect(.regular, in: Rectangle()))
            }
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .padding(30)
    }

    private func testColumn(label: String, @ViewBuilder header: () -> AnyView) -> some View {
        ZStack(alignment: .top) {
            StripeContent()
            header()
                .frame(height: 60)
                .overlay(Text(label).font(.system(size: 10)).foregroundColor(.black))
        }
        .frame(width: 150, height: 480)
        .clipped()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: TestWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: TestView())
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.isOpaque = false

        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.layer?.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true

        if let targetScreen = NSScreen.screens.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            let f = targetScreen.frame
            window.setFrameOrigin(NSPoint(x: f.midX - 360, y: f.midY - 300))
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
