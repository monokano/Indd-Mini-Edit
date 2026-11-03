//
//  main.swift
//  Indd Mini-Edit
//
//  エントリポイント（純 AppKit ライフサイクル）。
//  入力バーは非アクティブ化 NSPanel（style mask・レベルを細かく制御する）で作るため、
//  SwiftUI の App／WindowGroup は使わない（App-浮紙の main.swift と同じ構成）。
//
//  ⚠️ @main / @NSApplicationMain は使わず main.swift で明示的に起動する。
//    delegate はこのファイルのグローバル定数が保持する（NSApplication.delegate は弱参照）。
//

import AppKit

let appDelegate = AppDelegate()
// NSApplicationDelegate 準拠は MainActor 隔離のため、メインスレッド上であることを明示して接続する
// （main.swift のトップレベルは実際にメインスレッドで走る）。
MainActor.assumeIsolated {
    NSApplication.shared.delegate = appDelegate
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
