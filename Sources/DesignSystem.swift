import AppKit
import SwiftUI

/// DESIGN.md のデザインシステム実装。ビューはここのトークンのみを使い、直値を書かない。
/// フェーズ2（Liquid Glass 再スキン・2026-07-06確定）: 素のガラス(glassEffect)+システム外観追従。
/// ウィンドウ背景・角丸・影はすべてシステム標準の.titledウィンドウとglassEffectに任せるため、
/// それらのトークンは持たない（自作タイトルバー時代のトークンは2026-07-07に削除）。
enum DS {
    enum Color {
        /// システム外観に追従（ダークではガラスが暗くなり白文字、ライトでは黒文字）
        static let labelPrimary = SwiftUI.Color.primary
        static let labelSecondary = SwiftUI.Color.secondary
        static let accent = SwiftUI.Color(nsColor: .controlAccentColor)
        static let debugPass = SwiftUI.Color(nsColor: .systemGreen)
        static let debugFail = SwiftUI.Color(nsColor: .systemRed)
        /// 白プレートは白固定・ダーク追従しない(2026-07-10ユーザー指示)。
        /// Figma: ガラス(rgba 255,255,255,0.6)の上に#FEFEFEプレート。中央はほぼ白、
        /// ごく縁の近くだけ下のglassEffectのブラーがふわっと滲む。
        /// RadialGradient(中央から円形)は大画面で不自然だったため、
        /// 「縁がわずかに透ける白ベース + 内側にblurした白コア」の
        /// 縁からの距離ベースのフェードに変更(2026-07-10ユーザー指示)。
        /// 合成後の不透明度: 中央 ≈ base+core×(1-base) ≈ 0.96 / 縁 ≈ 0.78
        static let plateBase = SwiftUI.Color.white.opacity(0.78)
        static let plateCore = SwiftUI.Color.white.opacity(0.82)
        /// ライブ表示カード(Figma #F1F1F1)。白プレート同様、固定色でダーク追従しない
        static let cardFill = SwiftUI.Color(red: 241 / 255, green: 241 / 255, blue: 241 / 255)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let sectionSpacing: CGFloat = 16
        static let windowPadding: CGFloat = 20
        /// ガラス縁のリム幅。白プレートをウィンドウ全辺からこの分だけ内側に敷く(Figma: 8px)
        static let plateInset: CGFloat = 8
        /// 白コア(plateCore)をプレート縁から引っ込める幅。ここがフェード帯になる
        static let plateFadeWidth: CGFloat = 26
        /// 左カラムのフラット行同士の間隔(Figma 5px を実機の読みやすさで拡大・2026-07-10)
        static let rowGap: CGFloat = 8
        /// ジェスチャー群とマクロ群の間の空き
        static let groupGap: CGFloat = 14
        /// ライブ表示カード内の余白
        static let cardPadding: CGFloat = 10
        /// ライブ表示見出しとカードの縦間隔
        static let cardHeadingGap: CGFloat = 12
        /// ライブ表示見出しのカード左端からのインデント
        static let headingIndent: CGFloat = 12
    }

    enum Radius {
        /// 白プレートの角丸。同心円角丸の原則(内側の角丸はウィンドウ外側の角丸−インセット8)。
        /// macOS 26の.titledウィンドウの角丸はcontinuous(squircle)で、カーブ範囲は実測≈28pt。
        /// スクリーンショットの法線距離実測で continuous 16pt がリム幅8ptを
        /// 角でも辺でも均一(7.5〜8.5pt)に見せる(2026-07-10確定)。
        /// 使用側は必ず style: .continuous を指定すること(circularだと角で痩せる)
        static let plate: CGFloat = 16
        /// ライブ表示カードの角丸(Figma: 10px)
        static let card: CGFloat = 10
    }

    enum Blur {
        /// プレート白コアの縁ぼかし。plateFadeWidthの帯の中で白→透けへ滑らかに移る
        static let plateFade: CGFloat = 18
    }

    enum Font {
        static let sectionHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let value = SwiftUI.Font.system(size: 12, design: .monospaced)
        static let caption = SwiftUI.Font.system(size: 11)
        /// メイン画面の行ラベル。Figmaの10ptは実機で小さすぎたため
        /// macOS標準body(13pt)に拡大(2026-07-10ユーザー指示)。trackingはビュー側で付与
        static let rowLabel = SwiftUI.Font.system(size: 13)
        /// カード見出し「タップ座標のライブ表示」(12pt)
        static let cardHeading = SwiftUI.Font.system(size: 12)
        /// ライブ表示カード内の見出し・本文・値(11pt。値はmonospaced維持)
        static let cardBody = SwiftUI.Font.system(size: 11)
        static let cardCaption = SwiftUI.Font.system(size: 11)
        static let cardValue = SwiftUI.Font.system(size: 11, design: .monospaced)
    }

    enum Layout {
        // フェーズ3改2(2026-07-10 実機フィードバック): Figma node 4:179 の比率
        // (縁8pxリム・角丸・左右2カラム・カード余白感)は維持したまま、文字13pt基準に
        // 合わせて全体を約1.27倍にスケールアップ。
        // これはNSWindowのcontentSize(タイトルバーを除く)。unifiedツールバーの
        // タイトルバー66pxが上に足され、ウィンドウ総高は414+66=480(実測)になる。
        // 高さはカード下端(66+20+見出し15+間12+カード340=453)+下余白19+リム8=480で決定
        // (下余白が冗長だったため520→480に詰めた・2026-07-10ユーザー指示)
        static let windowSize = CGSize(width: 700, height: 414)
        static let mainColumnWidth: CGFloat = 310
        /// ライブ表示カードの固定サイズ(プレート内に収め、はみ出し禁止)
        static let liveCardSize = CGSize(width: 264, height: 340)
        /// コンテンツ左端のウィンドウ左端からの距離(Figma x=33 ×1.27≒44)
        static let contentLeading: CGFloat = 44
        /// 左カラム右端とカード左端の間隔。カード右端とプレート右端(x=692)の
        /// 余白が30px(44+310+44+264=662)になるよう決めた値
        static let columnGap: CGFloat = 44
        /// コンテンツ上端のタイトルバー(safe area)下端からの距離
        /// (unifiedツールバー高52px + 20 = 窓上端から72 ≒ Figma y=57 ×1.27)
        static let contentTop: CGFloat = 20
        /// 左カラムのフラット行の高さ
        static let rowHeight: CGFloat = 26
        static let sliderLabelWidth: CGFloat = 140
        static let valueWidth: CGFloat = 56
    }
}

/// 全スライダーで共用する行コンポーネント（DESIGN.md コンポーネント規約）。
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    init(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String = { String(format: "%.2f", $0) }
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        HStack {
            Text(label)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.labelPrimary)
                .frame(width: DS.Layout.sliderLabelWidth, alignment: .leading)
            Slider(value: $value, in: range)
            Text(format(value))
                .font(DS.Font.value)
                .foregroundColor(DS.Color.labelSecondary)
                .frame(width: DS.Layout.valueWidth, alignment: .trailing)
        }
    }
}
