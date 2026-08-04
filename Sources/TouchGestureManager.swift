// The early tap-recognition prototype was informed by MouseToucher.
// Copyright (c) 2025 Roger Hughes, used under the MIT License.
// See THIRD_PARTY_NOTICES.md. Magic Mouse Toolkit changes: GPL-3.0-only.

import Foundation
import Darwin
import Combine
import QuartzCore

// MARK: - スレッド間共有状態（MTコールバックスレッド ⇔ CGEventTapスレッド）

/// os_unfair_lock で保護された、両コールバックから読み書きされる状態。
/// 保持時間はナノ秒級（フィールドの読み書きのみ）。
final class SharedState {
    static let shared = SharedState()
    private init() {}

    private var lock = os_unfair_lock()

    private var _fingerCount: Int = 0
    private var _lastFrameAt: CFTimeInterval = -1e9
    private var _lastScrollAt: CFTimeInterval = -1e9
    private var _momentumActive: Bool = false
    // 左右を単一Boolに畳むと「左Down→右Down→左Up」で右が押下中なのに解放扱いになるため、
    // ボタンごとに持つ(タップ常時左クリック設定では物理右クリックが主経路になり実際に起こりうる)
    private var _leftButtonDown: Bool = false
    private var _rightButtonDown: Bool = false
    private var _lastButtonUpAt: CFTimeInterval = -1e9
    private var _convertingToMiddle: Bool = false
    private var _accessibilityGranted: Bool = false
    private var _trackpadModeActive: Bool = false
    private var _trackpadScrollPassthrough: Bool = false
    private var _trackpadMomentumEligibleUntil: CFTimeInterval = -1e9
    private var _trackpadScrollOwner: Int = 0
    private var _builtInTrackpadFingerCount: Int = 0
    private var _builtInTrackpadLastFrameAt: CFTimeInterval = -1e9

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }

    var fingerCount: Int {
        get { withLock { _fingerCount } }
        set { withLock { _fingerCount = newValue } }
    }
    var lastFrameAt: CFTimeInterval {
        get { withLock { _lastFrameAt } }
        set { withLock { _lastFrameAt = newValue } }
    }
    var lastScrollAt: CFTimeInterval {
        get { withLock { _lastScrollAt } }
        set { withLock { _lastScrollAt = newValue } }
    }
    var momentumActive: Bool {
        get { withLock { _momentumActive } }
        set { withLock { _momentumActive = newValue } }
    }
    /// 第4層物理ボタンベトの判定用。左右いずれかが押下中なら true(TapRecognizerはこれだけを見る)
    var buttonDown: Bool {
        withLock { _leftButtonDown || _rightButtonDown }
    }
    var leftButtonDown: Bool {
        get { withLock { _leftButtonDown } }
        set { withLock { _leftButtonDown = newValue } }
    }
    var rightButtonDown: Bool {
        get { withLock { _rightButtonDown } }
        set { withLock { _rightButtonDown = newValue } }
    }
    var lastButtonUpAt: CFTimeInterval {
        get { withLock { _lastButtonUpAt } }
        set { withLock { _lastButtonUpAt = newValue } }
    }
    var convertingToMiddle: Bool {
        get { withLock { _convertingToMiddle } }
        set { withLock { _convertingToMiddle = newValue } }
    }
    /// AppDelegate の権限フローが更新する。コールバック内で AXIsProcessTrusted の IPC を避けるためのキャッシュ。
    var accessibilityGranted: Bool {
        get { withLock { _accessibilityGranted } }
        set { withLock { _accessibilityGranted = newValue } }
    }
    /// トラックパッドモード中は通常のタップ/ジェスチャ経路をバイパスし、
    /// TrackpadModeController がタッチを専有する。
    var trackpadModeActive: Bool {
        get { withLock { _trackpadModeActive } }
        set { withLock { _trackpadModeActive = newValue } }
    }
    /// トラックパッドモード中の2本指スクロールが進行中（慣性を含む）。
    var trackpadScrollPassthrough: Bool {
        get { withLock { _trackpadScrollPassthrough } }
        set { withLock { _trackpadScrollPassthrough = newValue } }
    }
    /// 2本指の直接スクロール終了後、続くネイティブ慣性開始を受け入れる期限。
    var trackpadMomentumEligibleUntil: CFTimeInterval {
        get { withLock { _trackpadMomentumEligibleUntil } }
        set { withLock { _trackpadMomentumEligibleUntil = newValue } }
    }
    /// 0=なし、1=Magic Mouse、2=MacBook内蔵トラックパッド。
    var trackpadScrollOwner: Int {
        get { withLock { _trackpadScrollOwner } }
        set { withLock { _trackpadScrollOwner = newValue } }
    }
    var builtInTrackpadFingerCount: Int {
        get { withLock { _builtInTrackpadFingerCount } }
        set { withLock { _builtInTrackpadFingerCount = newValue } }
    }
    var builtInTrackpadLastFrameAt: CFTimeInterval {
        get { withLock { _builtInTrackpadLastFrameAt } }
        set { withLock { _builtInTrackpadLastFrameAt = newValue } }
    }
}

// MARK: - タッチ追跡

struct TouchTrack {
    let id: Int32
    let startTime: Double
    let startPos: MTPoint
    var lastPos: MTPoint
    var pathLength: Float = 0
    var maxVelocity: Float = 0
    var frames: Int = 1
    var beganDuringMomentum: Bool = false
    var vetoed: Bool = false
    /// 接触中に複数指の同時接触を観測したか。単独クリックとしての誤発火抑制に使う
    var sawMultipleContacts: Bool = false
    /// リリース時の判定結果(TapRecognizer)を保持。ゾーン要求は指本数確定後に評価する
    var inZone: Bool = false
}

// MARK: - デバッグフィード（SettingsView の DisclosureGroup 表示用）

struct DebugEvent: Identifiable {
    let id = UUID()
    let text: String
    let at: Date
}

final class DebugFeed: ObservableObject {
    static let shared = DebugFeed()
    private init() {}

    /// DisclosureGroup が開いている間だけ true。false の間は push が即座に無視される。
    @Published var isActive: Bool = false
    @Published var currentFingerCount: Int = 0
    @Published var latestTouchX: Float = 0
    @Published var latestTouchY: Float = 0
    @Published var lastAttempt: [TapConditionResult] = []
    @Published var recentEvents: [DebugEvent] = []

    func pushEvent(_ text: String) {
        guard isActive else { return }
        DispatchQueue.main.async {
            self.recentEvents.insert(DebugEvent(text: text, at: Date()), at: 0)
            if self.recentEvents.count > 10 {
                self.recentEvents.removeLast(self.recentEvents.count - 10)
            }
        }
    }

    func pushAttempt(_ conditions: [TapConditionResult]) {
        guard isActive else { return }
        DispatchQueue.main.async { self.lastAttempt = conditions }
    }

    func pushTouchState(fingerCount: Int, x: Float, y: Float) {
        guard isActive else { return }
        DispatchQueue.main.async {
            self.currentFingerCount = fingerCount
            self.latestTouchX = x
            self.latestTouchY = y
        }
    }
}

// MARK: - タップ判定本体

/// MTコールバック（バックグラウンドスレッド）で駆動される、1本指/2本指タップの検出。
final class TouchGestureManager {
    static let shared = TouchGestureManager()

    private let queue = DispatchQueue(label: "com.mori0818.magicmousetoolkit.touch.pending")
    private var activeTouches: [Int32: TouchTrack] = [:]

    // 同時タップ判定用の保留グループ（2本指・3本指共通、専用タイマー1本を使い回す）。
    // 「ほぼ同時に開始・リリースされた個別のタップ群」として本数を数え、確定時に本数で分岐する。
    private var pendingGroup: [TouchTrack] = []
    private var pendingGroupLatestReleaseTime: Double = 0
    private var pendingTimer: DispatchSourceTimer

    /// トラックパッド切り替えに割り当てた3本指タップの1打目。
    private var lastThreeFingerToggleTapAt: Double = -1e9
    private let trackpadToggleDoubleTapWindow: Double = 0.45

    private init() {
        pendingTimer = DispatchSource.makeTimerSource(queue: queue)
        pendingTimer.setEventHandler { [weak self] in self?.pendingTimerFired() }
        pendingTimer.schedule(deadline: .distantFuture)
        pendingTimer.resume()
    }

    var currentFingerCount: Int { SharedState.shared.fingerCount }

    /// MultitouchDeviceManager の C コールバックから呼ばれる。バックグラウンドスレッド。
    func handleContactFrame(touches: UnsafeBufferPointer<MTTouch>, timestamp: Double, frame: Int32) {
        let settings = SettingsStore.shared.snapshot
        // 時刻は必ず CACurrentMediaTime に統一する。MTフレームの timestamp は
        // 別の時刻系のため、EventInterceptor 側(CACurrentMediaTime)と比較すると
        // スクロールベト・ボタンベト・指本数相関ガードがすべて誤動作する。
        let now = CACurrentMediaTime()

        if !settings.enabled {
            SharedState.shared.fingerCount = 0
            activeTouches.removeAll()
            clearPendingGroup()
            return
        }

        // トラックパッドモード中は通常のタップ/ジェスチャ経路を完全にバイパスし、
        // 単一指のストローク/タップ判定を TrackpadModeController に専有させる。
        if SharedState.shared.trackpadModeActive {
            activeTouches.removeAll()
            clearPendingGroup()
            TrackpadModeController.shared.handleContactFrame(touches: touches, timestamp: now, settings: settings)
            return
        }

        var touchingIDs: Set<Int32> = []
        var count = 0
        var latestX: Float = 0
        var latestY: Float = 0

        for touch in touches {
            guard touch.state == 4 else { continue }
            count += 1
            touchingIDs.insert(touch.identifier)
            latestX = touch.normalized.position.x
            latestY = touch.normalized.position.y
        }

        // 複数指同時接触かどうかが確定してからトラックを更新する。
        // sawMultipleContacts は「このフレームに複数指が写っていたか」を記録し、
        // 二段ガード(handleRelease)で単独クリックの誤発火を抑制するために使う
        let hasMultipleContacts = count >= 2
        for touch in touches {
            guard touch.state == 4 else { continue }
            updateTrack(for: touch, at: now, hasMultipleContacts: hasMultipleContacts, settings: settings)
        }

        let releasedIDs = Set(activeTouches.keys).subtracting(touchingIDs)
        for id in releasedIDs {
            guard let track = activeTouches.removeValue(forKey: id) else { continue }
            // pendingRelease はタイマーハンドラ(queue上)と共有するため、
            // リリース処理全体を同じ直列キューへ載せてデータ競合を防ぐ
            queue.async { [weak self] in
                self?.handleRelease(track: track, releaseTime: now, settings: settings)
            }
        }

        SharedState.shared.fingerCount = count
        SharedState.shared.lastFrameAt = now
        DebugFeed.shared.pushTouchState(fingerCount: count, x: latestX, y: latestY)
    }

    private func updateTrack(for touch: MTTouch, at now: CFTimeInterval, hasMultipleContacts: Bool, settings: SettingsSnapshot) {
        let id = touch.identifier
        if var track = activeTouches[id] {
            let dx = touch.normalized.position.x - track.lastPos.x
            let dy = touch.normalized.position.y - track.lastPos.y
            track.pathLength += hypot(dx, dy)
            let velocity = hypot(touch.normalized.velocity.x, touch.normalized.velocity.y)
            track.maxVelocity = max(track.maxVelocity, velocity)
            track.lastPos = touch.normalized.position
            track.frames += 1
            if hasMultipleContacts {
                track.sawMultipleContacts = true
            }
            if Double(track.pathLength) > settings.tapMaxPathLength
                || Double(track.maxVelocity) > settings.tapMaxVelocity {
                track.vetoed = true
            }
            activeTouches[id] = track
        } else {
            let track = TouchTrack(
                id: id,
                startTime: now,
                startPos: touch.normalized.position,
                lastPos: touch.normalized.position,
                beganDuringMomentum: SharedState.shared.momentumActive,
                sawMultipleContacts: hasMultipleContacts
            )
            activeTouches[id] = track
        }
    }

    private func handleRelease(track: TouchTrack, releaseTime: Double, settings: SettingsSnapshot) {
        let evaluation = TapRecognizer.evaluate(track: track, releaseTime: releaseTime, settings: settings)
        DebugFeed.shared.pushAttempt(evaluation.conditions)

        guard evaluation.passed else {
            if let reason = evaluation.firstFailure {
                DebugFeed.shared.pushEvent(reason.localizedDescription)
                MMTLog.log("[診断] タップ不成立 id=\(track.id): \(reason.localizedDescription)")
            }
            return
        }

        var track = track
        track.inZone = evaluation.inZone

        guard settings.oneFingerTapEnabled || settings.twoFingerTapEnabled || settings.threeFingerTapEnabled else {
            return
        }

        // 接触中に一度も複数指を観測していないトラックは 2本指/3本指の構成要素に
        // なりえないため、グループ化の待ち(twoFingerSyncWindow * 2)を挟まず即発火する。
        // ここを待たせると 1本指クリック全体に体感できる遅延が乗る
        guard track.sawMultipleContacts else {
            // ゾーン要求はグループ確定側の 1本ケースと同一条件に揃える
            guard track.inZone else {
                DebugFeed.shared.pushEvent(TapFailureReason.outOfZone.localizedDescription)
                return
            }
            fireOneFingerTap(track: track, settings: settings)
            return
        }

        if let first = pendingGroup.first,
           abs(track.startTime - first.startTime) <= settings.twoFingerSyncWindow,
           abs(releaseTime - pendingGroupLatestReleaseTime) <= settings.twoFingerSyncWindow * 2 {
            pendingGroup.append(track)
            pendingGroupLatestReleaseTime = releaseTime
            pendingTimer.schedule(deadline: .now() + settings.twoFingerSyncWindow * 2)
            return
        }

        // 相方ではない: 保留中のグループを確定させ、今回のトラックを新たなグループの先頭にする
        finalizePendingGroup(settings: settings)
        pendingGroup = [track]
        pendingGroupLatestReleaseTime = releaseTime
        pendingTimer.schedule(deadline: .now() + settings.twoFingerSyncWindow * 2)
    }

    private func pendingTimerFired() {
        finalizePendingGroup(settings: SettingsStore.shared.snapshot)
    }

    /// 保留グループを本数で分岐して確定させる。1本→1本指タップ、2本→2本指クリック、
    /// 3本以上→3本指アクション。各分岐の有効/無効設定は呼び出し先で個別にガードする。
    private func finalizePendingGroup(settings: SettingsSnapshot) {
        guard !pendingGroup.isEmpty else { return }
        let group = pendingGroup
        let releaseTime = pendingGroupLatestReleaseTime
        pendingGroup = []
        cancelPendingTimer()
        MMTLog.log("[診断] グループ確定: \(group.count)本 inZone=\(group.map(\.inZone))")

        // ゾーン要求は本数確定後のここで課す。3本指以上は全面を対象とする
        // (指の本数自体が意図表明であり、ゾーン必須にすると3本を範囲内に収める操作が非現実的なため)
        switch group.count {
        case 1:
            // 1本指タップ自体が無効なら、圏外判定のDebugFeed通知(誤解を招く)を出す前に抜ける
            guard settings.oneFingerTapEnabled else { return }
            guard group[0].inZone else {
                DebugFeed.shared.pushEvent(TapFailureReason.outOfZone.localizedDescription)
                return
            }
            fireOneFingerTap(track: group[0], settings: settings)
        case 2:
            guard settings.twoFingerTapEnabled else { return }
            guard group.allSatisfy(\.inZone) else {
                DebugFeed.shared.pushEvent(TapFailureReason.outOfZone.localizedDescription)
                return
            }
            fireClick(button: .left, reason: NSLocalizedString("2本指タップ", comment: "タップ成立イベント種別"))
        default:
            guard settings.threeFingerTapEnabled else {
                MMTLog.log("[診断] 3本指: threeFingerTapEnabled=false のため不発")
                return
            }
            if settings.threeFingerTapAction.isTrackpadToggle {
                if releaseTime - lastThreeFingerToggleTapAt <= trackpadToggleDoubleTapWindow {
                    lastThreeFingerToggleTapAt = -1e9
                } else {
                    lastThreeFingerToggleTapAt = releaseTime
                    MMTLog.log("[診断] 3本指ダブルタップ: 1打目")
                    return
                }
            }
            MMTLog.log("[診断] 3本指: アクション実行 \(settings.threeFingerTapAction)")
            ActionExecutor.perform(settings.threeFingerTapAction)
            DebugFeed.shared.pushEvent(String(format: NSLocalizedString("タップ成立(%@)", comment: "タップ成立通知"), NSLocalizedString("3本指", comment: "タップ成立イベント種別")))
        }
    }

    private func cancelPendingTimer() {
        pendingTimer.schedule(deadline: .distantFuture)
    }

    /// 無効化・トラックパッドモード移行時に保留中のグループを破棄する。
    /// pendingGroup は直列キュー上でのみ読み書きするため、破棄もそのキューへ載せる
    private func clearPendingGroup() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingGroup = []
            self.cancelPendingTimer()
        }
    }

    private func fireOneFingerTap(track: TouchTrack, settings: SettingsSnapshot) {
        guard settings.oneFingerTapEnabled else {
            MMTLog.log("[診断] 1本指: oneFingerTapEnabled=false のため不発")
            return
        }
        // 常時左クリック設定では右ゾーンを評価しない。右クリックは物理クリックに任せる
        if !settings.tapAlwaysLeftClick, Double(track.lastPos.x) > settings.rightZoneMinX {
            fireClick(button: .right, reason: NSLocalizedString("1本指タップ(右)", comment: "タップ成立イベント種別"))
        } else {
            fireClick(button: .left, reason: NSLocalizedString("1本指タップ(左)", comment: "タップ成立イベント種別"))
        }
    }

    private func fireClick(button: SynthesizedClick.Button, reason: String) {
        guard SharedState.shared.accessibilityGranted else {
            DebugFeed.shared.pushEvent(String(format: NSLocalizedString("%@を検出 — アクセシビリティ権限が未許可のためクリックできません", comment: "権限未許可時の通知"), reason))
            MMTLog.log("タップ成立(\(reason))したが権限未許可のためクリック送出せず")
            return
        }
        MMTLog.log("タップ成立(\(reason)) → クリック送出")
        SynthesizedClick.post(button: button)
        DebugFeed.shared.pushEvent(String(format: NSLocalizedString("タップ成立(%@)", comment: "タップ成立通知"), reason))
    }
}
