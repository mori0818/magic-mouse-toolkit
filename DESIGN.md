# Magic Mouse Toolkit デザインシステム（DESIGN.md)

作成日: 2026-07-02。プロトタイプ（フェーズ1）から最終 Liquid Glass デザイン（フェーズ2）まで一貫して使うデザインシステム。**ビューに直値を書かず、必ず `DesignSystem.swift` のトークンを経由する**。これによりフェーズ2の再スキンはトークン値の差し替えだけで完了する。

## デザインコンセプト（最終形 = フェーズ2)

**「Magic Mouse 2（白）の表面ガラスをそのままウィンドウにする」**

- 白ベースの乳白 Liquid Glass。ダークモードでも白基調を維持（外観固定）
- ウィンドウ縁は半透明のガラス帯 + 白ハイライトストロークで、マウス表面の縁の光り方をモチーフにする
- 装飾は「ガラスの物理表現」に必要なものだけ。それ以外の影・グラデーションは持たない

フェーズ1（プロトタイプ）は同じトークン名でネイティブなシステム値にマップし、実装を簡単にする。

## トークン定義

`DesignSystem.swift` に `enum DS` として実装する。

### カラー `DS.Color`

| トークン | フェーズ1（プロトタイプ） | フェーズ2（Liquid Glass） | 用途 |
|---|---|---|---|
| windowBackground | `Color(nsColor: .windowBackgroundColor)` | 乳白ガラス（glassEffect + white 0.6） | ウィンドウ地 |
| surface | `Color(nsColor: .controlBackgroundColor)` | white 0.35 | セクション面 |
| edgeHighlight | `.clear`（未使用） | white 0.8 | 縁のハイライトストローク |
| labelPrimary | `Color(nsColor: .labelColor)` | 濃グレー #3A3A3C | 主要テキスト |
| labelSecondary | `Color(nsColor: .secondaryLabelColor)` | グレー #8E8E93 | 補助テキスト・単位 |
| accent | `Color(nsColor: .controlAccentColor)` | ライトグレー #C7C7CC 系（白基調に馴染む） | トグルON・スライダー |
| debugPass / debugFail | systemGreen / systemRed | 同左（彩度を落とす） | デバッグ判定表示 |

### スペーシング `DS.Space`（両フェーズ共通）

| トークン | 値 |
|---|---|
| xs / s / m / l / xl | 4 / 8 / 12 / 16 / 24 |
| sectionSpacing | 16 |
| windowPadding | 20 |

### 角丸 `DS.Radius`

| トークン | フェーズ1 | フェーズ2 |
|---|---|---|
| window | 0（標準ウィンドウ） | 24（continuous、Magic Mouse 輪郭モチーフ） |
| surface | 6 | 12（continuous） |
| control | システム標準 | システム標準 |

### タイポグラフィ `DS.Font`（両フェーズ共通、San Francisco のみ）

| トークン | 定義 | 用途 |
|---|---|---|
| sectionHeader | `.system(size: 11, weight: .semibold)` + labelSecondary | Section ヘッダー |
| body | `.system(size: 13)` | ラベル全般 |
| value | `.system(size: 12, design: .monospaced)` | スライダー現在値・デバッグ数値 |
| caption | `.system(size: 11)` + labelSecondary | 説明・単位 |

### レイアウト定数 `DS.Layout`

| トークン | 値 |
|---|---|
| windowSize | 440 × 620（リサイズ不可） |
| sliderLabelWidth | 140（ラベル列の固定幅、スライダー開始位置を揃える） |
| valueWidth | 56（数値表示列の固定幅） |

## コンポーネント規約

- **トグル**: `Toggle` + `.toggleStyle(.switch)`。tint は `DS.Color.accent`
- **スライダー行**: `HStack { Text(label).frame(width: DS.Layout.sliderLabelWidth, alignment: .leading); Slider(...); Text(value).font(DS.Font.value).frame(width: DS.Layout.valueWidth, alignment: .trailing) }` — 全スライダーでこの1つの行コンポーネント（`SliderRow`）を共用する
- **セクション**: フェーズ1は `Form` + `Section(header:)`。フェーズ2は同じ構造を `DS.Color.surface` の角丸パネルに載せ替える
- **デバッグ表示**: `DisclosureGroup`。数値は必ず `DS.Font.value`（等幅）。判定は ✓/✗ + debugPass/debugFail 色
- 独自描画のカスタムコントロールは作らない（範囲指定も min/max 2本のスライダーで表現）

## 禁止事項

- ビュー内での直値指定（`.padding(13)`、`Color.gray`、`.font(.system(size: 12))` 等）→ 必ず DS トークン
- サードパーティフォント・カラーアセット
- フェーズ1でのガラス・ブラー・影の先行実装（フェーズ2でウィンドウごと差し替える)

## フェーズ2 移行手順（メモ）

1. `GlassWindow.swift`（borderless・透明・canBecomeKey・isMovableByWindowBackground）を追加
2. `DS.Color` / `DS.Radius` のフェーズ2値へ切り替え（`static let phase2 = true` のようなフラグでも、値の直接書き換えでもよい）
3. ルートビューに `glassEffect` + 白レイヤー + 縁ストロークの背景を追加、`preferredColorScheme(.light)` 固定
4. 閉じるボタンを自前配置（タイトルバー廃止のため）
