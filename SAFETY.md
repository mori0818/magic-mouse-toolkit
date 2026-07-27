# Safety

Magic Controlは、システム全体の入力を監視・変換するCGEventTapと、Appleの非公開
MultitouchSupport APIを使用します。通常利用では実機確認済みですが、権限やプロセスを
強制的に変更する操作には注意が必要です。

## アクセシビリティ権限

Magic Controlの実行中に、次の操作をしないでください。

- システム設定でMagic Controlのアクセシビリティ権限をOFFにする
- アクセシビリティ一覧からMagic Controlを削除する
- `tccutil reset`で権限をリセットする
- 権限を短時間に何度もON／OFFする

CGEventTapを持つアプリの実行中に権限を剥奪すると、macOS側でクリックやキーボード入力が
停止する場合があります。

権限を変更する場合:

1. メニューバーからMagic Controlを通常終了する
2. Activity Monitorで`MagicControl`が終了したことを確認する
3. システム設定で権限を変更する
4. Magic Controlを起動する

入力が反応しなくなった場合は、別の利用可能な入力経路からMagic Controlを終了してください。
それでも復旧しない場合はmacOSを再起動してください。

## カーソル速度

速度ブーストはシステム全体の`HIDMouseAcceleration`を一時的に変更します。
通常終了時には元の値へ戻します。

強制終了後に速度が残った場合:

1. Magic Controlを終了する
2. 「システム設定 → マウス → 軌跡の速さ」を一度動かす
3. 必要ならMagic Controlの速度ブーストをOFFにして再起動する

## マクロ録画

録画中はすべてのキーボードイベントをlisten-onlyのCGEventTapで監視します。
録画データは端末内にだけ保存されますが、パスワードや秘密情報を入力している間は
録画しないでください。

## 開発・検証

入力系コードを変更した場合でも、権限のON／OFFを回帰テストとして使用しないでください。
EventInterceptor、PermissionMonitor、MultitouchDevice周辺の変更は、ビルド・コードレビュー・
通常終了経路の確認を先に行ってください。
