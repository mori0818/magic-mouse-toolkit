# 多言語化（日本語/英語ローカライズ）実装手順書

作成日: 2026-07-27。この文書は現行コード（`main` ブランチ, `ce0998e`）を実地確認した上で作成している（実コード照合済み）。
この文書だけを見て多言語化作業を完了できることを目標とする。README向けの告知文の書き換えは対象外（別タスク）。

## 0. 現状（実コード照合済み）

- **ビルド方式**: Xcodeプロジェクトなし。`build.sh` が `swiftc` を直接呼んで arm64/x86_64 を個別コンパイルし `lipo` で結合している。
  つまり `.lproj` の自動コンパイル・バンドルは行われない。**手動でリソースをバンドルする必要がある。**
- **ローカライズ基盤**: `NSLocalizedString` / `.strings` / `.xcstrings` は現状ゼロ。`Info.plist` に
  `CFBundleDevelopmentRegion` / `CFBundleLocalizations` も未設定。
- **日本語文字列の分布**（`Sources/` 全19ファイル、552行に日本語を含む）:
  - うち **382行はコメントのみ**（翻訳対象外。開発者向けメモとして日本語のまま残す）
  - 残り **約170行がコード内文字列**（UI表示 or ログ出力）で、これが変換対象の候補

## 1. スコープ（今回の変換対象・対象外）

### 対象（NSLocalizedStringでラップする）

ユーザーが画面上で目にする文字列のみ。実地確認した該当箇所:

| ファイル | 内容 | 件数目安 |
|---|---|---|
| `Sources/AppDelegate.swift` | メニューバーの項目タイトル（164, 169, 174, 179, 186, 193, 197, 203, 209行目）と動的ステータス文字列（262-263, 268-269, 276-277行目） | 約18箇所 |
| `Sources/SettingsView.swift` | 設定画面の `Text` / `Button` / `Toggle` / `Picker` / `caption` / `SliderRow` ラベル全般 | 約90箇所 |
| `Sources/TrackpadModeHUD.swift` | 69行目 `"トラックパッドモード beta"` | 1箇所 |
| `Sources/TapRecognizer.swift` | `TapFailureReason` の10ケース（16-26行目）と `record()` 呼び出しのlabel/actual/threshold文字列 | 約25箇所 |
| `Sources/TouchGestureManager.swift` | `DebugFeed.shared.pushEvent(...)` の3箇所（357, 379, 385行目） | 3箇所 |

これらはユーザーがスクリーンショットで見たデバッグライブ表示（「直近のイベント」「判定内訳」欄）にも出るため、
`TapFailureReason` と `pushEvent` の文言は見落としやすいが対象に含める。

### 対象外（今回は手を付けない）

- `MMTLog.log(...)` 呼び出しの日本語メッセージ（開発者向け診断ログで `~/Library/Logs/MagicMouseToolkit.log` にのみ出力され、UIに出ない）。
  将来必要になれば別タスクとして切り出す。
- コメント（382行）。
- `README.md` 等ドキュメント文面（ユーザーの指示により今回は対象外。コード対応が終わった後の別作業とする）。

## 2. 要注意箇所（enumのrawValueが表示文字列を兼ねている）

実地確認したところ、以下2箇所は enum の `rawValue` がそのまま画面表示文字列になっている。
**永続化（`Codable`/`UserDefaults`）はされていないため書き換え自体は安全**だが、
`rawValue` を直接英訳すると `.rawValue` を参照している既存コードの表示ロジックが空文字列的に壊れるため、
「識別子用のrawValue」と「表示用の文字列」を分離する。

- `Sources/SettingsView.swift` 68-71行目 `BoundActionKind`（`case macro = "マクロ"` 等）
  → `rawValue` はASCII識別子に変更し、`var localizedTitle: String` を追加してUI側はそちらを参照する。
  用途は `ForEach(BoundActionKind.allCases)` と `Identifiable` の `id` のみ（212行目）なので、他ロジックへの影響なし（確認済み）。
- `Sources/TapRecognizer.swift` 16-26行目 `TapFailureReason`
  → 同様に `rawValue` を識別子化し、`var localizedDescription: String` を追加。
  参照箇所は `TouchGestureManager.swift` 277, 278, 330, 337行目の `.rawValue` 呼び出しのみ（確認済み）で、
  これらを `.localizedDescription` に置き換える。

## 3. インフラ構築

1. **Info.plist に追加**:
   ```xml
   <key>CFBundleDevelopmentRegion</key>
   <string>ja</string>
   <key>CFBundleLocalizations</key>
   <array>
       <string>ja</string>
       <string>en</string>
   </array>
   ```
2. **リソースディレクトリ新設**: `Resources/ja.lproj/Localizable.strings`、`Resources/en.lproj/Localizable.strings`
   （空ファイルで作成し、§4のgenstringsで ja 版を生成する）
3. **`build.sh` 修正**: `.app` バンドル生成部分（現在 `Contents/MacOS` を作って `cp Info.plist` している箇所）に
   Resources のコピーを追加する:
   ```sh
   mkdir -p "build/$APP/Contents/Resources"
   cp -R Resources/ja.lproj Resources/en.lproj "build/$APP/Contents/Resources/"
   ```
4. `build.yml` の `Validate scripts and plist` ステップは `plutil -lint Info.plist` のみなので、
   キー追加後もそのまま通る想定（追加のCI変更は不要）。

## 4. コード変換・翻訳フロー

1. §1の対象箇所を `NSLocalizedString("元の日本語", comment: "画面上のどこに出るかの説明")` でラップする。
   キーは日本語原文をそのまま使う（Apple標準の `genstrings` ワークフローに合わせ、キーの新規採番はしない）。
2. `String(format:)` を使っている箇所（例: `SettingsView.swift` 187, 341, 349行目等、`TapRecognizer.swift` 64-134行目）は
   フォーマット文字列自体を `NSLocalizedString` でラップする。英語で語順が変わりうる場合は `%1$@` 等の位置指定子を使う。
3. §2の2箇所は `rawValue` を識別子化した上で `localizedTitle` / `localizedDescription` 内で `NSLocalizedString` を呼ぶ。
4. 全箇所のラップが終わったら抽出:
   ```sh
   genstrings -o Resources/ja.lproj Sources/*.swift
   ```
   生成された `Resources/ja.lproj/Localizable.strings` はUTF-16のためコミット前に
   `iconv -f UTF-16 -t UTF-8` 等でエンコーディングを確認する。
5. `Resources/en.lproj/Localizable.strings` を作成し、`ja.lproj` の各キーに対応する英訳を追記する（手動翻訳）。

## 5. ビルド・動作確認手順

1. `./build.sh` でビルド。
2. 英語UI確認: `open "build/Magic Mouse Toolkit.app" --args -AppleLanguages "(en)"` で起動し、
   メニューバー・設定画面・デバッグライブ表示（タップ判定内訳欄を含む）の3箇所を目視確認する。
3. 日本語（デフォルト）でも文字列欠落がないことを確認する（`genstrings` 直後は ja=原文のため差分なしのはず）。
4. `codesign --verify --deep --strict` は `build.yml` の既存ステップでそのまま検証されるため追加対応不要。

## 6. 進め方の提案

170箇所前後の変換を一度に行うとレビューが困難なため、ファイル単位で段階的に進める:

1. `TapFailureReason` / `BoundActionKind` の識別子分離（§2）— 他ファイルの前提になるため最初に着手
2. `AppDelegate.swift`（メニュー）
3. `SettingsView.swift`（設定画面、件数が多いので必要なら前半/後半で分割）
4. `TrackpadModeHUD.swift` / `TouchGestureManager.swift`（残り）
5. §3のインフラ整備・§4のgenstrings実行・英訳
6. 動作確認（§5）

ブランチは公開リポジトリの `main` から `feature/localization` を切って進める（プライベート開発リポジトリ
`~/Documents/Claude/MagicControl` とは別系統。現在 `main` が公開リポジトリの正本のため直接そこから分岐する）。
