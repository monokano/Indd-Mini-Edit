//
//  MessagePopover.swift
//  Indd Mini-Edit
//
//  入力バーの上に出すメッセージのポップオーバー（旧版 MyPopover.Show＝HANDOFF-Xojo §10.1）。
//   - NSPopover（transient・アニメーションあり）。中身は選択可・編集不可のラベル（背景・枠なし・中央揃え）。
//   - 文字色は既定で赤（警告）。赤でないときはライト＝黒／ダーク＝白（ラベルの標準色）。システムフォント 16pt。
//   - 入力欄の上辺に、左端寄せで出す（旧版は対象矩形の幅をポップオーバーの幅に縮めて左に寄せていた）。
//   - 表示中にもう一度出すと、閉じてから出し直す。
//  旧版は文末の「。」の有無で右余白を変えていたが、Swift 版は文字列の実寸から大きさを決めるので不要
//  （メッセージの文末の「。」もユーザー指示で全廃 2026-10-29）。
//

import AppKit

@MainActor
final class MessagePopover {

    private var popover: NSPopover?

    /// 上下左右の余白（旧版: テキストの原点 (24, 14)・ビューは文字列＋右 48／上下 28 だった。左右を揃えて 24）。
    private static let horizontalPadding: CGFloat = 24
    private static let verticalPadding: CGFloat = 14

    /// メッセージを出す。`view` の上辺に、左端へ寄せて表示する。
    /// `view` は flipped でない（上辺＝maxY）ビューを渡すこと（入力欄の NSScrollView）。
    func show(_ message: String, relativeTo view: NSView, isRed: Bool = true, fontSize: CGFloat = 16) {
        close()

        let label = NSTextField(labelWithString: message)
        label.isSelectable = true
        label.alignment = .center
        label.font = .systemFont(ofSize: fontSize)
        label.textColor = isRed ? .systemRed : .labelColor
        label.sizeToFit()

        let size = NSSize(width: ceil(label.frame.width) + Self.horizontalPadding * 2,
                          height: ceil(label.frame.height) + Self.verticalPadding * 2)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        label.frame.origin = NSPoint(x: Self.horizontalPadding, y: Self.verticalPadding)
        content.addSubview(label)

        let controller = NSViewController()
        controller.view = content

        let popover = NSPopover()
        popover.animates = true
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = size

        // ポップオーバーの表示位置を左端に寄せる（対象矩形の幅をポップオーバーの幅に縮める＝旧版と同じ）。
        var anchor = view.bounds
        anchor.size.width = min(anchor.width, size.width)
        popover.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
        self.popover = popover
    }

    /// 表示中なら閉じる。
    func close() {
        popover?.performClose(nil)
        popover = nil
    }
}
