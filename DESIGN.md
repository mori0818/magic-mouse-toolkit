# Magic Mouse Toolkit デザインシステム（DESIGN.md）

作成 2026-07-02 / 全面改訂 2026-07-28。
**正本は `Sources/DesignSystem.swift`。このドキュメントはその意図と実測の根拠を説明する。**
値が食い違ったらコードが正しい。ビューに直値を書かず、必ず `DS.*` トークンを経由すること。

当初あった「フェーズ1（ネイティブ）→ フェーズ2（Liquid Glass 再スキン）」の二段構えは
2026-07-06 に完了済み。以下はすべて現行（フェーズ2以降）の実装を記述する。

## デザインコンセプト

**「Magic Mouse 2（白）の表面ガラスをそのままウィンドウにする」**

- 標準の `.titled` ウィンドウ＋透明タイトルバー＋空の unified `NSToolbar`。信号機とタイトルバーは自作しない
- ウィンドウ全面に `glassEffect(.regular)` を敷き、その上に**白プレート**を全辺 8pt インセットで載せる。
  この 8pt の帯が「ガラスのリム」に見える
- 装飾はガラスの物理表現に必要なものだけ。**影・グラデーション・複数のアクセント色は持たない**
- 白プレートは白固定（`window.appearance = .aqua` で外観をライトに固定）。テキストはシステム外観追従トークンを使う

## トークン規約（自己ルール）

1. 同じ役割には同じトークン。**役割ごとの階段は1本だけ**持ち、重複トークンを作らない
   （例: コンテンツ上余白は `contentTop` 1本。ページ種別ごとに増やさない）
2. スペーシングは 4/8 グリッド（`DS.Space`）から外れた値を使わない。例外は `DS.Plate` のみ
3. フォントウェイトは `.regular` と `.semibold` だけ（`.medium` は使わない）
4. 影は使わない。角丸のグラマー（continuous / circular）を混ぜない
5. アクセント色は `DS.Color.accent` の1色のみ。**明示的に `.tint` するのは `Toggle` だけ**
6. **レイアウト値は目視で決めない。** @2x キャプチャの画素実測かフォントメトリクス実測で決め、
   根拠をトークンのコメントに残す

## トークン定義（`Sources/DesignSystem.swift`）

### カラー `DS.Color`

| トークン | 値 | 用途 |
|---|---|---|
| `labelPrimary` | `.primary` | 操作行のラベル・見出し |
| `labelSecondary` | `.secondary` | キャプション・単位・数値 |
| `accent` | `.controlAccentColor` | Toggle のみ（唯一のアクセント） |
| `debugPass` / `debugFail` | systemGreen / systemRed | ライブ表示の判定 ✓ / ✗ |
| `plateBase` | white 0.78 | 白プレートの地。縁がわずかに透ける |
| `plateCore` | white 0.82 | 縁から 26pt 引っ込め blur(18) した白コア |
| `cardFill` | rgb(241,241,241) | ライブ表示カード |

`plateBase` + `plateCore` の合成で、中央 ≈0.96（ほぼ白）／縁 ≈0.78（下のガラスが滲む）になる。
中央基点の `RadialGradient` は大画面で円形の明度ムラが出るため**使わない**（縁からの距離ベースのフェード）。

### スペーシング `DS.Space`

`xs 4 / s 8 / m 12 / l 16 / xl 24 / xxl 32`。この階段だけを使い、用途ごとの一点物を作らない。

### プレート幾何 `DS.Plate` — **触るな**

| トークン | 値 | 意味 |
|---|---|---|
| `inset` | 8 | ガラスリムの幅（白プレートを全辺から内側へ） |
| `fadeWidth` | 26 | 白コアをプレート縁から引っ込める幅＝フェード帯 |
| `fadeBlur` | 18 | 白コアの縁ぼかし |
| `radius` | 16 | 白プレートの角丸（**必ず `style: .continuous`**） |

**同心円角丸の原則**: 内側の角丸 = 外側ウィンドウの角丸 − インセット。
macOS 26 の `.titled` ウィンドウは continuous（squircle・カーブ範囲実測 ≈28pt）なので、
インセット 8pt に対して continuous 16pt がリム幅を角でも辺でも均一（実測 7.5〜8.5pt）に見せる。
`circular` にすると角でリムが痩せる。

### 角丸 `DS.Radius`

`card = 10` のみ。プレート幾何を除き、アプリ内の角丸はこの1種類。

### タイポグラフィ `DS.Font`（5トークン）

| トークン | 定義 | 用途 |
|---|---|---|
| `pageTitle` | 13 / semibold | ページ見出し「詳細設定」・戻るボタンのアイコン |
| `sectionHeader` | 11 / semibold | Section ヘッダー・カラム見出し |
| `body` | 13 | 操作行のラベル・HUD 本文 |
| `caption` | 11 | 補足キャプション・カード内本文 |
| `value` | 12 / monospaced | スライダー値・ライブ表示の実測値 |

Figma カンプの 10pt / 7pt は実機で小さすぎたため macOS 標準の可読サイズへ引き上げ済み（2026-07-10）。

### レイアウト `DS.Layout`

| トークン | 値 | 根拠 |
|---|---|---|
| `windowSize` | 700 × 392 | contentSize。unified タイトルバー 66pt が上に足され総高 458（実測） |
| `contentLeading` / `contentTrailing` | 32 (`Space.xxl`) | 左右対称。40→32 に短縮（2026-07-28 実機フィードバック） |
| `mainColumnWidth` | 328 | 32 + **328** + 44 + 264 + 32 = 700 |
| `columnGap` | 44 | 左カラム右端〜カード左端 |
| `liveCardSize` | 264 × 340 | プレート内に収める。はみ出し禁止 |
| `contentTop` | 8 (`Space.s`) | タイトルバー（safe area）下端からの距離。**全ページ共用** |
| `formBuiltInInset` | 30 | `Form(.grouped)` の内蔵インセット。**@2x 実測値** |
| `formInsetCompensation` | `contentLeading − 30` = 2 | 詳細設定ページの左右端をメイン画面に揃える補正 |
| `rowHeight` | 26 | 操作行の固定高。折り返しで揺れないよう機械的に固定 |
| `sliderLabelWidth` | 176 | 最長ラベル en "2-finger simultaneity window" = 175.2pt 実測 → 8グリッド直上 |
| `valueWidth` | 64 | 最長値 en "0.25 sec" = 59.3pt 実測 → 8グリッド直上 |

**高さの内訳**: `contentTop 8 + 見出し 15 + 間 12 + カード 340 = 375` + 下余白 9 + リム 8 = 392。
上を詰めたら下端も実測し、上下が同程度（上 8 / 下 9.5pt）になるまで高さトークンを縮める。

**`Form(.formStyle(.grouped))` の左端（macOS 26・幅 700pt で @2x 実測・2026-07-28）**

| 要素 | 左端 |
|---|---|
| セクション見出しテキスト | 30pt |
| グループカード内の行の中身（ラベル・キャプション） | 30pt |
| **グループカードの背景矩形そのもの** | **20pt**（見出し・行より 10pt 外側） |

基準にできるのは「見出しと行が共有する 30」。**カード背景だけは常に 10pt 外へはみ出し、
Form の構造を保ったままでは揃わない**（揃えたければ `VStack` + 自前カードへの構造変更が要る）。
自前ヘッダー（戻るボタン＋ページタイトル）は `contentLeading` を、
Form には `formInsetCompensation` を与えることで、全テキストが同一の左ライン（32pt）に乗る。

## コンポーネント規約

- **トグル**: `Toggle` + `.toggleStyle(.switch)` + `.controlSize(.small)` + `.tint(DS.Color.accent)`
- **ボタン**: 文法は `.bordered` **1本に統一**し、階層は `controlSize` だけで表す
  （主要＝`.regular` / 副次・下位設定＝`.small`）。`.borderedProminent` は使わない
- **スライダー行**: 全スライダーで `SliderRow` を共用。`lineLimit(1)` + `frame(height: rowHeight)` で固定。
  **値カラムには「数値＋単位」しか入れない**（「先端から25%」のような修飾語は行ラベル側に持たせる）。
  固定幅の値カラムに可変長テキストを入れるとその行だけ折り返し、セクション間で行のリズムが崩れる
- **セクション**: 詳細設定ページは `Form` + `Section(header:)` + `.formStyle(.grouped)` +
  `.scrollContentBackground(.hidden)`。メイン画面はフラットな `VStack`
- **ライブ表示**: 数値は必ず `DS.Font.value`（等幅）。判定は ✓/✗ + `debugPass`/`debugFail`
- 独自描画のカスタムコントロールは作らない

## 禁止事項

- ビュー内での直値指定（`.padding(13)`、`Color.gray`、`.font(.system(size: 12))` 等）
- サードパーティフォント・カラーアセット
- 影、複数のアクセント色、`.borderedProminent`
- 幅を固定した2カラム `HStack` の末尾に `Spacer(minLength: 0)` を残すこと。
  `spacing` は隣接ペアすべてに入るため gap が2回分効き、はみ出した `HStack` が中央寄せされて
  左右余白が非対称になる。余白は外側の `padding` で対称に取る
- 目視でのレイアウト決定。実装後は @2x キャプチャで左右端・上下端の実座標を測って数値で確認する

## ローカライズとレイアウト

`NSLocalizedString` の第1引数は**日本語リテラルそのものがキー**（ja/en 両 `.strings` の共通キー・現在117件）。
文言を変えるとキーが変わるため、レイアウト調整で表示文字列に手を入れるときは
必ず `Resources/{ja,en}.lproj/Localizable.strings` を同時に更新し、キー突合（欠落0・未使用0）を確認する。

固定幅カラムの幅は**全言語で**フォント実測してから決める（日本語だけ見て決めない）。
実際、英語ラベルのほうが日本語より長く、`sliderLabelWidth` は英語が律速している。

## 検証手順

1. `./build.sh`（Xcode プロジェクトなし。SourceKit の "Cannot find ... in scope" は各ファイル単独索引による偽陽性）
2. `open "build/Magic Mouse Toolkit.app"` → `pgrep -x MagicMouseToolkit` で生存確認
3. `screencapture -l <windowID>` で @2x キャプチャ（px ÷ 2 = pt）し、左右端・上下端・行高を画素実測
4. ローカライズキー突合（`Sources/*.swift` の第1引数 vs `plutil -convert json` した両 `.strings`）
