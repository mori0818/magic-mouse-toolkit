// The early tap-recognition prototype was informed by MouseToucher.
// Copyright (c) 2025 Roger Hughes, used under the MIT License.
// See THIRD_PARTY_NOTICES.md. Magic Control changes: GPL-3.0-only.

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
    private var _buttonDown: Bool = false
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
    var buttonDown: Bool {
        get { withLock { _buttonDown } }
        set { withLock { _buttonDown = newValue } }
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

    private let queue = DispatchQueue(label: "com.magiccontrol.touch.pending")
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
            return
        }

        // トラックパッドモード中は通常のタップ/ジェスチャ経路を完全にバイパスし、
        // 単一指のストローク/タップ判定を TrackpadModeController に専有させる。
        if SharedState.shared.trackpadModeActive {
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
            updateTrack(for: touch, at: now, settings: settings)
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

    private func updateTrack(for touch: MTTouch, at now: CFTimeInterval, settings: SettingsSnapshot) {
        let id = touch.identifier
        if var track = activeTouches[id] {
            let dx = touch.normalized.position.x - track.lastPos.x
            let dy = touch.normalized.position.y - track.lastPos.y
            track.pathLength += hypot(dx, dy)
            let velocity = hypot(touch.normalized.velocity.x, touch.normalized.velocity.y)
            track.maxVelocity = max(track.maxVelocity, velocity)
            track.lastPos = touch.normalized.position
            track.frames += 1
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
                beganDuringMomentum: SharedState.shared.momentumActive
            )
            activeTouches[id] = track
        }
    }

    private func handleRelease(track: TouchTrack, releaseTime: Double, settings: SettingsSnapshot) {
        let evaluation = TapRecognizer.evaluate(track: track, releaseTime: releaseTime, settings: settings)
        DebugFeed.shared.pushAttempt(evaluation.conditions)

        guard evaluation.passed else {
            if let reason = evaluation.firstFailure {
                DebugFeed.shared.pushEvent(reason.rawValue)
                MCLog.log("[診断] タップ不成立 id=\(track.id): \(reason.rawValue)")
            }
            return
        }

        var track = track
        track.inZone = evaluation.inZone

        guard settings.oneFingerTapEnabled || settings.twoFingerTapEnabled || settings.threeFingerTapEnabled else {
            return
        }

        guard settings.twoFingerTapEnabled || settings.threeFingerTapEnabled else {
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
        MCLog.log("[診断] グループ確定: \(group.count)本 inZone=\(group.map(\.inZone))")

        // ゾーン要求は本数確定後のここで課す。3本指以上は全面を対象とする
        // (指の本数自体が意図表明であり、ゾーン必須にすると3本を範囲内に収める操作が非現実的なため)
        switch group.count {
        case 1:
            guard group[0].inZone else {
                DebugFeed.shared.pushEvent(TapFailureReason.outOfZone.rawValue)
                return
            }
            fireOneFingerTap(track: group[0], settings: settings)
        case 2:
            guard settings.twoFingerTapEnabled else { return }
            guard group.allSatisfy(\.inZone) else {
                DebugFeed.shared.pushEvent(TapFailureReason.outOfZone.rawValue)
                return
            }
            fireClick(button: .left, reason: "2本指タップ")
        default:
            guard settings.threeFingerTapEnabled else {
                MCLog.log("[診断] 3本指: threeFingerTapEnabled=false のため不発")
                return
            }
            if settings.threeFingerTapAction.isTrackpadToggle {
                if releaseTime - lastThreeFingerToggleTapAt <= trackpadToggleDoubleTapWindow {
                    lastThreeFingerToggleTapAt = -1e9
                } else {
                    lastThreeFingerToggleTapAt = releaseTime
                    MCLog.log("[診断] 3本指ダブルタップ: 1打目")
                    return
                }
            }
            MCLog.log("[診断] 3本指: アクション実行 \(settings.threeFingerTapAction)")
            ActionExecutor.perform(settings.threeFingerTapAction)
            DebugFeed.shared.pushEvent("タップ成立(3本指)")
        }
    }

    private func cancelPendingTimer() {
        pendingTimer.schedule(deadline: .distantFuture)
    }

    private func fireOneFingerTap(track: TouchTrack, settings: SettingsSnapshot) {
        guard settings.oneFingerTapEnabled else {
            MCLog.log("[診断] 1本指: oneFingerTapEnabled=false のため不発")
            return
        }
        if Double(track.lastPos.x) > settings.rightZoneMinX {
            fireClick(button: .right, reason: "1本指タップ(右)")
        } else {
            fireClick(button: .left, reason: "1本指タップ(左)")
        }
    }

    private func fireClick(button: SynthesizedClick.Button, reason: String) {
        guard SharedState.shared.accessibilityGranted else {
            DebugFeed.shared.pushEvent("\(reason)を検出 — アクセシビリティ権限が未許可のためクリックできません")
            MCLog.log("タップ成立(\(reason))したが権限未許可のためクリック送出せず")
            return
        }
        MCLog.log("タップ成立(\(reason)) → クリック送出")
        SynthesizedClick.post(button: button)
        DebugFeed.shared.pushEvent("タップ成立(\(reason))")
    }
}
