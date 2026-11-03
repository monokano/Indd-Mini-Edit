//
//  SendKey.swift
//  Indd Mini-Edit
//
//  InDesign へ送るキー（旧版 pModifiers＝HANDOFF-Xojo §6.1）。
//  **厳密に判定する**（ユーザー決定 2026-10-29）: 設定した修飾キーの組み合わせ「だけ」が押されているときに送る
//  （例＝⌥return 設定で ⌥⇧return は送らない）。旧版は「その修飾キーが押されているか」だけを見ていた。
//  選択は右クリック「入力キー」（ステップ7）、保存は環境設定（ステップ8）。それまでは既定の ⌥return。
//  旧版の ⌥⌘return は macOS のホットキーとぶつかるため廃止（ユーザー指示 2026-10-31・ステップ7.2）。
//

import AppKit

enum SendKey: String, CaseIterable {
    case optionReturn = "opt"                // ⌥ + return（旧版の既定）
    case commandReturn = "cmd"               // ⌘ + return
    case returnOnly = "return"               // return 単独（このとき改行は入力できない）

    /// 既定（旧版 Preferences の既定値 "opt"）。rawValue は旧版の Modifiers の値と同じにしてある。
    static let `default`: SendKey = .optionReturn

    /// 判定に使う修飾キーの組み合わせ（CapsLock・fn 等は判定に含めない）。
    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .optionReturn: return [.option]
        case .commandReturn: return [.command]
        case .returnOnly: return []
        }
    }

    /// 判定の対象にする修飾キー。これ以外（CapsLock・fn・テンキー等のフラグ）は無視する。
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// return キー（テンキーの enter は含めない＝旧版も Asc 13 の return だけ）。
    static let returnKeyCode: UInt16 = 36

    /// このキーイベントが送信キーか。
    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == Self.returnKeyCode
            && event.modifierFlags.intersection(Self.relevantModifiers) == modifiers
    }
}
