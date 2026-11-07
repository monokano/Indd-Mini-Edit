//
//  ContextMenu.swift
//  Indd Mini-Edit
//
//  入力欄の右クリックメニュー（ステップ7・旧版 TextArea1.ConstructContextualMenu＝HANDOFF-Xojo §8.2）。
//  文言はユーザー承認済み（2026-10-31。一覧＝HANDOFF §5「UI 文字列」）。
//
//  方針:
//   - NSTextView の標準メニュー（スペル・自動置換・フォントパネル・読み上げ等）は使わず、毎回作り直す。
//     標準のままだと、オフにした自動置換を利用者が入れ直せてしまうため。標準からはカット／コピー／ペーストだけ残す。
//   - 「古い方法を使う」は廃止（HANDOFF §6 決定済み）。
//   - 文字サイズ・フォント・入力キーは選んだ時点で環境設定（Settings。ステップ8）に保存する。
//   - 「自動保存を読み込む」は保存ファイル（AutoSave。ステップ8）があるときだけ有効。
//

import AppKit

/// 右クリックメニューで選べるフォント（旧版の4書体。tag 0〜3 の順）。
struct MenuFont {
    let postScriptName: String
    let title: String

    static let all: [MenuFont] = [
        MenuFont(postScriptName: "HiraginoSans-W3", title: String(localized: "Hiragino Sans W3")),
        MenuFont(postScriptName: "HiraMinProN-W3", title: String(localized: "Hiragino Mincho ProN W3")),
        MenuFont(postScriptName: "YuGo-Medium", title: String(localized: "Yu Gothic Medium")),
        MenuFont(postScriptName: "YuMin-Medium", title: String(localized: "Yu Mincho Medium")),
    ]
}

extension SendKey {
    /// 右クリック「入力キー」の表記（記号表記・訳さない）。
    var menuTitle: String {
        switch self {
        case .optionReturn: return "⌥ + return"
        case .commandReturn: return "⌘ + return"
        case .returnOnly: return "return"
        }
    }

    /// メニューでの並び（旧版と同じ順。⌥⌘ + return は廃止＝ステップ7.2）。
    static let menuOrder: [SendKey] = [.optionReturn, .commandReturn, .returnOnly]
}

/// 英数字の全角／半角変換（旧版 RepAll2Zen／RepAll2Han＝HANDOFF-Xojo §8.3）。
/// 対象は 0-9・a-z・A-Z の 62 文字だけ（記号・スペース・カナは変えない）。UTF-16 の長さは変わらない。
nonisolated enum AlphanumericWidth {
    /// 全角英数字と半角英数字のコードポイントの差（U+FF10 − U+0030）。
    private static let offset: UInt32 = 0xFEE0

    private static func isHalfAlphanumeric(_ v: UInt32) -> Bool {
        (0x30...0x39).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
    }

    static func toFullWidth(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { scalar in
            isHalfAlphanumeric(scalar.value) ? Unicode.Scalar(scalar.value + offset)! : scalar
        }))
    }

    static func toHalfWidth(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { scalar in
            scalar.value >= offset && isHalfAlphanumeric(scalar.value - offset)
                ? Unicode.Scalar(scalar.value - offset)! : scalar
        }))
    }
}

extension InputPanelController: NSMenuItemValidation {

    /// 右クリックメニューを作る（開くたびに作り直す＝チェックは現在値）。InputTextView.menu(for:) から呼ぶ。
    /// 設定ボタン（ステップ8.1）からは `includesTextEditing: false`＝カット／コピー／ペーストを除く。
    func contextMenu(includesTextEditing: Bool = true) -> NSMenu {
        let menu = NSMenu()

        // 標準のテキスト操作（target 指定なし＝入力欄へ届き、有効・無効も NSTextView 任せ）。
        if includesTextEditing {
            menu.addItem(NSMenuItem(title: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: ""))
            menu.addItem(.separator())
        }

        menu.addItem(item(String(localized: "About Indd Mini-Edit"), #selector(showAbout(_:))))
        menu.addItem(item(String(localized: "Help"), #selector(showHelp(_:))))
        menu.addItem(.separator())

        // 文字サイズ ▸
        let sizeMenu = NSMenu()
        for size in Self.menuFontSizes {
            let sizeItem = item("\(size)", #selector(selectFontSize(_:)), tag: size)
            sizeItem.state = Int(currentFontSize) == size ? .on : .off
            sizeMenu.addItem(sizeItem)
        }
        menu.addItem(submenuItem(String(localized: "Text Size"), sizeMenu))

        // フォント ▸
        let fontMenu = NSMenu()
        for (index, font) in MenuFont.all.enumerated() {
            let fontItem = item(font.title, #selector(selectFont(_:)), tag: index)
            fontItem.state = currentFontName == font.postScriptName ? .on : .off
            fontMenu.addItem(fontItem)
        }
        menu.addItem(submenuItem(String(localized: "Font"), fontMenu))

        // 入力キー ▸
        let keyMenu = NSMenu()
        for (index, key) in SendKey.menuOrder.enumerated() {
            let keyItem = item(key.menuTitle, #selector(selectSendKey(_:)), tag: index)
            keyItem.state = inputTextView.sendKey == key ? .on : .off
            keyMenu.addItem(keyItem)
        }
        // 改行を入力しない（2026-11-07 追加）。入力キーが return 単独のときは常に改行できないので、
        // チェックを付けてグレーアウトする（validateMenuItem）。
        keyMenu.addItem(.separator())
        let lineBreakItem = item(String(localized: "Disallow Line Breaks"), #selector(toggleDisallowLineBreaks(_:)))
        lineBreakItem.state = inputTextView.blocksLineBreaks ? .on : .off
        keyMenu.addItem(lineBreakItem)
        menu.addItem(submenuItem(String(localized: "Send Key"), keyMenu))

        // 位置 ▸
        let positionMenu = NSMenu()
        positionMenu.addItem(item(String(localized: "Adjust Position"), #selector(adjustPosition(_:))))
        positionMenu.addItem(item(String(localized: "Reset Position"), #selector(resetPosition(_:))))
        menu.addItem(submenuItem(String(localized: "Position"), positionMenu))
        menu.addItem(.separator())

        menu.addItem(item(String(localized: "Load Auto-Saved Text"), #selector(loadAutoSavedText(_:))))
        menu.addItem(.separator())

        menu.addItem(item(String(localized: "Convert Alphanumerics to Full-Width"), #selector(convertToFullWidth(_:))))
        menu.addItem(item(String(localized: "Convert Alphanumerics to Half-Width"), #selector(convertToHalfWidth(_:))))
        return menu
    }

    /// 設定ボタンの下にメニューを出す（ステップ8.1）。画面の下端では AppKit が上向きに出す。
    func showSettingsMenu(from view: NSView) {
        contextMenu(includesTextEditing: false).popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: view)
    }

    /// 文字サイズの選択肢（旧版と同じ）。
    static let menuFontSizes = [14, 16, 18, 20, 22, 24]

    private func item(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectFont(_:)):
            // 入っていない書体は選べない（選ぶとフォールバックの書体になってしまうため）。
            return NSFont(name: MenuFont.all[menuItem.tag].postScriptName, size: 12) != nil
        case #selector(loadAutoSavedText(_:)):
            return AutoSave.exists
        case #selector(toggleDisallowLineBreaks(_:)):
            return inputTextView.sendKey != .returnOnly
        case #selector(convertToFullWidth(_:)), #selector(convertToHalfWidth(_:)):
            return textView.selectedRanges.contains { $0.rangeValue.length > 0 }
        default:
            return true
        }
    }

    // MARK: - 動作

    /// 標準の About パネル。アプリは常に非アクティブなので、前面に出すためにアクティブにする
    /// （旧版も 200ms 後に自アプリを前面化していた）。
    @objc private func showAbout(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// ヘルプウインドウ（HelpWindowController）。About と同じく自アプリをアクティブにして前面に出す。
    @objc private func showHelp(_ sender: NSMenuItem) {
        HelpWindowController.shared.show()
    }

    @objc private func selectFontSize(_ sender: NSMenuItem) {
        applyFont(name: currentFontName, size: CGFloat(sender.tag))
        Settings.fontSize = currentFontSize
    }

    @objc private func selectFont(_ sender: NSMenuItem) {
        applyFont(name: MenuFont.all[sender.tag].postScriptName, size: currentFontSize)
        Settings.fontName = currentFontName
    }

    @objc private func selectSendKey(_ sender: NSMenuItem) {
        inputTextView.sendKey = SendKey.menuOrder[sender.tag]
        Settings.sendKey = inputTextView.sendKey
    }

    @objc private func toggleDisallowLineBreaks(_ sender: NSMenuItem) {
        inputTextView.disallowLineBreaks.toggle()
        Settings.disallowLineBreaks = inputTextView.disallowLineBreaks
    }

    @objc private func adjustPosition(_ sender: NSMenuItem) {
        panel.adjustToScreen()
    }

    @objc private func resetPosition(_ sender: NSMenuItem) {
        panel.resetFrame()
    }

    /// 自動保存を読み込む（旧版 §9）。全文を置き換え、1回の取り消しで戻せる。キャレットは末尾。
    /// 中身が空なら「自動保存は空です」（黒字）。
    @objc private func loadAutoSavedText(_ sender: NSMenuItem) {
        guard let text = AutoSave.load(), let storage = textView.textStorage else { return }
        if text.isEmpty {
            showMessage(String(localized: "The auto-saved text is empty."), isRed: false)
            return
        }
        let all = NSRange(location: 0, length: storage.length)
        guard textView.shouldChangeText(in: all, replacementString: text) else { return }
        textView.breakUndoCoalescing()
        // 入力欄が空のとき String で置き換えると属性が付かないので、入力属性（フォント・行の高さ等）付きで入れる。
        storage.replaceCharacters(in: all, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    @objc private func convertToFullWidth(_ sender: NSMenuItem) {
        convertSelection(AlphanumericWidth.toFullWidth)
    }

    @objc private func convertToHalfWidth(_ sender: NSMenuItem) {
        convertSelection(AlphanumericWidth.toHalfWidth)
    }

    /// 選択範囲（複数可）の文字列を変換して置き換える。1回の取り消しで戻せる。置換後も同じ範囲を選択したままにする
    /// （長さが変わらないため。旧版は insertText でキャレットが末尾に移っていた）。
    private func convertSelection(_ convert: (String) -> String) {
        let ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty, let storage = textView.textStorage else { return }
        let replacements = ranges.map { convert((storage.string as NSString).substring(with: $0)) }
        guard textView.shouldChangeText(inRanges: ranges as [NSValue], replacementStrings: replacements) else { return }
        textView.breakUndoCoalescing()
        storage.beginEditing()
        // 後ろから置き換える（長さは変わらないが、念のため前の範囲をずらさない順にする）。
        for (range, replacement) in zip(ranges, replacements).reversed() {
            storage.replaceCharacters(in: range, with: replacement)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.selectedRanges = ranges as [NSValue]
    }
}
