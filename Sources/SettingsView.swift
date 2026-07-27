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
        case macro = "マクロ"
        case trackpadToggle = "トラックパッドモード切替"
        var id: String { rawValue }
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
        // ガラスは縁8pxのリムとしてだけ見え、その内側に白プレート(角丸はDS.Radius.plate)を敷く。
        // プレートはタイトルバー領域の下まで届く(ignoresSafeArea)ため、
        // 信号機・タイトルはプレートの上に重なって見える。
        // プレートは白固定。フェードは縁からの距離ベース(2026-07-10改):
        // 縁がわずかに透ける白ベース(plateBase)の上に、縁からplateFadeWidthだけ
        // 引っ込めてblurした白コア(plateCore)を重ねる。中央はほぼ白(≈0.96)、
        // ごく縁の近くだけ下のglassEffectのブラーがふわっと滲む(Figmaの質感)。
        // 角丸はcontinuousでウィンドウ外側の角丸と同心にする(DS.Radius.plate参照)
        .background(
            ZStack {
                SwiftUI.Color.clear
                    .glassEffect(.regular, in: Rectangle())
                RoundedRectangle(cornerRadius: DS.Radius.plate, style: .continuous)
                    .fill(DS.Color.plateBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.plate, style: .continuous)
                            .fill(DS.Color.plateCore)
                            .blur(radius: DS.Blur.plateFade)
                            .padding(DS.Space.plateFadeWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.plate, style: .continuous))
                    .padding(DS.Space.plateInset)
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

    private var mainPage: some View {
        HStack(alignment: .top, spacing: DS.Layout.columnGap) {
            leftColumn
                .frame(width: DS.Layout.mainColumnWidth, alignment: .topLeading)
            liveDisplayPanel
            Spacer(minLength: 0)
        }
        .padding(.leading, DS.Layout.contentLeading)
        .padding(.top, DS.Layout.contentTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: DS.Space.rowGap) {
            toggleRow("有効にする", isOn: $enabled)
                .notifyOnChange(of: enabled)
            toggleRow("1本指タップで左/右クリック", isOn: $oneFingerTapEnabled)
                .notifyOnChange(of: oneFingerTapEnabled)
            toggleRow("2本指タップで左クリック", isOn: $twoFingerTapEnabled)
                .notifyOnChange(of: twoFingerTapEnabled)
            toggleRow("2本指クリックでミドルクリック", isOn: $middleClickEnabled)
                .notifyOnChange(of: middleClickEnabled)
            toggleRow("縦方向のみにスクロール(横スクロール無効)", isOn: $verticalScrollOnly)
                .notifyOnChange(of: verticalScrollOnly)

            HStack(spacing: DS.Space.s) {
                // ラベルはSliderに押されて省略(…)されやすいため全文表示を優先する
                rowLabel("右クリックの開始位置")
                    .fixedSize()
                    .layoutPriority(1)
                Slider(value: $rightZoneMinX, in: 0...1)
                    .controlSize(.mini)
                Text(String(format: "左から%.0f%%", rightZoneMinX * 100))
                    .font(DS.Font.cardValue)
                    .foregroundColor(DS.Color.labelSecondary)
            }
            .frame(height: DS.Layout.rowHeight)
            .notifyOnChange(of: rightZoneMinX)

            HStack {
                Spacer()
                Button("詳細設定") {
                    showDetailSettings = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            toggleRow(
                tap3ActionKind == .trackpadToggle
                    ? "3本指ダブルタップで実行"
                    : "3本指タップで実行",
                isOn: $threeFingerTapEnabled)
                .notifyOnChange(of: threeFingerTapEnabled)
                .padding(.top, DS.Space.groupGap)

            Picker("割り当て", selection: $tap3ActionKind) {
                ForEach(BoundActionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
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
                    Button(isRecordingTap3Macro ? "録画を停止して保存" : "録画を開始") {
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
                    Button("クリア") {
                        macroRecorder.clear()
                        AppSettings.shared.threeFingerTapAction = .macro([])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(macroRecorder.isRecording || savedMacroEventCount == 0)
                }

                Text(isRecordingTap3Macro
                     ? "録画中… \(macroRecorder.recordedEvents.count)イベント"
                     : "登録済み：\(savedMacroEventCount)イベント")
                    .font(DS.Font.cardCaption)
                    .foregroundColor(isRecordingTap3Macro ? DS.Color.debugFail : DS.Color.labelSecondary)
            }
        }
    }

    /// メイン画面のフラット行ラベル(13pt/secondary/tracking 0.5)。
    private func rowLabel(_ text: String) -> Text {
        Text(text)
            .font(DS.Font.rowLabel)
            .tracking(0.5)
            .foregroundColor(DS.Color.labelSecondary)
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
        VStack(alignment: .leading, spacing: DS.Space.cardHeadingGap) {
            Text("タップ座標のライブ表示")
                .font(DS.Font.cardHeading)
                .tracking(0.5)
                .foregroundColor(DS.Color.labelSecondary)
                .padding(.leading, DS.Space.headingIndent)

            ScrollView {
                debugContent
                    .padding(DS.Space.cardPadding)
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glass)

            Text("詳細設定")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.labelPrimary)

            Spacer()
        }
        .padding(.horizontal, DS.Space.windowPadding)
        .padding(.top, DS.Space.m)
        .padding(.bottom, DS.Space.xs)
    }

    private var detailForm: some View {
        Form {
            Section(header: sectionHeader("タップに反応する範囲")) {
                SliderRow("先端側の反応範囲", value: frontDepthBinding, range: 0.05...1.0) {
                    String(format: "先端から%.0f%%", $0 * 100)
                }
                .notifyOnChange(of: zoneMinY)
                caption("マウス表面の先端(指先側)からこの割合までをタップに反応させます。初期値は25%です")

                Toggle("詳細設定を表示", isOn: $zoneDetailExpanded)
                    .toggleStyle(.switch).tint(DS.Color.accent)
                if zoneDetailExpanded {
                    SliderRow("左右: 左端", value: $zoneMinX, range: 0...1) { String(format: "左から%.0f%%", $0 * 100) }
                        .notifyOnChange(of: zoneMinX)
                    SliderRow("左右: 右端", value: $zoneMaxX, range: 0...1) { String(format: "左から%.0f%%", $0 * 100) }
                        .notifyOnChange(of: zoneMaxX)
                    SliderRow("前後: 手前端", value: $zoneMinY, range: 0...1) { String(format: "手前から%.0f%%", $0 * 100) }
                        .notifyOnChange(of: zoneMinY)
                    SliderRow("前後: 先端", value: $zoneMaxY, range: 0...1) { String(format: "手前から%.0f%%", $0 * 100) }
                        .notifyOnChange(of: zoneMaxY)
                    caption("0%=左端・手前(手首側)、100%=右端・先端(指先側)。「前後: 手前端」は上の「先端側の反応範囲」と連動します")
                    Button("反応範囲を初期設定に戻す") {
                        AppSettings.shared.resetZoneToDefaults()
                    }
                    .controlSize(.small)
                }
            }

            Section(header: sectionHeader("タップ判定のきびしさ")) {
                SliderRow("タップの最長時間", value: $tapMaxDuration, range: 0.05...0.5) { String(format: "%.2f秒", $0) }
                    .notifyOnChange(of: tapMaxDuration)
                SliderRow("位置ズレの許容量", value: $tapMaxStraightDistance, range: 0.01...0.3) { String(format: "%.2f", $0) }
                    .notifyOnChange(of: tapMaxStraightDistance)
                SliderRow("動きの合計の許容量", value: $tapMaxPathLength, range: 0.01...0.3) { String(format: "%.2f", $0) }
                    .notifyOnChange(of: tapMaxPathLength)
                SliderRow("動きの速さの許容量", value: $tapMaxVelocity, range: 0.2...8.0) { String(format: "%.1f", $0) }
                    .notifyOnChange(of: tapMaxVelocity)
                SliderRow("最短の接触フレーム数", value: tapMinFramesBinding, range: 1...10) { String(format: "%.0f", $0) }
                    .notifyOnChange(of: tapMinFrames)
                caption("それぞれ右に動かすほど反応しやすくなります(最短接触フレーム数のみ左に動かすほど反応しやすい)。反応しやすいほどスクロールとの誤反応は増えます")
                Button("タップ判定を初期設定に戻す") {
                    AppSettings.shared.resetSensitivityToDefaults()
                }
                .controlSize(.small)
            }

            Section(header: sectionHeader("誤反応の防止")) {
                SliderRow("スクロール後の待ち時間", value: $scrollVetoWindow, range: 0...1.0) { String(format: "%.2f秒", $0) }
                    .notifyOnChange(of: scrollVetoWindow)
                SliderRow("クリック後の待ち時間", value: $buttonVetoWindow, range: 0...0.5) { String(format: "%.2f秒", $0) }
                    .notifyOnChange(of: buttonVetoWindow)
                SliderRow("2本指の同時判定時間", value: $twoFingerSyncWindow, range: 0.02...0.2) { String(format: "%.2f秒", $0) }
                    .notifyOnChange(of: twoFingerSyncWindow)
                caption("スクロールや物理クリックの直後は、この時間だけタップを無視して誤クリックを防ぎます。2本指の同時判定時間は、2本の指のタッチ開始がこの時間内に収まったとき2本指タップとみなす設定です")
                Button("誤反応の防止を初期設定に戻す") {
                    AppSettings.shared.resetVetoToDefaults()
                }
                .controlSize(.small)
            }

            Section(header: sectionHeader("カーソル速度ブースト")) {
                SliderRow("軌跡の速さ", value: $pointerSpeedBoost, range: 0...9.0) {
                    $0 <= 0 ? "オフ(システム設定のまま)" : String(format: "x%.1f", $0)
                }
                .notifyOnChange(of: pointerSpeedBoost)
                caption("システム設定の上限(3.0)を超えてカーソルの軌跡速度を上げます。オフにする、またはアプリを終了すると元の速度に戻ります。システム設定の「マウス」を開くと一時的に上書きされることがあります")
            }

            Section(header: sectionHeader("トラックパッドモード")) {
                SliderRow("移動ゲイン", value: $trackpadModeGain, range: 200...3000) { String(format: "%.0f", $0) }
                    .notifyOnChange(of: trackpadModeGain)
                caption("マウス表面のなぞりをカーソル移動に変換する際の倍率です。3本指ダブルタップ、または下のボタンでモードのON/OFFを切り替えます")
                Button(TrackpadModeController.shared.isActive ? "今すぐOFFにする" : "今すぐONにする") {
                    TrackpadModeController.shared.toggle()
                }
                .controlSize(.small)
            }

            Section {
                Button("すべての設定を既定値に戻す") {
                    AppSettings.shared.resetAllToDefaults()
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
                Text("指の本数：\(debugFeed.currentFingerCount)")
                Spacer()
                Text(String(format: "左から%.0f%% 手前から%.0f%%",
                            debugFeed.latestTouchX * 100, debugFeed.latestTouchY * 100))
            }
            .font(DS.Font.cardBody)
            .foregroundColor(DS.Color.labelSecondary)

            Divider()

            Text("直近のイベント")
                .font(DS.Font.cardCaption)
                .foregroundColor(DS.Color.labelSecondary)
            ForEach(debugFeed.recentEvents) { event in
                Text(event.text)
                    .font(DS.Font.cardCaption)
                    .foregroundColor(DS.Color.labelPrimary)
            }

            Divider()

            Text("直近のタップ試行の判定内訳")
                .font(DS.Font.cardCaption)
                .foregroundColor(DS.Color.labelSecondary)
            if debugFeed.lastAttempt.isEmpty {
                Text("(まだ試行なし)")
                    .font(DS.Font.cardCaption)
                    .foregroundColor(DS.Color.labelSecondary)
            } else {
                ForEach(debugFeed.lastAttempt) { condition in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.Space.xs) {
                            Text(condition.passed ? "✓" : "✗")
                                .font(DS.Font.cardCaption)
                                .foregroundColor(condition.passed ? DS.Color.debugPass : DS.Color.debugFail)
                            Text(condition.label)
                                .font(DS.Font.cardCaption)
                                .foregroundColor(DS.Color.labelPrimary)
                        }
                        Text("\(condition.actual) / \(condition.threshold)")
                            .font(DS.Font.cardValue)
                            .foregroundColor(DS.Color.labelSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
