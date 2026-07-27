// The initial permission and menu-bar setup was informed by MouseToucher.
// Copyright (c) 2025 Roger Hughes, used under the MIT License.
// See THIRD_PARTY_NOTICES.md. Magic Control changes: GPL-3.0-only.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    private var permissionStatusItem: NSMenuItem?
    private var deviceStatusItem: NSMenuItem?
    private var batteryStatusItem: NSMenuItem?
    private var openAccessibilityItem: NSMenuItem?

    /// Dock/Finderから再度開かれたとき設定ウィンドウを表示する
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MCLog.log("========== Magic Control 起動 ==========")
        AppSettings.shared.registerDefaults()
        // イベントタップ/MTコールバック内での遅延初期化(アロケーション+オブザーバ登録)を
        // 避けるため、ここで先に初期化しておく
        _ = SettingsStore.shared.snapshot
        setupMenuBar()

        // タッチ監視はアクセシビリティ権限と無関係に動くため即起動する
        // （権限が無くてもライブ表示・タップ判定のデバッグができるように）
        MultitouchDeviceManager.shared.start()
        // Bluetooth 再接続（スリープ復帰後・アイドル切断後）を検知して自動再検出する
        MultitouchDeviceManager.shared.startHotplugMonitoring()

        // トラッキング速度ブースト: 元値の保持と現在設定の適用
        PointerSpeedManager.shared.start()

        showAccessibilityPromptIfNeeded()

        // 権限の有無は PermissionMonitor が生存期間中ずっとポーリングし続ける
        // (AXIsProcessTrusted は権限OFF直後もtrueを返し続けるため信頼できない。
        // SAFETY.md参照)。ON→OFF→ONと何度変化しても同じ経路で処理される。
        PermissionMonitor.start(
            onGranted: { [weak self] in self?.onPermissionGranted() },
            onRevoked: { [weak self] in self?.handleAccessibilityRevoked() }
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        // スリープ前にタッチ監視を止める。デバイスが生きているうちにクリーンに
        // 停止・解放しないと、スリープ中のBluetooth切断で死んだ参照に対して
        // 復帰時の restart()→stop() が MTDeviceStop を呼びクラッシュする(2026-07-11)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)

        // UI検証用(MC_DISABLE_TAPと同じenv切り分けパターン)。
        // 通常起動では何もしない。1にすると起動直後に設定ウィンドウを開く
        // (スクリーンショットによるデザイン確認のため。2026-07-10)
        if ProcessInfo.processInfo.environment["MC_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }

        // クリック合成経路の自己診断(2026-07-11 リグレッション調査用)。
        // 自アプリの設定ウィンドウのタイトルバーへ合成クリックを1回撃ち、
        // post→HID注入→着弾の各段をログで確認する。外部UIには一切触れない。
        if ProcessInfo.processInfo.environment["MC_SELFTEST_CLICK"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.runClickSelfTest()
            }
        }
    }

    /// 合成クリックのセルフテスト。着弾確認用のローカルモニタを張ってから、
    /// 設定ウィンドウのタイトルバー中央(無害な着弾点)へ SynthesizedClick.post する。
    private func runClickSelfTest() {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let frame = self?.settingsWindow?.frame,
                  let mainScreen = NSScreen.screens.first else {
                MCLog.log("[自己診断] 設定ウィンドウの座標が取得できず中止")
                return
            }
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                MCLog.log("[自己診断] 自ウィンドウがleftMouseDownを受領(着弾確認)")
                return event
            }
            // AppKit座標(左下原点)→CGEvent座標(左上原点)。タイトルバー内の点を狙う
            let point = CGPoint(x: frame.midX, y: mainScreen.frame.maxY - frame.maxY + 12)
            MCLog.log("[自己診断] 合成クリックを自ウィンドウのタイトルバーへ送出 loc=(\(Int(point.x)),\(Int(point.y)))")
            SynthesizedClick.post(button: .left, at: point)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MCLog.log("終了")
        PermissionMonitor.stop()
        EventInterceptor.shared.stop()
        MultitouchDeviceManager.shared.stopHotplugMonitoring()
        MultitouchDeviceManager.shared.stop()
        PointerSpeedManager.shared.restoreAndStop()
    }

    // MARK: - 権限フロー

    /// 初回起動時などまだ未許可の場合、システムのアクセシビリティ許可ダイアログを
    /// 一度だけ表示するためのトリガー。実行中の権限変化の検知には使わない
    /// (AXIsProcessTrustedWithOptions もキャッシュの影響を受けるため)。
    private func showAccessibilityPromptIfNeeded() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        MCLog.log("アクセシビリティ権限(起動時点): \(trusted ? "許可済み" : "未許可(システムダイアログを表示)")")
    }

    private func onPermissionGranted() {
        MCLog.log("アクセシビリティ権限を検知(許可)")
        SharedState.shared.accessibilityGranted = true
        // 開発時の切り分け用: MC_DISABLE_TAP=1 の場合は
        // CGEventTapを一切作らない(MultitouchDeviceManagerのみ動作)。
        // これでもフリーズが再現すればタップ以外が原因と判定できる。
        if ProcessInfo.processInfo.environment["MC_DISABLE_TAP"] == "1" {
            MCLog.log("MC_DISABLE_TAP=1 のためイベントタップ作成をスキップ(切り分け検証モード)")
            return
        }
        EventInterceptor.shared.start()
    }

    /// PermissionMonitor がテストタップの作成失敗を検知したら呼ばれる。
    /// タップを即座に破棄し(CFMachPortInvalidate含む)、権限復帰を待つ状態に戻る。
    private func handleAccessibilityRevoked() {
        MCLog.log("アクセシビリティ権限の喪失を検知。タップを破棄します")
        SharedState.shared.accessibilityGranted = false
        EventInterceptor.shared.stop()
    }

    @objc private func willSleep() {
        MCLog.log("スリープ準備: タッチ監視を停止")
        MultitouchDeviceManager.shared.stop()
    }

    @objc private func didWake() {
        MCLog.log("スリープ復帰")
        MultitouchDeviceManager.shared.restart()
        PointerSpeedManager.shared.reapply()
    }

    // MARK: - メニューバー

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "magicmouse", accessibilityDescription: "Magic Control")
            button.image?.isTemplate = true
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 状態表示（menuWillOpen で毎回更新）
        let permissionItem = NSMenuItem(title: "権限: 確認中…", action: nil, keyEquivalent: "")
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)
        permissionStatusItem = permissionItem

        let deviceItem = NSMenuItem(title: "デバイス: 確認中…", action: nil, keyEquivalent: "")
        deviceItem.isEnabled = false
        menu.addItem(deviceItem)
        deviceStatusItem = deviceItem

        let batteryItem = NSMenuItem(title: "バッテリー: 確認中…", action: nil, keyEquivalent: "")
        batteryItem.isEnabled = false
        menu.addItem(batteryItem)
        batteryStatusItem = batteryItem

        let openAXItem = NSMenuItem(title: "アクセシビリティ設定を開く…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        openAXItem.target = self
        menu.addItem(openAXItem)
        openAccessibilityItem = openAXItem

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(title: "有効", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = AppSettings.shared.enabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        let openSettingsItem = NSMenuItem(title: "設定を開く…", action: #selector(openSettings), keyEquivalent: ",")
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        let rediscoverItem = NSMenuItem(title: "デバイスを再検出", action: #selector(rediscoverDevices), keyEquivalent: "")
        rediscoverItem.target = self
        menu.addItem(rediscoverItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "Magic Control について", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        menu.delegate = self
        return menu
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        AppSettings.shared.enabled.toggle()
        sender.state = AppSettings.shared.enabled ? .on : .off
        MCLog.log("有効切り替え: \(AppSettings.shared.enabled)")
    }

    @objc private func rediscoverDevices() {
        MultitouchDeviceManager.shared.restart()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            // Liquid Glass ウィンドウ（フェーズ2）
            let window = GlassWindow.make(
                rootView: SettingsView(),
                title: "Magic Control",
                contentSize: DS.Layout.windowSize
            )
            window.delegate = self
            settingsWindow = window
            // 初回生成時のみ中央配置。既存ウィンドウはユーザーが動かした位置を尊重する
            window.center()
        }
        // makeKeyAndOrderFront は最小化(Dock収納)状態を解除しないため明示的に戻す
        if settingsWindow?.isMiniaturized == true {
            settingsWindow?.deminiaturize(nil)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let trusted = AXIsProcessTrusted()
        permissionStatusItem?.title = trusted
            ? "権限: 許可済み ✓"
            : "権限: 未許可 ✗（クリックが送出できません）"
        openAccessibilityItem?.isHidden = trusted

        let manager = MultitouchDeviceManager.shared
        if manager.activeDeviceCount > 0 {
            let fallbackNote = manager.usedFallbackFilter ? "・フォールバック中" : ""
            deviceStatusItem?.title = "デバイス: \(manager.activeDeviceCount)台 検出\(fallbackNote)"
        } else {
            deviceStatusItem?.title = "デバイス: 未検出 ✗（familyId: \(manager.lastDiscoveredFamilyIDs)）"
        }

        if let percent = BatteryMonitor.mouseBatteryPercent() {
            batteryStatusItem?.title = percent <= 20
                ? "バッテリー: \(percent)% ⚠"
                : "バッテリー: \(percent)%"
            batteryStatusItem?.isHidden = false
        } else {
            // マウス未接続時はデバイス表示と情報が重複するため、行ごと隠す。
            batteryStatusItem?.isHidden = true
        }

        // 有効トグルの状態を同期（状態表示の後、セパレータの次）
        for item in menu.items where item.action == #selector(toggleEnabled) {
            item.state = AppSettings.shared.enabled ? .on : .off
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DebugFeed.shared.isActive = false
        settingsWindow = nil
    }
}
