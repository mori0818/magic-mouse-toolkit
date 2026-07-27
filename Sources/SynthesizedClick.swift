// The initial synthesized-click approach was informed by MouseToucher.
// Copyright (c) 2025 Roger Hughes, used under the MIT License.
// See THIRD_PARTY_NOTICES.md. Magic Control changes: GPL-3.0-only.

import CoreGraphics

/// タップ→クリック合成。EventInterceptor は `eventSourceUserData` でこの署名を検出し、
/// 自己合成イベントを無変更で素通しする（無限ループ・二重処理防止）。
enum SynthesizedClick {
    enum Button: Codable {
        case left
        case right
        case middle
    }

    static let signature: Int64 = 0x4D43_4C4B  // "MCLK"

    static func post(button: Button, at location: CGPoint? = nil) {
        let loc: CGPoint
        if let location {
            loc = location
        } else {
            guard let current = CGEvent(source: nil)?.location else {
                MCLog.log("[診断] SynthesizedClick: カーソル位置の取得失敗(CGEvent(source:nil)がnil)")
                return
            }
            loc = current
        }
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            MCLog.log("[診断] SynthesizedClick: CGEventSource(.hidSystemState)の生成失敗")
            return
        }

        let downType: CGEventType
        let upType: CGEventType
        let mouseButton: CGMouseButton

        switch button {
        case .left:
            downType = .leftMouseDown
            upType = .leftMouseUp
            mouseButton = .left
        case .right:
            downType = .rightMouseDown
            upType = .rightMouseUp
            mouseButton = .right
        case .middle:
            downType = .otherMouseDown
            upType = .otherMouseUp
            mouseButton = .center
        }

        guard
            let down = CGEvent(mouseEventSource: src, mouseType: downType, mouseCursorPosition: loc, mouseButton: mouseButton),
            let up = CGEvent(mouseEventSource: src, mouseType: upType, mouseCursorPosition: loc, mouseButton: mouseButton)
        else {
            MCLog.log("[診断] SynthesizedClick: CGEventの生成失敗")
            return
        }
        down.setIntegerValueField(.eventSourceUserData, value: signature)
        down.post(tap: .cghidEventTap)
        up.setIntegerValueField(.eventSourceUserData, value: signature)
        up.post(tap: .cghidEventTap)
        MCLog.log("[診断] SynthesizedClick: post完了 \(button) loc=(\(Int(loc.x)),\(Int(loc.y)))")
    }
}
