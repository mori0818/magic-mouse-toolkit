# Magic Control

Magic Control is an open-source macOS utility that adds configurable gestures
and a virtual trackpad mode to Apple Magic Mouse.

現在は日本語UIです。英語UIを含むローカライズ基盤は公開後の開発項目です。

## Features

- 1本指タップによる左／右クリック
- 2本指タップによる左クリック
- 2本指の物理クリックによるミドルクリック
- 3本指で録画したキーボードマクロを実行
- Magic Mouse表面を1本指でなぞる仮想トラックパッドモード
- 仮想トラックパッドモード中の2本指スクロールとネイティブ慣性
- 3本指ダブルタップによるモード切り替え
- MacBook内蔵トラックパッドとの入力分離
- Magic Mouseのバッテリー残量表示
- カーソル速度ブースト
- タップ範囲・感度・スクロール設定をUIから変更

## Requirements

- macOS 26以降
- Apple Magic Mouse
- ビルドにはXcodeまたはmacOS 26 SDKを含むSwift toolchain
- クリック合成・マクロ・入力変換にはアクセシビリティ権限

このアプリはAppleの非公開`MultitouchSupport.framework`とIOKit SPIを使用します。
将来のmacOSアップデートで動作しなくなる可能性があり、Mac App Store向けではありません。

## Safety

**Magic Controlの実行中に、システム設定からアクセシビリティ権限をOFF・削除しないでください。**

CGEventTapを使用するアプリの実行中に権限を変更すると、macOSのシステム入力が停止する場合があります。
権限を変更する必要がある場合は、先にメニューバーからMagic Controlを通常終了してください。
`tccutil reset`は通常のセットアップやトラブルシューティングでは使用しないでください。

詳しくは[SAFETY.md](./SAFETY.md)を参照してください。

## Build

```sh
git clone <repository-url>
cd magic-control
./build.sh
open "build/Magic Control.app"
```

`SIGN_ID`を指定しない場合はad-hoc署名を使用します。

```sh
SIGN_ID="Developer ID Application: Example (TEAMID)" ./build.sh
```

ローカルの自己署名証明書も`SIGN_ID`で指定できます。証明書や秘密鍵はリポジトリへ
コミットしないでください。署名が変わると、macOSからアクセシビリティ権限の再許可を
求められることがあります。その場合も、権限を変更する前に古いアプリを終了してください。

## Privacy

- アプリ本体にテレメトリ、解析SDK、ネットワーク送信処理はありません。
- マクロ録画中は、キーボードのキーコード・修飾キー・押下状態・タイミングを端末内の
  UserDefaultsへ保存します。文字列や入力内容を外部へ送信しません。
- パスワードや秘密情報を入力している間はマクロを録画しないでください。
- 診断ログは`~/Library/Logs/MagicControl.log`へ保存され、約1 MiBでローテーションします。
  ログにはジェスチャー判定や座標などの操作メタデータが含まれる場合があります。

## System-wide settings

カーソル速度ブーストは、システム全体の`HIDMouseAcceleration`を一時的に変更します。
通常終了時には元の値へ戻しますが、強制終了後に速度が残った場合は、Magic Controlを
終了してから「システム設定 → マウス → 軌跡の速さ」を動かして復旧してください。

## Documentation

- [SAFETY.md](./SAFETY.md) — 権限変更・入力フリーズ・速度設定に関する安全情報
- [SPEC.md](./SPEC.md) — 機能仕様
- [ARCHITECTURE.md](./ARCHITECTURE.md) — 構成と第三者コードの由来
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) — 実装仕様
- [UI_DESIGN.md](./UI_DESIGN.md) — UI・デザイン方針
- [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) — 第三者コードとライセンス
- [CONTRIBUTING.md](./CONTRIBUTING.md) — 開発への参加方法
- [SECURITY.md](./SECURITY.md) — 脆弱性の報告方法

## Third-party work

Magic ControlはMouseToucherのMITライセンス対象コードと設計を起点の一部として利用し、
MiddleClickのGPL-3.0実装を参考・改変しています。由来とライセンス全文は
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)を参照してください。

## License

Magic Control is licensed under the GNU General Public License v3.0 only.
See [LICENSE](./LICENSE).
