import CoreGraphics
import Darwin
import Foundation

/// 仮想トラックパッドモード。有効化中はマルチタッチのストロークをカーソル移動に変換し、
/// タップをクリックとして合成する。プロトタイプ(prototypes/virtual_trackpad/main.swift)の
/// 検証済みロジックを、本体の SharedState/SettingsSnapshot/SynthesizedClick に接続して移植したもの。
///
/// 規律(手順書 magic-control-仮想トラックパッド実装手順.md 準拠):
/// MTコールバック(handleContactFrame)内では CGEvent 生成・メモリ確保・ログ出力を行わず、
/// os_unfair_lock で保護したアキュムレータへの書き込みのみに留める。実際の CGEvent 生成/post は
/// 専用シリアルキュー上の 120Hz タイマー(drainAndPost)でのみ行う。
final class TrackpadModeController {
    static let shared = TrackpadModeController()

    private init() {}

    private let drainQueue = DispatchQueue(label: "com.magiccontrol.trackpadmode.drain")
    private var drainTimer: DispatchSourceTimer?

    private var accLock = os_unfair_lock()
    private var accDX: Double = 0
    private var accDY: Double = 0
    private var accClickPending = false
    private var accTogglePending = false

    // 現在追跡中の指(1本のみ)。2本以上では追跡を中断し、スクロールに専念する。
    private var trackedID: Int32?
    private var lastTouchPos = MTPoint(x: 0, y: 0)

    // タップ判定用の追跡状態(タッチ開始時にリセット)
    private var touchStartPos = MTPoint(x: 0, y: 0)
    private var touchStartTime: Double = 0
    private var touchPathLength: Double = 0
    private var touchMaxVelocity: Double = 0
    private var touchFrameCount: Int = 0

    // モード解除用の3本指タップ追跡。MTコールバック内では数値状態だけを更新し、
    // 実際の切り替えは drainAndPost からメインキューへ渡す。
    private var threeFingerTracking = false
    private var threeFingerStartTime: Double = 0
    private var threeFingerStartPos = MTPoint(x: 0, y: 0)
    private var threeFingerLastPos = MTPoint(x: 0, y: 0)
    private var threeFingerPathLength: Double = 0
    private var threeFingerMaxVelocity: Double = 0
    private var threeFingerFrameCount: Int = 0
    private var lastThreeFingerToggleTapAt: Double = -1e9
    private let trackpadToggleDoubleTapWindow: Double = 0.45

    private(set) var isActive = false

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    private func activate() {
        guard !isActive else { return }
        isActive = true
        resetTrackingState()

        os_unfair_lock_lock(&accLock)
        accDX = 0
        accDY = 0
        accClickPending = false
        accTogglePending = false
        os_unfair_lock_unlock(&accLock)

        SharedState.shared.trackpadScrollPassthrough = false
        SharedState.shared.trackpadMomentumEligibleUntil = -1e9
        SharedState.shared.trackpadScrollOwner = 0
        SharedState.shared.fingerCount = 0
        SharedState.shared.trackpadModeActive = true

        let timer = DispatchSource.makeTimerSource(queue: drainQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 120.0)
        timer.setEventHandler { [weak self] in self?.drainAndPost() }
        timer.resume()
        drainTimer = timer

        MCLog.log("[診断] TrackpadMode: 有効化")
        TrackpadModeHUD.show()
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        SharedState.shared.trackpadModeActive = false
        SharedState.shared.trackpadScrollPassthrough = false
        SharedState.shared.trackpadMomentumEligibleUntil = -1e9
        SharedState.shared.trackpadScrollOwner = 0
        SharedState.shared.fingerCount = 0

        drainTimer?.cancel()
        drainTimer = nil
        trackedID = nil

        MCLog.log("[診断] TrackpadMode: 無効化")
        TrackpadModeHUD.hide()
    }

    private func resetTrackingState() {
        trackedID = nil
        lastTouchPos = MTPoint(x: 0, y: 0)
        touchStartPos = MTPoint(x: 0, y: 0)
        touchStartTime = 0
        touchPathLength = 0
        touchMaxVelocity = 0
        touchFrameCount = 0
        lastThreeFingerToggleTapAt = -1e9
        resetThreeFingerTracking()
    }

    private func resetThreeFingerTracking() {
        threeFingerTracking = false
        threeFingerStartTime = 0
        threeFingerStartPos = MTPoint(x: 0, y: 0)
        threeFingerLastPos = MTPoint(x: 0, y: 0)
        threeFingerPathLength = 0
        threeFingerMaxVelocity = 0
        threeFingerFrameCount = 0
    }

    /// MTコールバック経由(TouchGestureManager)から呼ばれる。CGEvent生成・ログ出力禁止。
    func handleContactFrame(touches: UnsafeBufferPointer<MTTouch>, timestamp: Double, settings: SettingsSnapshot) {
        // モード中は TouchGestureManager が早期returnするため、指本数と時刻をここで共有する。
        var touchingCount = 0
        var firstTouch: MTTouch?
        var positionSumX: Float = 0
        var positionSumY: Float = 0
        var maxVelocity: Double = 0
        for touch in touches where touch.state == 4 {
            touchingCount += 1
            if firstTouch == nil { firstTouch = touch }
            positionSumX += touch.normalized.position.x
            positionSumY += touch.normalized.position.y
            let velocity = touch.normalized.velocity
            let magnitude = (Double(velocity.x) * Double(velocity.x)
                + Double(velocity.y) * Double(velocity.y)).squareRoot()
            maxVelocity = max(maxVelocity, magnitude)
        }
        SharedState.shared.fingerCount = touchingCount
        SharedState.shared.lastFrameAt = timestamp

        if touchingCount >= 3,
           settings.threeFingerTapEnabled,
           settings.threeFingerTapAction.isTrackpadToggle {
            let centroid = MTPoint(
                x: positionSumX / Float(touchingCount),
                y: positionSumY / Float(touchingCount))
            if threeFingerTracking {
                let dx = Double(centroid.x - threeFingerLastPos.x)
                let dy = Double(centroid.y - threeFingerLastPos.y)
                threeFingerPathLength += (dx * dx + dy * dy).squareRoot()
                threeFingerLastPos = centroid
                threeFingerMaxVelocity = max(threeFingerMaxVelocity, maxVelocity)
                threeFingerFrameCount += 1
            } else {
                threeFingerTracking = true
                threeFingerStartTime = timestamp
                threeFingerStartPos = centroid
                threeFingerLastPos = centroid
                threeFingerPathLength = 0
                threeFingerMaxVelocity = maxVelocity
                threeFingerFrameCount = 1
            }

            trackedID = nil
            os_unfair_lock_lock(&accLock)
            accDX = 0
            accDY = 0
            os_unfair_lock_unlock(&accLock)
            return
        }

        // 3本指を順に離す途中は2本指スクロールへ遷移させず、全指リリース時に確定する。
        if threeFingerTracking {
            if touchingCount == 0 {
                let dx = Double(threeFingerLastPos.x - threeFingerStartPos.x)
                let dy = Double(threeFingerLastPos.y - threeFingerStartPos.y)
                let straightDistance = (dx * dx + dy * dy).squareRoot()
                let duration = timestamp - threeFingerStartTime
                let isTap = duration <= settings.tapMaxDuration
                    && straightDistance <= settings.tapMaxStraightDistance
                    && threeFingerPathLength <= settings.tapMaxPathLength
                    && threeFingerMaxVelocity <= settings.tapMaxVelocity
                    && threeFingerFrameCount >= settings.tapMinFrames
                resetThreeFingerTracking()
                if isTap {
                    if timestamp - lastThreeFingerToggleTapAt <= trackpadToggleDoubleTapWindow {
                        lastThreeFingerToggleTapAt = -1e9
                        os_unfair_lock_lock(&accLock)
                        accTogglePending = true
                        os_unfair_lock_unlock(&accLock)
                    } else {
                        lastThreeFingerToggleTapAt = timestamp
                    }
                } else {
                    lastThreeFingerToggleTapAt = -1e9
                }
            }
            return
        }

        // 2本以上ではカーソル・タップ追跡を中断し、未ドレインの移動量も破棄する。
        if touchingCount >= 2 {
            trackedID = nil
            os_unfair_lock_lock(&accLock)
            accDX = 0
            accDY = 0
            os_unfair_lock_unlock(&accLock)
            return
        }

        guard let touch = firstTouch else {
            evaluateTapAndReset(endPos: lastTouchPos, endTime: timestamp, settings: settings)
            return
        }

        if trackedID != touch.identifier {
            // 新規タッチ開始。デルタ0で基準位置だけ記録(いきなり跳ばないように)
            trackedID = touch.identifier
            lastTouchPos = touch.normalized.position
            touchStartPos = touch.normalized.position
            touchStartTime = timestamp
            touchPathLength = 0
            touchMaxVelocity = 0
            touchFrameCount = 0
            return
        }

        let ndx = Double(touch.normalized.position.x - lastTouchPos.x)
        let ndy = Double(touch.normalized.position.y - lastTouchPos.y)
        let rawDX = ndx * settings.trackpadModeGain
        // MTの正規化Yは前方(指を伸ばす先端側)が大きい。画面は上原点でYが下に増えるため、
        // 「前方へなぞる=カーソルが上へ動く」という直感に合わせて符号反転する(プロトタイプStep2確認済み)
        let rawDY = -ndy * settings.trackpadModeGain
        lastTouchPos = touch.normalized.position

        touchPathLength += (ndx * ndx + ndy * ndy).squareRoot()
        let velocity = touch.normalized.velocity
        let velocityMagnitude = (Double(velocity.x) * Double(velocity.x) + Double(velocity.y) * Double(velocity.y)).squareRoot()
        touchMaxVelocity = max(touchMaxVelocity, velocityMagnitude)
        touchFrameCount += 1

        os_unfair_lock_lock(&accLock)
        accDX += rawDX
        accDY += rawDY
        os_unfair_lock_unlock(&accLock)
    }

    /// タッチ終了(リリース)時にタップかどうかを判定し、成立していればクリックフラグを立てる。
    /// CGEventの生成はここでは行わない(MTコールバックの規律)。
    private func evaluateTapAndReset(endPos: MTPoint, endTime: Double, settings: SettingsSnapshot) {
        guard trackedID != nil else { return }
        trackedID = nil

        let dx = Double(endPos.x - touchStartPos.x)
        let dy = Double(endPos.y - touchStartPos.y)
        let straightDistance = (dx * dx + dy * dy).squareRoot()
        let duration = endTime - touchStartTime

        let isTap = duration <= settings.tapMaxDuration
            && straightDistance <= settings.tapMaxStraightDistance
            && touchPathLength <= settings.tapMaxPathLength
            && touchMaxVelocity <= settings.tapMaxVelocity
            && touchFrameCount >= settings.tapMinFrames

        if isTap {
            os_unfair_lock_lock(&accLock)
            accClickPending = true
            os_unfair_lock_unlock(&accLock)
        }
    }

    /// 専用キューのタイマーがアキュムレータをドレインし、mouseMoved / クリックを post する(120Hz)。
    private func drainAndPost() {
        os_unfair_lock_lock(&accLock)
        let dx = accDX
        let dy = accDY
        let clickPending = accClickPending
        let togglePending = accTogglePending
        accDX = 0
        accDY = 0
        accClickPending = false
        accTogglePending = false
        os_unfair_lock_unlock(&accLock)

        if dx != 0 || dy != 0 {
            if let current = CGEvent(source: nil)?.location {
                var newX = current.x + dx
                var newY = current.y + dy

                // 座標系は左上原点。まずメインディスプレイのみ対応し、範囲外に出ないようクランプする
                let bounds = CGDisplayBounds(CGMainDisplayID())
                newX = min(max(newX, bounds.minX), bounds.maxX - 1)
                newY = min(max(newY, bounds.minY), bounds.maxY - 1)

                if let src = CGEventSource(stateID: .hidSystemState),
                   let move = CGEvent(
                        mouseEventSource: src,
                        mouseType: .mouseMoved,
                        mouseCursorPosition: CGPoint(x: newX, y: newY),
                        mouseButton: .left
                   ) {
                    move.setIntegerValueField(.eventSourceUserData, value: SynthesizedClick.signature)
                    move.post(tap: .cghidEventTap)
                }
            }
        }

        if clickPending {
            SynthesizedClick.post(button: .left)
        }

        if togglePending {
            DispatchQueue.main.async { TrackpadModeController.shared.toggle() }
        }
    }
}
