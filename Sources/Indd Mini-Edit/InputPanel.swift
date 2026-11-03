//
//  InputPanel.swift
//  Indd Mini-Edit
//
//  入力バー（唯一のウインドウ）。
//
//  送信時に最前面プロセスが InDesign であることを前提にしているため（HANDOFF §5・HANDOFF-Xojo §4.1）、
//  キー入力はパネルに入るがアプリはアクティブにならない **非アクティブ化パネル**（.nonactivatingPanel）にする
//  （ステップ2の試作で IME・キー等価・Space／フルスクリーンとも実機OK＝方式確定 2026-10-29）。
//
//  外観（ステップ3・旧版 Window1 を踏襲＝HANDOFF-Xojo §4）:
//   - 高さ 38・タイトル非表示・full-size content・信号機ボタン非表示。
//   - 左端 28pt はウインドウ地（ドラッグで移動できる）に閉じるアイコン。その右が入力欄。
//     入力欄はタイトルバー領域にも重なるが、クリックはテキストビューに届く（ヒットテストで実測 2026-10-29）。
//   - 配色: 入力欄はライト＝白地に黒字／ダーク＝黒地に白字。入力欄の左に 1pt の境界線（ライト #D0D0D0／ダーク黒）。
//   - 閉じるアイコンはキーウインドウのとき青（ダークは白）、キーでないとき灰。
//   - 位置・サイズは記憶する（frame autosave）。初回とリセットは画面下端に横いっぱい。画面外へははみ出させない。
//   - Esc でパネルを閉じる＝アプリ終了（ステップ2で追加・正式採用 2026-10-29）。
//
//  不可視文字（ステップ5）: InvisiblesLayoutManager（浮紙から移植）を使い、常に systemPink で表示する。
//
//  InDesign への送信（ステップ6）: 送信キー（SendKey・厳密判定）で InDesignController（FILL Id から移植・
//  pid 指定の do script）へ。成功したら閉じる＝終了。だめならメッセージ（MessagePopover）を出して閉じない。
//  送り先は最前面でない InDesign でもよい（ステップ7.4・InDesignController.resolveTarget）。
//
//  右クリックメニュー（ステップ7）: ContextMenu.swift（InputPanelController の extension）。
//  設定ボタン（ステップ8.1）: 閉じるアイコンの下の歯車。クリックで右クリックと同じメニュー（カット／コピー／ペーストを除く）。
//  左端の帯（入力欄より左）はどこをドラッグしてもウインドウが動く（ステップ8.1。高さを広げたときの下側も）。
//
//  入力欄（ステップ4・旧版 TextArea1＝HANDOFF-Xojo §11）:
//   - 自動置換類はすべてオフ。カーニング・リガチャもオフ（typingAttributes の .kern 0／.ligature 0）。
//   - 行の高さは「文字サイズ × 1.5」に固定（旧版 LineSpacing 1.5。浮紙と同じく layoutManager デリゲートで
//     全行に強制し、文字は行内の上下中央）。フォント固有の行間（usesFontLeading）は使わない。
//   - 1行目がバーの高さ 38 の縦中央に来るよう、上の余白を文字サイズから計算する。下の余白は 0
//     （複数行でスクロールしたとき、前の行の下半分が見えるようにする＝前の行があると分かる。ユーザー要望 2026-10-29）。
//

import AppKit

/// 非アクティブ化パネル。キーウインドウにはなるが、アプリをアクティブにしない。
final class InputPanel: NSPanel {

    /// 既定の高さ（旧版の Window1.Height / MinimumHeight と同じ）。
    static let defaultHeight: CGFloat = 38
    /// 入力欄の左端（旧版 TextArea1.Left＝28。左側は閉じるアイコンとドラッグ移動の場所）。
    static let textLeft: CGFloat = 28
    /// 画面の左端から空ける量（旧版 AdjustWindow の ScreenLimitLeft +2 / ScreenMaxWidth −2）。
    static let screenLeftMargin: CGFloat = 2
    /// 位置・サイズを記憶する frame autosave 名。UserDefaults のキーは "NSWindow Frame <名前>"。
    static let frameAutosaveName = "InputPanel"

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: Self.defaultHeight),
                   styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        // NSPanel の既定は「アプリが非アクティブになると隠れる」。このアプリは常に非アクティブなので必ず切る。
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 200, height: Self.defaultHeight)

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc で閉じる＝アプリ終了（旧版に無い操作。正式採用 2026-10-29）。
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// ⌘W（ファイル ▸ 閉じる）で閉じる＝アプリ終了。performClose は「閉じるボタンを押す」操作で、
    /// 閉じるボタン（.closable）の無いこのパネルでは AppKit が何もしない（実機 2026-10-31・ステップ7.2）。
    override func performClose(_ sender: Any?) {
        close()
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performClose(_:)) { return true }
        return super.validateMenuItem(menuItem)
    }

    // MARK: - 位置・サイズ

    /// 記憶した位置・サイズを復元する。記憶が無ければ（初回）リセット位置に置く。最後に画面内へ補正する。
    func restoreFrame() {
        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame \(Self.frameAutosaveName)") != nil
        // setFrameAutosaveName は保存済みの frame があればそれを適用し、以後の移動・リサイズを自動保存する。
        setFrameAutosaveName(Self.frameAutosaveName)
        if !hasSavedFrame {
            resetFrame()
        }
        adjustToScreen()
    }

    /// リセット: 画面（可視領域）の下端に横いっぱい・既定の高さで置く（旧版 Window1.Reset）。
    /// 旧版は初回の既定位置（Preferences.DefaultWindowSize）だけ左端の +2 が無かったが、ここで統一した。
    func resetFrame() {
        guard let visible = targetScreen?.visibleFrame else { return }
        let x = visible.minX + Self.screenLeftMargin
        setFrame(NSRect(x: x, y: visible.minY, width: visible.maxX - x, height: Self.defaultHeight),
                 display: true)
    }

    /// 画面（可視領域＝メニューバー・Dock を除く）からはみ出していれば、位置をずらし、
    /// 収まらなければ縮める（旧版 WindowEx.AdjustWindow 相当）。
    func adjustToScreen() {
        guard let visible = targetScreen?.visibleFrame else { return }
        var f = frame
        let minX = visible.minX + Self.screenLeftMargin
        f.size.width = min(max(f.width, minSize.width), visible.maxX - minX)
        f.size.height = min(max(f.height, minSize.height), visible.height)
        f.origin.x = min(max(f.minX, minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        if f != frame {
            setFrame(f, display: true)
        }
    }

    /// ウインドウのいる画面。どの画面にも重なっていなければメインの画面（旧版 GetWindowScreen は Screen(0)）。
    private var targetScreen: NSScreen? { screen ?? NSScreen.main ?? NSScreen.screens.first }
}

// MARK: - 配色

/// 入力バーの色（旧版 Window1.Paint の値。ライト／ダークで切り替わる動的色）。
enum InputBarColors {
    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
    /// 入力欄の地（ライト白／ダーク黒）。
    static let textBackground = dynamic(light: .white, dark: .black)
    /// 入力欄の文字（ライト黒／ダーク白）。
    static let text = dynamic(light: .black, dark: .white)
    /// 入力欄の左の境界線（ライト #D0D0D0／ダーク黒）。
    static let border = dynamic(light: NSColor(srgbRed: 0xD0 / 255, green: 0xD0 / 255, blue: 0xD0 / 255, alpha: 1),
                                dark: .black)
}

/// パネルの contentView。入力欄の地と、その左の境界線を描く。左端（textLeft より左）は描かず
/// ウインドウ地を見せる＝そこをドラッグするとウインドウが動く。
final class InputBarView: NSView {
    /// 左端の帯のクリックでウインドウを動かす。ウインドウ地のドラッグ移動はタイトルバー領域（上 28pt）しか効かず、
    /// 高さを広げると左側の下でつまめなかった（実機 2026-10-31・ステップ8.1）。入力欄・アイコンのクリックはここに来ない。
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let left = InputPanel.textLeft
        InputBarColors.textBackground.setFill()
        NSRect(x: left, y: 0, width: bounds.width - left, height: bounds.height).fill()
        InputBarColors.border.setFill()
        NSRect(x: left - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}

/// 入力欄。上だけに余白を取る NSTextView（textContainerInset は上下対称にしか効かないため）。
///
/// 複数行でキャレットの行までスクロールしたとき、下の余白があるとその分だけ前の行が隠れ、
/// 「前の行の下が少しだけ見える」状態になる。下の余白を 0 にして、前の行の下半分が見えるようにする
/// （前の行があると分かるように。ユーザー要望 2026-10-29）。
///
/// 仕組み: textContainerInset.height を「上の余白の半分」にして、テキストビューの高さ（使用領域＋上下の inset）を
/// 「使用領域＋上の余白」にし、textContainerOrigin を上の余白ぶん下げる＝上だけに余白、下は 0。
final class InputTextView: NSTextView {

    private var topInset: CGFloat = 0

    func setTopOnlyInset(_ inset: CGFloat) {
        topInset = inset
        textContainerInset = NSSize(width: 0, height: inset / 2)
        invalidateTextContainerOrigin()
    }

    override var textContainerOrigin: NSPoint {
        NSPoint(x: super.textContainerOrigin.x, y: topInset)
    }

    // MARK: 送信キー（ステップ6）

    /// InDesign へ送るキー（SendKey。厳密に判定）。
    var sendKey: SendKey = .default
    /// 送信キーが押されたときに呼ぶ。
    var onSend: (() -> Void)?

    /// 送信キーなら送る。IME の変換中（未確定の文字があるとき）の return は確定に使われるので送らない。
    /// ⌘return は performKeyEquivalent（メニュー）で該当項目が無いので、ここへ届く。
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), sendKey.matches(event), let onSend {
            onSend()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: 右クリックメニュー（ステップ7）

    /// 右クリックメニューを作る（InputPanelController.contextMenu。ContextMenu.swift）。
    var contextMenuProvider: (() -> NSMenu)?

    /// 標準のメニューの代わりに、自前のメニューを出す。
    override func menu(for event: NSEvent) -> NSMenu? {
        // ※ macOS は返したメニューの最下部に「自動入力」を足す。willOpenMenu で取り除いても消えなかった
        //   （実機 2026-10-31）ため、そのままにする（ユーザー了承）。
        contextMenuProvider?() ?? super.menu(for: event)
    }
}

/// 閉じるアイコン。クリックでパネルを閉じる＝アプリ終了（旧版 Canvas1.MouseDown）。
final class CloseIconView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.close()
    }
}

/// 設定ボタン（歯車）。クリックで右クリックと同じメニューをボタンの下に出す（ステップ8.1。ツールチップなし）。
/// 見た目は **SPAi のパネルの設定ボタンに揃える**（ステップ8.2・ユーザー指定 2026-10-31。SPAi ScriptPanelView.settingsButton）:
/// `.caption` の大きさ・文字色 75%（記号は 8.3 で gearshape → ellipsis、色は 8.5 で 90%・8.6 で 100%）。押している間（＝メニューを開いている間）だけ
/// 文字色 15% の角丸 3 の座布団を敷く（SPAi HeaderPressButtonStyle）。
///
/// ⚠️ NSImageView＋contentTintColor をやめて自前で描く（ステップ8.4）: NSImageView だと実機で記号が指定（75%）より
/// かなり薄く見えた（ui-snapshot では 75%＝差が出ない。InDesign を最前面にしたまま使う非アクティブ化パネルの状態で、
/// テンプレート画像が淡く描かれると見られる＝推測）。記号に色をじかに塗って描けば、ウインドウ／アプリの状態に左右されない。
final class SettingsButtonView: NSView {
    /// クリックされたときに呼ぶ（InputPanelController がメニューを出す）。
    var onClick: ((NSView) -> Void)?
    /// 「…」の四角1つの一辺と四角どうしの間隔（pt。整数 pt なので 1x・2x とも整数ピクセルになる）。
    /// ステップ8.7: SF Symbols の ellipsis（小さい丸3つ）はアンチエイリアスで崩れて見えたため、
    /// アンチエイリアスなしの四角3つを自前で塗る（ユーザー指定 2026-11-01）。
    private static let dotSize: CGFloat = 2
    private static let dotGap: CGFloat = 2
    /// 記号の色（文字色 100%。SPAi は 75% だが、「…」は点が小さく実機で薄く見えたため濃くした
    /// ＝ステップ8.5で 90%・8.6で 100%・ユーザー指定 2026-10-31）。
    /// ⚠️ 描くたびに作る（ステップ8.7）: labelColor.withAlphaComponent は**呼んだ時点の外観で色が固定される**
    /// （ライトで作るとダークでも黒のまま。単体ランナーで実測）。draw の中なら現在の外観で解決される。
    private var symbolColor: NSColor { NSColor.labelColor.withAlphaComponent(1) }
    private var isPressed = false {
        didSet { needsDisplay = true }
    }
    // ライト／ダークの切替で描き直す（色は draw の中で解決するため）。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        displayIfNeeded()
        onClick?(self)   // メニューは閉じるまで戻らない（popUp は同期）
        isPressed = false
    }
    override func draw(_ dirtyRect: NSRect) {
        if isPressed {
            NSColor.labelColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // 四角3つをフレームの中央に。各辺をピクセル境界に揃え、アンチエイリアスを切って塗る（縁がにじまない）。
        let size = Self.dotSize, gap = Self.dotGap
        let totalWidth = size * 3 + gap * 2
        let originX = ((bounds.width - totalWidth) / 2).rounded(.down)
        let originY = ((bounds.height - size) / 2).rounded(.down)
        context.saveGState()
        context.setShouldAntialias(false)
        symbolColor.setFill()
        for i in 0..<3 {
            let rect = NSRect(x: originX + CGFloat(i) * (size + gap), y: originY, width: size, height: size)
            backingAlignedRect(rect, options: .alignAllEdgesNearest).fill()
        }
        context.restoreGState()
    }

    // VoiceOver では「設定」ボタンとして読む（ツールチップは出さない）。
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool {
        onClick?(self)
        return true
    }
}

// MARK: - コントローラ

/// 入力バーの中身を組み立てて表示する。
@MainActor
final class InputPanelController: NSObject, NSLayoutManagerDelegate {

    let panel = InputPanel()
    private(set) var textView: NSTextView!
    /// textView を InputTextView として扱う（送信キー・右クリックメニュー）。
    var inputTextView: InputTextView { textView as! InputTextView }
    private let closeIcon = CloseIconView()
    private let settingsButton = SettingsButtonView()

    /// InDesign 連携（pid 指定の do script。FILL Id から移植）と、メッセージのポップオーバー（ステップ6）。
    let indesign = InDesignController()
    private let messagePopover = MessagePopover()

    /// 既定のフォント（PostScript 名）とサイズ（旧版 Preferences の既定値）。
    static let defaultFontName = "HiraginoSans-W3"
    static let defaultFontSize: CGFloat = 16
    /// 行の高さの倍率（旧版 TextArea1.LineSpacing = 1.5）。
    private static let lineHeightFactor: CGFloat = 1.5

    /// 現在のフォント（PostScript 名）とサイズ（applyFont で更新。右クリックのチェック・環境設定の保存に使う）。
    private(set) var currentFontName = defaultFontName
    private(set) var currentFontSize = defaultFontSize

    /// 全行に強制する行の高さと、行フラグメント上端からベースラインまでの距離（applyFont で計算）。
    private var lineHeight: CGFloat = 0
    private var baselineOffset: CGFloat = 0

    /// 閉じるアイコンの画像（Assets。旧版 IconSetting／IconSettingDarkMode／IconSettingBack の PDF）。
    private static let activeIcon = NSImage(named: "CloseIcon")          // キー時（ダークは白の版）
    private static let inactiveIcon = NSImage(named: "CloseIconInactive") // 非キー時

    override init() {
        super.init()
        buildContent()
        observeKeyState()
        observeScreenChanges()
    }

    private func buildContent() {
        let contentView = InputBarView(frame: NSRect(x: 0, y: 0, width: 600, height: InputPanel.defaultHeight))
        panel.contentView = contentView

        // 閉じるアイコン: 旧版 Canvas1（Left 10・Top 2・15×20。20×20 の画像の左 15pt を表示）。上端・左端に固定。
        let iconHeight: CGFloat = 20
        closeIcon.frame = NSRect(x: 10, y: contentView.bounds.height - 2 - iconHeight, width: 15, height: iconHeight)
        closeIcon.autoresizingMask = [.minYMargin]
        closeIcon.imageScaling = .scaleNone
        closeIcon.imageAlignment = .alignTopLeft
        closeIcon.image = Self.inactiveIcon
        contentView.addSubview(closeIcon)

        // 設定ボタン: 閉じるアイコンの下（上端に固定＝高さを広げても閉じるアイコンの下から動かない）。
        // 記号は「…」（ステップ8.3・ユーザー指定 2026-10-31。8.2 までは SPAi と同じ gearshape）。
        // 8.7 から SF Symbols ではなく SettingsButtonView が四角3つを自前で描く。記号はフレームの中央に置く。
        // フレーム（＝押下の座布団・クリック範囲）は歯車のときと同じ 20×14pt に固定（記号から決めると高さ 5pt しかない）。
        // 左右は SPAi の 4pt より狭い＝入力欄の左の境界線 x 27 にかからない幅。
        // 位置: 中心 x 17（閉じるアイコンの中心線）・高さ 38 で中心 y 10（ステップ8.1の中心 y 9 から上へ 1pt＝ユーザー指定）。
        settingsButton.setAccessibilityLabel(String(localized: "Settings"))
        let gearFrameSize = NSSize(width: 20, height: 14)
        settingsButton.frame = NSRect(x: 17 - gearFrameSize.width / 2,
                                      y: closeIcon.frame.minY - 6 - gearFrameSize.height / 2,
                                      width: gearFrameSize.width, height: gearFrameSize.height)
        settingsButton.autoresizingMask = [.minYMargin]
        settingsButton.onClick = { [weak self] view in self?.showSettingsMenu(from: view) }
        contentView.addSubview(settingsButton)

        // TextKit 1 のスタックを明示的に組み立てる（浮紙 UkigamiTextView と同じ。NSLayoutManager を
        // 自前で持つと TextKit 1 になり、不可視文字描画の NSLayoutManager サブクラスを差し込める）。
        let textStorage = NSTextStorage()
        // 不可視文字を重ね描きする NSLayoutManager（ステップ5・浮紙から移植。色は旧版の systemPink）。
        let layoutManager = InvisiblesLayoutManager()
        // フォントの LineGap（leading）を使わない（旧版 usesFontLeading = False）。行の高さは下のデリゲートで固定する。
        layoutManager.usesFontLeading = false
        layoutManager.delegate = self
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let left = InputPanel.textLeft
        let scrollFrame = NSRect(x: left, y: 0,
                                 width: contentView.bounds.width - left,
                                 height: contentView.bounds.height)
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        // full-size content のパネルでは、NSScrollView がタイトルバーの高さ（28pt）を上の
        // contentInsets に自動で入れ、高さ 38 の中で本文が下へ押し出されて切れる（ui-snapshot で実測）。
        // 入力欄はタイトルバー領域にも重ねて使う（旧版 TextArea1.Top=-30 と同じ考え方）ので自動調整を切る。
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let textView = InputTextView(frame: NSRect(origin: .zero, size: scrollFrame.size),
                                     textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.drawsBackground = true
        textView.backgroundColor = InputBarColors.textBackground

        // DTP 用途では「賢い」自動変換は邪魔なので無効化する（旧版 TextArea1.Opening・浮紙と同じ）。
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        scrollView.documentView = textView
        contentView.addSubview(scrollView)
        self.textView = textView
        textView.onSend = { [weak self] in self?.send() }
        textView.contextMenuProvider = { [weak self] in self?.contextMenu() ?? NSMenu() }
        // 環境設定（ステップ8）からフォント・サイズ・入力キーを復元する。
        textView.sendKey = Settings.sendKey
        applyFont(name: Settings.fontName, size: Settings.fontSize)
    }

    // MARK: - フォント・行の高さ

    /// PostScript 名からフォントを得る。無ければヒラギノ角ゴ ProN W3、それも無ければシステムフォント
    /// （旧版 NSFont.getNSFont と同じフォールバック）。
    static func font(named name: String, size: CGFloat) -> NSFont {
        NSFont(name: name, size: size)
            ?? NSFont(name: "HiraKakuProN-W3", size: size)
            ?? .systemFont(ofSize: size)
    }

    /// 入力欄のフォント・サイズを設定し、行の高さ・余白・入力属性を作り直す。
    /// 右クリック「文字サイズ」「フォント」（ステップ7）と環境設定の復元（ステップ8）からも呼ぶ。
    func applyFont(name: String, size: CGFloat) {
        let font = Self.font(named: name, size: size)
        currentFontName = name
        currentFontSize = size

        // 行の高さ＝文字サイズ × 1.5（固定）。文字は行内の上下中央に置く（浮紙 UkigamiTextView と同じ計算）。
        lineHeight = (size * Self.lineHeightFactor).rounded()
        baselineOffset = ((lineHeight - (font.ascender - font.descender)) / 2 + font.ascender).rounded()

        let style = NSMutableParagraphStyle()
        // 段落スタイルでも行の高さを固定する。改行直後の空の最終行は「余剰行フラグメント」で、
        // 下のデリゲート（shouldSetLineFragmentRect）が呼ばれず、フォント本来の高さ（16pt で 16）になる。
        // すると文字を入力して普通の行（24）になった瞬間に全体が 8pt 上へずれる（実測 2026-10-29）。
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        textView.defaultParagraphStyle = style
        textView.font = font
        // リガチャ・カーニングは無効化する（旧版 turnOffKerning／turnOffLigatures）。
        // カーニングは日本語では palt 前提なのに、NSTextView は palt 未適用でも効かせてしまうため明示的に 0。
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: InputBarColors.text,
            .paragraphStyle: style,
            .ligature: 0,
            .kern: 0,
        ]
        textView.typingAttributes = attributes
        if let storage = textView.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }

        // 1行目をバーの高さ 38 の縦中央に（文字サイズ 24 でも行の高さ 36 なので収まる）。余白は上だけ（InputTextView）。
        let inset = max(0, ((InputPanel.defaultHeight - lineHeight) / 2).rounded(.down))
        (textView as? InputTextView)?.setTopOnlyInset(inset)
        // 不可視文字の代替グリフも本文と同じサイズに（旧版の文字サイズ変更時と同じ）。
        (textView.layoutManager as? InvisiblesLayoutManager)?.invisiblesFontSize = size
        textView.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
                                                 actualCharacterRange: nil)
    }

    /// 各行の高さを固定値に強制する（フォント非依存の行送り。浮紙 UkigamiTextView.Coordinator と同じ）。
    nonisolated func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        MainActor.assumeIsolated {   // レイアウトは常にメインスレッド
            guard lineHeight > 0 else { return false }
            lineFragmentRect.pointee.size.height = lineHeight
            lineFragmentUsedRect.pointee.size.height = lineHeight
            baselineOffset.pointee = self.baselineOffset
            return true
        }
    }

    /// キーウインドウかどうかで閉じるアイコンを切り替える（旧版 Activated／Deactivated → Paint）。
    private func observeKeyState() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyStateDidChange(_:)),
                           name: NSWindow.didBecomeKeyNotification, object: panel)
        center.addObserver(self, selector: #selector(keyStateDidChange(_:)),
                           name: NSWindow.didResignKeyNotification, object: panel)
    }

    @objc private func keyStateDidChange(_ note: Notification) {
        closeIcon.image = panel.isKeyWindow ? Self.activeIcon : Self.inactiveIcon
    }

    /// 画面構成（解像度・接続・Dock の位置など）が変わったら画面内へ補正する（旧版 WindowAdjustPosition）。
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    @objc private func screenParametersDidChange(_ note: Notification) {
        panel.adjustToScreen()
    }

    // MARK: - InDesign への送信（ステップ6・旧版 Window1.Run＝HANDOFF-Xojo §6.2）

    /// 入力欄のテキストを最前面の InDesign の選択範囲へ流し込む。成功したらパネルを閉じる＝アプリ終了。
    /// チェックに引っかかったらメッセージを出して閉じない。
    private func send() {
        let text = textView.string
        // 空なら何もしないで閉じる（旧版は Close() のあと Return が無く後続へ進むバグがあった＝直した）。
        if text.isEmpty {
            panel.close()
            return
        }
        // 応答待ちの間の送信キーは無視する（滞留したイベントが後から InDesign でまとめて実行される事故の防止）。
        guard !indesign.isBusy else { return }

        guard indesign.runningCount > 0 else {
            showMessage(String(localized: "No InDesign is running."))
            return
        }
        // 送り先: 最前面の InDesign → 最後にアクティブになった InDesign（初期値は起動元）→ 画面上でいちばん手前の InDesign → 1つだけ起動している InDesign（ステップ7.4〜7.6）。
        guard let target = indesign.resolveTarget() else {
            showMessage(String(localized: "Bring InDesign to the front."))
            return
        }
        // 最前面でない InDesign に送るときは、送れたあと InDesign を最前面にする。
        let bringToFront = NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid

        // 合成除外文字を守った NFC → 改行を CR（InDesign の段落区切り）に統一。
        let prepared = TextNormalizer.unifyToCR(TextNormalizer.nfcSafe(text))
        indesign.setText(prepared, target: target, bringToFront: bringToFront) { [weak self] result in
            guard let self else { return }
            switch result {
            case .ok:
                self.panel.close()
            case .noDocument:
                self.showMessage(String(localized: "There is no InDesign document."))
            case .noSelection:
                self.showMessage(String(localized: "No text is selected in the document."))
            case .minimized:
                self.showMessage(String(localized: "The document window is minimized in the Dock."))
            case .notPermitted:
                self.showMessage(String(localized: "Allow Indd Mini-Edit to control InDesign in System Settings > Privacy & Security > Automation."))
            case .failed:
                self.showMessage(String(localized: "Couldn't send the text to InDesign."))
            }
        }
    }

    /// 入力欄の上辺にメッセージを出す（既定は赤字。黒字は「自動保存は空です」＝ContextMenu.swift）。
    func showMessage(_ message: String, isRed: Bool = true) {
        guard let anchor = textView.enclosingScrollView else { return }
        messagePopover.show(message, relativeTo: anchor, isRed: isRed)
    }

    /// 記憶した位置（初回は画面下端）に出してキーにし、入力欄にフォーカスする。
    func show() {
        panel.restoreFrame()
        focus()
    }

    /// 入力バーをキーにし、入力欄にフォーカスする（起動直後に自分を非アクティブにしたあとにも呼ぶ＝AppDelegate）。
    func focus() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }
}
