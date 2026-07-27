import CoreGraphics
import Darwin
import Foundation
import QuartzCore

/// ActionKind の実行。マクロ再生は専用シリアルキューへ分離する。
enum ActionExecutor {
    private static let macroQueue = DispatchQueue(label: "com.mori0818.magicmousetoolkit.macroPlayback")
    private static var macroLock = os_unfair_lock()
    /// 再生ごとに1つ進む世代番号。再トリガー時にインクリメントし、
    /// 再生ループ側で世代のズレを検知したら即座に中断する(重複再生防止)。
    private static var macroGeneration = 0

    static func perform(_ action: ActionKind) {
        switch action {
        case .click(let button):
            SynthesizedClick.post(button: button)

        case .macro(let events):
            guard !events.isEmpty else { return }

            os_unfair_lock_lock(&macroLock)
            macroGeneration += 1
            let myGeneration = macroGeneration
            os_unfair_lock_unlock(&macroLock)

            // 録画開始ボタンを押してから最初のキーを打つまでの間合いは再生時に不要なので詰める。
            // さらにイベント間の間合いにも上限を設け、録画中に考え込んだ長い沈黙を圧縮する。
            let maxGap: Double = 0.5
            let baseOffset = events.first?.offset ?? 0
            var previousOffset = baseOffset
            var adjustedOffsets: [Double] = []
            adjustedOffsets.reserveCapacity(events.count)
            var accumulated: Double = 0
            for recorded in events {
                let gap = min(recorded.offset - previousOffset, maxGap)
                accumulated += max(gap, 0)
                adjustedOffsets.append(accumulated)
                previousOffset = recorded.offset
            }

            macroQueue.async {
                guard let src = CGEventSource(stateID: .hidSystemState) else { return }
                let start = CACurrentMediaTime()
                for (index, recorded) in events.enumerated() {
                    os_unfair_lock_lock(&macroLock)
                    let stillCurrent = myGeneration == macroGeneration
                    os_unfair_lock_unlock(&macroLock)
                    guard stillCurrent else {
                        MMTLog.log("macro: 再トリガーのため再生を中断")
                        return
                    }

                    let target = start + adjustedOffsets[index]
                    let now = CACurrentMediaTime()
                    if target > now {
                        Thread.sleep(forTimeInterval: target - now)
                    }

                    let e = CGEvent(keyboardEventSource: src, virtualKey: recorded.keyCode, keyDown: recorded.isDown)
                    e?.flags = CGEventFlags(rawValue: recorded.flags)
                    if recorded.isFlagsChanged {
                        e?.type = .flagsChanged
                    }
                    e?.setIntegerValueField(.eventSourceUserData, value: SynthesizedClick.signature)
                    e?.post(tap: .cghidEventTap)
                }
            }

        case .toggleTrackpadMode:
            TrackpadModeController.shared.toggle()
        }
    }
}
