import AppKit
import SwiftUI

/// トラックパッドモード中であることを示す軽量HUD。フォーカスを奪わず常に最前面に浮かぶ
/// (設定ウィンドウのGlassWindowとは要件が異なるため、非活性化パネルとして独立実装する)。
enum TrackpadModeHUD {
    private static var panel: NSPanel?

    static func show() {
        if Thread.isMainThread {
            showOnMain()
        } else {
            DispatchQueue.main.async { showOnMain() }
        }
    }

    static func hide() {
        if Thread.isMainThread {
            hideOnMain()
        } else {
            DispatchQueue.main.async { hideOnMain() }
        }
    }

    private static func showOnMain() {
        if panel == nil {
            let content = HUDView()
            let hosting = NSHostingView(rootView: content)
            hosting.frame = CGRect(origin: .zero, size: CGSize(width: 200, height: 44))

            let p = NSPanel(
                contentRect: hosting.frame,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.contentView = hosting

            if let screenFrame = NSScreen.main?.frame {
                let origin = CGPoint(
                    x: screenFrame.midX - hosting.frame.width / 2,
                    y: screenFrame.maxY - hosting.frame.height - 40
                )
                p.setFrameOrigin(origin)
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    private static func hideOnMain() {
        panel?.orderOut(nil)
    }
}

private struct HUDView: View {
    var body: some View {
        HStack(spacing: DS.Space.s) {
            Circle()
                .fill(DS.Color.accent)
                .frame(width: 8, height: 8)
            Text("トラックパッドモード beta")
                .font(DS.Font.body)
                .foregroundColor(DS.Color.labelPrimary)
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
