import Foundation

/// 録画したキーボードイベント1件。マクロ再生は録画開始からの相対時刻(offset)でタイミングを合わせる。
/// isFlagsChanged: 修飾キー単体の押下/解放(flagsChangedイベント)か、通常のkeyDown/keyUpか。
struct RecordedKeyEvent: Codable, Equatable {
    let keyCode: UInt16
    let flags: UInt64
    let isDown: Bool
    let isFlagsChanged: Bool
    let offset: Double
}

/// タップ/ジェスチャーに割り当てる実行内容。UserDefaults に JSON でエンコードして保存する
/// (ゾーン・3本指タップなど複数の割り当て先を持てるようにするため、単一の値ではなくリスト運用を想定)。
enum ActionKind: Codable, Equatable {
    case click(SynthesizedClick.Button)
    case macro([RecordedKeyEvent])
    case toggleTrackpadMode

    var isTrackpadToggle: Bool {
        if case .toggleTrackpadMode = self { return true }
        return false
    }
}
