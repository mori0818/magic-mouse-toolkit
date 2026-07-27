import Foundation
import IOKit
import CoreGraphics
import os

// Step 4: TapRecognizer(本体 Sources/TapRecognizer.swift + Settings.swift のデフォルト閾値)
// を流用したタップ→クリック判定を追加。ドラッグ(タップ&ホールド)はフェーズ2で対象外。
// 安全プロトコル(手順書 magic-mouse-toolkit-仮想トラックパッド実装手順.md 準拠)を引き続き厳守:
//   - 自動タイムアウト必須(既定60秒、引数で延長しても120秒でクランプ)
//   - killタイマーを事前アームしてから起動すること(このプログラム自体は行わない)
//   - TCC権限のON/OFFは絶対に試さない
// 検証項目:
//   - タップが正しくクリックとして認識されるか
//   - カーソル移動(ドラッグ相当)がタップと誤認識されないか(誤クリック率)
//
// 起動: ./build.sh && ./build/VirtualPadProto [seconds(既定60・最大120にクランプ)]

private let magicMouseFamilyIDs: Set<Int32> = [112, 113]

// 自己合成した mouseMoved に埋める署名。EventInterceptor 統合時、
// SynthesizedClick.signature("MCLK") と同じ仕組みで自己イベントの再入を避けるため別値にする。
private let virtualPadSignature: Int64 = 0x5650_4144  // "VPAD"

// 固定ゲイン: 正規化座標(表面全幅=1.0)を画面ピクセルに変換。まずタッチ全幅≈1000px相当から開始
private let gain: Double = 1000.0

// タップ判定閾値。Sources/Settings.swift のデフォルト値(tapMax*)をそのまま流用。
private let tapMaxDuration: Double = 0.25
private let tapMaxStraightDistance: Double = 0.15
private let tapMaxPathLength: Double = 0.18
private let tapMaxVelocity: Double = 4.0
private let tapMinFrames: Int = 2

private var activeDevices: [MTDeviceRef] = []

// MTコールバックとドレインタイマー間で共有するアキュムレータ。
// 手順書の規律どおり、MTコールバック内では CGEvent を作らずここに書き込むだけにする。
private var accLock = os_unfair_lock()
private var accDX: Double = 0
private var accDY: Double = 0
private var accClickPending = false

// 現在追跡中の指(1本のみ)。複数指が触れていても最初に見つかった1本だけを使う。
private var trackedID: Int32? = nil
private var lastTouchPos: MTPoint = MTPoint(x: 0, y: 0)

// タップ判定用の追跡状態(タッチ開始時にリセット)
private var touchStartPos: MTPoint = MTPoint(x: 0, y: 0)
private var touchStartTime: Double = 0
private var touchPathLength: Double = 0
private var touchMaxVelocity: Double = 0
private var touchFrameCount: Int = 0

private var frameCount = 0
private var lastLogTime: Double = 0

// スクロール抑制タップ(Step 3)
private var scrollTap: CFMachPort?
private var scrollRunLoopSource: CFRunLoopSource?

/// scrollWheel を握りつぶす(nilを返す)ためのタップコールバック。
/// EventInterceptor.swift と同じ規律: tapDisabledByTimeoutはその場で再有効化、
/// tapDisabledByUserInputは何もしない(権限剥奪時は配送自体が止まるため無意味)。
private func scrollSuppressionCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout {
        if let tap = scrollTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[診断] scrollTap: タイムアウトにより無効化されたため再有効化")
        }
        return Unmanaged.passUnretained(event)
    }
    if type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }
    // scrollWheel のみ購読しているので、ここに来るのは基本 scrollWheel。飲み込む。
    return nil
}

private func startScrollSuppression() {
    let eventsOfInterest: CGEventMask = (1 << CGEventType.scrollWheel.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventsOfInterest,
        callback: scrollSuppressionCallback,
        userInfo: nil
    ) else {
        print("エラー: スクロール抑制タップの作成に失敗(アクセシビリティ権限を確認)")
        return
    }
    scrollTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    scrollRunLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    print("スクロール抑制タップ: 有効化")
}

private func stopScrollSuppression() {
    if let source = scrollRunLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    if let tap = scrollTap {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
    }
    scrollTap = nil
    scrollRunLoopSource = nil
    print("スクロール抑制タップ: 無効化(スクロール復帰)")
}

/// タッチ終了(リリース)時にタップかどうかを判定し、成立していればクリックフラグを立てる。
/// CGEventの生成はここでは行わない(MTコールバックの規律)。
private func evaluateTapAndReset(endPos: MTPoint, endTime: Double) {
    guard trackedID != nil else { return }
    trackedID = nil

    let dx = Double(endPos.x - touchStartPos.x)
    let dy = Double(endPos.y - touchStartPos.y)
    let straightDistance = (dx * dx + dy * dy).squareRoot()
    let duration = endTime - touchStartTime

    let isTap = duration <= tapMaxDuration
        && straightDistance <= tapMaxStraightDistance
        && touchPathLength <= tapMaxPathLength
        && touchMaxVelocity <= tapMaxVelocity
        && touchFrameCount >= tapMinFrames

    print(String(
        format: "[Tap] %@ duration=%.3f distance=%.3f path=%.3f maxVel=%.2f frames=%d",
        isTap ? "成立" : "不成立", duration, straightDistance, touchPathLength, touchMaxVelocity, touchFrameCount
    ))

    if isTap {
        os_unfair_lock_lock(&accLock)
        accClickPending = true
        os_unfair_lock_unlock(&accLock)
    }
}

private func contactCallback(
    _ device: MTDeviceRef?,
    _ touches: UnsafeMutablePointer<MTTouch>?,
    _ numTouches: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32 {
    frameCount += 1

    guard let touches = touches, numTouches > 0 else {
        evaluateTapAndReset(endPos: lastTouchPos, endTime: timestamp)
        return 0
    }
    let buffer = UnsafeBufferPointer(start: touches, count: Int(numTouches))

    // state 4 = Touching。最初に見つかった1本だけを追跡する(複数指はStep2の対象外)
    guard let touch = buffer.first(where: { $0.state == 4 }) else {
        evaluateTapAndReset(endPos: lastTouchPos, endTime: timestamp)
        return 0
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
        return 0
    }

    let ndx = Double(touch.normalized.position.x - lastTouchPos.x)
    let ndy = Double(touch.normalized.position.y - lastTouchPos.y)
    let rawDX = ndx * gain
    // MTの正規化Yは前方(指を伸ばす先端側)が大きい。画面は上原点でYが下に増えるため、
    // 「前方へなぞる=カーソルが上へ動く」という直感に合わせて符号反転する(Step2確認済み)
    let rawDY = -ndy * gain
    lastTouchPos = touch.normalized.position

    touchPathLength += (ndx * ndx + ndy * ndy).squareRoot()
    let velocity = touch.normalized.velocity
    let velocityMagnitude = (Double(velocity.x) * Double(velocity.x) + Double(velocity.y) * Double(velocity.y)).squareRoot()
    touchMaxVelocity = max(touchMaxVelocity, velocityMagnitude)
    touchFrameCount += 1

    if timestamp - lastLogTime > 0.1 {
        lastLogTime = timestamp
        print(String(format: "delta dx=%.2f dy=%.2f pos=(%.3f,%.3f)", rawDX, rawDY, touch.normalized.position.x, touch.normalized.position.y))
    }

    os_unfair_lock_lock(&accLock)
    accDX += rawDX
    accDY += rawDY
    os_unfair_lock_unlock(&accLock)

    return 0
}

/// 専用キューのタイマーがアキュムレータをドレインし、mouseMoved / クリックを post する(120Hz)。
private func drainAndPost() {
    os_unfair_lock_lock(&accLock)
    let dx = accDX
    let dy = accDY
    let clickPending = accClickPending
    accDX = 0
    accDY = 0
    accClickPending = false
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
                move.setIntegerValueField(.eventSourceUserData, value: virtualPadSignature)
                move.post(tap: .cghidEventTap)
            }
        }
    }

    if clickPending {
        postSynthesizedClick()
    }
}

/// タップ確定時のクリック合成。移動合成と同じ署名(virtualPadSignature)を使い、
/// 自己合成イベントであることを示す(統合時、既存 EventInterceptor 側での再入判定に利用可能)。
private func postSynthesizedClick() {
    guard let loc = CGEvent(source: nil)?.location else { return }
    guard let src = CGEventSource(stateID: .hidSystemState) else { return }
    guard
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: loc, mouseButton: .left),
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: loc, mouseButton: .left)
    else { return }
    down.setIntegerValueField(.eventSourceUserData, value: virtualPadSignature)
    up.setIntegerValueField(.eventSourceUserData, value: virtualPadSignature)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    print(String(format: "[Tap] クリック合成 loc=(%.0f,%.0f)", loc.x, loc.y))
}

private func startDevices() {
    let list = MTDeviceCreateList().takeRetainedValue()
    let count = CFArrayGetCount(list)
    var matched: [MTDeviceRef] = []
    var externalDevices: [MTDeviceRef] = []

    print("デバイス列挙: 合計\(count)台")
    for i in 0..<count {
        guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
        let device = UnsafeMutableRawPointer(mutating: raw)
        var familyId: Int32 = -1
        let status = MTDeviceGetFamilyID(device, &familyId)
        let builtIn = MTDeviceIsBuiltIn(device)
        print("  [\(i)] familyId=\(familyId) status=\(status) builtIn=\(builtIn)")
        guard !builtIn else { continue }
        externalDevices.append(device)
        if status == noErr, magicMouseFamilyIDs.contains(familyId) {
            matched.append(device)
        }
    }
    if matched.isEmpty {
        matched = externalDevices
        if !matched.isEmpty {
            print("familyIdフィルタに一致なし。外部デバイス\(matched.count)台にフォールバック")
        }
    }
    if matched.isEmpty {
        print("警告: 使用可能なマルチタッチデバイスが見つかりません")
    }

    for device in matched {
        _ = Unmanaged<AnyObject>.fromOpaque(device).retain()
        MTRegisterContactFrameCallback(device, contactCallback)
        MTDeviceStart(device, 0)
    }
    activeDevices = matched
    print("タッチ監視開始: \(matched.count)台")
}

private func stopDevices() {
    for device in activeDevices {
        MTUnregisterContactFrameCallback(device, contactCallback)
        MTDeviceStop(device)
        Unmanaged<AnyObject>.fromOpaque(device).release()
    }
    activeDevices.removeAll()
    print("タッチ監視停止")
}

signal(SIGINT) { _ in
    print("\nSIGINT受信。終了処理中...")
    stopScrollSuppression()
    stopDevices()
    exit(0)
}

startDevices()
startScrollSuppression()

// mouseMoved のドレイン専用タイマー(120Hz、専用シリアルキュー)
let drainQueue = DispatchQueue(label: "com.mori0818.magicmousetoolkit.virtualpad.drain")
let drainTimer = DispatchSource.makeTimerSource(queue: drainQueue)
drainTimer.schedule(deadline: .now(), repeating: 1.0 / 120.0)
drainTimer.setEventHandler { drainAndPost() }
drainTimer.resume()

// フレームレート(Hz)を1秒ごとに報告
let hzTimer = DispatchSource.makeTimerSource(queue: .main)
hzTimer.schedule(deadline: .now() + 1, repeating: 1)
hzTimer.setEventHandler {
    print("[Hz] \(frameCount) frames/sec")
    frameCount = 0
}
hzTimer.resume()

// 安全プロトコル: 自動タイムアウトは必須。既定60秒、引数を渡しても120秒でクランプする。
let args = CommandLine.arguments
let requestedSeconds = (args.count > 1 ? Double(args[1]) : nil) ?? 60.0
let seconds = min(requestedSeconds, 120.0)
print("\(seconds)秒後に自動的にスクロール抑制を解除し終了します(安全プロトコル・120秒でクランプ)")
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    print("タイムアウト。終了します")
    stopScrollSuppression()
    stopDevices()
    exit(0)
}

print("Step4: カーソル移動合成+スクロール抑制+タップ→クリックを実行中(モードON状態。Ctrl-Cで終了)...")
RunLoop.main.run()
