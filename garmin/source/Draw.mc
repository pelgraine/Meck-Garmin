using Toybox.Graphics;
using Toybox.WatchUi;
using Toybox.StringUtil;

// Layout shared by every screen. The fenix 7S face is 240x240 and round;
// the content column is kept inside the circle at every row height used.
module Draw {
    const FONT      = Graphics.FONT_XTINY;
    const X         = 32;    // content left edge
    const W         = 176;   // content width (x 32..208)
    const HEAD_Y    = 20;    // header text top
    const CX        = 120;   // screen centre

    // Meck Watch header: "<" at the left, centred title, rule underneath.
    // Returns the y where content may start.
    function header(dc, title, showBack) {
        var fh = dc.getFontHeight(FONT);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (showBack) {
            dc.drawText(X + 4, HEAD_Y, FONT, "<", Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.drawText(CX, HEAD_Y, FONT, fitTo(dc, title, W - 40), Graphics.TEXT_JUSTIFY_CENTER);
        var ruleY = HEAD_Y + fh + 2;
        dc.drawLine(X, ruleY, X + W, ruleY);
        return ruleY + 4;
    }

    // One-line footer near the bottom of the circle.
    function footer(dc, text) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(CX, 208, FONT, fitTo(dc, text, 120), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Cut a string so it fits in w pixels, no ellipsis (Meck Watch incoming style).
    function fitTo(dc, s, w) {
        if (dc.getTextWidthInPixels(s, FONT) <= w) {
            return s;
        }
        var n = s.length();
        while (n > 0) {
            n--;
            var t = s.substring(0, n);
            if (dc.getTextWidthInPixels(t, FONT) <= w) {
                return t;
            }
        }
        return "";
    }

    // Shorten with "..." (Meck Watch sent-message style).
    function ellipsize(dc, s, w) {
        if (dc.getTextWidthInPixels(s, FONT) <= w) {
            return s;
        }
        var n = s.length();
        while (n > 0) {
            n--;
            var t = s.substring(0, n) + "...";
            if (dc.getTextWidthInPixels(t, FONT) <= w) {
                return t;
            }
        }
        return "...";
    }

    var _emojiH = -1;

    // Rows are spaced by the taller of the text font and the system emoji
    // font, so a line with an emoji cannot spill into the next row.
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
