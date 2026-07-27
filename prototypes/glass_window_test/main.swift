import AppKit
import SwiftUI

/// フェーズ2最大の未知数（仕様書v2 難所#6/#7）を単独検証するための最小プロトタイプ。
///
/// Attempt 1 (glassEffect + borderless透明ウィンドウ) は実機で失敗:
/// ウィンドウが単なる不透明グレーの箱になり、背後が一切透けなかった。
/// このAttempt 2はフォールバック方針(仕様書v2で規定済み)を検証する:
/// NSVisualEffectView(.hudWindow) + 白ティントオーバーレイ。

final class GlassTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// AppKitのNSVisualEffectViewをSwiftUIから使うためのブリッジ
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct GlassTestView: View {
    var body: some View {
        // Attempt 5: Appleの想定する素直な使い方。
        // 手動でRoundedRectangle+.fill(.clear)+overlayを重ねるのではなく、
        // コンテンツ本体に直接 .glassEffect() を掛け、shapeの生成・背景合成は
        // モディファイア自身に任せる(WWDC24サンプルの標準パターン)。
        VStack(spacing: 16) {
            Text("Glass Window Prototype (Attempt 9: SwiftUI側shadow)")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("この文字が乳白ガラスの上に読めていればOK\n背後の壁紙・動画がうっすら透けているか確認")
                .font(.callout)
                .multilineTextAlignment(.center)
            Toggle("ダミートグル", isOn: .constant(true))
                .toggleStyle(.switch)
            Slider(value: .constant(0.5))
            Button("閉じる") { NSApp.terminate(nil) }
        }
        .padding(32)
        .frame(width: 320)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        // ウィンドウ影(hasShadow)は透明ウィンドウだと矩形の輪郭線が出るためOFFにし、
        // 影はSwiftUI側でガラス形状そのものに付ける。外周paddingは影の描画領域。
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .padding(30)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: GlassTestWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: GlassTestView())
        // NSHostingController の view はデフォルトで不透明な背景を持つため、
        // ウィンドウ側の isOpaque=false / backgroundColor=.clear だけでは効かない。
        // ここを明示的に透明化しないとガラス効果の有無を判定できない(今回のハマりどころ)。
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        // 本命の修正: CALayerはデフォルトでisOpaque=trueのため、backgroundColorをclearにしても
        // コンポジタがアルファを無視して不透明前提で合成してしまう(今回の根本原因)。
        hosting.view.layer?.isOpaque = false
        // Attempt 8: .borderless に回帰。
        // ブラーが効かなかった真因は CALayer.isOpaque(解決済み)であり、.titled構成は
        // デバッグ中の暫定だった。.titledはウィンドウ自身がフレーム(タイトルバー領域の縁)を
        // 描くため、SwiftUIのガラス形状の上端に黒い線・二重輪郭として残ってしまう
        // (titlebarSeparatorStyle = .none でも消えない)。ウィンドウ自身が何も描かない
        // .borderless に戻し、形状の描画をSwiftUI側に一元化する。
        let window = GlassTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.layer?.isOpaque = false
        // 透明ウィンドウ + glassEffect では影の形状が矩形のまま計算され「四隅の尖った
        // 黒い輪郭線」になる(難所#6、実機確認済み。invalidateShadow()でも解消せず)。
        // ウィンドウ影は使わず、SwiftUI側で .shadow をガラス形状に直接付ける方式にする。
        window.hasShadow = false
        window.isMovableByWindowBackground = true

        // マルチディスプレイ環境で center() が非メインの(内蔵/オフの)画面を
        // 使ってしまうことがあるため、最も解像度の大きい画面を明示的に選んで中央配置する。
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
