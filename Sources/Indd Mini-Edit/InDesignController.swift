import AppKit
import Carbon

/// 操作対象の InDesign インスタンス。**pid で特定**する（複数バージョン同時起動対応の要）。
/// 全バージョンが同一 Bundle ID `com.adobe.InDesign` のため、パスや名前では特定できず、
/// `tell application` 系はバンドルID解決で1インスタンスに収束してしまう。pid 指定の Apple Event なら確実。
struct InDesignTarget {
    let pid: pid_t
    let name: String   // 診断ログ用（例: "Adobe InDesign 2026"）
}

/// InDesign への流し込みの結果。メッセージの出し分けに使う（HANDOFF §5・HANDOFF-Xojo §6.2）。
enum SetTextResult {
    case ok            // 置換できた
    case noDocument    // ドキュメントが無い
    case noSelection   // テキスト系の選択（挿入点を含む）が無い
    case minimized     // 作業中のドキュメントウインドウが Dock にしまわれている（ステップ7.7）
    case notPermitted  // オートメーション（Apple イベント送信）が拒否されている
    case failed        // 送信失敗・タイムアウト・想定外の応答
}

/// InDesign 連携。**App-FILL Id `InDesignController.swift` からの移植**（HANDOFF §5）。
/// `do script`（JavaScript）を **pid 指定の Apple Event** で送る。
///
/// 送信は専用のシリアルキューで行い、**メインスレッドをブロックしない**（FILL Id のフリーズ対策）。
/// InDesign がビジーで応答しなくても、固まるのはバックグラウンドのキューだけで、入力バーは生きたまま。
///
/// FILL Id との違い:
/// - 流し込みスクリプトが「ドキュメントなし」「選択なし」「成功」を返し分ける（旧版のメッセージを出し分けるため）。
/// - 送る前にオートメーション許可を pid 宛てに確認し（未確定なら同意ダイアログ）、拒否を見分ける。
/// - ズーム・グリッド等の FILL Id 固有の操作は持ち込まない。
@MainActor
final class InDesignController {

    nonisolated static let bundleID = "com.adobe.InDesign"

    /// Apple Event 送信用のシリアルキュー。送信順を保証するため 1 本に直列化する。
    private let sendQueue = DispatchQueue(label: "com.tama-san.Indd-Mini-Edit.indesign-ae", qos: .userInitiated)

    /// 応答待ち中の Apple Event の数（メインスレッドで読み書き）。
    private var inFlightCount = 0

    /// InDesign への送信が応答待ち中か。送信キーの多重押しガードが参照する。
    /// ビジー中の連打を無視しないと、送信側がタイムアウトしてもイベントは InDesign 側のキューに残り、
    /// 後からまとめて実行される（多重ペースト等。FILL Id で実害あり）。
    var isBusy: Bool { inFlightCount > 0 }

    /// 起動している InDesign の数（全バージョン。旧版 CountBooting）。
    var runningCount: Int {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Self.bundleID }.count
    }

    /// 起動時に最前面だったアプリ（AppDelegate が設定。ふつうは ⌥ + return で Mini-Edit を起動した InDesign）。
    /// InDesign なら「最後にアクティブになった InDesign」の初期値にする（ステップ7.6）。
    var launchApp: NSRunningApplication? {
        didSet {
            if let app = launchApp, app.bundleIdentifier == Self.bundleID { lastActivatedApp = app }
        }
    }

    /// 最後にアクティブになった InDesign（ステップ7.5。7.6で起動元の InDesign を初期値にした）。
    /// 例: 起動元の InDesign を終了すると macOS が残りの InDesign をアクティブにする→それを覚えておく。
    /// 起動元より優先する＝ほかの版をクリックしてから別アプリへ切り替えても、前面にある版へ送る（ステップ7.6・ユーザー要望）。
    private var lastActivatedApp: NSRunningApplication?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.bundleID else { return }
            // queue: .main なのでメインスレッドで呼ばれる。
            MainActor.assumeIsolated { self?.lastActivatedApp = app }
        }
    }

    /// 送り先の InDesign を決める（ステップ7.4。InDesign が最前面でなくても送れるようにした＝ユーザー承認 2026-10-31）。
    /// 1. 最前面アプリが InDesign ならそれ（旧版 frontmostAppPath の pid 版）
    /// 2. 最後にアクティブになった InDesign（初期値は起動元の InDesign。まだ起動していれば。ステップ7.5・7.6）
    /// 3. 画面上でいちばん手前にウインドウがある InDesign（ステップ7.5）
    /// 4. 起動している InDesign が1つだけならそれ
    /// どれでもなければ nil（InDesign のウインドウが画面上に無く、複数の版が起動している等）。
    func resolveTarget() -> InDesignTarget? {
        if let app = NSWorkspace.shared.frontmostApplication, let target = Self.target(of: app) {
            return target
        }
        if let app = lastActivatedApp, !app.isTerminated, let target = Self.target(of: app) {
            return target
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Self.bundleID }
        if let app = Self.frontmostOnScreen(among: running), let target = Self.target(of: app) {
            return target
        }
        if running.count == 1, let target = Self.target(of: running[0]) {
            return target
        }
        return nil
    }

    /// `apps` のうち、画面上でいちばん手前にウインドウがあるもの（ステップ7.5）。
    /// `CGWindowListCopyWindowInfo` は手前から奥の順に返す。所有者の pid とレイヤーを読むだけなら
    /// 画面収録の許可はいらない（許可が要るのはウインドウ名）。しまった／隠した InDesign や、
    /// 別の操作スペースにしかウインドウが無い InDesign は候補にならない。
    private static func frontmostOnScreen(among apps: [NSRunningApplication]) -> NSRunningApplication? {
        guard !apps.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let app = apps.first(where: { $0.processIdentifier == pid }) else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            return app
        }
        return nil
    }

    /// InDesign のプロセスなら送り先にする。
    private static func target(of app: NSRunningApplication) -> InDesignTarget? {
        guard app.bundleIdentifier == bundleID else { return nil }
        // localizedName は全バージョン "InDesign" になるため、診断用の名前は .app 名から採る（例: "Adobe InDesign 2026"）。
        let name = app.bundleURL?.deletingPathExtension().lastPathComponent ?? app.localizedName ?? "InDesign"
        return InDesignTarget(pid: app.processIdentifier, name: name)
    }

    // MARK: - 流し込み

    /// 選択範囲の contents を直接置換する。undo mode=fast entire script で InDesign 側 1 回の取り消しにまとめる。
    /// ドキュメント・選択の確認と置換を 1 本のスクリプトに統合し、InDesign との往復を 1 回にしている。
    /// 空（""）にはせず**先頭1文字を残してから**置換することで、選択範囲（先頭文字）の書式を保持する。
    /// 置換“前”に末尾の挿入ポイントを `select()` しておくと、置換後は挿入テキスト直後にキャレットが残る。
    /// タイムアウトは巨大テキストの置換に時間がかかり得るため 30 秒（FILL Id と同じ）。
    /// `bringToFront` が true なら、置換できたあと InDesign を最前面にする（`app.activate()`。最前面でない InDesign に
    /// 送ったとき、結果が見えるように。Mini-Edit は送信後に終了するので InDesign 自身に前面化させる）。
    func setText(_ text: String, target: InDesignTarget, bringToFront: Bool = false, completion: @escaping @MainActor (SetTextResult) -> Void) {
        guard !text.isEmpty else { completion(.failed); return }
        let js = """
        var r="nodoc";
        if(app.documents.length>0){
        r="nosel";
        if(app.selection.length>0){
        var s=app.selection[0];
        var k=s.constructor.name;
        if(k=="Text"||k=="InsertionPoint"||k=="Character"||k=="Word"||k=="Line"||k=="Paragraph"||k=="TextStyleRange"||k=="TextColumn"){
        var t=\(Self.jsString(text));
        s.insertionPoints[-1].select();
        if(s.contents.length>0){s.contents=s.contents.substring(0,1);}
        s.contents=t;
        r="ok";
        }
        }
        }
        \(bringToFront ? #"if(r=="ok"){app.activate();}"# : "")
        r;
        """
        // 隠した（⌘H）InDesign はウインドウがすべて画面外になり、しまったのと見分けられないので確認しない
        // （送れたら app.activate() で表示される）。
        let checkMinimized = !(NSRunningApplication(processIdentifier: target.pid)?.isHidden ?? false)
        inFlightCount += 1
        sendQueue.async {
            if checkMinimized && Self.isActiveWindowMinimized(target) {
                Task { @MainActor in
                    self.inFlightCount -= 1
                    completion(.minimized)
                }
                return
            }
            let outcome = Self.sendDoScript(js, to: target, undo: true, timeout: 30)
            let result: SetTextResult
            switch outcome {
            case .reply(let reply):
                switch reply?.stringValue {
                case "ok": result = .ok
                case "nodoc": result = .noDocument
                case "nosel": result = .noSelection
                default: result = .failed
                }
            case .notPermitted:
                result = .notPermitted
            case .failed:
                result = .failed
            }
            Task { @MainActor in
                self.inFlightCount -= 1
                completion(result)
            }
        }
    }

    // MARK: - しまわれたウインドウの判定（ステップ7.7）

    /// 作業中のウインドウが Dock にしまわれているか。sendQueue から呼ぶ（InDesign との往復がある）。
    /// InDesign DOM のウインドウには「しまわれているか」の属性が無い（minimize()／maximize() メソッドだけ）ため、
    /// `app.activeWindow.bounds` を聞き、同じ pid・同じ左端／幅／高さの layer 0 のウインドウを
    /// `CGWindowListCopyWindowInfo(.optionAll)` で探して `kCGWindowIsOnscreen` を見る。
    /// 実機（2026-11-01・2024／2026 で確認）: しまっても bounds は変わらず、onscreen だけ false になる。
    /// 上端は InDesign 側が版ごとに違う基準（71px／78px ずれ）なので照合に使わない。
    /// 一致するウインドウが無い・問い合わせに失敗したときは「しまわれていない」とする（送信を止めない）。
    /// ⚠️ 別の操作スペースにあるウインドウも onscreen=false になるので、しまわれている扱いになる。
    private nonisolated static func isActiveWindowMinimized(_ target: InDesignTarget) -> Bool {
        let js = #"var r="";try{var b=app.activeWindow.bounds;r=b[1]+","+(b[3]-b[1])+","+(b[2]-b[0]);}catch(e){} r;"#
        guard case .reply(let reply) = sendDoScript(js, to: target, undo: false, timeout: 5),
              let parts = reply?.stringValue?.split(separator: ",").compactMap({ Double($0) }), parts.count == 3,
              let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        var matched = false
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == target.pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  abs(rect.minX - parts[0]) <= 1, abs(rect.width - parts[1]) <= 1, abs(rect.height - parts[2]) <= 1
            else { continue }
            if info[kCGWindowIsOnscreen as String] as? Bool == true { return false }
            matched = true
        }
        return matched
    }

    // MARK: - pid 指定の do script 送信（バックグラウンド・シリアルキュー）

    private enum SendOutcome {
        case reply(NSAppleEventDescriptor?)   // reply の ---- パラメータ
        case notPermitted
        case failed
    }

    /// オートメーション許可を確認してから Apple Event を組み立てて同期送信する。
    /// ブロックしてよいバックグラウンドスレッド（sendQueue）から呼ぶ。
    private nonisolated static func sendDoScript(_ js: String, to target: InDesignTarget,
                                                 undo: Bool, timeout: TimeInterval) -> SendOutcome {
        let targetDescriptor = NSAppleEventDescriptor(processIdentifier: target.pid)

        // 許可の確認（未確定なら同意ダイアログを出し、答えるまで待つ）。
        // 送信そのもの（timeout 30 秒）の中で同意ダイアログが出ると、答えるのが遅いだけでタイムアウト扱いになるため先に済ませる。
        // AEDeterminePermissionToAutomateTarget はブロックし得る IPC なので、メインスレッドでは呼ばない（FILL Id の知見）。
        if let aeDesc = targetDescriptor.aeDesc {
            let status = AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, true)
            if status == OSStatus(errAEEventNotPermitted) {
                return .notPermitted
            }
        }

        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: osType("K2  "),   // InDesign スイート
            eventID: osType("dosc"),          // do script
            targetDescriptor: targetDescriptor,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))

        // 直接オブジェクト = スクリプト本体
        event.setParam(NSAppleEventDescriptor(string: js), forKeyword: osType("----"))
        // language = javascript
        event.setParam(NSAppleEventDescriptor(enumCode: osType("JSLg")), forKeyword: osType("doLg"))
        // undo mode = fast entire script
        if undo {
            event.setParam(NSAppleEventDescriptor(enumCode: osType("eSfU")), forKeyword: osType("pSUM"))
        }

        do {
            let reply = try event.sendEvent(options: [.waitForReply], timeout: timeout)
            if let err = reply.paramDescriptor(forKeyword: osType("errs"))?.stringValue, !err.isEmpty {
                NSLog("[Indd Mini-Edit] InDesign script error (%@): %@", target.name, err)
            }
            return .reply(reply.paramDescriptor(forKeyword: osType("----")))
        } catch {
            NSLog("[Indd Mini-Edit] do script send failed (%@): %@", target.name, error.localizedDescription)
            if (error as NSError).code == Int(errAEEventNotPermitted) {
                return .notPermitted
            }
            return .failed
        }
    }

    /// 4文字コード→OSType（4文字未満は空白でパディング。例: "K2  "）。
    private nonisolated static func osType(_ s: String) -> OSType {
        var bytes = Array(s.utf8.prefix(4))
        while bytes.count < 4 { bytes.append(0x20) }
        return bytes.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }

    /// 文字列を JavaScript の文字列リテラル（前後のダブルクォート含む）へ。
    /// CR はそのまま `\r`（InDesign の段落区切り）として埋め込む。
    /// U+2028（LS）・U+2029（PS）は JavaScript では文字列リテラル内でも行終端子＝生のまま入れると構文エラーに
    /// なるためエスケープする（FILL Id の元コードには無い。Mini-Edit で追加 2026-10-29）。
    nonisolated static func jsString(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\r": out += "\\r"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if u.value < 0x20 {
                    out += String(format: "\\u%04X", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
        return out
    }
}
