import AppKit
import SwiftUI

/// DESIGN.md のデザインシステム実装。ビューはここのトークンのみを使い、直値を書かない。
/// フェーズ2（Liquid Glass 再スキン・2026-07-06確定）: 素のガラス(glassEffect)+システム外観追従。
/// ウィンドウ背景・角丸・影はすべてシステム標準の.titledウィンドウとglassEffectに任せるため、
/// それらのトークンは持たない（自作タイトルバー時代のトークンは2026-07-07に削除）。
///
/// トークン規約(2026-07-27 整理):
/// - 同じ役割には必ず同じトークン。役割ごとの階段は1本だけ持ち、重複トークンを作らない
/// - スペーシングは 4/8 グリッド(DS.Space)から外れた値を使わない
///   （例外はプレート幾何 DS.Plate。実測で決めた値なので触らない）
/// - ウェイトは .regular と .semibold のみ（.medium は使わない）
/// - 影は使わない。角丸のグラマーを混ぜない。アクセント色は DS.Color.accent の1色のみ
enum DS {
    enum Color {
        /// システム外観に追従（ダークではガラスが暗くなり白文字、ライトでは黒文字）
        static let labelPrimary = SwiftUI.Color.primary
        static let labelSecondary = SwiftUI.Color.secondary
        /// アプリ唯一のアクセント色。明示的に .tint する対象は Toggle のみとする
        /// （他のコントロールには .tint を付けない。システムアクセントと同値なので
        /// 付けても見た目は変わらないが、規約として付ける場所を1種類に固定する）
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

    /// 汎用スペーシング。4/8 グリッドのこの階段だけを使い、用途ごとの一点物を増やさない
    /// (2026-07-27: rowGap 8→s / groupGap 14→l / cardPadding 10→m /
    ///  cardHeadingGap 12→m / headingIndent 12→m に統合)。
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// 白プレートの幾何。**触るな**: ウィンドウ角丸・ガラスリム幅に対して
    /// スクリーンショット実測で決めた値で、4/8グリッドの対象外(2026-07-10確定)。
    /// 変えると縁のリム幅が角で痩せたりフェード帯が破綻する。
    enum Plate {
        /// ガラス縁のリム幅。白プレートをウィンドウ全辺からこの分だけ内側に敷く(Figma: 8px)
        static let inset: CGFloat = 8
        /// 白コア(plateCore)をプレート縁から引っ込める幅。ここがフェード帯になる
        static let fadeWidth: CGFloat = 26
        /// 白コアの縁ぼかし。fadeWidthの帯の中で白→透けへ滑らかに移る
        static let fadeBlur: CGFloat = 18
        /// 白プレートの角丸。同心円角丸の原則(内側の角丸はウィンドウ外側の角丸−インセット8)。
        /// macOS 26の.titledウィンドウの角丸はcontinuous(squircle)で、カーブ範囲は実測≈28pt。
        /// スクリーンショットの法線距離実測で continuous 16pt がリム幅8ptを
        /// 角でも辺でも均一(7.5〜8.5pt)に見せる(2026-07-10確定)。
        /// 使用側は必ず style: .continuous を指定すること(circularだと角で痩せる)
        static let radius: CGFloat = 16
    }

    enum Radius {
        /// ライブ表示カード・HUD の角丸(Figma: 10px)。アプリ内の角丸はプレート幾何を除きこの1種類
        static let card: CGFloat = 10
    }

    /// タイポグラフィの階段(2026-07-27に9→5トークンへ圧縮)。ウェイトは regular / semibold のみ。
    enum Font {
        /// ページ見出し「詳細設定」。ページ内で最上位の見出し。戻るボタンのアイコンにも使う
        static let pageTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// セクション/カラムの見出し(詳細設定の Section ヘッダー、ライブ表示カードの見出し)
        static let sectionHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// 操作行のラベル・HUD本文。macOS標準のbodyサイズ(Figmaの10ptは実機で小さすぎたため
        /// 13ptに拡大・2026-07-10ユーザー指示)。色は labelPrimary を使う
        static let body = SwiftUI.Font.system(size: 13)
        /// 補足キャプション・ライブ表示カード内の本文。色は labelSecondary を使う
        static let caption = SwiftUI.Font.system(size: 11)
        /// 数値表示(スライダーの値・ライブ表示の実測値)。桁の揺れを抑えるため monospaced
        static let value = SwiftUI.Font.system(size: 12, design: .monospaced)
    }

    enum Layout {
        // フェーズ3改2(2026-07-10 実機フィードバック): Figma node 4:179 の比率
        // (縁8pxリム・角丸・左右2カラム・カード余白感)は維持したまま、文字13pt基準に
        // 合わせて全体を約1.27倍にスケールアップ。
        // これはNSWindowのcontentSize(タイトルバーを除く)。unifiedツールバーの
        // タイトルバー66pxが上に足され、ウィンドウ総高は392+66=458(実測)になる。
        // 高さはカード下端(contentTop 8+見出し15+間12+カード340=375)+下余白9+リム8=392で決定。
        // contentTop を 20→8 に詰めた分(12)に加え、下が余って下重心に見えないよう
        // さらに12詰めて上下の視覚的な釣り合いを取った(414→392・2026-07-28実機フィードバック)
        static let windowSize = CGSize(width: 700, height: 392)
        /// コンテンツ左右の余白。左右対称にするため両辺で同じ値を使う(2026-07-27)。
        /// 全体が広く見えるとの実機フィードバックで 40→32 に詰めた(2026-07-28)。
        /// 内訳: 32 + mainColumnWidth 328 + columnGap 44 + カード幅 264 + 32 = 700
        static let contentLeading: CGFloat = Space.xxl
        static let contentTrailing: CGFloat = Space.xxl
        static let mainColumnWidth: CGFloat = 328
        /// ライブ表示カードの固定サイズ(プレート内に収め、はみ出し禁止)
        static let liveCardSize = CGSize(width: 264, height: 340)
        /// 左カラム右端とカード左端の間隔。左右余白を contentLeading/Trailing = 32 の
        /// 対称にした上で、残り(700-32-32-264=372)を左カラム328とこの44に配分している
        static let columnGap: CGFloat = 44
        /// コンテンツ上端のタイトルバー(safe area)下端からの距離。メイン/詳細設定の両ページで共用。
        /// 20→8 に統一(2026-07-28 実機フィードバック: 見出しとウィンドウ上辺の間が広すぎる)。
        /// Space.s(8) まで詰めても、unifiedツールバー(52pt)の下端から
        /// 8 + 行高(≈16〜20) でコンテンツ中心が下端から十分離れるためタイトルバーには
        /// 食い込まない(実ビルドのキャプチャで確認)。Space.xs(4)まで詰めると詳細設定の
        /// 戻るボタン(.small/高さ≈20pt)の上端がタイトルバー境界に接近しすぎるため 8 を採用
        static let contentTop: CGFloat = Space.s
        /// SwiftUI の Form(.formStyle(.grouped)) が内部で持つ左右インセットの実測値。
        /// macOS 26・幅700ptのウィンドウを @2x キャプチャして画素実測(2026-07-28):
        /// - セクション見出しテキスト: 左端 30pt
        /// - グループカード内の行の中身(ラベル・キャプション): 左端 30pt(見出しと同値)
        /// - グループカードの背景矩形そのもの: 左端 20pt(＝見出し・行より 10pt 外側)
        /// つまり基準にできるのは「見出しと行が共有する 30」。カード背景だけは常に
        /// 10pt 外へはみ出す(Form の仕様。ここを揃えたい場合は Form 以外の構造が要る)。
        /// Form の構造を変えずに見出し・行の左右端を contentLeading/Trailing に合わせるための基準値
        static let formBuiltInInset: CGFloat = 30
        /// 上記を打ち消して詳細設定ページの左右端をメイン画面と揃えるための追加パディング
        static let formInsetCompensation: CGFloat = contentLeading - formBuiltInInset
        /// 操作行の高さ。メイン画面のフラット行と詳細設定の SliderRow で共用し、
        /// 折り返しの有無で行高が揺れないよう機械的に固定する(2026-07-28)
        static let rowHeight: CGFloat = 26
        /// SliderRow のラベル列幅。lineLimit(1) で固定するため、最長ラベルが
        /// 省略(…)されない幅が要る。NSFont.systemFont(13) 実測の最長は
        /// en "2-finger simultaneity window" = 175.2pt(ja 最長は「スクロール後の待ち時間」132.0pt)。
        /// 8グリッドで直上の 176 を採用(2026-07-28 実測)
        static let sliderLabelWidth: CGFloat = 176
        /// SliderRow の値列幅。値は「数値+単位」だけに保ち、方向の修飾語はラベルに任せる。
        /// monospacedSystemFont(12) 実測の最長は en "0.25 sec" = 59.3pt
        /// (ja 最長は「0.25秒」42.3pt)。8グリッドで直上の 64 を採用(2026-07-28 実測)。
        /// 行内訳: 176 + 8 + slider 380 + 8 + 64 = 636 (= 700 - contentLeading/Trailing 32×2)
        /// ※実際の行はさらにカード内側パディング分だけ狭まるが、可変幅の slider が吸収する
        static let valueWidth: CGFloat = 64
    }
}

/// 全スライダーで共用する行コンポーネント（DESIGN.md コンポーネント規約）。
/// 行高は必ず DS.Layout.rowHeight に固定し、ラベル・値は lineLimit(1)。
/// 値カラムが折り返すとその行だけ背が高くなり、セクション間で行のリズムが崩れるため
/// (2026-07-28 ユーザー指摘: 「タップに反応する範囲」だけ行が広い)。
/// → 値の書式は「数値+単位」だけにし、方向の修飾語(先端から/手前から)はラベル側に持たせる。
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
                .controlSize(.small)
            Text(format(value))
                .font(DS.Font.value)
                .foregroundColor(DS.Color.labelSecondary)
                .frame(width: DS.Layout.valueWidth, alignment: .trailing)
        }
        .lineLimit(1)
        .frame(height: DS.Layout.rowHeight)
    }
}
