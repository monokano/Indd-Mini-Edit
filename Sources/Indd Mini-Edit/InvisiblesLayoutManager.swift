//
//  InvisiblesLayoutManager.swift
//  Indd Mini-Edit
//
//  不可視文字（タブ・スペース・全角スペース・改行など）を可視化する NSLayoutManager。
//  **App-浮紙 `UkigamiLayoutManager.swift` からの移植**（HANDOFF §5・HANDOFF-Xojo §5.2）。
//
//  TextKit 1（自前 NSLayoutManager）構成のうえで、通常のグリフ描画のあとに、不可視文字の
//  位置へ専用フォント Invisibles2-R（旧版のフォント）の代替グリフを重ね描きする（CotEditor と同方式）。
//
//  浮紙から持ち込まなかったもの:
//  - 代替グリフのユーザー設定（glyphOverrides と UserDefaults の監視）。既定表のまま固定。
//  - fillBackgroundRectArray の上書き（浮紙の検索の現在マッチ色用）。
//
//  座標について:
//  - NSTextView は flipped（左上原点・y は下向き）。CoreText のグリフはフォント空間で y が
//    上向きなので、描画時にベースライン位置へ平行移動し y を反転（scaleBy(y: -1)）して描く。
//
//  罠（浮紙 QUIRKS.md に詳細）:
//  - 行末グリフのセル幅に lineFragmentUsedRect を使うと lineFragmentPadding 分（5pt）広く出る
//    → boundingRect(forGlyphRange: 1個, in:) を使う（浮紙ステップ147）。
//  - .null グリフ（VS15/VS16 など）は boundingRect がクラスタ全体の矩形を返す
//    → propertyForGlyph(at:).contains(.null) なら幅 0（浮紙ステップ205）。
//

import AppKit
import CoreText

nonisolated final class InvisiblesLayoutManager: NSLayoutManager {

    /// 不可視文字を表示するか（Mini-Edit は常に表示。旧版 showInvisibleCharacters = True）。
    var showsInvisibles = true

    /// 代替グリフの描画色（旧版は systemPink）。
    var invisiblesColor: NSColor = .systemPink

    /// 代替グリフを描くサイズ（本文フォントサイズに合わせる）。サイズが変わるとグリフ送り幅も
    /// 変わるのでキャッシュを捨てる。
    var invisiblesFontSize: CGFloat = 16 {
        didSet {
            if invisiblesFontSize != oldValue {
                subGlyphCache.removeAll()
                fallbackResolved = false   // � の解決（グリフ・送り幅・フォント）もサイズ依存なので捨てる
            }
        }
    }

    /// 代替グリフをベースラインからわずかに持ち上げる量（pt）。フォントサイズ比でスケールさせる（浮紙と同じ）。
    private var baselineRaise: CGFloat { invisiblesFontSize * 0.11 }

    /// 代替文字コードポイント（sub）→ (代替グリフ, 送り幅)。サイズ変更時に作り直す。
    /// 多くの不可視文字が同じ sub（例: ¦）を共有するので、sub 側でキャッシュすると無駄がない。
    private var subGlyphCache: [UInt32: (glyph: CGGlyph, advance: CGFloat)] = [:]

    /// コードポイント → 「未対応の不可視文字か（� を出すか）」の判定キャッシュ。Unicode カテゴリ由来で
    /// フォントサイズに依らないため、サイズ変更でも捨てない。
    private var unsupportedCache: [UInt32: Bool] = [:]

    /// フォールバックの � グリフ（と送り幅・描画フォント）。不可視フォントに U+FFFD があればそれを、
    /// 無ければシステムフォントの � を使う。一度だけ解決してキャッシュ（サイズ変更で捨てる）。
    private var fallbackGlyphEntry: (glyph: CGGlyph, advance: CGFloat, ctFont: CTFont)?
    private var fallbackResolved = false

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showsInvisibles else { return }
        drawInvisibles(forGlyphRange: glyphsToShow, at: origin)
    }

    /// 表示範囲の不可視文字を走査し、代替グリフを描く。
    private func drawInvisibles(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage,
              let ctFont = InvisiblesFont.shared.ctFont(size: invisiblesFontSize),
              let context = NSGraphicsContext.current?.cgContext else { return }

        let string = textStorage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        context.saveGState()
        context.setFillColor(invisiblesColor.cgColor)

        var charIndex = charRange.location
        let end = NSMaxRange(charRange)
        while charIndex < end {
            let unit = string.character(at: charIndex)

            // CRLF（CR+LF）: レイアウト上 CR と LF は行末の同じ位置に来るため、素朴に描くと重なる。
            // CR のグリフを行末位置に描き、LF のグリフを CR の送り幅ぶん右へずらして並べる（浮紙ステップ64）。
            if unit == 0x000D, charIndex + 1 < end, string.character(at: charIndex + 1) == 0x000A,
               let cr = glyph(for: 0x000D, ctFont: ctFont) {
                drawGlyph(cr.glyph,
                          advance: cr.advance,
                          forCharacterAt: charIndex,
                          isLineBreak: true,
                          ctFont: ctFont,
                          origin: origin,
                          context: context)
                if let lf = glyph(for: 0x000A, ctFont: ctFont) {
                    drawGlyph(lf.glyph,
                              advance: lf.advance,
                              forCharacterAt: charIndex,   // CR と同じ行末位置を基準に
                              isLineBreak: true,
                              ctFont: ctFont,
                              origin: origin,
                              context: context,
                              xOffset: cr.advance)         // CR の送り幅ぶん右へ
                }
                charIndex += 2
                continue
            }

            // 基本は UTF-16 1 単位＝1 コードポイント。ただし IVS（U+E0100–E01EF）など BMP 外の
            // 対象はサロゲートペアなので、上位＋下位を合成して真のコードポイントを得る。
            var codepoint = UInt32(unit)
            var length = 1
            if UTF16.isLeadSurrogate(unit), charIndex + 1 < end {
                let low = string.character(at: charIndex + 1)
                if UTF16.isTrailSurrogate(low) {
                    codepoint = 0x10000
                        + ((UInt32(unit) - 0xD800) << 10)
                        + (UInt32(low) - 0xDC00)
                    length = 2
                }
            }
            if Invisibles.shouldDraw(codepoint) {
                if let entry = glyph(for: codepoint, ctFont: ctFont) {
                    drawGlyph(entry.glyph,
                              advance: entry.advance,
                              forCharacterAt: charIndex,
                              isLineBreak: Invisibles.lineBreakCodepoints.contains(codepoint),
                              ctFont: ctFont,
                              origin: origin,
                              context: context)
                }
            } else if isUnsupportedInvisibleCached(codepoint), let fb = fallbackGlyph() {
                // 専用グリフを持たない非表示系（Cc/Cf/Zl/Zp）は � で存在だけ示す。改行系は既に
                // 専用グリフ対応済みなのでここには来ない＝中央寄せでよい（isLineBreak: false）。
                drawGlyph(fb.glyph,
                          advance: fb.advance,
                          forCharacterAt: charIndex,
                          isLineBreak: false,
                          ctFont: fb.ctFont,
                          origin: origin,
                          context: context)
            }
            charIndex += length
        }

        context.restoreGState()
    }

    /// 1 つの代替グリフを、不可視文字のレイアウト位置に描く。
    /// `xOffset` はレイアウト位置からの右方向の追加ずらし（CRLF の LF を CR の右に並べる用）。
    private func drawGlyph(
        _ subGlyph: CGGlyph,
        advance subAdvance: CGFloat,
        forCharacterAt charIndex: Int,
        isLineBreak: Bool,
        ctFont: CTFont,
        origin: NSPoint,
        context: CGContext,
        xOffset: CGFloat = 0
    ) {
        let glyphIndex = glyphIndexForCharacter(at: charIndex)
        var lineGlyphRange = NSRange(location: 0, length: 0)
        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
        let location = location(forGlyphAt: glyphIndex)   // 行フラグメント原点からの相対（y はベースライン）

        // 横位置: 改行系は行末にそのまま置く。字幅を持つものは、その文字の送り幅の中央へ寄せる。
        var x = origin.x + lineRect.origin.x + location.x + xOffset
        if !isLineBreak {
            let cellAdvance = cellAdvanceForGlyph(at: glyphIndex, lineGlyphRange: lineGlyphRange, glyphX: location.x)
            x += (cellAdvance - subAdvance) / 2
        }
        // flipped 座標では y が小さいほど上。少しだけ持ち上げる。
        let baselineY = origin.y + lineRect.origin.y + location.y - baselineRaise

        // flipped コンテキストでグリフを正立させる（ベースラインへ移動して y を反転）。
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: x, y: baselineY)
        context.scaleBy(x: 1, y: -1)
        var glyph = subGlyph
        var position = CGPoint.zero
        CTFontDrawGlyphs(ctFont, &glyph, &position, 1, context)
        context.restoreGState()
    }

    /// 不可視文字 1 文字分の送り幅（セル幅）。次グリフとの位置差から求め、行末では
    /// 当該グリフ1個のレイアウト矩形（boundingRect）の幅を使う（浮紙ステップ147・205）。
    private func cellAdvanceForGlyph(at glyphIndex: Int, lineGlyphRange: NSRange, glyphX: CGFloat) -> CGFloat {
        // 送り幅を持たないグリフ（.null＝異体字セレクタなど、直前の字と1クラスタを成す字）はセル幅 0。
        // 行末では boundingRect がクラスタ全体（＝直前の字を含む）の矩形を返すため、先に弾く。
        if propertyForGlyph(at: glyphIndex).contains(.null) { return 0 }
        let nextGlyph = glyphIndex + 1
        if nextGlyph < NSMaxRange(lineGlyphRange) {
            return max(0, location(forGlyphAt: nextGlyph).x - glyphX)
        }
        // 行内最後のグリフ: 自身のレイアウト矩形の幅をセル幅とみなす（usedRect は lineFragmentPadding を含むので使わない）。
        guard let container = textContainer(forGlyphAt: glyphIndex, effectiveRange: nil) else {
            return 0
        }
        return boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                            in: container).width
    }

    /// 不可視文字（source コードポイント）→ 代替グリフ。既定表（substitutions）で sub を引いてから取得する。
    private func glyph(for codepoint: UInt32, ctFont: CTFont) -> (glyph: CGGlyph, advance: CGFloat)? {
        guard let subCodepoint = Invisibles.substitutions[codepoint] else { return nil }
        return subGlyph(subCodepoint, ctFont: ctFont)
    }

    /// 代替文字コードポイント（sub）→ 代替グリフ（と送り幅）。専用（不可視）フォントの cmap 直接引き。
    private func subGlyph(_ subCodepoint: UInt32, ctFont: CTFont) -> (glyph: CGGlyph, advance: CGFloat)? {
        if let cached = subGlyphCache[subCodepoint] { return cached }
        guard let entry = rawGlyph(subCodepoint, ctFont: ctFont) else { return nil }
        subGlyphCache[subCodepoint] = entry
        return entry
    }

    /// 指定フォントで sub 文字のグリフと送り幅を引く（キャッシュなし）。グリフが無ければ nil。
    private func rawGlyph(_ subCodepoint: UInt32, ctFont: CTFont) -> (glyph: CGGlyph, advance: CGFloat)? {
        guard let scalar = Unicode.Scalar(subCodepoint) else { return nil }
        var utf16 = Array(String(scalar).utf16)   // 代替文字はすべて BMP（1 単位）
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count),
              let glyph = glyphs.first, glyph != 0 else { return nil }

        var advance = CGSize.zero
        var g = glyph
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &g, &advance, 1)
        return (glyph: glyph, advance: advance.width)
    }

    /// フォールバック（未対応の不可視文字）に描く � の (グリフ, 送り幅, 描画フォント)。
    /// 不可視フォントに U+FFFD があればそれ、無ければシステムフォントの � を使う。一度だけ解決。
    private func fallbackGlyph() -> (glyph: CGGlyph, advance: CGFloat, ctFont: CTFont)? {
        if fallbackResolved { return fallbackGlyphEntry }
        fallbackResolved = true
        let cp = Invisibles.fallbackSubstitute
        if let ctFont = InvisiblesFont.shared.ctFont(size: invisiblesFontSize),
           let e = rawGlyph(cp, ctFont: ctFont) {
            fallbackGlyphEntry = (e.glyph, e.advance, ctFont)
        } else {
            let sysCT = NSFont.systemFont(ofSize: invisiblesFontSize) as CTFont
            if let e = rawGlyph(cp, ctFont: sysCT) {
                fallbackGlyphEntry = (e.glyph, e.advance, sysCT)
            } else {
                fallbackGlyphEntry = nil
            }
        }
        return fallbackGlyphEntry
    }

    /// 「未対応の不可視文字か」をキャッシュ付きで判定（Unicode カテゴリ照会を 1 コードポイント 1 回に）。
    private func isUnsupportedInvisibleCached(_ codepoint: UInt32) -> Bool {
        if let cached = unsupportedCache[codepoint] { return cached }
        let result = Invisibles.isUnsupportedInvisible(codepoint)
        unsupportedCache[codepoint] = result
        return result
    }
}
