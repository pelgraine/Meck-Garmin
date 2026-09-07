using Toybox.WatchUi;
using Toybox.Graphics;

// Compose screen, laid out per E: channel name at the very top, a single-line
// draft box with Send at its right, the three QWERTY rows as large as ten
// columns on a 240px round face allow (they sit in the wide middle band), and
// Canned + space along the bottom. Mode key cycles lower / UPPER / 123.
class ComposeView extends WatchUi.View {

    const KFONT = Graphics.FONT_SMALL;   // key labels
    const KH = 36;
    const R1_X = 20;  const R1_W = 20;   // 10 keys, y 58..94
    const R2_X = 21;  const R2_W = 22;   // 9 keys,  y 96..132
    const R3_X = 21;  const R3_W = 22;   // mode + 7 keys + delete, y 134..170
    const R1_Y = 58;
    const R2_Y = 96;
    const R3_Y = 134;
    const BOT_Y = 174;  const BOT_H = 28;   // Cnd + space
    const CND_X = 36;   const CND_W = 44;
    const SPC_X = 84;   const SPC_W = 120;
    const BOX_X = 36;   const BOX_Y = 30;  const BOX_W = 126;  const BOX_H = 24;
    const SEND_X = 166; const SEND_W = 38;
    const MAX_LEN = 133;

    var _idx;
    var _prefix;
    var _text;
    var _mode = 0;        // 0 lower, 1 upper, 2 symbols
    var _rows;

    function initialize(idx, prefix) {
        View.initialize();
        _idx = idx;
        _prefix = prefix;
        _text = prefix;
        _rows = [
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"],
            ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"],
            ["1234567890", "!@#$%&*()", "-?,.:;/"]
        ];
    }

    // ---------------------------------------------------------------- drawing

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var fh = dc.getFontHeight(Draw.FONT);

        // channel name, top of the circle
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.CX, 8, Draw.FONT, Draw.fitTo(dc, gModel.channelName(_idx), 84), Graphics.TEXT_JUSTIFY_CENTER);

        // draft box: tail of the text, cursor at the end
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(BOX_X, BOX_Y, BOX_W, BOX_H, 4);
        var shown = longestSuffix(dc, _text + "_", BOX_W - 8);
        dc.drawText(BOX_X + 4, BOX_Y + (BOX_H - fh) / 2, Draw.FONT, shown, Graphics.TEXT_JUSTIFY_LEFT);
        drawKey(dc, SEND_X, BOX_Y, SEND_W, BOX_H, "Send", Draw.FONT, true);

        // letter rows
        var r = _rows[_mode];
        drawRow(dc, r[0], R1_X, R1_Y, R1_W);
        drawRow(dc, r[1], R2_X, R2_Y, R2_W);
        var modeLabel = (_mode == 0) ? "ABC" : ((_mode == 1) ? "123" : "abc");
        drawKey(dc, R3_X, R3_Y, R3_W, KH, modeLabel, Draw.FONT, false);
        drawRow(dc, r[2], R3_X + R3_W, R3_Y, R3_W);
        drawKey(dc, R3_X + 8 * R3_W, R3_Y, R3_W, KH, "<", KFONT, false);

        // bottom: Canned + space
        drawKey(dc, CND_X, BOT_Y, CND_W, BOT_H, "Cnd", Draw.FONT, false);
        drawKey(dc, SPC_X, BOT_Y, SPC_W, BOT_H, "space", Draw.FONT, false);

        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function drawRow(dc, chars, x0, y, kw) {
        var n = chars.length();
        for (var i = 0; i < n; i++) {
            drawKey(dc, x0 + i * kw, y, kw, KH, chars.substring(i, i + 1), KFONT, false);
        }
    }

    function drawKey(dc, x, y, w, h, label, font, accent) {
        var fh = dc.getFontHeight(font);
        if (accent) {
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_BLUE);
            dc.fillRoundedRectangle(x, y, w - 1, h - 1, 3);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, y, w - 1, h - 1, 3);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(x + w / 2, y + (h - fh) / 2, font, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function longestSuffix(dc, s, w) {
        var n = s.length();
        var start = 0;
        while (start < n && dc.getTextWidthInPixels(s.substring(start, n), Draw.FONT) > w) {
            start++;
        }
        return s.substring(start, n);
    }

    // ---------------------------------------------------------------- input

    function tapAt(x, y) {
        if (y >= BOX_Y && y < BOX_Y + BOX_H && x >= SEND_X && x < SEND_X + SEND_W) {
            send();
            return;
        }
        if (y >= BOT_Y && y < BOT_Y + BOT_H) {
            if (x >= CND_X && x < CND_X + CND_W) {
                openCanned();
            } else if (x >= SPC_X && x < SPC_X + SPC_W) {
                append(" ");
            }
            return;
        }
        var r = _rows[_mode];
        if (y >= R1_Y && y < R1_Y + KH) {
            keyIn(r[0], R1_X, R1_W, x);
        } else if (y >= R2_Y && y < R2_Y + KH) {
            keyIn(r[1], R2_X, R2_W, x);
        } else if (y >= R3_Y && y < R3_Y + KH) {
            if (x >= R3_X && x < R3_X + R3_W) {
                _mode = (_mode + 1) % 3;
                WatchUi.requestUpdate();
            } else if (x >= R3_X + 8 * R3_W && x < R3_X + 9 * R3_W) {
                backspace();
            } else {
                keyIn(r[2], R3_X + R3_W, R3_W, x);
            }
        }
    }

    function keyIn(chars, x0, kw, x) {
        if (x < x0) { return; }
        var i = (x - x0) / kw;
        if (i >= chars.length()) { return; }
        append(chars.substring(i, i + 1));
    }

    function append(s) {
        if (_text.length() >= MAX_LEN) {
            gModel.showToast("Max " + MAX_LEN + " chars");
            return;
        }
        _text = _text + s;
        WatchUi.requestUpdate();
    }

    function backspace() {
        if (_text.length() > 0) {
            _text = _text.substring(0, _text.length() - 1);
            WatchUi.requestUpdate();
        }
    }

    function send() {
        if (_text.length() == 0) {
            gModel.showToast("Nothing to send");
            return;
        }
        gLink.sendChannelText(_idx, _text);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    // Canned list over the keyboard; the current draft becomes its prefix,
    // so "@[name] " + canned works for replies.
    function openCanned() {
        var v = new CannedView(_idx, _text);
        WatchUi.pushView(v, new CannedDelegate(v), WatchUi.SLIDE_UP);
    }
}

class ComposeDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onTap(evt) {
        var c = evt.getCoordinates();
        _v.tapAt(c[0], c[1]);
        return true;
    }

    function onSelect() { _v.send(); return true; }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
