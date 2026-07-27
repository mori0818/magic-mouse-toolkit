// Device-enumeration foundations are derived from MouseToucher.
// Copyright (c) 2025 Roger Hughes, used under the MIT License.
// See THIRD_PARTY_NOTICES.md. Magic Mouse Toolkit changes: GPL-3.0-only.

import AppKit
import IOKit
import QuartzCore

private let magicMouseFamilyIDs: Set<Int32> = [112, 113]

private func multitouchContactCallback(
    _ device: MTDeviceRef?,
    _ touches: UnsafeMutablePointer<MTTouch>?,
    _ numTouches: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32 {
    if let device, MTDeviceIsBuiltIn(device) {
        var touchingCount = 0
        if let touches, numTouches > 0 {
            let buffer = UnsafeBufferPointer(start: touches, count: Int(numTouches))
            for touch in buffer where touch.state == 4 {
                touchingCount += 1
            }
        }
        let shared = SharedState.shared
        shared.builtInTrackpadFingerCount = touchingCount
        shared.builtInTrackpadLastFrameAt = CACurrentMediaTime()
        return 0
    }

    guard let touches = touches, numTouches > 0 else {
        TouchGestureManager.shared.handleContactFrame(touches: UnsafeBufferPointer(start: nil, count: 0), timestamp: timestamp, frame: frame)
        return 0
    }
    let buffer = UnsafeBufferPointer(start: touches, count: Int(numTouches))
    TouchGestureManager.shared.handleContactFrame(touches: buffer, timestamp: timestamp, frame: frame)
    return 0
}

/// Magic Mouse のマルチタッチデバイスを列挙・フィルタし、コールバック登録/解除を管理する。
final class MultitouchDeviceManager {
    static let shared = MultitouchDeviceManager()
    private init() {}

    private var activeDevices: [MTDeviceRef] = []
    /// 内蔵トラックパッドはジェスチャー処理せず、入力元判別用の接触状態だけを監視する。
    private var builtInMonitorDevices: [MTDeviceRef] = []

    /// 再検出リトライの世代番号。restart() のたびにインクリメントし、
    /// 古い世代のリトライ予約を無効化する（スリープ復帰が連続した場合の多重リトライ防止）
    private var retryGeneration = 0
    private let retryInterval: TimeInterval = 2.0
    private let maxRetries = 15  // 2秒 × 15回 = 最大30秒待つ

    /// AppleMultitouchDevice の着脱監視（Bluetooth 再接続の検知）
    private var ioNotifyPort: IONotificationPortRef?
    private var ioMatchIterator: io_iterator_t = 0

    /// メニューバーの状態表示用
    private(set) var lastDiscoveredFamilyIDs: [Int32] = []
    private(set) var usedFallbackFilter = false
    var activeDeviceCount: Int { activeDevices.count }

    func start() {
        guard activeDevices.isEmpty else { return }
        let list = MTDeviceCreateList().takeRetainedValue()

        let count = CFArrayGetCount(list)
        var discoveredFamilyIDs: [Int32] = []
        var strictMatched: [MTDeviceRef] = []
        var externalDevices: [MTDeviceRef] = []
        var builtInDevices: [MTDeviceRef] = []

        MMTLog.log("デバイス列挙開始: 合計\(count)台のマルチタッチデバイス")

        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)

            var familyId: Int32 = -1
            let status = MTDeviceGetFamilyID(device, &familyId)
            let builtIn = MTDeviceIsBuiltIn(device)
            discoveredFamilyIDs.append(familyId)
            MMTLog.log("  デバイス[\(i)]: familyId=\(familyId) (status=\(status)) builtIn=\(builtIn)")

            if builtIn {
                builtInDevices.append(device)
                continue
            }
            externalDevices.append(device)

            if status == noErr, magicMouseFamilyIDs.contains(familyId) {
                strictMatched.append(device)
            }
        }

        lastDiscoveredFamilyIDs = discoveredFamilyIDs
        usedFallbackFilter = false

        var matched: [MTDeviceRef]
        if AppSettings.shared.deviceFilterStrict {
            matched = strictMatched
            // familyId が想定(112/113)と異なる Magic Mouse 個体への自動フォールバック:
            // 厳格フィルタで0台でも外部デバイスがあればそれを使う(内蔵トラックパッドは除外済み)
            if matched.isEmpty && !externalDevices.isEmpty {
                matched = externalDevices
                usedFallbackFilter = true
                MMTLog.log("familyIdフィルタ(112/113)に一致なし。外部デバイス\(externalDevices.count)台にフォールバック")
            }
        } else {
            matched = externalDevices
        }

        if matched.isEmpty {
            MMTLog.log("警告: 使用可能な外部マルチタッチデバイスなし。検出familyId: \(discoveredFamilyIDs)")
        }

        if builtInMonitorDevices.isEmpty {
            for device in builtInDevices {
                _ = Unmanaged<AnyObject>.fromOpaque(device).retain()
                MTRegisterContactFrameCallback(device, multitouchContactCallback)
                MTDeviceStart(device, 0)
            }
            builtInMonitorDevices = builtInDevices
            MMTLog.log("内蔵トラックパッド監視開始: \(builtInDevices.count)台（入力元判別のみ）")
        }

        for device in matched {
            // activeDevices に保持する間は自前で所有権を持つ。retain しないと
            // CreateList の配列解放後は MultitouchSupport の内部参照だけが命綱になり、
            // スリープ中のBluetooth切断でフレームワークが参照を手放した瞬間に
            // 「稼働中デバイスの最終解放」が内部スレッド上で走って CFRelease(NULL) で
            // クラッシュする(2026-07-11 スリープ中クラッシュの主因)。
            _ = Unmanaged<AnyObject>.fromOpaque(device).retain()
            MTRegisterContactFrameCallback(device, multitouchContactCallback)
            MTDeviceStart(device, 0)
        }
        activeDevices = matched
        MMTLog.log("タッチ監視開始: \(matched.count)台")
    }

    func stop() {
        // 先に activeDevices を空にする: willSleep と restart() が近接して二重に
        // 呼ばれても、同じ参照に二度 MTDeviceStop しないための再入ガード
        let devices = activeDevices + builtInMonitorDevices
        activeDevices.removeAll()
        builtInMonitorDevices.removeAll()
        guard !devices.isEmpty else { return }
        for device in devices {
            MTUnregisterContactFrameCallback(device, multitouchContactCallback)
            MTDeviceStop(device)
            // start() での CFRetain と対。停止処理の後に自前スレッドで最終解放する
            Unmanaged<AnyObject>.fromOpaque(device).release()
        }
        SharedState.shared.builtInTrackpadFingerCount = 0
        SharedState.shared.builtInTrackpadLastFrameAt = -1e9
        MMTLog.log("タッチ監視停止: \(devices.count)台を解放")
    }

    /// デバイスを再検出する。スリープ復帰直後は Magic Mouse の Bluetooth 再接続が
    /// 数秒〜十数秒遅れるため、一度の列挙で外部デバイスが見つからなくても
    /// 2秒間隔で最大30秒リトライする（一発列挙で0台のまま死ぬバグの修正）。
    func restart() {
        MMTLog.log("デバイス再検出")
        retryGeneration += 1
        let generation = retryGeneration
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.attemptStart(generation: generation, attempt: 1)
        }
    }

    private func attemptStart(generation: Int, attempt: Int) {
        guard generation == retryGeneration else { return }  // 新しい restart() に取って代わられた
        start()
        if activeDeviceCount > 0 { return }
        guard attempt < maxRetries else {
            MMTLog.log("デバイス再検出: \(maxRetries)回試行しても外部デバイスなし。接続通知を待ちます")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryInterval) { [weak self] in
            self?.attemptStart(generation: generation, attempt: attempt + 1)
        }
    }

    // MARK: - デバイス着脱監視（IOKit）

    /// AppleMultitouchDevice の登録（= Magic Mouse の Bluetooth 接続/再接続）を監視し、
    /// 接続を検知したら再検出する。スリープを伴わないアイドル切断→再接続
    /// （didWakeNotification が飛ばないケース）もこれで拾える。
    func startHotplugMonitoring() {
        guard ioNotifyPort == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            MMTLog.log("警告: IONotificationPort の作成に失敗（着脱監視なしで継続）")
            return
        }
        ioNotifyPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching("AppleMultitouchDevice"),
            { refcon, iterator in
                guard let refcon = refcon else { return }
                let manager = Unmanaged<MultitouchDeviceManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleDeviceMatched(iterator: iterator)
            },
            selfPtr,
            &ioMatchIterator
        )
        guard result == KERN_SUCCESS else {
            MMTLog.log("警告: デバイス着脱通知の登録に失敗 (\(result))")
            IONotificationPortDestroy(port)
            ioNotifyPort = nil
            return
        }
        // 通知を有効化するには初回に iterator を空にする必要がある（既存デバイスが列挙される）
        drainIterator(ioMatchIterator)
        MMTLog.log("デバイス着脱監視を開始 (AppleMultitouchDevice)")
    }

    func stopHotplugMonitoring() {
        if ioMatchIterator != 0 {
            IOObjectRelease(ioMatchIterator)
            ioMatchIterator = 0
        }
        if let port = ioNotifyPort {
            IONotificationPortDestroy(port)
            ioNotifyPort = nil
        }
    }

    private func handleDeviceMatched(iterator: io_iterator_t) {
        drainIterator(iterator)
        // MultitouchSupport 側の登録が落ち着くまで少し待ってから再検出する。
        // restart() 側の世代管理により、通知が連続しても最後の1回だけが生き残る。
        MMTLog.log("マルチタッチデバイスの接続を検知")
        restart()
    }

    private func drainIterator(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
