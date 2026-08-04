import Foundation
import Darwin
import CoreGraphics

extension Notification.Name {
    static let settingsChanged = Notification.Name("com.mori0818.magicmousetoolkit.settingsChanged")
}

/// コールバックスレッドから安全に読める、設定値のイミュータブルなスナップショット。
struct SettingsSnapshot {
    var enabled: Bool
    var oneFingerTapEnabled: Bool
    /// ONのとき1本指タップは位置に関係なく常に左クリック。右クリックは物理クリックのみになる
    var tapAlwaysLeftClick: Bool
    var twoFingerTapEnabled: Bool
    var threeFingerTapEnabled: Bool
    var threeFingerTapAction: ActionKind
    var middleClickEnabled: Bool
    var verticalScrollOnly: Bool

    var rightZoneMinX: Double
    var zoneMinX: Double
    var zoneMaxX: Double
    var zoneMinY: Double
    var zoneMaxY: Double

    var tapMaxDuration: Double
    var tapMaxStraightDistance: Double
    var tapMaxPathLength: Double
    var tapMaxVelocity: Double
    var tapMinFrames: Int

    var scrollVetoWindow: Double
    var buttonVetoWindow: Double
    var twoFingerSyncWindow: Double

    /// 0 = オフ(システム設定に従う)。0より大きい場合はその値をHIDMouseAccelerationへ書き込む
    var pointerSpeedBoost: Double

    // 仮想トラックパッドモード
    var trackpadModeGain: Double
}

/// UserDefaults バックの設定モデル。値変更のたびに `.settingsChanged` を通知する。
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// SettingsView の @AppStorage から同一キーを参照するため internal（モジュール内共有）にする。
    enum Key {
        static let enabled = "mmt.enabled"
        static let oneFingerTapEnabled = "mmt.tap1.enabled"
        static let tapAlwaysLeftClick = "mmt.tap1.alwaysLeft"
        static let twoFingerTapEnabled = "mmt.tap2.enabled"
        static let threeFingerTapEnabled = "mmt.tap3.enabled"
        static let threeFingerTapAction = "mmt.tap3.action"
        static let middleClickEnabled = "mmt.middle.enabled"
        static let verticalScrollOnly = "mmt.scroll.verticalOnly"

        static let rightZoneMinX = "mmt.zone.rightMinX"
        static let zoneMinX = "mmt.zone.minX"
        static let zoneMaxX = "mmt.zone.maxX"
        static let zoneMinY = "mmt.zone.minY"
        static let zoneMaxY = "mmt.zone.maxY"

        static let tapMaxDuration = "mmt.tap.maxDuration"
        static let tapMaxStraightDistance = "mmt.tap.maxStraight"
        static let tapMaxPathLength = "mmt.tap.maxPath"
        static let tapMaxVelocity = "mmt.tap.maxVelocity"
        static let tapMinFrames = "mmt.tap.minFrames"

        static let scrollVetoWindow = "mmt.veto.scroll"
        static let buttonVetoWindow = "mmt.veto.button"
        static let twoFingerSyncWindow = "mmt.tap2.syncWindow"

        static let pointerSpeedBoost = "mmt.pointer.speedBoost"

        static let trackpadModeGain = "mmt.trackpad.gain"
    }

    /// 3本指タップの既定アクション: トラックパッドモード切替。有効化しただけで意味のある動作をする。
    private static let defaultThreeFingerTapActionJSON: String = {
        let action = ActionKind.toggleTrackpadMode
        guard let data = try? JSONEncoder().encode(action),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }()

    static let defaultValues: [String: Any] = [
        Key.enabled: true,
        Key.oneFingerTapEnabled: true,
        Key.tapAlwaysLeftClick: false,
        Key.twoFingerTapEnabled: true,
        Key.threeFingerTapEnabled: false,
        Key.threeFingerTapAction: defaultThreeFingerTapActionJSON,
        Key.middleClickEnabled: true,
        Key.verticalScrollOnly: false,

        Key.rightZoneMinX: 0.6,
        // 反応範囲の初期値: 横は全域、縦は前方(先端側)25%のみ
        Key.zoneMinX: 0.0,
        Key.zoneMaxX: 1.0,
        Key.zoneMinY: 0.75,
        Key.zoneMaxY: 1.0,

        // 反応しやすさ優先の初期値（実機キャリブレーション前提の緩め設定）
        Key.tapMaxDuration: 0.25,
        Key.tapMaxStraightDistance: 0.15,
        Key.tapMaxPathLength: 0.18,
        Key.tapMaxVelocity: 4.0,
        Key.tapMinFrames: 2,

        Key.scrollVetoWindow: 0.20,
        Key.buttonVetoWindow: 0.10,
        Key.twoFingerSyncWindow: 0.08,

        Key.pointerSpeedBoost: 0.0,

        // プロトタイプ検証(2026-07-20 Step5)でゲイン調整不要と確認済みの値
        Key.trackpadModeGain: 1000.0,
    ]

    private init() {}

    /// AppDelegate起動シーケンスの最初に呼ぶ。
    func registerDefaults() {
        defaults.register(defaults: AppSettings.defaultValues)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled); notifyChanged() }
    }
    var oneFingerTapEnabled: Bool {
        get { defaults.bool(forKey: Key.oneFingerTapEnabled) }
        set { defaults.set(newValue, forKey: Key.oneFingerTapEnabled); notifyChanged() }
    }
    /// ONのとき1本指タップは位置に関係なく常に左クリック。右クリックは物理クリックのみになる
    var tapAlwaysLeftClick: Bool {
        get { defaults.bool(forKey: Key.tapAlwaysLeftClick) }
        set { defaults.set(newValue, forKey: Key.tapAlwaysLeftClick); notifyChanged() }
    }
    var twoFingerTapEnabled: Bool {
        get { defaults.bool(forKey: Key.twoFingerTapEnabled) }
        set { defaults.set(newValue, forKey: Key.twoFingerTapEnabled); notifyChanged() }
    }
    var threeFingerTapEnabled: Bool {
        get { defaults.bool(forKey: Key.threeFingerTapEnabled) }
        set { defaults.set(newValue, forKey: Key.threeFingerTapEnabled); notifyChanged() }
    }
    /// ActionKind をJSON文字列としてUserDefaultsに保存する。デコード失敗時は空のマクロ(.macro([]))
    /// にフォールバックする(安全側)。
    var threeFingerTapAction: ActionKind {
        get {
            guard let json = defaults.string(forKey: Key.threeFingerTapAction),
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(ActionKind.self, from: data) else {
                return .macro([])
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            defaults.set(json, forKey: Key.threeFingerTapAction)
            notifyChanged()
        }
    }
    var middleClickEnabled: Bool {
        get { defaults.bool(forKey: Key.middleClickEnabled) }
        set { defaults.set(newValue, forKey: Key.middleClickEnabled); notifyChanged() }
    }
    var verticalScrollOnly: Bool {
        get { defaults.bool(forKey: Key.verticalScrollOnly) }
        set { defaults.set(newValue, forKey: Key.verticalScrollOnly); notifyChanged() }
    }

    var rightZoneMinX: Double {
        get { defaults.double(forKey: Key.rightZoneMinX) }
        set { defaults.set(newValue, forKey: Key.rightZoneMinX); notifyChanged() }
    }
    var zoneMinX: Double {
        get { defaults.double(forKey: Key.zoneMinX) }
        set { defaults.set(newValue, forKey: Key.zoneMinX); notifyChanged() }
    }
    var zoneMaxX: Double {
        get { defaults.double(forKey: Key.zoneMaxX) }
        set { defaults.set(newValue, forKey: Key.zoneMaxX); notifyChanged() }
    }
    var zoneMinY: Double {
        get { defaults.double(forKey: Key.zoneMinY) }
        set { defaults.set(newValue, forKey: Key.zoneMinY); notifyChanged() }
    }
    var zoneMaxY: Double {
        get { defaults.double(forKey: Key.zoneMaxY) }
        set { defaults.set(newValue, forKey: Key.zoneMaxY); notifyChanged() }
    }

    var tapMaxDuration: Double {
        get { defaults.double(forKey: Key.tapMaxDuration) }
        set { defaults.set(newValue, forKey: Key.tapMaxDuration); notifyChanged() }
    }
    var tapMaxStraightDistance: Double {
        get { defaults.double(forKey: Key.tapMaxStraightDistance) }
        set { defaults.set(newValue, forKey: Key.tapMaxStraightDistance); notifyChanged() }
    }
    var tapMaxPathLength: Double {
        get { defaults.double(forKey: Key.tapMaxPathLength) }
        set { defaults.set(newValue, forKey: Key.tapMaxPathLength); notifyChanged() }
    }
    var tapMaxVelocity: Double {
        get { defaults.double(forKey: Key.tapMaxVelocity) }
        set { defaults.set(newValue, forKey: Key.tapMaxVelocity); notifyChanged() }
    }
    var tapMinFrames: Int {
        get { defaults.integer(forKey: Key.tapMinFrames) }
        set { defaults.set(newValue, forKey: Key.tapMinFrames); notifyChanged() }
    }

    var scrollVetoWindow: Double {
        get { defaults.double(forKey: Key.scrollVetoWindow) }
        set { defaults.set(newValue, forKey: Key.scrollVetoWindow); notifyChanged() }
    }
    var buttonVetoWindow: Double {
        get { defaults.double(forKey: Key.buttonVetoWindow) }
        set { defaults.set(newValue, forKey: Key.buttonVetoWindow); notifyChanged() }
    }
    var twoFingerSyncWindow: Double {
        get { defaults.double(forKey: Key.twoFingerSyncWindow) }
        set { defaults.set(newValue, forKey: Key.twoFingerSyncWindow); notifyChanged() }
    }

    /// 0 = オフ(システム設定のまま)。0より大きい値はHIDMouseAccelerationへ直接書き込む
    /// (システム設定スライダーの上限3.0を超える値も設定可能)。
    var pointerSpeedBoost: Double {
        get { defaults.double(forKey: Key.pointerSpeedBoost) }
        set { defaults.set(newValue, forKey: Key.pointerSpeedBoost); notifyChanged() }
    }

    var trackpadModeGain: Double {
        get { defaults.double(forKey: Key.trackpadModeGain) }
        set { defaults.set(newValue, forKey: Key.trackpadModeGain); notifyChanged() }
    }

    /// 永続化されたキーを削除して registration domain の値に戻す。
    /// 既定値自体を変更した将来のバージョンでも正しく追従する。
    private func removeAndNotify(_ keys: [String]) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        notifyChanged()
    }

    func resetAllToDefaults() {
        removeAndNotify(Array(AppSettings.defaultValues.keys))
    }

    func resetZoneToDefaults() {
        removeAndNotify([Key.zoneMinX, Key.zoneMaxX, Key.zoneMinY, Key.zoneMaxY])
    }

    func resetSensitivityToDefaults() {
        removeAndNotify([Key.tapMaxDuration, Key.tapMaxStraightDistance,
                         Key.tapMaxPathLength, Key.tapMaxVelocity, Key.tapMinFrames])
    }

    func resetVetoToDefaults() {
        removeAndNotify([Key.scrollVetoWindow, Key.buttonVetoWindow, Key.twoFingerSyncWindow])
    }

    func makeSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            enabled: enabled,
            oneFingerTapEnabled: oneFingerTapEnabled,
            tapAlwaysLeftClick: tapAlwaysLeftClick,
            twoFingerTapEnabled: twoFingerTapEnabled,
            threeFingerTapEnabled: threeFingerTapEnabled,
            threeFingerTapAction: threeFingerTapAction,
            middleClickEnabled: middleClickEnabled,
            verticalScrollOnly: verticalScrollOnly,
            rightZoneMinX: rightZoneMinX,
            zoneMinX: zoneMinX,
            zoneMaxX: zoneMaxX,
            zoneMinY: zoneMinY,
            zoneMaxY: zoneMaxY,
            tapMaxDuration: tapMaxDuration,
            tapMaxStraightDistance: tapMaxStraightDistance,
            tapMaxPathLength: tapMaxPathLength,
            tapMaxVelocity: tapMaxVelocity,
            tapMinFrames: tapMinFrames,
            scrollVetoWindow: scrollVetoWindow,
            buttonVetoWindow: buttonVetoWindow,
            twoFingerSyncWindow: twoFingerSyncWindow,
            pointerSpeedBoost: pointerSpeedBoost,
            trackpadModeGain: trackpadModeGain
        )
    }
}

/// コールバックスレッド（MTコールバック・CGEventTap）から安全に読める SettingsSnapshot キャッシュ。
/// `.settingsChanged` 通知を受けたときだけメインスレッドで UserDefaults を読み直し、
/// コールバック内では絶対に UserDefaults へアクセスしない。
final class SettingsStore {
    static let shared = SettingsStore()

    private var lock = os_unfair_lock()
    private var _snapshot: SettingsSnapshot

    private init() {
        _snapshot = AppSettings.shared.makeSnapshot()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: .settingsChanged, object: nil)
    }

    @objc private func refresh() {
        let newSnapshot = AppSettings.shared.makeSnapshot()
        os_unfair_lock_lock(&lock)
        _snapshot = newSnapshot
        os_unfair_lock_unlock(&lock)
    }

    var snapshot: SettingsSnapshot {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _snapshot
    }

    // CGEventTapコールバックでBool1個だけ読みたい箇所向け。`snapshot`経由だと
    // ActionKind(macroの配列)を含む構造体全体をコピーしretain/releaseが発生するため、
    // 個別フィールドだけを取り出す軽量アクセサを分けている。
    var middleClickEnabled: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _snapshot.middleClickEnabled
    }

    var verticalScrollOnly: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _snapshot.verticalScrollOnly
    }
}
