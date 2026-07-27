# Magic Mouse Toolkit architecture

Magic Mouse Toolkitは、Magic Mouseのマルチタッチ入力を読み取り、CGEventを使ってクリック、
スクロール、カーソル移動、キーボードマクロへ変換するメニューバーアプリです。

## Runtime

- Swift 6
- macOS 26 SDK
- AppKit + SwiftUI
- `swiftc`直接ビルド
- arm64 / x86_64 Universal Binary
- Bundle ID: `com.mori0818.magicmousetoolkit`

## Third-party provenance

詳細な著作権表示とライセンスは
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)を参照してください。

### MouseToucher

[MouseToucher](https://github.com/meatpaste/mousetoucher)はMIT Licenseです。
Magic Mouse Toolkitの初期プロトタイプでは、次の領域を起点として利用しました。

- `MultitouchSupport.framework`用のCブリッジ宣言
- `MTDeviceCreateList`と`MTDeviceIsBuiltIn`によるデバイス列挙
- `swiftc`と`lipo`を使うUniversal Binaryのビルド方式
- アクセシビリティ権限要求の初期構成
- タップ検出ステートマシンの初期設計

現行コードでは、デバイスのretain／release、Bluetooth再接続、IOKit着脱通知、
コールバック間共有状態、スクロールベト、マクロ、仮想トラックパッドなどを追加し、
ファイル構成と実装を大きく再設計しています。それでも由来は実質的であるため、
MouseToucherの著作権表示とMIT Licenseを継続して掲載します。

### MiddleClick

[MiddleClick](https://github.com/artginzburg/MiddleClick)はGPL-3.0です。
物理クリックイベントを破棄・再送信せず、同じCGEventのtypeとボタン番号を書き換えて
ミドルクリックとして返す方式を参考・改変しています。

Magic Mouse Toolkit全体をGPL-3.0-onlyで公開することで、この由来と互換性を保ちます。

## Components

### `MultitouchDevice.swift`

- MultitouchSupportからデバイスを列挙
- Magic Mouseのfamily IDとbuilt-in属性を判定
- 内蔵トラックパッドを入力元判別専用で監視
- デバイス参照のretain／release
- スリープ復帰、Bluetooth再接続、IOKit着脱通知

### `TouchGestureManager.swift` / `TapRecognizer.swift`

- タッチフレームを追跡
- 1本指・2本指・3本指ジェスチャーを判定
- スクロール、物理クリック、慣性中の誤タップを抑制
- 設定値は`SettingsSnapshot`から読み、MTコールバック内でUserDefaultsを読まない

### `EventInterceptor.swift`

1本のCGEventTapで次を処理します。

- 物理クリック監視
- 2本指物理クリックからミドルクリックへの変換
- スクロール状態の監視
- 仮想トラックパッドモード中のスクロール所有元分離
- ネイティブ慣性スクロールの通過

CGEventTapコールバック内では、アロケーション、ファイルログ、UserDefaults読み取りを
行わないことが安全要件です。

### `TrackpadModeController.swift`

- Magic Mouse表面の相対移動をカーソル移動へ変換
- 120 Hzの専用キューでイベントを生成
- 2本指スクロール中はカーソル追跡を停止
- 3本指ダブルタップによるモード切り替え

### `MacroRecorder.swift` / `ActionExecutor.swift`

- listen-only CGEventTapでキーイベントを録画
- 200イベントまたは60秒で自動停止
- 端末内のUserDefaultsへ保存
- 専用シリアルキューで再生
- 再トリガー時は世代番号で以前の再生を中断

公開版では任意シェルコマンド、任意アプリ起動、汎用キーストロークの未使用経路を
削除し、マクロとトラックパッド切り替えだけを公開しています。

### `PermissionMonitor.swift`

`AXIsProcessTrusted()`のTCCキャッシュだけに依存せず、テスト用CGEventTapを作成できるかで
権限状態を監視します。権限喪失時はEventInterceptorを完全に破棄します。

ユーザー向けの安全要件は[SAFETY.md](./SAFETY.md)を参照してください。

### `PointerSpeedManager.swift`

IOHIDEventSystemClient SPIでシステムの`HIDMouseAcceleration`を変更します。
元値をUserDefaultsに保持し、通常終了時に復元します。

### `Logger.swift`

unified logと`~/Library/Logs/MagicMouseToolkit.log`へ診断情報を書きます。
ファイルログは約1 MiBで`MagicMouseToolkit.log.old`へローテーションします。

## Build and signing

`build.sh`はarm64とx86_64を個別にコンパイルし、`lipo`でUniversal Binaryへ統合します。

- `SIGN_ID`未指定: ad-hoc署名
- `SIGN_ID`指定かつKeychainに存在: 指定identityで署名

公開バイナリを配布する場合は、Developer ID Application署名とApple notarizationを
別途行う必要があります。秘密鍵や証明書はリポジトリへ含めません。

## Private API boundary

次の非公開APIへ依存します。

- `/System/Library/PrivateFrameworks/MultitouchSupport.framework`
- `MTDevice*`
- `MTRegisterContactFrameCallback`
- `IOHIDEventSystemClient*`
- `HIDMouseAcceleration`

このためMac App Store向けではなく、将来のmacOSで互換性が失われる可能性があります。
