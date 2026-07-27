import Foundation
import CoreFoundation
import IOKit

/// システム設定の上限(3.0)を超えてカーソルの軌跡速度をブーストする。
/// IOHIDEventSystemClient 経由で HIDMouseAcceleration(システム設定スライダーの実体)を
/// 直接書き換える(SPI依存。2026-07-10 判断メモ参照)。
final class PointerSpeedManager {
    static let shared = PointerSpeedManager()

    private static let accelerationKey = "HIDMouseAcceleration" as CFString
    /// 初回取得時の元値を永続化するキー。ブースト適用中にkillされ復元が走らなかった場合でも、
    /// 次回起動時にブースト済みの値を元値として誤保持しない（汚染の連鎖防止）
    private static let originalValueDefaultsKey = "mmt.pointer.originalAcceleration"
    /// システム設定「軌跡の速さ」スライダーの上限。これを超える値はユーザー設定ではあり得ない
    private static let systemSliderMax = 3.0

    private var client: IOHIDEventSystemClientRef?
    /// 復元先の元値。初回取得時にUserDefaultsへ永続化した値を優先する（resolveOriginalValue参照）
    private var originalValue: Double?

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
    }

    /// AppDelegate起動シーケンスから1回呼ぶ。クライアント生成・元値の保持・現在設定の適用を行う。
    func start() {
        guard client == nil else { return }
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        originalValue = resolveOriginalValue()
        MMTLog.log("PointerSpeedManager: 元値を確定 \(originalValue.map { String($0) } ?? "未確定")")
        applyFromSettings()
    }

    /// スリープ復帰など、システム側の値が上書きされ得るタイミングで再適用する。
    func reapply() {
        guard client != nil else { return }
        applyFromSettings()
    }

    /// アプリ終了直前に呼ぶ。ブースト中であれば元の値へ復元する。
    func restoreAndStop() {
        guard client != nil else { return }
        if let original = originalValue {
            write(original)
            MMTLog.log("PointerSpeedManager: 終了時に元値へ復元 \(original)")
        }
        client = nil
    }

    @objc private func settingsChanged() {
        applyFromSettings()
    }

    private func applyFromSettings() {
        let boost = AppSettings.shared.pointerSpeedBoost
        if boost <= 0 {
            if let original = originalValue {
                write(original)
            }
        } else {
            write(boost)
        }
    }

    /// 復元先となる「元値」を決める。単純に起動時の現在値を採用すると、ブースト適用中に
    /// killされた場合にブースト済みの値を元値として保持してしまう（実際に発生した汚染連鎖）。
    /// そのため初回取得時にUserDefaultsへ永続化し、以後の起動では保存値を優先する。
    private func resolveOriginalValue() -> Double? {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: Self.originalValueDefaultsKey) as? Double

        guard let current = readCurrentValue() else {
            MMTLog.log("PointerSpeedManager: 現在値の取得に失敗。保存済み元値を使用 \(saved.map { String($0) } ?? "なし")")
            return saved
        }

        if looksLikeLeftoverBoost(current) {
            if let saved {
                MMTLog.log("PointerSpeedManager: 現在値 \(current) は前回のブースト残留。保存済み元値 \(saved) を使用")
                return saved
            }
            MMTLog.log("PointerSpeedManager: 現在値 \(current) はブースト残留の疑いがあり元値にできない。システム設定のスライダーを一度動かすと再取得する")
            return nil
        }

        if let saved, quantized(saved) == quantized(current) {
            return saved
        }
        if let saved {
            MMTLog.log("PointerSpeedManager: 保存済み元値 \(saved) と現在値 \(current) が乖離。システム設定の変更とみなし元値を更新")
        }
        defaults.set(current, forKey: Self.originalValueDefaultsKey)
        return current
    }

    /// 現在値が「前回セッションで適用したブーストの残留」に見えるか。
    /// システムスライダーの上限を超えている、またはブースト設定値と
    /// 固定小数点量子化後に一致する場合はユーザー設定ではないと判断する。
    private func looksLikeLeftoverBoost(_ current: Double) -> Bool {
        if current > Self.systemSliderMax + 0.0001 { return true }
        let boost = AppSettings.shared.pointerSpeedBoost
        return boost > 0 && quantized(boost) == quantized(current)
    }

    /// HIDMouseAccelerationの固定小数点表現(×65536)。書き込み時と同じ量子化で値を比較する
    private func quantized(_ value: Double) -> Int32 {
        Int32((value * 65536.0).rounded())
    }

    private func readCurrentValue() -> Double? {
        guard let client else { return nil }
        guard let raw = IOHIDEventSystemClientCopyProperty(client, Self.accelerationKey) else {
            return nil
        }
        let number = raw as! CFNumber
        var fixed: Int32 = 0
        guard CFNumberGetValue(number, .sInt32Type, &fixed) else { return nil }
        return Double(fixed) / 65536.0
    }

    private func write(_ value: Double) {
        guard let client else { return }
        let fixed = Int32((value * 65536.0).rounded())
        var mutableFixed = fixed
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &mutableFixed) else { return }
        IOHIDEventSystemClientSetProperty(client, Self.accelerationKey, number)
    }
}
