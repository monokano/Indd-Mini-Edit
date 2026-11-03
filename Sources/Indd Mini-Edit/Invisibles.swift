//
//  Invisibles.swift
//  Indd Mini-Edit
//
//  不可視文字の可視化に使うデータと専用フォント。
//  **App-浮紙 `Invisibles.swift` からの移植**（ユーザー指示＝浮紙の方式。HANDOFF §5・HANDOFF-Xojo §5.2）。
//
//  旧 Xojo 版は、中身非公開の外部コード `Invisible` と専用フォント `Invisibles2-R` で、
//  NSLayoutManager の showInvisibleCharacters を使って表示していた。マッピングは旧版の
//  `DefaultInvisibleCharMapping.txt`（81項目）と同一で、VT・FF の代替だけ浮紙で改めたもの。
//
//  浮紙から持ち込まなかったもの:
//  - 代替グリフのユーザー設定（`ConfigurableItem`・`glyphDefaultsKey`・`loadGlyphOverrides`）。
//    Mini-Edit には設定ウィンドウが無いため、既定表のまま固定。
//  浮紙と違うもの:
//  - 専用フォントは旧版の Invisibles2-R（浮紙は U-Invisibles-R）。
//
//  実際の描画は InvisiblesLayoutManager（NSLayoutManager サブクラス）が行う。
//

import AppKit
import CoreText

nonisolated enum Invisibles {

    /// 不可視文字のコードポイント → 表示する代替文字のコードポイント（sub）。
    /// 代替文字のグリフは専用フォント Invisibles2-R が持つ。これに異体字セレクタを合成する。
    static let substitutions: [UInt32: UInt32] = {
        var map = mappingEntries
        // 異体字セレクタ（ゼロ幅で存在が見えない）を、他の Cf・ゼロ幅文字と同じ汎用マーカー
        // ¦ (U+00A6) で可視化する。IVS（U+E0100–E01EF）は BMP 外なので描画側でサロゲート
        // ペア処理が要る（InvisiblesLayoutManager 参照）。※ U+180E は下の表に別グリフで既出。
        let vsMarker: UInt32 = 0x00A6
        for range in variationSelectorRanges {
            for cp in range { map[cp] = vsMarker }
        }
        // NEL（U+0085・次行）は改行の一種。代替は ↵（U+21B5）。
        map[0x0085] = 0x21B5
        return map
    }()

    /// 異体字セレクタのコードポイント範囲。
    /// - VS1–VS16  : U+FE00–FE0F（SVS＝標準異体字列。絵文字の字形指定 VS15/VS16 を含む）
    /// - VS17–VS256: U+E0100–E01EF（IVS＝表意文字異体字列。追加面＝サロゲートペア）
    /// - 蒙古 FVS  : U+180B–180D, U+180F（FVS1–FVS4。U+180E は母音区切りで別扱い・既出）
    static let variationSelectorRanges: [ClosedRange<UInt32>] = [
        0xFE00...0xFE0F,
        0xE0100...0xE01EF,
        0x180B...0x180D,
        0x180F...0x180F,
    ]

    /// 旧版 DefaultInvisibleCharMapping.txt（＝浮紙 InvisiblesMapping.xml）由来の対応表（異体字セレクタ合成前）。
    private static let mappingEntries: [UInt32: UInt32] = [
        0x0001: 0x00A6,  // Cc: Start Of Heading
        0x0002: 0x00A6,  // Cc: Start Of Text
        0x0003: 0x00A6,  // Cc: End Of Text
        0x0004: 0x00A6,  // Cc: End Of Transmission
        0x0005: 0x00A6,  // Cc: Enquiry
        0x0006: 0x00A6,  // Cc: Acknowledge
        0x0007: 0x00A6,  // Cc: Bell
        0x0008: 0x00A6,  // Cc: Backspace
        0x0009: 0x21E5,  // Cc: Tab
        0x000A: 0x00B6,  // Cc: LF
        0x000B: 0x21B5,  // Cc: Line Tabulation (VT) — 旧版は ¦。浮紙で ↵ に変更（Word の段落内改行の実体）
        0x000C: 0x00AC,  // Cc: Form Feed (FF) — 旧版は ¦。浮紙で ¬ に変更（改ページ）
        0x000D: 0x23CE,  // Cc: CR
        0x000E: 0x00A6,  // Cc: Shift Out
        0x000F: 0x00A6,  // Cc: Shift In
        0x0010: 0x00A6,  // Cc: Data Link Escape
        0x0011: 0x00A6,  // Cc: Device Control One
        0x0012: 0x00A6,  // Cc: Device Control Two
        0x0013: 0x00A6,  // Cc: Device Control Three
        0x0014: 0x00A6,  // Cc: Device Control Four
        0x0015: 0x00A6,  // Cc: Negative Acknowledge
        0x0016: 0x00A6,  // Cc: Synchronous Idle
        0x0017: 0x00A6,  // Cc: End Of Transmission Block
        0x0018: 0x00A6,  // Cc: Cancel
        0x0019: 0x00A6,  // Cc: End Of Medium
        0x001A: 0x00A6,  // Cc: Substitute
        0x001B: 0x00A6,  // Cc: ESCAPE
        0x001C: 0x00A6,  // Cc: Information Separator Four (FS)
        0x001D: 0x00A6,  // Cc: Information Separator Three (GS)
        0x001E: 0x00A6,  // Cc: Information Separator Two (RS)
        0x001F: 0x00A6,  // Cc: Information Separator One (US)
        0x0020: 0x002E,  // Zs: Space
        0x007F: 0x00A6,  // Cc: Delete
        0x00A0: 0x2304,  // Zs: No-Break Space
        0x00AD: 0x00A6,  // Cf: Soft Hyphen
        0x180E: 0x29EB,  // Cf: Mongolian Vowel Separator
        0x2000: 0x00BD,  // Zs: EN Quad
        0x2001: 0x2588,  // Zs: EM Quad
        0x2002: 0x00BD,  // Zs: EN Space
        0x2003: 0x2588,  // Zs: EM Space
        0x2004: 0x2153,  // Zs: Three-Per-Em Space (⅓)
        0x2005: 0x00BC,  // Zs: Four-Per-Em Space (¼)
        0x2006: 0x2159,  // Zs: Six-Per-Em Space (⅙)
        0x2007: 0x00BD,  // Zs: Figure Space
        0x2008: 0x29EB,  // Zs: Punctuation Space
        0x2009: 0x2155,  // Zs: Thin Space (⅕)
        0x200A: 0x215B,  // Zs: Hair Space (⅛)
        0x200B: 0x00A6,  // Cf: Zero Width Space
        0x200C: 0x00A6,  // Cf: Zero Width Non-Joiner
        0x200D: 0x00A6,  // Cf: Zero Width Joiner
        0x200E: 0x00A6,  // Cf: Left-To-Right Mark (LRM)
        0x200F: 0x00A6,  // Cf: Right-To-Left Mark (RLM)
        0x2028: 0x2193,  // Zl: Line Separator
        0x2029: 0x21D3,  // Zp: Paragraph Separator
        0x202A: 0x00A6,  // Cf: Left-To-Right Embedding (LRE)
        0x202B: 0x00A6,  // Cf: Right-To-Left Embedding (RLE)
        0x202C: 0x00A6,  // Cf: Pop Directional Formatting (PDF)
        0x202D: 0x00A6,  // Cf: Left-To-Right Override (LRO)
        0x202E: 0x00A6,  // Cf: Right-To-Left Override (RLO)
        0x202F: 0x2304,  // Zs: Narrow No-Break Space
        0x205F: 0x29EB,  // Zs: Medium Mathematical Space
        0x2060: 0x00A6,  // Cf: Word Joiner
        0x2061: 0x00A6,  // Cf: Function Application
        0x2062: 0x00A6,  // Cf: Invisible Times
        0x2063: 0x00A6,  // Cf: Invisible Separator
        0x2064: 0x00A6,  // Cf: Invisible Plus
        0x2066: 0x00A6,  // Cf: Left-To-Right Isolate
        0x2067: 0x00A6,  // Cf: Right-To-Left Isolate
        0x2068: 0x00A6,  // Cf: First Strong Isolate
        0x2069: 0x00A6,  // Cf: Pop Directional Isolate
        0x206A: 0x00A6,  // Cf: Inhibit Symmetric Swapping (Deprecated)
        0x206B: 0x00A6,  // Cf: Activate Symmetric Swapping (Deprecated)
        0x206C: 0x00A6,  // Cf: Inhibit Arabic Form Shaping (Deprecated)
        0x206D: 0x00A6,  // Cf: Activate Arabic Form Shaping (Deprecated)
        0x206E: 0x00A6,  // Cf: National Digit Shapes (Deprecated)
        0x206F: 0x00A6,  // Cf: Nominal Digit Shapes (Deprecated)
        0x3000: 0x25A1,  // Zs: Ideographic Space
        0xFEFF: 0x00A6,  // Cf: Zero Width No-Break Space
        0xFFF9: 0x00A6,  // Cf: Interlinear Annotation Anchor
        0xFFFA: 0x00A6,  // Cf: Interlinear Annotation Separator
        0xFFFB: 0x00A6,  // Cf: Interlinear Annotation Terminator
    ]

    /// 改行系（行末に置かれ、横方向の中央寄せをしない）。NEL(U+0085) も NSLayoutManager が
    /// 行分割する（浮紙で実測確認済み 2026-07-06）ので含める。
    static let lineBreakCodepoints: Set<UInt32> = [0x000A, 0x000D, 0x0085, 0x2028, 0x2029]

    /// このコードポイントを専用グリフで描くか。
    static func shouldDraw(_ codepoint: UInt32) -> Bool {
        substitutions[codepoint] != nil
    }

    /// 専用グリフを持たない不可視文字（フォールバック描画）に使う代替文字コードポイント。
    /// 不可視フォントが U+FFFD を持てばそれを、無ければシステムフォントの � を使う（描画側で解決）。
    static let fallbackSubstitute: UInt32 = 0xFFFD

    /// 専用グリフを持たない「未対応の不可視文字」か。true なら代替として `fallbackSubstitute`（�）を出す。
    /// 判定は Unicode 一般カテゴリで、非表示系（Cc／Cf／Zl／Zp）だけを対象にする（浮紙と同じ）。
    /// 可視文字・結合マーク（VS 含む）・通常スペース（Zs）は対象外。`substitutions` に既にあるものは
    /// 専用グリフを使うのでここでは false。単独サロゲート等の不正コードは Scalar 化できないので対象外。
    static func isUnsupportedInvisible(_ codepoint: UInt32) -> Bool {
        guard substitutions[codepoint] == nil,
              let scalar = Unicode.Scalar(codepoint) else { return false }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return false
        }
    }
}

/// 不可視文字描画に使う専用フォント。システムには登録せず、バンドルした otf から
/// CGFont を一度だけ読み、要求サイズごとに CTFont を作る（描画専用）。
nonisolated final class InvisiblesFont {
    static let shared = InvisiblesFont()

    /// バンドルのフォントファイル名（拡張子なし）。**旧 Xojo 版の Invisibles2-R**（ユーザー指示 2026-10-29）。
    /// 浮紙の U-Invisibles-R ではない。代替文字はすべて収録済み（↵・¬ を含む。U+FFFD は無いので
    /// � はシステムフォントで描く）。浮紙版よりタブ⇥・改行¶などの字幅が細い。
    static let resourceName = "Invisibles2-R"

    private let cgFont: CGFont?

    private init() {
        if let url = Bundle.main.url(forResource: Self.resourceName, withExtension: "otf"),
           let data = try? Data(contentsOf: url),
           let provider = CGDataProvider(data: data as CFData) {
            cgFont = CGFont(provider)
        } else {
            cgFont = nil
        }
    }

    /// 指定ポイントサイズの CTFont（フォントを読めなければ nil）。
    func ctFont(size: CGFloat) -> CTFont? {
        guard let cgFont else { return nil }
        return CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    }
}
