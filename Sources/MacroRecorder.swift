import CoreGraphics
import QuartzCore

/// CGEventTap の C コールバック（capture 不可のためグローバル関数）。listenOnlyのため戻り値は常に素通し。
private func macroRecorderCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    MacroRecorder.shared.handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

/// 3本指タップに割り当てるマクロの録画。listenOnlyのCGEventTapでキーボードイベント
/// (keyDown/keyUp/flagsChanged)を記録する。安全のため200イベントまたは60秒で自動停止する。
final class MacroRecorder: ObservableObject {
    static let shared = MacroRecorder()

    private static let maxEvents = 200
    private static let maxDuration: Double = 60

    @Published private(set) var isRecording = false
    @Published private(set) var recordedEvents: [RecordedKeyEvent] = []
    /// 録画中のセッションがどの割り当て先のものか。UI側の相互排他に使う。
    @Published private(set) var sessionLabel: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startTime: Double = 0
    private var lastFlags: CGEventFlags = []
    /// 録画終了時(手動stop・自動停止とも)に録画結果を保存先へ渡すクロージャ。
    /// 保存先を呼び出し側が確定させることで、複数の割り当て先での混線を防ぐ。
    private var onStop: (([RecordedKeyEvent]) -> Void)?

    private init() {}

    func start(label: String, onStop: @escaping ([RecordedKeyEvent]) -> Void) {
        guard eventTap == nil else { return }
        recordedEvents = []
        sessionLabel = label
        self.onStop = onStop
        startTime = CACurrentMediaTime()
        lastFlags = []

        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventsOfInterest,
            callback: macroRecorderCallback,
            userInfo: nil
        ) else {
            MMTLog.log("MacroRecorder: イベントタップ作成失敗(アクセシビリティ権限を確認)")
            sessionLabel = nil
            self.onStop = nil
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        isRecording = true
        MMTLog.log("MacroRecorder: 録画開始")
    }

    func stop() {
        guard eventTap != nil else { return }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
        isRecording = false
        MMTLog.log("MacroRecorder: 録画終了(\(sessionLabel ?? "?"): \(recordedEvents.count)イベント)")
        sessionLabel = nil
        // 自動停止(上限到達)でも録画結果が保存されるよう、保存はここで一元的に行う
        let handler = onStop
        onStop = nil
        handler?(recordedEvents)
    }

    func clear() {
        recordedEvents = []
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        // 自己合成イベント(マクロ再生中の自分自身)は記録しない(無限ループ・混入防止)。
        if event.getIntegerValueField(.eventSourceUserData) == SynthesizedClick.signature {
            return
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let offset = CACurrentMediaTime() - startTime

        switch type {
        case .keyDown, .keyUp:
            append(RecordedKeyEvent(
                keyCode: keyCode, flags: event.flags.rawValue,
                isDown: type == .keyDown, isFlagsChanged: false, offset: offset))

        case .flagsChanged:
            let newRaw = event.flags.rawValue
            let oldRaw = lastFlags.rawValue
            let isDown = (newRaw & ~oldRaw) != 0  // 新しく立ったビットがあれば押下、なければ解放
            lastFlags = event.flags
            append(RecordedKeyEvent(
                keyCode: keyCode, flags: newRaw,
                isDown: isDown, isFlagsChanged: true, offset: offset))

        default:
            break
        }
    }

    private func append(_ event: RecordedKeyEvent) {
        recordedEvents.append(event)
        if recordedEvents.count >= Self.maxEvents || (CACurrentMediaTime() - startTime) >= Self.maxDuration {
            stop()
        }
    }
}
