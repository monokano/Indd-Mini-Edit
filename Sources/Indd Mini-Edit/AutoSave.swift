//
//  AutoSave.swift
//  Indd Mini-Edit
//
//  自動保存（ステップ8・旧版 AutoSave＝HANDOFF-Xojo §9）。
//   - 保存先: ~/Library/Application Support/monokano/Indd Mini-Edit2/AutoSave.txt（UTF-8。ユーザー指定 2026-10-31）。
//     旧版は ~/Library/Caches/com.tama-san.InddMiniEditor/AutoSave.txt（引き継がない＝HANDOFF §6）。
//     Caches は macOS が消すことがあり、復旧用には向かないため Application Support にした。
//   - 保存: アプリの終了時（AppDelegate.applicationWillTerminate）。送信成功・Esc・閉じるアイコン・⌘W・⌘Q のどれでも。
//     テキストが空ならファイルを削除する（旧版と同じ）。
//   - 読込: 右クリック「自動保存を読み込む」（ContextMenu.swift）。
//

import Foundation

enum AutoSave {

    static let fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("monokano", isDirectory: true)
        .appendingPathComponent("Indd Mini-Edit2", isDirectory: true)
        .appendingPathComponent("AutoSave.txt", isDirectory: false)

    /// 保存ファイルがあるか（右クリック「自動保存を読み込む」の有効・無効）。
    static var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// テキストを書き出す。空ならファイルを削除する。失敗しても何もしない（終了処理を止めない）。
    static func save(_ text: String) {
        let manager = FileManager.default
        if text.isEmpty {
            try? manager.removeItem(at: fileURL)
            return
        }
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// 保存したテキストを読む。ファイルが無い・読めなければ nil。
    static func load() -> String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }
}
