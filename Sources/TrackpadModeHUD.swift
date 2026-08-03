import AppKit
import SwiftUI

/// トラックパッドモードのON/OFF切り替わりを知らせるトースト。フォーカスを奪わず最前面に浮かび、
/// 一定時間で自動的に消える(設定ウィンドウのGlassWindowとは要件が異なるため、非活性化パネルとして独立実装する)。
///
/// デザイン(2026-08-03改訂): macOS標準のシステムHUD/バナー(集中モード切替・AirPods接続時に
/// 画面上部へ出るピル)に寄せる。
/// - 形状は Capsule。システムHUDと同じく「アイコン + 1行ラベル」だけを持つ
/// - 背景は Liquid Glass(.glassEffect(.regular))。トーストは浮遊するナビゲーション層なので
///   ガラスの適用対象として正しい(知見: liquid-glass-design-guideline 原則1)。
///   Capsule の角丸はシェイプ側が持つため同心円則の破綻も起きない
/// - 外観はシステム追従(設定ウィンドウのライト固定とは別。HUDはデスクトップ上に単独で出るため)
/// - **サイズは固定しない**。NSHostingView.fittingSize の実測値でパネルを組むので、
///   日本語「トラックパッドモード OFF」/ 英語 "Trackpad Mode OFF" のどちらでも文字が切れない。
///   サイズが変わるたびに上部中央の原点も再計算する
enum TrackpadModeHUD {
    private static let visibleDuration: TimeInterval = 1.2
    private static let fadeInDuration: TimeInterval = 0.12
    private static let fadeOutDuration: TimeInterval = 0.25
    /// メニューバー下端(visibleFrame上端)からトーストまでの距離。システムHUDの位置感に合わせる
    private static let topMargin: CGFloat = DS.Space.m

    private static var panel: NSPanel?
    private static var generation = 0

    static func flash(active: Bool) {
        if Thread.isMainThread {
            flashOnMain(active: active)
        } else {
            DispatchQueue.main.async { flashOnMain(active: active) }
        }
    }

    private static func flashOnMain(active: Bool) {
        generation += 1
        let myGeneration = generation

        // 文言の長さ(言語・ON/OFF)でサイズが変わるため、毎回ホスティングビューを作り直して実測する
        let hostingView = NSHostingView(rootView: HUDView(isActive: active))
        // NSHostingView のバッキング CALayer は既定で不透明。false にしないと
        // glassEffect のブラー・透過が効かない(知見: swiftui-nshostingview-glasseffect-opaque-layer)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        let fitting = hostingView.fittingSize
        let size = CGSize(width: ceil(fitting.width), height: ceil(fitting.height))
        hostingView.frame = CGRect(origin: .zero, size: size)

        let p = panel ?? makePanel()
        panel = p
        p.contentView = hostingView
        p.setFrame(CGRect(origin: origin(for: size), size: size), display: true)

        if !p.isVisible { p.alphaValue = 0 }
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeInDuration
            p.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration) {
            guard generation == myGeneration, let p = panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeOutDuration
                p.animator().alphaValue = 0
            }, completionHandler: {
                // フェード中に次の切り替えが来ていたら消さない(世代カウンタで判定)
                guard generation == myGeneration else { return }
                p.orderOut(nil)
            })
        }
    }

    /// パネル本体は使い回す。ここの各設定は動作要件(フォーカスを奪わない・マウス操作を邪魔しない・
    /// 全スペースで最前面)に直結するため変更しないこと
    private static func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        // 影はガラス自身が落とすため、ウィンドウ影は使わない(borderlessの矩形影が角の外に出る)
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isMovableByWindowBackground = false
        return p
    }

    /// 表示中スクリーンの上部中央。メニューバーを避けるため visibleFrame を基準にする。
    /// 本アプリは常時バックグラウンドで NSScreen.main(キーウィンドウのスクリーン)が
    /// 作業中のディスプレイと一致しないため、カーソルのいるスクリーンを基準にする
    private static func origin(for size: CGSize) -> CGPoint {
        let screen = screenUnderCursor() ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return .zero }
        return CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - topMargin
        )
    }

    private static func screenUnderCursor() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }
}

/// システムHUD相当の中身: 状態アイコン + 1行ラベル。固定幅を持たず内容でサイズが決まる
private struct HUDView: View {
    let isActive: Bool

    private var label: String {
        isActive
            ? NSLocalizedString("トラックパッドモード ON", comment: "トラックパッドモード切替トースト")
            : NSLocalizedString("トラックパッドモード OFF", comment: "トラックパッドモード切替トースト")
    }

    /// ON=トラックパッド面 / OFF=Magic Mouse。色だけでなく図像でも状態が分かるようにする
    /// (色覚特性・グレースケール環境でも区別できる)
    private var symbol: String {
        isActive ? "rectangle.and.hand.point.up.left.filled" : "magicmouse.fill"
    }

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isActive ? DS.Color.accent : DS.Color.labelSecondary)
                .symbolRenderingMode(.hierarchical)
                // ON/OFFでシンボルの実高が1pt違い、そのままだとトーストの高さが跳ねるため
                // アイコン枠を正方形に固定してカプセル高さを一定(18+12×2=42pt)にする
                .frame(width: 18, height: 18, alignment: .center)
            Text(label)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.labelPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
        .glassEffect(.regular, in: Capsule())
        .fixedSize()
    }
}
