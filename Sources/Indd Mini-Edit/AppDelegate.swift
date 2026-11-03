//
//  AppDelegate.swift
//  Indd Mini-Edit
//
//  アプリケーションデリゲート（純 AppKit）。
//   - LSUIElement（Dock に出ない・メニューバーを持たない）のエージェント型アプリ。
//   - 入力バーを閉じたらアプリを終了する（旧版の App.AllowAutoQuit = True 相当。入力バーの willClose で終了）。
//
//  入力バーは InputPanel（非アクティブ化パネル。ステップ2＝試作）。
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var inputPanelController: InputPanelController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 環境設定の既定値（ステップ8）。入力バーを作る前に登録する。
        Settings.registerDefaults()
        // 起動前の最前面アプリ（ふつうは InDesign）。起動で自分が最前面になったときに戻す先。
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousFrontmostApp = frontmost == NSRunningApplication.current ? nil : frontmost
        // ウィンドウの自動アニメーション（表示時のフェードイン等）を無効化する（浮紙と同じ）。
        UserDefaults.standard.register(defaults: ["NSAutomaticWindowAnimationsEnabled": false])
        // メインメニューをコードで構築する（xib 不使用。ショートカット用）。
        MainMenuBuilder.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = InputPanelController()
        inputPanelController = controller
        // 起動時に最前面だった InDesign を送り先の候補として覚えておく（ステップ7.4）。
        controller.indesign.launchApp = previousFrontmostApp
        controller.show()
        // 入力バーが閉じたら終了する（送信成功・Esc・閉じるアイコン・⌘W はどれも入力バーを閉じる）。
        // 閉じる処理を終えてから終了するよう、次のランループで terminate する。
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: controller.panel, queue: .main) { _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        // 起動で自分が最前面アプリになっていたら、起動前の最前面アプリ（InDesign）へ戻す。
        DispatchQueue.main.async { [weak self] in
            self?.returnFrontmostToPreviousApp()
        }
    }

    /// 起動前の最前面アプリ（applicationWillFinishLaunching で捕捉。ふつうは InDesign）。
    private var previousFrontmostApp: NSRunningApplication?

    /// 自分が実際の最前面アプリになっているときだけ、起動前の最前面アプリをアクティブに戻し、入力バーをキーにし直す。
    ///
    /// ⚠️ `NSApp.isActive` では判定しない（ステップ7.3）: 非アクティブ化パネルがキーになると、最前面アプリは
    /// 他のアプリのままでも isActive は true を返す。それを見て `NSApp.deactivate()` すると入力バーのキーが外れ、
    /// 本当にアクティブだったわけではないので didResignActive も来ない＝起動しても入力バーがアクティブにならなかった
    /// （実機 2026-10-31・実験アプリで再現）。また本当に最前面のときの `deactivate()` は前のアプリへ最前面を戻さない
    /// （実験）。前のアプリを `activate()` してから入力バーをキーにし直すと、どちらも解決する（実験で確認）。
    private func returnFrontmostToPreviousApp() {
        guard NSWorkspace.shared.frontmostApplication == NSRunningApplication.current else { return }
        guard let previous = previousFrontmostApp else {
            NSApp.deactivate()
            return
        }
        previous.activate(options: [])
        // 前のアプリがアクティブになってから（入力バーのキーが外れたあと）キーにし直す。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.inputPanelController?.focus()
        }
    }

    /// 終了時に入力欄のテキストを自動保存する（ステップ8。空ならファイルを消す）。
    /// 送信成功・Esc・閉じるアイコン・⌘W（入力バーの willClose → terminate）と ⌘Q のどれもここを通る。
    func applicationWillTerminate(_ notification: Notification) {
        if let text = inputPanelController?.textView.string {
            AutoSave.save(text)
        }
    }

    /// 「最後のウインドウを閉じたら終了」は使わない（ステップ7.1）。AppKit は NSPanel（入力バー）を
    /// 「残っているウインドウ」に数えないため、右クリックメニュー・変換候補・About パネル等が閉じただけで
    /// 終了してしまう（実験で確認 2026-10-31）。終了は入力バーの willClose で行う（applicationDidFinishLaunching）。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
