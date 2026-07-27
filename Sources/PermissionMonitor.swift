import CoreGraphics
import Foundation

/// アクセシビリティ(正確には CGEventTap の PostEvent/ListenEvent)権限の有無を監視する。
///
/// `AXIsProcessTrusted()` は権限をシステム設定でOFFにした直後もTCCキャッシュにより
/// true を返し続けるため、実行中の権限喪失検知には使えないことが実機・フォーラム双方で
/// 確認されている(SAFETY.md参照)。このため本クラスは「実際にテスト用タップを
/// 作成できるか」でのみ権限判定を行う。CGEventTapCreate は権限が無ければ即座に NULL を
/// 返すため、これが唯一信頼できる判定方法。
///
/// メインRunLoopには一切依存しない(バックグラウンドキューでポーリングし、結果だけ
/// メインスレッドへ dispatch する)。旧実装の Timer.scheduledTimer はメインRunLoopが
/// 何らかの理由でブロックされると発火しなくなる弱点があったため置き換えた。
enum PermissionMonitor {
    private static let queue = DispatchQueue(label: "com.mori0818.magicmousetoolkit.permission.monitor", qos: .utility)
    private static var timer: DispatchSourceTimer?

    // 以下はすべてメインスレッド上でのみ読み書きする(コールバックは必ず main.async 経由)。
    private static var consecutiveGranted = 0
    private static var lastReportedGranted: Bool?

    /// 本タップ(.cghidEventTap + .headInsertEventTap)とは無関係な、判定専用の
    /// 軽量タップを作って即破棄する。.listenOnly かつ .cgSessionEventTap /
    /// .tailAppendEventTap を使い、本タップの登録・イベント配送に一切干渉しない。
    static func canCreateEventTap() -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        return true
    }

    /// 1秒間隔でポーリングを開始する。状態が変化した時だけコールバックを呼ぶ。
    /// - 権限喪失(OFF)は1回の失敗で即座に通知する(フリーズの引き金になり得るため、
    ///   検知の速さを優先する)。
    /// - 権限復帰(ON)は2回連続成功してから通知する(削除→再追加直後などTCCの状態が
    ///   一瞬不安定になる場面での誤検知・タップの作り直しすぎを避けるため)。
    static func start(onGranted: @escaping () -> Void, onRevoked: @escaping () -> Void) {
        stop()
        consecutiveGranted = 0
        lastReportedGranted = nil

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler {
            let granted = canCreateEventTap()
            DispatchQueue.main.async {
                handleResult(granted, onGranted: onGranted, onRevoked: onRevoked)
            }
        }
        t.resume()
        timer = t
    }

    static func stop() {
        timer?.cancel()
        timer = nil
    }

    private static func handleResult(_ granted: Bool, onGranted: () -> Void, onRevoked: () -> Void) {
        if granted {
            consecutiveGranted += 1
            if consecutiveGranted >= 2 && lastReportedGranted != true {
                lastReportedGranted = true
                onGranted()
            }
        } else {
            consecutiveGranted = 0
            if lastReportedGranted != false {
                lastReportedGranted = false
                onRevoked()
            }
        }
    }
}
