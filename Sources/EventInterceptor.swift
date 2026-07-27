// The middle-click event transformation is adapted from MiddleClick (GPL-3.0).
// See THIRD_PARTY_NOTICES.md. Magic Control is licensed under GPL-3.0-only.

import CoreGraphics
import QuartzCore
import AppKit

/// CGEventTap の C コールバック（capture 不可のためグローバル関数）。
private func eventInterceptorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    EventInterceptor.shared.handle(type: type, event: event)
}

/// 1本の CGEventTap で3役を兼ねる:
/// - スクロール監視（第2層・第3層ベトの情報源。ScrollMonitor役）
/// - 物理クリック監視（第4層ベトの情報源）
/// - 2本指物理クリック→ミドルクリック変換
///
/// コールバック規律: アロケーション・ログ・UserDefaults 読み取り禁止。
/// SettingsSnapshot と共有状態の読み取り + 整数フィールド書き換えのみ。
///
/// 権限喪失の検知と復旧は本クラスの責務ではなく PermissionMonitor + AppDelegate が担う
/// (SAFETY.md参照)。理由: `.tapDisabledByUserInput` はアクセシビリティ権限を
/// システム設定でOFFにした際、実機では配送されないことが確認されている(剥奪と同時に
/// タップへのイベント配送自体が止まるため)。このコールバック内で権限喪失を検知する
/// 設計は機能しないので採用しない。
final class EventInterceptor {
    static let shared = EventInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// メニューバーの状態表示用
    var isRunning: Bool { eventTap != nil }

    private init() {
        // .settingsChanged の購読は生存期間中1回だけ行う。start()/stop() のたびに
        // 登録し直すと、権限失効→復旧のサイクルを重ねるごとにオブザーバが重複登録され、
        // updateEnabledState() が多重に呼ばれるようになるため。
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
    }

    func start() {
        guard eventTap == nil else { return }

        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: eventInterceptorCallback,
            userInfo: nil
        ) else {
            MCLog.log("イベントタップ作成失敗(アクセシビリティ権限を確認)")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        MCLog.log("イベントタップ作成成功(クリック監視・ミドルクリック変換が有効)")

        updateEnabledState()
    }

    /// タップを完全に破棄する。`tapEnable(false)` だけでなく `CFMachPortInvalidate` まで
    /// 行うのが重要: WindowServer側にポート登録が残ったままだと、権限剥奪直後の
    /// フリーズからの回復が遅れる/回復しない可能性があるため(SAFETY.md参照)。
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    @objc private func settingsChanged() {
        updateEnabledState()
    }

    /// master enable OFF 時は tap 自体を無効化する（タップ判定もベト先も不要なため）。
    /// middleClick のみ OFF でタップ有効の場合は tap は生かす（第2層のスクロール監視のため）。
    ///
    /// 注意: ここでは SettingsStore のスナップショットではなく AppSettings を直接読む。
    /// スナップショットの更新も同じ .settingsChanged 通知で行われるため、オブザーバの
    /// 実行順序によっては1世代古い値を読んでしまい、有効トグルが1テンポずれる
    /// （OFF→ONに戻しても無効のままになる）バグの原因になる。
    private func updateEnabledState() {
        guard let tap = eventTap else { return }
        let enabled = AppSettings.shared.enabled
        if !enabled {
            // OFF 中は mouseUp を取りこぼすため、変換途中・押下中の状態を必ずクリアする
            // （残っていると再有効化後の最初のクリックが誤ってミドルUpに変換される）
            let shared = SharedState.shared
            shared.convertingToMiddle = false
            shared.buttonDown = false
            shared.momentumActive = false
            shared.trackpadScrollPassthrough = false
            shared.trackpadMomentumEligibleUntil = -1e9
            shared.trackpadScrollOwner = 0
        }
        CGEvent.tapEnable(tap: tap, enable: enabled)
        MCLog.log("イベントタップ: \(enabled ? "有効化" : "無効化")")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // コールバックが重くてシステムに自動無効化された場合のみ、その場で再有効化してよい。
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // システム設定でユーザーがアクセシビリティ/入力監視をOFFにした場合。
        // 実機検証では、権限剥奪と同時にこのタップへのイベント配送自体が止まり、
        // このイベントがコールバックに配送されないことが確認されている
        // (~/Library/Logs/MagicControl.log に復旧ログが一切残らなかった)。
        // つまりここで何をしても頼りにできない。絶対に tapEnable(true) は呼ばない
        // (呼んでも意味が無い上、万一配送された場合に同期ループの引き金になりうる)。
        // 権限喪失の検知と復旧は PermissionMonitor が別経路(ポーリング)で行う。
        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        let shared = SharedState.shared
        let now = CACurrentMediaTime()

        switch type {
        case .scrollWheel:
            if shared.trackpadModeActive {
                // 直近フレームで2本指を確認できたスクロールと、その慣性列だけを通す。
                // デルタ値には触れず、macOSが生成した高精度の減速カーブをそのまま維持する。
                let magicMouseTwoFingers = shared.fingerCount >= 2 && (now - shared.lastFrameAt) < 0.08
                let builtInTwoFingers = shared.builtInTrackpadFingerCount >= 2
                    && (now - shared.builtInTrackpadLastFrameAt) < 0.08
                // 両方が同時なら内蔵トラックパッドを優先する。
                let detectedOwner = builtInTwoFingers ? 2 : (magicMouseTwoFingers ? 1 : 0)
                let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
                let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
                let inMomentum = (momentumPhase == 1 || momentumPhase == 2)  // began / continued
                let endsScroll = (scrollPhase == 4 || scrollPhase == 8)  // ended / cancelled
                let endsMomentum = (momentumPhase == 3)
                let passthroughActive = shared.trackpadScrollPassthrough
                let mayStartMomentum = now <= shared.trackpadMomentumEligibleUntil
                let currentOwner = shared.trackpadScrollOwner

                if endsMomentum && passthroughActive {
                    // CGMomentumScrollPhase の終端値は3。終端イベント自体を通してから閉じる。
                    shared.trackpadScrollPassthrough = false
                    shared.trackpadMomentumEligibleUntil = -1e9
                    shared.trackpadScrollOwner = 0
                } else if endsScroll && (passthroughActive || detectedOwner != 0) {
                    // 直接操作の終端イベントを通し、直後の慣性開始だけを短時間受け入れる。
                    shared.trackpadScrollPassthrough = false
                    shared.trackpadMomentumEligibleUntil = now + 0.12
                    if currentOwner == 0 { shared.trackpadScrollOwner = detectedOwner }
                } else if detectedOwner != 0 {
                    shared.trackpadScrollPassthrough = true
                    shared.trackpadMomentumEligibleUntil = -1e9
                    shared.trackpadScrollOwner = detectedOwner
                } else if inMomentum && (passthroughActive || mayStartMomentum) && currentOwner != 0 {
                    shared.trackpadScrollPassthrough = true
                    shared.trackpadMomentumEligibleUntil = -1e9
                } else if passthroughActive {
                    // MTフレームとscrollWheelの配送順が前後しても、開始済みの列は欠落させない。
                } else {
                    shared.trackpadScrollPassthrough = false
                    shared.trackpadMomentumEligibleUntil = -1e9
                    shared.trackpadScrollOwner = 0
                    return nil
                }
            }

            // Magic Mouse はタップ程度の接触でもデルタ0のスクロールイベント(phase通知)を
            // 発生させるため、実際に移動量のあるイベントだけを「スクロール」として記録する。
            // そうしないと全タップがスクロールベトで潰される。
            let d1 = abs(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            let d2 = abs(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            if d1 + d2 > 0 {
                shared.lastScrollAt = now
            }
            let phase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            shared.momentumActive = (phase == 1 || phase == 2)  // began / continued

            // 横スクロール無効化: Axis2(横)の3種のデルタ表現(整数生値・整数ポイント値・
            // 固定小数点値)をすべてゼロ化する。慣性フェーズのイベントも同じフィールドを
            // 持つため、この処理だけで横方向の慣性スクロールも止まる。
            if SettingsStore.shared.snapshot.verticalScrollOnly {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            if event.getIntegerValueField(.eventSourceUserData) == SynthesizedClick.signature {
                MCLog.log("[診断] 合成leftMouseDownがHIDタップを通過(注入成功)")
                return Unmanaged.passUnretained(event)
            }
            shared.buttonDown = true
            let settings = SettingsStore.shared.snapshot
            if settings.middleClickEnabled
                && shared.fingerCount == 2
                && (now - shared.lastFrameAt) < 0.08 {
                shared.convertingToMiddle = true
                event.type = .otherMouseDown
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseUp:
            if event.getIntegerValueField(.eventSourceUserData) == SynthesizedClick.signature {
                return Unmanaged.passUnretained(event)
            }
            shared.buttonDown = false
            shared.lastButtonUpAt = now
            if shared.convertingToMiddle {
                shared.convertingToMiddle = false
                event.type = .otherMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
