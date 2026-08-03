import SwiftUI

private func notifySettingsChanged() {
    NotificationCenter.default.post(name: .settingsChanged, object: nil)
}

extension View {
    /// @AppStorage の変更をバックエンド（TouchGestureManager / EventInterceptor）へ伝える。
    func notifyOnChange<V: Equatable>(of value: V) -> some View {
        self.onChange(of: value) { _, _ in notifySettingsChanged() }
    }
}

/// フェーズ3（2026-07-10 Figmaプロトタイプ反映）設定画面。DS(DesignSystem)のトークンのみを使い、直値は書かない。
/// メイン画面: 左=主要操作、右=タップ座標のライブ表示(常設)の2カラム。
/// 詳細設定: 「詳細設定」ボタンで内部state切り替えにより遷移する別ページ(単カラム、戻るボタンつき)。
struct SettingsView: View {
    // 一般
    @AppStorage(AppSettings.Key.enabled) private var enabled: Bool = true

    // ジェスチャー
    @AppStorage(AppSettings.Key.oneFingerTapEnabled) private var oneFingerTapEnabled: Bool = true
    @AppStorage(AppSettings.Key.tapAlwaysLeftClick) private var tapAlwaysLeftClick: Bool = false
    @AppStorage(AppSettings.Key.twoFingerTapEnabled) private var twoFingerTapEnabled: Bool = true
    @AppStorage(AppSettings.Key.threeFingerTapEnabled) private var threeFingerTapEnabled: Bool = false
    @ObservedObject private var macroRecorder = MacroRecorder.shared
    @AppStorage(AppSettings.Key.middleClickEnabled) private var middleClickEnabled: Bool = true
    @AppStorage(AppSettings.Key.verticalScrollOnly) private var verticalScrollOnly: Bool = false
    @AppStorage(AppSettings.Key.rightZoneMinX) private var rightZoneMinX: Double = 0.6

    // 反応範囲
    @AppStorage(AppSettings.Key.zoneMinX) private var zoneMinX: Double = 0.0
    @AppStorage(AppSettings.Key.zoneMaxX) private var zoneMaxX: Double = 1.0
    @AppStorage(AppSettings.Key.zoneMinY) private var zoneMinY: Double = 0.75
    @AppStorage(AppSettings.Key.zoneMaxY) private var zoneMaxY: Double = 1.0

    // 感度
    @AppStorage(AppSettings.Key.tapMaxDuration) private var tapMaxDuration: Double = 0.25
    @AppStorage(AppSettings.Key.tapMaxStraightDistance) private var tapMaxStraightDistance: Double = 0.15
    @AppStorage(AppSettings.Key.tapMaxPathLength) private var tapMaxPathLength: Double = 0.18
    @AppStorage(AppSettings.Key.tapMaxVelocity) private var tapMaxVelocity: Double = 4.0
    @AppStorage(AppSettings.Key.tapMinFrames) private var tapMinFrames: Int = 2

    // 誤反応対策
    @AppStorage(AppSettings.Key.scrollVetoWindow) private var scrollVetoWindow: Double = 0.20
    @AppStorage(AppSettings.Key.buttonVetoWindow) private var buttonVetoWindow: Double = 0.10
    @AppStorage(AppSettings.Key.twoFingerSyncWindow) private var twoFingerSyncWindow: Double = 0.08

    // トラッキング速度ブースト
    @AppStorage(AppSettings.Key.pointerSpeedBoost) private var pointerSpeedBoost: Double = 0.0

    // 仮想トラックパッドモード
    @AppStorage(AppSettings.Key.trackpadModeGain) private var trackpadModeGain: Double = 1000.0

    @ObservedObject private var debugFeed = DebugFeed.shared
    @ObservedObject private var trackpadMode = TrackpadModeController.shared
    @State private var showDetailSettings = false
    @State private var zoneDetailExpanded = false

    @State private var tap3ActionKind: BoundActionKind = AppSettings.shared.threeFingerTapAction.isTrackpadToggle ? .trackpadToggle : .macro
    /// トラックパッドモード切替に切り替えた際、録画済みマクロを失わないためのセッション内キャッシュ(3本指用)。
    @State private var cachedTap3MacroAction: ActionKind = {
        if case .macro = AppSettings.shared.threeFingerTapAction {
            return AppSettings.shared.threeFingerTapAction
        }
        return .macro([])
    }()

    /// 3本指タップに割り当てられる ActionKind の種別(設定UI用)。
    private enum BoundActionKind: String, CaseIterable, Identifiable {
        case macro
        case trackpadToggle
        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .macro: return NSLocalizedString("マクロ", comment: "3本指タップの割り当て種別")
            case .trackpadToggle: return NSLocalizedString("トラックパッドモード切替", comment: "3本指タップの割り当て種別")
            }
        }
    }

    /// MacroRecorder のセッションラベル(保存先の確定と録画中の相互排他に使う)
    private static let tap3MacroLabel = "tap3"

    private var tapMinFramesBinding: Binding<Double> {
        Binding(
            get: { Double(tapMinFrames) },
            set: { tapMinFrames = Int($0.rounded()) }
        )
    }

    /// 現在UserDefaultsに保存されているマクロのイベント数(録画セッション外の状態表示用)。
    private var savedMacroEventCount: Int {
        if case .macro(let events) = AppSettings.shared.threeFingerTapAction {
            return events.count
        }
        return 0
    }

    private var isRecordingTap3Macro: Bool {
        macroRecorder.isRecording && macroRecorder.sessionLabel == Self.tap3MacroLabel
    }

    /// 「先端から◯%」表現。zoneMinY=0.75 は先端から25%。
    private var frontDepthBinding: Binding<Double> {
        Binding(
            get: { 1.0 - zoneMinY },
            set: { zoneMinY = 1.0 - $0 }
        )
    }

    var body: some View {
        // タイトルバー・信号機ボタンは標準の.titledウィンドウ(GlassWindow.swift参照)に
        // OSが自動適用する。ここではガラス背景を与えるだけ。
        Group {
            if showDetailSettings {
                detailSettingsPage
            } else {
                mainPage
            }
        }
        // scroll edge effect(タイトルバー下ブラー)はタイトルバー領域に白帯を描くため
        // 無効化(2026-07-07)。ヘッダーまで透けるガラスを優先する。
        // GlassWindowのツールバー不使用とペアの設定(知見: liquid-glass-design-guideline)
        .scrollEdgeEffectHidden(true, for: .top)
        .frame(width: DS.Layout.windowSize.width, height: DS.Layout.windowSize.height)
        // Figma node 4:179 の背景構造(2026-07-10確定): 全面ガラスではなく、
        // ガラスは縁8pxのリムとしてだけ見え、その内側に白プレート(角丸はDS.Plate.radius)を敷く。
        // プレートはタイトルバー領域の下まで届く(ignoresSafeArea)ため、
        // 信号機・タイトルはプレートの上に重なって見える。
        // プレートは白固定。フェードは縁からの距離ベース(2026-07-10改):
        // 縁がわずかに透ける白ベース(plateBase)の上に、縁からplateFadeWidthだけ
        // 引っ込めてblurした白コア(plateCore)を重ねる。中央はほぼ白(≈0.96)、
        // ごく縁の近くだけ下のglassEffectのブラーがふわっと滲む(Figmaの質感)。
        // 角丸はcontinuousでウィンドウ外側の角丸と同心にする(DS.Plate.radius参照)
        .background(
            ZStack {
                SwiftUI.Color.clear
                    .glassEffect(.regular, in: Rectangle())
                RoundedRectangle(cornerRadius: DS.Plate.radius, style: .continuous)
                    .fill(DS.Color.plateBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Plate.radius, style: .continuous)
                            .fill(DS.Color.plateCore)
                            .blur(radius: DS.Plate.fadeBlur)
                            .padding(DS.Plate.fadeWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Plate.radius, style: .continuous))
                    .padding(DS.Plate.inset)
            }
            .ignoresSafeArea()
        )
        // ライブ表示は常時表示化(2026-07-10)にともない、トグルではなくウィンドウの
        // 表示/非表示に連動させる(ページを問わず、開いている間は常にフィード購読)。
        .onAppear { debugFeed.isActive = true }
        .onDisappear { debugFeed.isActive = false }
    }

    // MARK: - メイン画面(2カラム: 左=フラット行の主要操作 / 右=ライブ表示カード常設)
    // Figma node 4:179: Form/Sectionは使わず、白プレートの上に直接置くフラット構成。
    // セクションヘッダー・行背景・グループ枠・説明キャプションは置かない。

    // HStack の spacing は隣接ペアすべてに入るため、末尾に Spacer を置くと columnGap が
    // 2回分(44×2)効いて 328+44+264+44=680 > 636(=700-32-32) になり、はみ出した HStack が
    // 中央寄せされて左右余白が非対称になる(左≈18/右≈62)。子は2つだけに保つこと(2026-07-27)。
    private var mainPage: some View {
        HStack(alignment: .top, spacing: DS.Layout.columnGap) {
            leftColumn
                .frame(width: DS.Layout.mainColumnWidth, alignment: .topLeading)
            liveDisplayPanel
        }
        .padding(.leading, DS.Layout.contentLeading)
        .padding(.trailing, DS.Layout.contentTrailing)
        .padding(.top, DS.Layout.contentTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            toggleRow(NSLocalizedString("有効にする", comment: "メイン設定トグル"), isOn: $enabled)
                .notifyOnChange(of: enabled)
            toggleRow(NSLocalizedString("1本指タップで左/右クリック", comment: "メイン設定トグル"), isOn: $oneFingerTapEnabled)
                .notifyOnChange(of: oneFingerTapEnabled)
            toggleRow(NSLocalizedString("タップは常に左クリック(右クリックは物理クリックのみ)", comment: "メイン設定トグル"), isOn: $tapAlwaysLeftClick)
                .notifyOnChange(of: tapAlwaysLeftClick)
            toggleRow(NSLocalizedString("2本指タップで左クリック", comment: "メイン設定トグル"), isOn: $twoFingerTapEnabled)
                .notifyOnChange(of: twoFingerTapEnabled)
            toggleRow(NSLocalizedString("2本指クリックでミドルクリック", comment: "メイン設定トグル"), isOn: $middleClickEnabled)
                .notifyOnChange(of: middleClickEnabled)
            toggleRow(NSLocalizedString("縦方向のみにスクロール(横スクロール無効)", comment: "メイン設定トグル"), isOn: $verticalScrollOnly)
                .notifyOnChange(of: verticalScrollOnly)

            if !tapAlwaysLeftClick {
                HStack(spacing: DS.Space.s) {
                    // ラベルはSliderに押されて省略(…)されやすいため全文表示を優先する
                    rowLabel(NSLocalizedString("右クリックの開始位置", comment: "メイン設定ラベル"))
                        .fixedSize()
                        .layoutPriority(1)
                    Slider(value: $rightZoneMinX, in: 0...1)
                        .controlSize(.small)
                    Text(String(format: NSLocalizedString("左から%.0f%%", comment: "座標(%)"), rightZoneMinX * 100))
                        .font(DS.Font.value)
                        .foregroundColor(DS.Color.labelSecondary)
                }
                .frame(height: DS.Layout.rowHeight)
                .notifyOnChange(of: rightZoneMinX)
            }

            // ボタンの文法は .bordered 1本に統一し、階層は controlSize だけで表す(2026-07-27)。
            // 「詳細設定」はページ遷移という主要アクションなので regular、録画/クリア等の
            // 副次アクションと周囲のトグル行は small に揃える(.borderedProminent は使わない)。
            HStack {
                Spacer()
                Button(NSLocalizedString("詳細設定", comment: "詳細設定ページへの遷移ボタン")) {
                    showDetailSettings = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            toggleRow(
                tap3ActionKind == .trackpadToggle
                    ? NSLocalizedString("3本指ダブルタップで実行", comment: "メイン設定トグル")
                    : NSLocalizedString("3本指タップで実行", comment: "メイン設定トグル"),
                isOn: $threeFingerTapEnabled)
                .notifyOnChange(of: threeFingerTapEnabled)
                .padding(.top, DS.Space.l)

            Picker(NSLocalizedString("割り当て", comment: "3本指タップの割り当て選択"), selection: $tap3ActionKind) {
                ForEach(BoundActionKind.allCases) { kind in
                    Text(kind.localizedTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            // 周囲のトグル行(すべて .small)と同じリズムに揃える。ここは「詳細設定」より
            // 下位の設定なので、サイズでもそう見せる
            .controlSize(.small)
            .onChange(of: tap3ActionKind) { _, newValue in
                switch newValue {
                case .trackpadToggle:
                    if case .macro = AppSettings.shared.threeFingerTapAction {
                        cachedTap3MacroAction = AppSettings.shared.threeFingerTapAction
                    }
                    AppSettings.shared.threeFingerTapAction = .toggleTrackpadMode
                case .macro:
                    AppSettings.shared.threeFingerTapAction = cachedTap3MacroAction
                }
            }

            if tap3ActionKind == .macro {
                HStack(spacing: DS.Space.s) {
                    Button(isRecordingTap3Macro
                           ? NSLocalizedString("録画を停止して保存", comment: "マクロ録画ボタン")
                           : NSLocalizedString("録画を開始", comment: "マクロ録画ボタン")) {
                        if isRecordingTap3Macro {
                            macroRecorder.stop()
                        } else {
                            macroRecorder.start(label: Self.tap3MacroLabel) { events in
                                AppSettings.shared.threeFingerTapAction = .macro(events)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    // 別の録画セッションが動作中の場合は開始しない(保存先の混線防止)
                    .disabled(macroRecorder.isRecording && !isRecordingTap3Macro)
                    Button(NSLocalizedString("クリア", comment: "マクロクリアボタン")) {
                        macroRecorder.clear()
                        AppSettings.shared.threeFingerTapAction = .macro([])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(macroRecorder.isRecording || savedMacroEventCount == 0)
                }

                Text(isRecordingTap3Macro
                     ? String(format: NSLocalizedString("録画中… %dイベント", comment: "マクロ録画中の件数表示"), macroRecorder.recordedEvents.count)
                     : String(format: NSLocalizedString("登録済み：%dイベント", comment: "マクロ登録済み件数表示"), savedMacroEventCount))
                    .font(DS.Font.caption)
                    .foregroundColor(isRecordingTap3Macro ? DS.Color.debugFail : DS.Color.labelSecondary)
            }
        }
    }

    /// メイン画面のフラット行ラベル。操作行のラベルは詳細設定のSliderRowと同じく
    /// body(13pt)/labelPrimary に統一する(macOSの慣例。labelSecondaryはキャプションと数値表示に限定)。
    private func rowLabel(_ text: String) -> Text {
        Text(text)
            .font(DS.Font.body)
            .foregroundColor(DS.Color.labelPrimary)
    }

    /// 「ラベル左寄せ + スイッチ右端」のフラット行(行高 DS.Layout.rowHeight)。
    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            rowLabel(label)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(DS.Color.accent)
        }
        .frame(height: DS.Layout.rowHeight)
    }

    /// 右カラム: 見出し + グレーカード(DS.Layout.liveCardSize固定・プレート内に収める)。
    /// カード内は上部に指の本数/座標、直近イベント、判定内訳の順でScrollView表示。
    private var liveDisplayPanel: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(NSLocalizedString("タップ座標のライブ表示", comment: "ライブ表示カードの見出し"))
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.labelSecondary)
                .padding(.leading, DS.Space.m)

            ScrollView {
                debugContent
                    .padding(DS.Space.m)
            }
            .scrollContentBackground(.hidden)
            .frame(width: DS.Layout.liveCardSize.width, height: DS.Layout.liveCardSize.height)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(DS.Color.cardFill)
            )
        }
    }

    // MARK: - 詳細設定ページ(単カラム、戻るボタンつき)

    private var detailSettingsPage: some View {
        VStack(spacing: 0) {
            detailHeader
            detailForm
        }
    }

    private var detailHeader: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                showDetailSettings = false
            } label: {
                // アイコンはページ見出しと同格(13pt/semibold)に揃える
                Image(systemName: "chevron.left")
                    .font(DS.Font.pageTitle)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(NSLocalizedString("詳細設定", comment: "詳細設定ページの見出し"))
                .font(DS.Font.pageTitle)
                .foregroundColor(DS.Color.labelPrimary)

            Spacer()
        }
        // 下の Form(.grouped) のセクション見出し・行の実効インセット
        // (DS.Layout.formBuiltInInset=30) は formInsetCompensation で contentLeading まで
        // 押し出してあるので、ヘッダーも同じ値を使えば戻るボタンの枠の左端が
        // セクション見出し・行ラベル・メイン画面の行ラベルと同じ 32pt に揃う
        // (@2xキャプチャの画素実測で確認・2026-07-28)
        .padding(.leading, DS.Layout.contentLeading)
        .padding(.trailing, DS.Layout.contentTrailing)
        // 上余白はメイン画面と同じ contentTop(8)。ページ種別ごとにトークンを分けず1本に統一
        .padding(.top, DS.Layout.contentTop)
        .padding(.bottom, DS.Space.xs)
    }

    private var detailForm: some View {
        Form {
            Section(header: sectionHeader(NSLocalizedString("タップに反応する範囲", comment: "詳細設定セクション見出し"))) {
                // 値カラムは「数値+単位」だけに保つ(方向はラベルが持っている)。
                // ローカライズ不要な純数値フォーマットにして、どの言語でも1行に収める(2026-07-28)
                SliderRow(NSLocalizedString("先端側の反応範囲", comment: "詳細設定スライダーラベル"), value: frontDepthBinding, range: 0.05...1.0) {
                    String(format: "%.0f%%", $0 * 100)
                }
                .notifyOnChange(of: zoneMinY)
                caption(NSLocalizedString("マウス表面の先端(指先側)からこの割合までをタップに反応させます。初期値は25%です", comment: "詳細設定キャプション"))

                Toggle(NSLocalizedString("詳細設定を表示", comment: "反応範囲の詳細表示トグル"), isOn: $zoneDetailExpanded)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(DS.Color.accent)
                if zoneDetailExpanded {
                    SliderRow(NSLocalizedString("左右: 左端", comment: "詳細設定スライダーラベル"), value: $zoneMinX, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                        .notifyOnChange(of: zoneMinX)
                    SliderRow(NSLocalizedString("左右: 右端", comment: "詳細設定スライダーラベル"), value: $zoneMaxX, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                        .notifyOnChange(of: zoneMaxX)
                    SliderRow(NSLocalizedString("前後: 手前端", comment: "詳細設定スライダーラベル"), value: $zoneMinY, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                        .notifyOnChange(of: zoneMinY)
                    SliderRow(NSLocalizedString("前後: 先端", comment: "詳細設定スライダーラベル"), value: $zoneMaxY, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                        .notifyOnChange(of: zoneMaxY)
                    caption(NSLocalizedString("0%=左端・手前(手首側)、100%=右端・先端(指先側)。「前後: 手前端」は上の「先端側の反応範囲」と連動します", comment: "詳細設定キャプション"))
                    Button(NSLocalizedString("反応範囲を初期設定に戻す", comment: "リセットボタン")) {
                        AppSettings.shared.resetZoneToDefaults()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Section(header: sectionHeader(NSLocalizedString("タップ判定のきびしさ", comment: "詳細設定セクション見出し"))) {
                SliderRow(NSLocalizedString("タップの最長時間", comment: "詳細設定スライダーラベル"), value: $tapMaxDuration, range: 0.05...0.5) { String(format: NSLocalizedString("%.2f秒", comment: "秒数"), $0) }
                    .notifyOnChange(of: tapMaxDuration)
                SliderRow(NSLocalizedString("位置ズレの許容量", comment: "詳細設定スライダーラベル"), value: $tapMaxStraightDistance, range: 0.01...0.3) { String(format: "%.2f", $0) }
                    .notifyOnChange(of: tapMaxStraightDistance)
                SliderRow(NSLocalizedString("動きの合計の許容量", comment: "詳細設定スライダーラベル"), value: $tapMaxPathLength, range: 0.01...0.3) { String(format: "%.2f", $0) }
                    .notifyOnChange(of: tapMaxPathLength)
                SliderRow(NSLocalizedString("動きの速さの許容量", comment: "詳細設定スライダーラベル"), value: $tapMaxVelocity, range: 0.2...8.0) { String(format: "%.1f", $0) }
                    .notifyOnChange(of: tapMaxVelocity)
                SliderRow(NSLocalizedString("最短の接触フレーム数", comment: "詳細設定スライダーラベル"), value: tapMinFramesBinding, range: 1...10) { String(format: "%.0f", $0) }
                    .notifyOnChange(of: tapMinFrames)
                caption(NSLocalizedString("それぞれ右に動かすほど反応しやすくなります(最短接触フレーム数のみ左に動かすほど反応しやすい)。反応しやすいほどスクロールとの誤反応は増えます", comment: "詳細設定キャプション"))
                Button(NSLocalizedString("タップ判定を初期設定に戻す", comment: "リセットボタン")) {
                    AppSettings.shared.resetSensitivityToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Section(header: sectionHeader(NSLocalizedString("誤反応の防止", comment: "詳細設定セクション見出し"))) {
                SliderRow(NSLocalizedString("スクロール後の待ち時間", comment: "詳細設定スライダーラベル"), value: $scrollVetoWindow, range: 0...1.0) { String(format: NSLocalizedString("%.2f秒", comment: "秒数"), $0) }
                    .notifyOnChange(of: scrollVetoWindow)
                SliderRow(NSLocalizedString("クリック後の待ち時間", comment: "詳細設定スライダーラベル"), value: $buttonVetoWindow, range: 0...0.5) { String(format: NSLocalizedString("%.2f秒", comment: "秒数"), $0) }
                    .notifyOnChange(of: buttonVetoWindow)
                SliderRow(NSLocalizedString("2本指の同時判定時間", comment: "詳細設定スライダーラベル"), value: $twoFingerSyncWindow, range: 0.02...0.2) { String(format: NSLocalizedString("%.2f秒", comment: "秒数"), $0) }
                    .notifyOnChange(of: twoFingerSyncWindow)
                caption(NSLocalizedString("スクロールや物理クリックの直後は、この時間だけタップを無視して誤クリックを防ぎます。2本指の同時判定時間は、2本の指のタッチ開始がこの時間内に収まったとき2本指タップとみなす設定です", comment: "詳細設定キャプション"))
                Button(NSLocalizedString("誤反応の防止を初期設定に戻す", comment: "リセットボタン")) {
                    AppSettings.shared.resetVetoToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Section(header: sectionHeader(NSLocalizedString("カーソル速度ブースト", comment: "詳細設定セクション見出し"))) {
                SliderRow(NSLocalizedString("軌跡の速さ", comment: "詳細設定スライダーラベル"), value: $pointerSpeedBoost, range: 0...9.0) {
                    $0 <= 0 ? NSLocalizedString("オフ", comment: "カーソル速度ブーストのオフ表示") : String(format: "x%.1f", $0)
                }
                .notifyOnChange(of: pointerSpeedBoost)
                caption(NSLocalizedString("システム設定の上限(3.0)を超えてカーソルの軌跡速度を上げます。オフにする、またはアプリを終了すると元の速度に戻ります。システム設定の「マウス」を開くと一時的に上書きされることがあります", comment: "詳細設定キャプション"))
            }

            Section(header: sectionHeader(NSLocalizedString("トラックパッドモード", comment: "詳細設定セクション見出し"))) {
                SliderRow(NSLocalizedString("移動ゲイン", comment: "詳細設定スライダーラベル"), value: $trackpadModeGain, range: 200...3000) { String(format: "%.0f", $0) }
                    .notifyOnChange(of: trackpadModeGain)
                caption(NSLocalizedString("マウス表面のなぞりをカーソル移動に変換する際の倍率です。3本指ダブルタップ、または下のボタンでモードのON/OFFを切り替えます", comment: "詳細設定キャプション"))
                Button(trackpadMode.isActive
                       ? NSLocalizedString("今すぐOFFにする", comment: "トラックパッドモード切替ボタン")
                       : NSLocalizedString("今すぐONにする", comment: "トラックパッドモード切替ボタン")) {
                    TrackpadModeController.shared.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Section {
                Button(NSLocalizedString("すべての設定を既定値に戻す", comment: "全設定リセットボタン")) {
                    AppSettings.shared.resetAllToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Form(.grouped) のセクション見出しが持つ左右インセット(formBuiltInInset)を、
        // メイン画面と同じ contentLeading/Trailing まで押し出す(Form の構造自体は変えない)
        .padding(.horizontal, DS.Layout.formInsetCompensation)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.Font.sectionHeader)
            .foregroundColor(DS.Color.labelSecondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.caption)
            .foregroundColor(DS.Color.labelSecondary)
    }

    /// ライブ表示カードの中身(11pt/secondary基調・値はmonospaced)。
    /// 上部=指の本数(左)+座標(右)、中央=直近イベント、下部=判定内訳。
    private var debugContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text(String(format: NSLocalizedString("指の本数：%d", comment: "ライブ表示: 指の本数"), debugFeed.currentFingerCount))
                Spacer()
                Text(String(format: NSLocalizedString("左から%.0f%% 手前から%.0f%%", comment: "座標(%)"),
                            debugFeed.latestTouchX * 100, debugFeed.latestTouchY * 100))
            }
            .font(DS.Font.caption)
            .foregroundColor(DS.Color.labelSecondary)

            Divider()

            Text(NSLocalizedString("直近のイベント", comment: "ライブ表示見出し"))
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.labelSecondary)
            ForEach(debugFeed.recentEvents) { event in
                Text(event.text)
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.labelPrimary)
            }

            Divider()

            Text(NSLocalizedString("直近のタップ試行の判定内訳", comment: "ライブ表示見出し"))
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.labelSecondary)
            if debugFeed.lastAttempt.isEmpty {
                Text(NSLocalizedString("(まだ試行なし)", comment: "ライブ表示: 判定内訳が空のときの表示"))
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.labelSecondary)
            } else {
                ForEach(debugFeed.lastAttempt) { condition in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack(spacing: DS.Space.xs) {
                            Text(condition.passed ? "✓" : "✗")
                                .font(DS.Font.caption)
                                .foregroundColor(condition.passed ? DS.Color.debugPass : DS.Color.debugFail)
                            Text(condition.label)
                                .font(DS.Font.caption)
                                .foregroundColor(DS.Color.labelPrimary)
                        }
                        Text("\(condition.actual) / \(condition.threshold)")
                            .font(DS.Font.value)
                            .foregroundColor(DS.Color.labelSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
