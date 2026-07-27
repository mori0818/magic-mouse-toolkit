# Magic Control 実装仕様書（コード直結版）

作成日: 2026-07-02。この文書だけを見て実装を完了できることを目標とする（実装担当: Sonnet 5 想定）。
背景・経緯は SPEC.md / ARCHITECTURE.md、デザイントークンは DESIGN.md を参照。

## 0. フェーズ

- **フェーズ1（プロトタイプ、本書のスコープ）**: 全機能 + 簡易UI（DESIGN.md のトークンを使ったネイティブ風 Form）。動作検証・キャリブレーションまで
- **フェーズ2**: Liquid Glass デザインへの再スキン（DesignSystem.swift のトークン値差し替えと GlassWindow 導入のみで済む構造にしておく）

## 1. タップ/スクロール誤反応対策 — 4層防衛（本仕様の核心）

タッチ座標のみからの推定（距離・速度閾値）には原理的に境界誤判定が残る。そこで **OS自身のスクロール判定（`.scrollWheel` イベント）を正解信号として利用する**。CGEventTap はミドルクリック変換用に必ず張るため、監視対象に `.scrollWheel` を加えるだけで追加コストはほぼゼロ。

タップ成立には以下 **全層の通過** が必要:

### 第1層: 接触ジオメトリ（タッチ座標ベース、従来方式）
- 接触時間 ≤ `tapMaxDuration`
- 直線距離（開始点→終了点） ≤ `tapMaxStraightDistance`
- 累積経路長（毎フレームの移動量合計） ≤ `tapMaxPathLength`
- 観測最大瞬間速度（`MTTouch.normalized.velocity` のノルム最大値） ≤ `tapMaxVelocity`
- 接触フレーム数 ≥ `tapMinFrames`（一瞬の掠り・ノイズフレーム除外。Magic Mouse のタッチフレームは約90Hz なので 3フレーム ≈ 33ms 以上の接触を要求）

### 第2層: スクロールベト（OS のスクロール判定を利用）
- タッチ開始〜タップ判定時点の間、および判定時点から遡って `scrollVetoWindow`（既定 0.25s）以内に `.scrollWheel` イベントが観測されていたら **不成立**
- scrollWheel の記録は受動的（イベントは無変更で素通し）。`ScrollMonitor` が最終観測時刻のみ保持

### 第3層: 慣性スクロールベト
- `.scrollWheel` の `kCGScrollWheelEventMomentumPhase` が began/continued の間（= 慣性スクロール中）に開始されたタッチは、**その接触全体をタップ候補から除外**する（フラグ `beganDuringMomentum` を立て、リリース時に必ず不成立）
- 理由: Magic Mouse では「慣性スクロールを指で止める」操作が日常的に発生し、これが誤クリックの最頻パターンになるため

### 第4層: 物理ボタンベト
- 物理ボタン押下中（leftMouseDown〜Up の間）、および buttonUp から `buttonVetoWindow`(既定 0.1s) 以内はタップ不成立
- 理由: 物理クリック時にも指はタッチとして検出されるため、「物理クリック + タップ合成」の二重クリックを防ぐ

### 既知の限界（README に明記する）
- トラックパッド等他デバイスのスクロール中に Magic Mouse をタップすると第2層が誤ベトする（クリックが1回無視される）。両手同時操作の稀なケースであり安全側の誤りなので許容
- 第2層はスクロールイベント発生が前提のため、スクロール開始直前の極小移動には第1層で対応する（役割分担）

## 2. プロジェクト構成

```
MagicControl/
├── build.sh
├── Info.plist
├── MagicControl.entitlements    （使わない。ad-hoc配布・App Sandbox無し）
├── Sources/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── MultitouchBridge.h       （HIDシステムSPI宣言も統合、単一ブリッジヘッダー制約のため）
│   ├── MultitouchDevice.swift
│   ├── TouchGestureManager.swift
│   ├── TapRecognizer.swift
│   ├── EventInterceptor.swift
│   ├── SynthesizedClick.swift
│   ├── ActionKind.swift         （タップ割り当てのCodableモデル。RecordedKeyEvent含む）
│   ├── ActionExecutor.swift     （ActionKind実行。マクロ再生の再入防止ロジック含む）
│   ├── MacroRecorder.swift      （3本指タップのマクロ録画、CGEventTap listen-only）
│   ├── PointerSpeedManager.swift（トラッキング速度ブースト、IOHIDEventSystemClient SPI）
│   ├── Settings.swift
│   ├── DesignSystem.swift       （DESIGN.md のトークン実装）
│   └── SettingsView.swift
└── docs（SPEC.md ほか既存）
```

## 3. ビルド・署名

### build.sh
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Magic Control.app"
BIN="MagicControl"
SIGN_ID="${SIGN_ID:-}"              # 未指定ならad-hoc署名

SWIFT_FILES=(Sources/*.swift)
FLAGS=(-import-objc-header Sources/MultitouchBridge.h
       -F /System/Library/PrivateFrameworks -framework MultitouchSupport
       -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit -O)

mkdir -p build
# フェーズ2のLiquid Glass(glassEffect)はmacOS 26+のAPIのためターゲットを引き上げ
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target arm64-apple-macos26.0  -o build/$BIN-arm64
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target x86_64-apple-macos26.0 -o build/$BIN-x86_64
lipo -create build/$BIN-arm64 build/$BIN-x86_64 -output build/$BIN

rm -rf "build/$APP"
mkdir -p "build/$APP/Contents/MacOS"
cp Info.plist "build/$APP/Contents/"
cp build/$BIN "build/$APP/Contents/MacOS/"
codesign --force --sign "$SIGN_ID" "build/$APP"
echo "Built: build/$APP"
```
- 環境変数 `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"` を build.sh 冒頭で export する（CLAUDE.md 既定）
- 動作確認は必ず `open -a "build/Magic Control.app"`（launchd 親）で行う。ターミナル直接実行では TCC が効かない

### Info.plist（必須キー）
| キー | 値 |
|---|---|
| CFBundleIdentifier | com.magiccontrol.app |
| CFBundleName / CFBundleDisplayName | Magic Control |
| CFBundleExecutable | MagicControl |
| CFBundleVersion / ShortVersionString | 1.0 |
| LSUIElement | true |
| NSHighResolutionCapable | true |

## 4. MultitouchBridge.h（全文）

```c
#ifndef MultitouchBridge_h
#define MultitouchBridge_h
#include <CoreFoundation/CoreFoundation.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
  int32_t frame;
  double timestamp;
  int32_t identifier;
  int32_t state;          // 4 = Touching
  int32_t fingerId, handId;
  MTVector normalized;    // position/velocity とも 0.0-1.0 正規化（Yは前方が大）
  float size;
  int32_t zero1;
  float angle, majorAxis, minorAxis;
  MTVector absolute;
  int32_t zero2, zero3;
  float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *touches,
                                         int numTouches, double timestamp, int frame);

CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef);
OSStatus MTDeviceGetFamilyID(MTDeviceRef, int32_t *familyId);

#endif
```
- タッチ state 定数: `4 (Touching)` のみ「接触中」として扱う。それ以外の state のタッチはフレーム内の指数カウントに含めない
- `MTTouch` レイアウトは MouseToucher フォークで実機検証済みのものと同一。もし position が異常値（0-1 範囲外）を返す場合はレイアウトずれを疑い、まず `timestamp` と `identifier` の妥当性をログで確認する

## 5. デバイス管理 — MultitouchDevice.swift

```swift
final class MultitouchDeviceManager {
    static let shared = MultitouchDeviceManager()
    private var activeDevices: [MTDeviceRef] = []
    func start()    // 列挙→フィルタ→登録
    func stop()     // 全 unregister + MTDeviceStop
    func restart()  // stop() → 0.5s 後 start()（デバイス再接続対応）
}
```

- **フィルタ条件（Magic Mouse 限定）**: `MTDeviceIsBuiltIn(dev) == false` かつ `MTDeviceGetFamilyID` が成功し `familyId == 112 || familyId == 113`
  - 112/113 = Magic Mouse 系ファミリー。**初回起動時にログへ実際の familyId を必ず出力すること**（Magic Mouse 2 / USB-C 版で値が異なる場合に即座に発見できるように）。フィルタ結果ゼロ台数の場合は「familyId フィルタを通過したデバイスなし。検出された familyId: [...]」と メニューバーの状態表示に出す
  - フォールバック設定 `deviceFilterStrict`（既定 true）。false にすると従来どおり `!MTDeviceIsBuiltIn` のみ（familyId が想定と違う個体への逃げ道）
- コールバックは C 関数ポインタのため capture 不可。グローバル関数 → `TouchGestureManager.shared` へ転送する
- **再接続対応**: `NSWorkspace.shared.notificationCenter` の `didWakeNotification` と、`IOServiceAddMatchingNotification`（AppleMultitouchDevice のマッチング）… は複雑なので **プロトタイプでは簡略化**: didWake 通知 + 「メニューバーの『デバイスを再検出』項目」で `restart()` を呼べるようにする。自動 BT 再接続検知はフェーズ2

## 6. 設定 — Settings.swift

`UserDefaults.standard` バック。全プロパティは `didSet` で `NotificationCenter.default.post(name: .settingsChanged)` を発行。読み手（TouchGestureManager / EventInterceptor）は通知受信時に全値をローカル構造体 `SettingsSnapshot` へコピーして保持する（コールバック内で UserDefaults を読まない — 速度と安全のため）。

| プロパティ | UserDefaults キー | 型 | 既定値 | UI範囲 |
|---|---|---|---|---|
| enabled | mc.enabled | Bool | true | — |
| oneFingerTapEnabled | mc.tap1.enabled | Bool | true | — |
| twoFingerTapEnabled | mc.tap2.enabled | Bool | true | — |
| middleClickEnabled | mc.middle.enabled | Bool | true | — |
| rightZoneMinX | mc.zone.rightMinX | Double | 0.6 | 0–1 |
| zoneMinX / zoneMaxX | mc.zone.minX / maxX | Double | 0.0 / 1.0 | 0–1 |
| zoneMinY / zoneMaxY | mc.zone.minY / maxY | Double | 0.0 / 1.0 | 0–1 |
| tapMaxDuration | mc.tap.maxDuration | Double | 0.16 | 0.05–0.5 s |
| tapMaxStraightDistance | mc.tap.maxStraight | Double | 0.09 | 0.01–0.3 |
| tapMaxPathLength | mc.tap.maxPath | Double | 0.07 | 0.01–0.3 |
| tapMaxVelocity | mc.tap.maxVelocity | Double | 1.5 | 0.2–8.0 /s |
| tapMinFrames | mc.tap.minFrames | Int | 3 | 1–10 |
| scrollVetoWindow | mc.veto.scroll | Double | 0.25 | 0–1.0 s |
| buttonVetoWindow | mc.veto.button | Double | 0.10 | 0–0.5 s |
| twoFingerSyncWindow | mc.tap2.syncWindow | Double | 0.06 | 0.02–0.2 s |
| deviceFilterStrict | mc.device.strict | Bool | true | — |

- `tapMaxVelocity` の既定 1.5 は暫定値。デバッグ表示でのキャリブレーション対象（§9）
- 初期値登録は `UserDefaults.standard.register(defaults:)` で起動時に行う

## 7. タップ判定 — TouchGestureManager.swift + TapRecognizer.swift

### 共有状態（EventInterceptor から読まれる）
```swift
struct TouchSharedState {          // os_unfair_lock で保護
    var fingerCount: Int = 0       // 現フレームの state==4 の指数
    var lastFrameAt: CFTimeInterval = 0   // 最後にタッチフレームを受信した時刻（CACurrentMediaTime）
}
```

### タッチフレーム処理（MTコールバック、バックグラウンドスレッド）
1. `SettingsSnapshot` 参照。`enabled == false` なら fingerCount 更新のみして return
2. 共有状態を更新（fingerCount, lastFrameAt）
3. 各タッチを `identifier` キーで `activeTouches: [Int32: TouchTrack]` に対応付けて更新

```swift
struct TouchTrack {
    let id: Int32
    let startTime: Double          // MTフレームの timestamp
    let startPos: MTPoint
    var lastPos: MTPoint
    var pathLength: Float = 0      // Σ|Δpos|
    var maxVelocity: Float = 0     // max ‖normalized.velocity‖
    var frames: Int = 1
    var beganDuringMomentum: Bool  // 開始時に ScrollMonitor.momentumActive だったか（第3層）
    var vetoed: Bool = false       // 途中で第1層の閾値超過が確定したら true（以降更新不要）
}
```

4. フレーム内に居るタッチ: track 更新。`pathLength += hypot(Δx, Δy)`、`maxVelocity = max(...)`。閾値超過したら `vetoed = true`
5. **前フレームに居て今フレームに居ない identifier = リリース**。リリース時に判定（§次項）
6. 3本以上の指が同時に観測されたフレームがあったら、その時点の全 track を `vetoed = true`

### リリース時のタップ判定（TapRecognizer）
```
成立条件（全て AND）:
  !track.vetoed
  !track.beganDuringMomentum                          // 第3層
  duration = releaseTime - startTime ≤ tapMaxDuration
  |endPos - startPos| ≤ tapMaxStraightDistance
  pathLength ≤ tapMaxPathLength
  maxVelocity ≤ tapMaxVelocity
  frames ≥ tapMinFrames
  startPos がゾーン [zoneMinX,zoneMaxX]×[zoneMinY,zoneMaxY] 内
  ScrollMonitor.lastScrollAt < startTime - scrollVetoWindow   // 第2層（開始前）
  ScrollMonitor.lastScrollAt < now → 接触中にスクロール無し     // 第2層（接触中）
  EventInterceptor.buttonDown == false                 // 第4層
  now - EventInterceptor.lastButtonUpAt > buttonVetoWindow
```
（第2層は「`lastScrollAt` が `startTime - scrollVetoWindow` 以降に一度でも更新されていたら不成立」と単純化して実装してよい）

- **1本指タップ**: 成立時、`endPos.x > rightZoneMinX` なら右クリック、それ以外は左クリックを合成
- **2本指タップ**: 2つの track が (a) 開始時刻差 ≤ `twoFingerSyncWindow`、(b) 両方リリース済みで両方成立条件を満たす、(c) リリース時刻差 ≤ `twoFingerSyncWindow * 2` のとき左クリック1回を合成。**2本指タップが成立したら、同じ2つの track で1本指タップを発火させない**（2本目のリリースまで最大 `twoFingerSyncWindow*2` だけ1本指判定を保留する。実装: リリース済み track を即発火せず `pendingRelease` に積み、(i) 相方が出現→2本指発火、(ii) タイムアウト→1本指発火、のディレイ判定。タイマーは `DispatchSourceTimer` 1本を使い回す）
  - 注: この保留は 2本指タップ有効時のみ。`twoFingerTapEnabled == false` なら1本指を即発火（遅延ゼロ）
- クリック合成は `SynthesizedClick.post(button:at:)`（§8）。発火位置は**現在のカーソル位置**（`CGEvent(source: nil)` の location）

## 8. イベントタップ — EventInterceptor.swift + SynthesizedClick.swift

### 1本の CGEventTap で3役
```swift
CGEvent.tapCreate(
  tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
  eventsOfInterest: (1 << CGEventType.leftMouseDown.rawValue)
                  | (1 << CGEventType.leftMouseUp.rawValue)
                  | (1 << CGEventType.scrollWheel.rawValue),
  callback: interceptorCallback, userInfo: nil)
```
コールバック規律: **アロケーション・ログ・UserDefaults 読み取り禁止**。SettingsSnapshot と共有状態の読み取り + 整数フィールド書き換えのみ。

処理分岐（擬似コード）:
```
case .tapDisabledByTimeout, .tapDisabledByUserInput:
    CGEventTapEnable(tap, true); return event            // 自己復旧
case .scrollWheel:                                        // ScrollMonitor 役
    lastScrollAt = now
    phase = event[.scrollWheelEventMomentumPhase]
    momentumActive = (phase == 1 || phase == 2)           // began/continued
    return event                                          // 無変更で素通し
case .leftMouseDown:
    if event[.eventSourceUserData] == kMCEventSignature: return event   // 自己合成は素通し
    buttonDown = true
    if middleClickEnabled
       && shared.fingerCount == 2
       && (now - shared.lastFrameAt) < 0.08 {             // デバイス相関ガード
        convertingToMiddle = true
        event.type = .otherMouseDown
        event[.mouseEventButtonNumber] = 2                // center
    }
    return event
case .leftMouseUp:
    if event[.eventSourceUserData] == kMCEventSignature: return event
    buttonDown = false; lastButtonUpAt = now
    if convertingToMiddle {                               // down で決めたら up も必ず変換
        convertingToMiddle = false
        event.type = .otherMouseUp
        event[.mouseEventButtonNumber] = 2
    }
    return event
```
- `enabled == false` または `middleClickEnabled == false` のとき: scrollWheel の記録は継続する必要がない（タップも無効/ベト先も無効）ため、**master enable OFF 時は `CGEventTapEnable(false)`**。middleClick のみ OFF でタップ有効の場合は tap は生かす（第2層のため）が Down/Up は素通し
- tap 作成失敗（権限なし）→ AppDelegate の権限フローへ（§10）

### SynthesizedClick.swift
```swift
enum SynthesizedClick {
    static let signature: Int64 = 0x4D43_4C4B          // "MCLK"
    static func post(button: CGMouseButton) {
        let loc = CGEvent(source: nil)!.location
        let src = CGEventSource(stateID: .hidSystemState)
        src?.userData = signature                       // 自己識別（EventInterceptor が素通しする）
        let (down, up): (CGEventType, CGEventType) = ...  // button に応じて left/right/other
        CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: up,   mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
    }
}
```
- down と up の間に遅延は入れない（MouseToucher 検証で問題なし）
- 注意: `CGEventSource.userData` はイベント側では `.eventSourceUserData` フィールドで読める

## 9. UI — SettingsView.swift（プロトタイプ版）

DESIGN.md のトークン（`DesignSystem.swift`）のみを使って構築する。直値のフォントサイズ・色・余白をビューに書かない。

構成（`Form` + `Section`、ウィンドウ 440×620、リサイズ不可）:
1. **一般**: 有効トグル（master）
2. **ジェスチャー**: 1本指タップ / 2本指タップ / ミドルクリック の各トグル + 右クリックゾーン開始X スライダー
3. **反応範囲**: X min/max、Y min/max の4スライダー（%表示）
4. **感度**: tapMaxDuration / MaxStraight / MaxPath / MaxVelocity / MinFrames の5スライダー（現在値を右端に等幅フォント表示）
5. **誤反応対策**: scrollVetoWindow / buttonVetoWindow / twoFingerSyncWindow
6. **デバッグ**（DisclosureGroup、開いている間のみ更新）:
   - 現在の指数・最新タッチ座標 (x, y)
   - **直近のタップ試行の判定内訳**: 各条件の実測値と閾値を並べ、どの層/条件で落ちたかを色分け表示（例: `path 0.11 > 0.07 ✗`）。これが速度閾値キャリブレーションの主手段
   - 直近のイベント: 「タップ成立(左)」「スクロールベト」「慣性ベト」等の履歴 最新10件
   - デバッグデータの受け渡し: TouchGestureManager が `DebugFeed.shared`（ObservableObject、リングバッファ10件）へ **DisclosureGroup が開いているときだけ** push する（`DebugFeed.isActive` フラグをビューの onAppear/onDisappear で切替。閉じている間のオーバーヘッドはフラグ分岐1つ）
7. **リセット**: 「感度を既定値に戻す」ボタン

メニューバー（NSMenu、AppKit）:
```
✓ 有効                     （toggle, master enable）
──────────
設定を開く…
デバイスを再検出            （MultitouchDeviceManager.restart）
──────────
Magic Control について
終了 ⌘Q
```
アイコン: SF Symbols `computermouse.fill`（template image）。設定ウィンドウは lazy 生成・closeで解放（`NSWindow.isReleasedWhenClosed` は SwiftUI ホスティングと相性が悪いので false にし、参照を nil 代入で解放）。

## 10. AppDelegate — 起動シーケンス

1. `UserDefaults.register(defaults:)`
2. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` — 未許可なら 2秒間隔のポーリングで許可を待つ（**許可後にタイマー破棄**。これが唯一のタイマー）
3. 許可後: `MultitouchDeviceManager.shared.start()` → `EventInterceptor.shared.start()`
4. メニューバーアイコン設置
5. `didWakeNotification` 購読 → `MultitouchDeviceManager.restart()`

## 11. スレッドと同期

| データ | 書き手 | 読み手 | 保護 |
|---|---|---|---|
| TouchSharedState (fingerCount, lastFrameAt) | MTコールバックスレッド | イベントタップ(メインRunLoop) | os_unfair_lock（保持時間ナノ秒級） |
| lastScrollAt / momentumActive / buttonDown / lastButtonUpAt / convertingToMiddle | イベントタップ | MTコールバックスレッド | 同上（同じ lock を共用してよい） |
| SettingsSnapshot | メイン（通知受信時に差し替え） | 両コールバック | 構造体まるごと差し替え + lock |
| DebugFeed | MTコールバック→メインへ dispatch | SwiftUI | isActive フラグで送出自体を抑制 |

## 12. テストチェックリスト（実機）

1. ガラス/ウィンドウ以前にコア動作: 1本指タップ左、右ゾーンで右、2本指タップ左、2本指物理クリックでミドル（Finder のタブ閉じ等で確認）
2. **誤反応シナリオ**（すべてクリックが発生しないこと）: ゆっくりスクロール開始 / 素早いフリック / 往復スクロール / 慣性スクロール中に指で停止 / 物理クリックしながらのタップ / トラックパッド操作中（そもそも反応しないこと）
3. 他マウス・トラックパッドのクリック/スクロールが一切影響を受けないこと
4. 設定変更の即時反映(リビルド・再起動なし)
5. スリープ復帰後の動作、「デバイスを再検出」の動作
6. リビルド→再署名→権限が失効しないこと
7. アクティビティモニタでアイドル CPU 0%台・メモリ ≤15MB
8. CGEventTap 自己復旧: 高負荷時に機能停止しないこと（長時間運用で確認）

## 13. フェーズ2への引き継ぎポイント

- 見た目の変更は `DesignSystem.swift` のトークン値変更 + `GlassWindow.swift` 追加（borderless NSWindow サブクラス）に閉じる。SettingsView のレイアウト構造は再利用
- Liquid Glass 検証: `.glassEffect()` を borderless 透明ウィンドウで単体検証してから統合（Vault の仕様書v2 難所#6/#7 参照）

## 14. 3本指タップ = マクロレコーダー / トラッキング速度ブースト（2026-07-10実装）

詳細な設計判断は Vault の `プロジェクト/magic-control/magic-control-マクロレコーダーと速度ブースト実装手順.md` と `インサイト/判断/2026-07-10-magiccontrol-速度ブースト方式.md` を参照。ここでは実装済みコードの要点のみ記す。

### マクロレコーダー(3本指タップ)
- `ActionKind.macro([RecordedKeyEvent])` を新設。`RecordedKeyEvent` は `keyCode/flags/isDown/isFlagsChanged/offset` を持つ Codable
- `MacroRecorder`（`ObservableObject`）: listen-only の専用 CGEventTap で keyDown/keyUp/flagsChanged を記録。上限200イベント/60秒で自動停止。自己合成イベント（`SynthesizedClick.signature`）は除外
- `ActionExecutor.perform(.macro)`: 専用シリアルキューで `offset` どおりに `CGEvent` を再生。`os_unfair_lock` で保護した世代カウンタにより、再生中の再トリガーは即座に前の再生をキャンセルする（重複再生防止）
- 3本指タップの既定アクションは空マクロ（`.macro([])`）に変更。旧 Mission Control キーストロークの既定は廃止
- 設定UI: 「3本指タップ(マクロ)」セクションに録画開始/停止・クリア・イベント数表示を追加

### トラッキング速度ブースト
- `PointerSpeedManager`: `IOHIDEventSystemClient` SPI（`IOHIDEventSystemClientCreateSimpleClient` / `CopyProperty` / `SetProperty`）経由で `HIDMouseAcceleration`（システム設定スライダーの実体、IOFixed 16.16）を直接書き換え、即時反映。起動時に初期値を保持し復元可能にする
- SPI宣言は既存の単一ブリッジヘッダー `MultitouchBridge.h` に統合（`swiftc -import-objc-header` は1つしか指定できないため）
- `AppSettings.pointerSpeedBoost: Double` を追加、`SettingsSnapshot` に反映
- 設定UI: 「カーソル速度ブースト」スライダーを追加

### ビルド・実機確認
- `./build.sh` 実行、上記2機能を含む全ソースがコンパイル成功。既存の `onChange(of:perform:)` 非推奨警告以外エラーなし。`build/Magic Control.app` 生成・署名まで確認済み
- マクロ録画／再生と速度ブーストは実機確認済み
- 仮想トラックパッド、2本指スクロール、ネイティブ慣性、内蔵トラックパッドとの入力分離も実機確認済み
- アクセシビリティ権限の実行中切り替えは既知のmacOS入力フリーズを誘発し得るため、回帰テスト対象外。安全要件は`SAFETY.md`を参照
