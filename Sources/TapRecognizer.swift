// The early tap-recognition design was informed by MouseToucher.
// Copyright (c) 2025 Roger Hughes, used under the MIT License.
// See THIRD_PARTY_NOTICES.md. Magic Mouse Toolkit changes: GPL-3.0-only.

import Foundation

/// 判定内訳の1条件（デバッグUI表示用）。
struct TapConditionResult: Identifiable {
    let id = UUID()
    let label: String
    let actual: String
    let threshold: String
    let passed: Bool
}

enum TapFailureReason: String {
    case geometryVeto
    case momentumVeto
    case duration
    case straightDistance
    case pathLength
    case velocity
    case minFrames
    case outOfZone
    case scrollVeto
    case buttonVeto

    /// デバッグライブ表示・診断ログに出す不成立理由の文言。
    var localizedDescription: String {
        switch self {
        case .geometryVeto: return NSLocalizedString("指の動きが大きすぎたため無視", comment: "タップ不成立理由: 接触中の動き超過")
        case .momentumVeto: return NSLocalizedString("慣性スクロール中のため無視", comment: "タップ不成立理由: 慣性スクロール中")
        case .duration: return NSLocalizedString("接触が長すぎたため無視", comment: "タップ不成立理由: 接触時間超過")
        case .straightDistance: return NSLocalizedString("位置ズレが大きすぎたため無視", comment: "タップ不成立理由: 位置ズレ超過")
        case .pathLength: return NSLocalizedString("動きの合計が大きすぎたため無視", comment: "タップ不成立理由: 移動量超過")
        case .velocity: return NSLocalizedString("動きが速すぎたため無視", comment: "タップ不成立理由: 速度超過")
        case .minFrames: return NSLocalizedString("接触が短すぎたため無視", comment: "タップ不成立理由: 接触フレーム不足")
        case .outOfZone: return NSLocalizedString("反応範囲の外だったため無視", comment: "タップ不成立理由: ゾーン外")
        case .scrollVeto: return NSLocalizedString("スクロール直後のため無視", comment: "タップ不成立理由: スクロール直後")
        case .buttonVeto: return NSLocalizedString("物理クリック直後のため無視", comment: "タップ不成立理由: 物理クリック直後")
        }
    }
}

/// リリースされた TouchTrack がタップとして成立するかを判定する（4層防衛、§1参照）。
enum TapRecognizer {
    struct Evaluation {
        /// ゾーン以外の全条件(ジオメトリ・ベト類)を満たしたか。
        /// ゾーンの要否は指の本数で変わる(3本指は免除)ため、確定時に inZone と組み合わせて判断する。
        let passed: Bool
        /// 開始点が反応範囲内だったか。1本指・2本指タップの成立に必要。
        let inZone: Bool
        let conditions: [TapConditionResult]
        let firstFailure: TapFailureReason?
    }

    static func evaluate(track: TouchTrack, releaseTime: Double, settings: SettingsSnapshot) -> Evaluation {
        let shared = SharedState.shared
        let now = releaseTime

        let duration = releaseTime - track.startTime
        let straightDistance = Double(hypot(
            track.lastPos.x - track.startPos.x,
            track.lastPos.y - track.startPos.y))

        var conditions: [TapConditionResult] = []
        var firstFailure: TapFailureReason? = nil

        func record(_ label: String, actual: String, threshold: String, passed: Bool, reason: TapFailureReason) {
            conditions.append(TapConditionResult(label: label, actual: actual, threshold: threshold, passed: passed))
            if !passed && firstFailure == nil { firstFailure = reason }
        }

        // 第1層: 接触ジオメトリ
        record(NSLocalizedString("接触中の動き超過", comment: "判定内訳ラベル"),
               actual: track.vetoed ? NSLocalizedString("超過あり", comment: "判定内訳の実測値") : NSLocalizedString("なし", comment: "判定内訳の実測値"),
               threshold: NSLocalizedString("なし", comment: "判定内訳の閾値"),
               passed: !track.vetoed, reason: .geometryVeto)

        record(NSLocalizedString("接触時間", comment: "判定内訳ラベル"),
               actual: String(format: NSLocalizedString("%.3f秒", comment: "秒数"), duration),
               threshold: String(format: NSLocalizedString("≤%.3f秒", comment: "秒数の上限"), settings.tapMaxDuration),
               passed: duration <= settings.tapMaxDuration, reason: .duration)

        record(NSLocalizedString("位置ズレ", comment: "判定内訳ラベル"),
               actual: String(format: "%.3f", straightDistance),
               threshold: String(format: NSLocalizedString("≤%.3f", comment: "数値の上限"), settings.tapMaxStraightDistance),
               passed: straightDistance <= settings.tapMaxStraightDistance, reason: .straightDistance)

        record(NSLocalizedString("動きの合計", comment: "判定内訳ラベル"),
               actual: String(format: "%.3f", track.pathLength),
               threshold: String(format: NSLocalizedString("≤%.3f", comment: "数値の上限"), settings.tapMaxPathLength),
               passed: Double(track.pathLength) <= settings.tapMaxPathLength, reason: .pathLength)

        record(NSLocalizedString("動きの速さ", comment: "判定内訳ラベル"),
               actual: String(format: "%.3f", track.maxVelocity),
               threshold: String(format: NSLocalizedString("≤%.3f", comment: "数値の上限"), settings.tapMaxVelocity),
               passed: Double(track.maxVelocity) <= settings.tapMaxVelocity, reason: .velocity)

        record(NSLocalizedString("接触フレーム数", comment: "判定内訳ラベル"),
               actual: "\(track.frames)",
               threshold: String(format: NSLocalizedString("≥%d", comment: "数値の下限"), settings.tapMinFrames),
               passed: track.frames >= settings.tapMinFrames, reason: .minFrames)

        // ゾーン判定: min/max が逆転して保存されていても自動補正し、範囲ゼロで全滅しないようにする
        let zoneLoX = min(settings.zoneMinX, settings.zoneMaxX)
        let zoneHiX = max(settings.zoneMinX, settings.zoneMaxX)
        let zoneLoY = min(settings.zoneMinY, settings.zoneMaxY)
        let zoneHiY = max(settings.zoneMinY, settings.zoneMaxY)
        let inZoneX = Double(track.startPos.x) >= zoneLoX && Double(track.startPos.x) <= zoneHiX
        let inZoneY = Double(track.startPos.y) >= zoneLoY && Double(track.startPos.y) <= zoneHiY
        let inZone = inZoneX && inZoneY
        // ゾーンは conditions(デバッグ表示)には記録するが、passed の集計からは除外する。
        // 3本指タップは全面が対象(指の本数自体が意図表明)のため、ゾーン要求の有無は
        // 指本数が確定する finalizePendingGroup 側で判断する
        conditions.append(TapConditionResult(
            label: NSLocalizedString("反応範囲内(開始点・3本指は全面)", comment: "判定内訳ラベル"),
            actual: String(format: NSLocalizedString("左から%.0f%% 手前から%.0f%%", comment: "座標(%)"), track.startPos.x * 100, track.startPos.y * 100),
            threshold: String(format: NSLocalizedString("左右%.0f-%.0f%% 前後%.0f-%.0f%%", comment: "反応範囲(%)"),
                               zoneLoX * 100, zoneHiX * 100, zoneLoY * 100, zoneHiY * 100),
            passed: inZone))

        // 第3層: 慣性スクロールベト
        record(NSLocalizedString("慣性スクロール中に開始", comment: "判定内訳ラベル"),
               actual: track.beganDuringMomentum ? NSLocalizedString("はい", comment: "判定内訳の実測値") : NSLocalizedString("いいえ", comment: "判定内訳の実測値"),
               threshold: NSLocalizedString("いいえ", comment: "判定内訳の閾値"),
               passed: !track.beganDuringMomentum, reason: .momentumVeto)

        // 第2層: スクロールベト（簡略化: lastScrollAt が start-window 以降に更新されていたら不成立）
        let lastScrollAt = shared.lastScrollAt
        let scrollVetoed = lastScrollAt >= track.startTime - settings.scrollVetoWindow
        let sinceScroll = track.startTime - lastScrollAt
        let scrollActual: String
        if lastScrollAt < -1e8 {
            scrollActual = NSLocalizedString("スクロールなし", comment: "判定内訳の実測値")
        } else if sinceScroll < 0 {
            scrollActual = NSLocalizedString("接触中にスクロール", comment: "判定内訳の実測値")
        } else {
            scrollActual = String(format: NSLocalizedString("%.2f秒前", comment: "経過秒数"), sinceScroll)
        }
        record(NSLocalizedString("スクロール直後でない", comment: "判定内訳ラベル"),
               actual: scrollActual,
               threshold: String(format: NSLocalizedString("%.2f秒以上あける", comment: "必要な間隔"), settings.scrollVetoWindow),
               passed: !scrollVetoed, reason: .scrollVeto)

        // 第4層: 物理ボタンベト
        let buttonDown = shared.buttonDown
        let lastButtonUpAt = shared.lastButtonUpAt
        let buttonVetoed = buttonDown || (now - lastButtonUpAt) <= settings.buttonVetoWindow
        record(NSLocalizedString("物理クリック直後でない", comment: "判定内訳ラベル"),
               actual: buttonDown ? NSLocalizedString("押下中", comment: "判定内訳の実測値") : String(format: NSLocalizedString("%.3f秒前にUp", comment: "経過秒数"), now - lastButtonUpAt),
               threshold: String(format: NSLocalizedString("%.2f秒以上あける", comment: "必要な間隔"), settings.buttonVetoWindow),
               passed: !buttonVetoed, reason: .buttonVeto)

        // ゾーンは record() を通していないため firstFailure に影響しない
        // (= passed はゾーン以外の全条件の合否)
        let passed = firstFailure == nil
        return Evaluation(passed: passed, inZone: inZone, conditions: conditions, firstFailure: firstFailure)
    }
}
