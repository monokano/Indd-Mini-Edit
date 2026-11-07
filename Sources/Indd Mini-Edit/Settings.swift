//
//  Settings.swift
//  Indd Mini-Edit
//
//  環境設定（ステップ8・旧版 Preferences＝HANDOFF-Xojo §7）。UserDefaults に保存し、キーはここで一元管理する。
//   - 既定値は起動時に registerDefaults()（AppDelegate.applicationWillFinishLaunching）。
//   - 右クリックで選んだ時点で保存する（旧版は閉じるときに保存していた）。
//   - ウインドウの位置・サイズは InputPanel の frame autosave（"NSWindow Frame InputPanel"）が保存する。
//   - 旧版の「古い方法を使う」（IsUseOldMethod）は廃止。⌥⌘ を押しながら起動して初期化する機能も入れない
//     （起動キーが ⌥ + return のため。ユーザー承認 2026-10-31）。
//

import AppKit

enum Settings {

    enum Key {
        static let fontName = "FontName"   // フォント（PostScript 名）
        static let fontSize = "FontSize"   // 文字サイズ
        static let sendKey = "SendKey"     // 入力キー（SendKey.rawValue＝旧版 Modifiers と同じ値）
        static let disallowLineBreaks = "DisallowLineBreaks"  // 改行を入力しない（2026-11-07 追加）
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.fontName: InputPanelController.defaultFontName,
            Key.fontSize: Double(InputPanelController.defaultFontSize),
            Key.sendKey: SendKey.default.rawValue,
            Key.disallowLineBreaks: true,   // 既定は ON（ユーザー指定 2026-11-07）
        ])
    }

    static var fontName: String {
        get { UserDefaults.standard.string(forKey: Key.fontName) ?? InputPanelController.defaultFontName }
        set { UserDefaults.standard.set(newValue, forKey: Key.fontName) }
    }

    static var fontSize: CGFloat {
        get {
            let size = UserDefaults.standard.double(forKey: Key.fontSize)
            return size > 0 ? CGFloat(size) : InputPanelController.defaultFontSize
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: Key.fontSize) }
    }

    /// 知らない値（廃止した "opt+cmd" 等）なら既定の ⌥ + return。
    static var sendKey: SendKey {
        get { UserDefaults.standard.string(forKey: Key.sendKey).flatMap(SendKey.init(rawValue:)) ?? .default }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.sendKey) }
    }

    /// 改行を入力しない（キー操作の改行だけ止める。ペースト・自動保存の読み込みは止めない）。
    static var disallowLineBreaks: Bool {
        get { UserDefaults.standard.bool(forKey: Key.disallowLineBreaks) }
        set { UserDefaults.standard.set(newValue, forKey: Key.disallowLineBreaks) }
    }
}
