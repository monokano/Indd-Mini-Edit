//
//  MainMenu.swift
//  Indd Mini-Edit
//
//  メインメニューのプログラム構築（xib 不使用）。AppDelegate.applicationWillFinishLaunching から
//  MainMenuBuilder.install() を呼ぶ。
//
//  方針:
//   - LSUIElement のためメニューバーには表示されない。⌘C／⌘Z 等のキーボードショートカットを
//     入力欄（NSTextView）に効かせるためだけに置く（旧版 MainMenuBar と同じ役割）。
//   - 標準コマンドは target = nil（レスポンダチェーン）で NSApplication／NSWindow／NSTextView に届く。
//     有効・無効の判定も AppKit 任せ。
//   - 旧版にあった「検索」は入れない（高さ 38pt の入力バーに検索バーを出す場所がない。ユーザー承認 2026-10-29）。
//

import AppKit

@MainActor
enum MainMenuBuilder {

    static func install() {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        NSApp.mainMenu = mainMenu
    }

    // MARK: - 部品

    /// サブメニュー付きのバー項目を作る。
    private static func barItem(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// メニュー項目を作る（target 指定なし＝レスポンダチェーン）。
    private static func item(
        _ title: String,
        action: Selector?,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }

    // MARK: - 各メニュー

    private static func appMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(item(String(localized: "About Indd Mini-Edit"),
                          action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Indd Mini-Edit"),
                          action: #selector(NSApplication.terminate(_:)), key: "q"))
        return barItem("Indd Mini-Edit", menu)
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "File"))
        menu.addItem(item(String(localized: "Close"),
                          action: #selector(NSWindow.performClose(_:)), key: "w"))
        return barItem(String(localized: "File"), menu)
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(item(String(localized: "Undo"), action: Selector(("undo:")), key: "z"))
        menu.addItem(item(String(localized: "Redo"), action: Selector(("redo:")),
                          key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Cut"), action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item(String(localized: "Copy"), action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item(String(localized: "Paste"), action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item(String(localized: "Delete"), action: #selector(NSText.delete(_:))))
        menu.addItem(item(String(localized: "Select All"),
                          action: #selector(NSText.selectAll(_:)), key: "a"))
        return barItem(String(localized: "Edit"), menu)
    }
}
