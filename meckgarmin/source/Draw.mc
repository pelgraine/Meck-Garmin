using Toybox.Graphics;
using Toybox.WatchUi;
using Toybox.StringUtil;

// Layout shared by every screen. The fenix 7S face is 240x240 and round;
// the content column is kept inside the circle at every row height used.
module Draw {
    const FONT      = Graphics.FONT_XTINY;
    const X         = 32;    // content left edge
    const W         = 176;   // content width (x 32..208)
    const HEAD_Y    = 8;     // header text top (in the circle's top gap)
    const CX        = 120;   // screen centre

    // Header: centred title in the top gap, rule underneath, then a clear
    // band before the first row so tall emoji glyphs cannot touch the rule.
    // (No "<" glyph: the circle is too narrow at this height; Back does it.)
    function header(dc, title, showBack) {
        var fh = dc.getFontHeight(FONT);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        text(dc, CX, HEAD_Y, fitTo(dc, title, 90), Graphics.TEXT_JUSTIFY_CENTER);
        var ruleY = HEAD_Y + fh + 2;
        dc.drawLine(X, ruleY, X + W, ruleY);
        return ruleY + 10;
    }

    // One-line footer near the bottom of the circle.
    function footer(dc, msg) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        text(dc, CX, 208, fitTo(dc, msg, 120), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Cut a string so it fits in w pixels, no ellipsis (Meck Watch incoming style).
    function fitTo(dc, s, w) {
        if (width(dc, s) <= w) {
            return s;
        }
        var n = s.length();
        while (n > 0) {
            n--;
            var t = s.substring(0, n);
            if (width(dc, t) <= w) {
                return t;
            }
        }
        return "";
    }

    // Shorten with "..." (Meck Watch sent-message style).
    function ellipsize(dc, s, w) {
        if (width(dc, s) <= w) {
            return s;
        }
        var n = s.length();
        while (n > 0) {
            n--;
            var t = s.substring(0, n) + "...";
            if (width(dc, t) <= w) {
                return t;
            }
        }
        return "...";
    }

    // ---- Black florette (U+273F) --------------------------------------
    // The fenix's built-in font has no glyph for it (it shows the
    // missing-glyph diamond), so the app carries a one-glyph font of its own
    // (resources/fonts/florette.fnt, 18 px tall to match the emoji glyphs).
    // Every place that draws text a node or a person supplied goes through
    // width() and text() below: plain strings take the normal path, and a
    // string holding the florette is drawn in runs, the letters from FONT
    // and each florette from the florette font, centred on the text row.
    // text() takes TEXT_JUSTIFY_LEFT, _CENTER or _RIGHT only.

    const FLORETTE_CP = 0x273F;
    var _florFont = null;     // the one-glyph font, loaded on first use
    var _florStr = null;      // "U+273F" as a String, built from its UTF-8 bytes
    var _segCache = {};       // String -> segments (null entry = one florette)

    function _florInit() {
        if (_florStr != null) { return; }
        _florFont = WatchUi.loadResource(Rez.Fonts.Florette);
        _florStr = StringUtil.convertEncodedString([0xE2, 0x9C, 0xBF]b, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
        });
    }

    function hasFlorette(s) {
        _florInit();
        return s.find(_florStr) != null;
    }

    // Split s into runs: Strings of ordinary text, and null for each florette.
    function _segments(s) {
        var segs = _segCache.get(s);
        if (segs != null) { return segs; }
        segs = [];
        var chars = s.toCharArray();
        var run = [];
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i].toNumber() == FLORETTE_CP) {
                if (run.size() > 0) { segs.add(StringUtil.charArrayToString(run)); run = []; }
                segs.add(null);
            } else {
                run.add(chars[i]);
            }
        }
        if (run.size() > 0) { segs.add(StringUtil.charArrayToString(run)); }
        if (_segCache.size() >= 32) { _segCache = {}; }
        _segCache.put(s, segs);
        return segs;
    }

    // Pixel width of s in FONT, with florettes measured in their own font.
    function width(dc, s) {
        if (!hasFlorette(s)) {
            return dc.getTextWidthInPixels(s, FONT);
        }
        var segs = _segments(s);
        var fw = dc.getTextWidthInPixels(_florStr, _florFont);
        var w = 0;
        for (var i = 0; i < segs.size(); i++) {
            w += (segs[i] == null) ? fw : dc.getTextWidthInPixels(segs[i], FONT);
        }
        return w;
    }

    // Draw s at (x, y) in FONT with the given left/centre/right justification,
    // florettes drawn from their own font. Same contract as dc.drawText with
    // FONT, so callers swap one for the other.
    function text(dc, x, y, s, justify) {
        if (!hasFlorette(s)) {
            dc.drawText(x, y, FONT, s, justify);
            return;
        }
        var total = width(dc, s);
        var cx = x;
        if (justify == Graphics.TEXT_JUSTIFY_CENTER) { cx = x - total / 2; }
        else if (justify == Graphics.TEXT_JUSTIFY_RIGHT) { cx = x - total; }
        var segs = _segments(s);
        var fw = dc.getTextWidthInPixels(_florStr, _florFont);
        var fy = y + (dc.getFontHeight(FONT) - dc.getFontHeight(_florFont)) / 2;
        for (var i = 0; i < segs.size(); i++) {
            if (segs[i] == null) {
                dc.drawText(cx, fy, _florFont, _florStr, Graphics.TEXT_JUSTIFY_LEFT);
                cx += fw;
            } else {
                dc.drawText(cx, y, FONT, segs[i], Graphics.TEXT_JUSTIFY_LEFT);
                cx += dc.getTextWidthInPixels(segs[i], FONT);
            }
        }
    }

    var _emojiH = -1;

    // Rows are spaced by the taller of the text font and the system emoji
    // font, so a line with an emoji cannot spill into the next row.
    // Draw s at (x, y) clipped to w, offset for a marquee with a trailing
    // second copy. Returns the text width so the caller can wrap the offset.
    function marqueeRow(dc, s, x, y, w, rowH, off, gap) {
        var tw = width(dc, s);
        dc.setClip(x, y, w, rowH);
        text(dc, x - off, y, s, Graphics.TEXT_JUSTIFY_LEFT);
        if (tw > w) {
            text(dc, x - off + tw + gap, y, s, Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.clearClip();
        return tw;
    }

    function rowHeight(dc) {
        var th = dc.getFontHeight(FONT);
        if (_emojiH < 0) {
            _emojiH = th;
            try {
                var sample = StringUtil.convertEncodedString([0xF0, 0x9F, 0x8C, 0xB1]b, {
                    :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                    :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
                });
                var dim = dc.getTextDimensions(sample, FONT);
                if (dim[1] > _emojiH) { _emojiH = dim[1]; }
            } catch (ex) {
            }
        }
        return _emojiH + 2;
    }
}
