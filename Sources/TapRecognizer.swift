// The early tap-recognition design was informed by MouseToucher.
// Copyright (c) 2025 Roger Hughes, used under the MIT License.
// See THIRD_PARTY_NOTICES.md. Magic Control changes: GPL-3.0-only.

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
    case geometryVeto = "指の動きが大きすぎたため無視"
    case momentumVeto = "慣性スクロール中のため無視"
    case duration = "接触が長すぎたため無視"
    case straightDistance = "位置ズレが大きすぎたため無視"
    case pathLength = "動きの合計が大きすぎたため無視"
    case velocity = "動きが速すぎたため無視"
    case minFrames = "接触が短すぎたため無視"
    case outOfZone = "反応範囲の外だったため無視"
    case scrollVeto = "スクロール直後のため無視"
    case buttonVeto = "物理クリック直後のため無視"
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
        record("接触中の動き超過",
               actual: track.vetoed ? "超過あり" : "なし", threshold: "なし",
               passed: !track.vetoed, reason: .geometryVeto)

        record("接触時間",
               actual: String(format: "%.3f秒", duration),
               threshold: String(format: "≤%.3f秒", settings.tapMaxDuration),
               passed: duration <= settings.tapMaxDuration, reason: .duration)

        record("位置ズレ",
               actual: String(format: "%.3f", straightDistance),
               threshold: String(format: "≤%.3f", settings.tapMaxStraightDistance),
               passed: straightDistance <= settings.tapMaxStraightDistance, reason: .straightDistance)

        record("動きの合計",
               actual: String(format: "%.3f", track.pathLength),
               threshold: String(format: "≤%.3f", settings.tapMaxPathLength),
               passed: Double(track.pathLength) <= settings.tapMaxPathLength, reason: .pathLength)

        record("動きの速さ",
               actual: String(format: "%.3f", track.maxVelocity),
               threshold: String(format: "≤%.3f", settings.tapMaxVelocity),
               passed: Double(track.maxVelocity) <= settings.tapMaxVelocity, reason: .velocity)

        record("接触フレーム数",
               actual: "\(track.frames)",
               threshold: "≥\(settings.tapMinFrames)",
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
            label: "反応範囲内(開始点・3本指は全面)",
            actual: String(format: "左から%.0f%% 手前から%.0f%%", track.startPos.x * 100, track.startPos.y * 100),
            threshold: String(format: "左右%.0f-%.0f%% 前後%.0f-%.0f%%",
                               zoneLoX * 100, zoneHiX * 100, zoneLoY * 100, zoneHiY * 100),
            passed: inZone))

        // 第3層: 慣性スクロールベト
        record("慣性スクロール中に開始",
               actual: track.beganDuringMomentum ? "はい" : "いいえ", threshold: "いいえ",
               passed: !track.beganDuringMomentum, reason: .momentumVeto)

        // 第2層: スクロールベト（簡略化: lastScrollAt が start-window 以降に更新されていたら不成立）
        let lastScrollAt = shared.lastScrollAt
        let scrollVetoed = lastScrollAt >= track.startTime - settings.scrollVetoWindow
        let sinceScroll = track.startTime - lastScrollAt
        let scrollActual: String
        if lastScrollAt < -1e8 {
            scrollActual = "スクロールなし"
        } else if sinceScroll < 0 {
            scrollActual = "接触中にスクロール"
        } else {
            scrollActual = String(format: "%.2f秒前", sinceScroll)
        }
        record("スクロール直後でない",
               actual: scrollActual,
               threshold: String(format: "%.2f秒以上あける", settings.scrollVetoWindow),
               passed: !scrollVetoed, reason: .scrollVeto)

        // 第4層: 物理ボタンベト
        let buttonDown = shared.buttonDown
        let lastButtonUpAt = shared.lastButtonUpAt
        let buttonVetoed = buttonDown || (now - lastButtonUpAt) <= settings.buttonVetoWindow
        record("物理クリック直後でない",
               actual: buttonDown ? "押下中" : String(format: "%.3f秒前にUp", now - lastButtonUpAt),
               threshold: String(format: "%.2f秒以上あける", settings.buttonVetoWindow),
               passed: !buttonVetoed, reason: .buttonVeto)

        // ゾーンは record() を通していないため firstFailure に影響しない
        // (= passed はゾーン以外の全条件の合否)
        let passed = firstFailure == nil
        return Evaluation(passed: passed, inZone: inZone, conditions: conditions, firstFailure: firstFailure)
    }
}
