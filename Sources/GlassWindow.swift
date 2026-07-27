import AppKit
import SwiftUI

/// Liquid Glass 用のウィンドウ。
///
/// 設計方針(2026-07-06確定): Appleの公式サンプル(Landmarks: Building an app with
/// Liquid Glass)はタイトルバー・信号機ボタン・ツールバー下のブラーを一切自作せず、
/// 標準ウィンドウにOSが自動適用するものをそのまま使っている。borderlessで
/// タイトルバーを自作する方式は信号ボタンの位置・ホバー・非アクティブ挙動・
/// スクロールブラーをすべて手で再現する羽目になり破綻した(コミット履歴参照)。
///
/// よって「標準の .titled ウィンドウ + 透明タイトルバー + fullSizeContentView」とし、
/// - 信号機ボタン: システム標準(位置・ホバーグリフ・非アクティブ挙動すべて自動)
/// - タイトル表示・ドラッグ移動: システム標準
/// - scroll edge effect(タイトルバー下ブラー)は**使わない**(2026-07-07改訂):
///   ツールバー+エッジ効果はタイトルバー領域に不透明な白帯を描き、ヘッダーまで透ける
///   ガラスにならないため。SettingsView側の .scrollEdgeEffectHidden(true, for: .top) と対。
///   ツールバーをこのウィンドウに再導入する場合は SettingsView 側も必ず見直すこと。
/// ガラス表現だけをSwiftUI側の背景(glassEffect)で与える。
///
/// 透明化の必須設定(実機検証済み・知見ノート swiftui-nshostingview-glasseffect-opaque-layer):
/// NSHostingView のバッキング CALayer は既定で isOpaque=true のため、
/// 明示的に false にしないと glassEffect のブラー・透過が一切効かない。
final class GlassWindow: NSWindow {
    /// SwiftUI ビューをホストするガラスウィンドウを生成する。
    /// CALayer.isOpaque罠対策の3点セット。backgroundColor=.clearだけでは
    /// レイヤーが不透明のまま合成され、glassEffectのブラー・透過が効かない
    private static func makeLayerTransparent(_ view: NSView?) {
        view?.wantsLayer = true
        view?.layer?.backgroundColor = NSColor.clear.cgColor
        view?.layer?.isOpaque = false
    }

    static func make<Content: View>(rootView: Content, title: String, contentSize: CGSize) -> GlassWindow {
        let hosting = NSHostingController(rootView: rootView)
        makeLayerTransparent(hosting.view)

        let window = GlassWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.setContentSize(contentSize)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // 背景は白プレート固定のため、ウィンドウ全体をライト外観に固定する
        // (2026-07-10ユーザー指示)。ダークモード環境でもタイトル文字・信号機・
        // SwiftUI側のセマンティックカラー(Color.primary等)がライトで描画される
        window.appearance = NSAppearance(named: .aqua)
        // タイトル行の位置合わせ(2026-07-10): 標準タイトルバー(高さ28・信号機上インセット9)
        // では信号機とタイトルがプレート上端(y=8)に張り付いてFigmaより上に寄る。
        // 空のunifiedツールバーでタイトルバーを52pxにし、信号機・タイトル中心を
        // y≈26に下げてFigma(タイトル行中心y=28〜30)の見え方に合わせる。
        // ※空NSToolbarの白帯問題(2026-07-07)は「ヘッダーまで透けるガラス」構成での話。
        //   現構成はタイトルバー下が白プレートなので白帯は同化して問題にならない
        //   (SettingsView側の .scrollEdgeEffectHidden(true, for: .top) は維持)
        let toolbar = NSToolbar()
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isOpaque = false
        window.backgroundColor = .clear
        makeLayerTransparent(window.contentView)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        return window
    }
}
