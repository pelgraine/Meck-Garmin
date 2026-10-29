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
    const R3_X = 21;  const R3_W = 22;   // 7 letter keys, y 134..170 (x 43..197)
    const MODE_X = 13; const MODE_W = 30; // mode key, widened out to the circle edge
    const DEL_X = 197; const DEL_W = 30;  // delete key, likewise
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
    var onDone = null;    // when set, Send hands the text to this Method instead of the channel
    var maxLen;           // length cap for this use (MAX_LEN unless set; canned slots set 40)
    var allowEmpty = false; // with onDone: Send on an empty draft is allowed (clears a canned slot)
    var title = null;     // when set, shown instead of the channel name
    var _rows;

    function initialize(idx, prefix) {
        View.initialize();
        _idx = idx;
        _prefix = prefix;
        _text = prefix;
        maxLen = MAX_LEN;
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
        var ttl = (title != null) ? title : gModel.channelName(_idx);
        dc.drawText(Draw.CX, 8, Draw.FONT, Draw.fitTo(dc, ttl, 84), Graphics.TEXT_JUSTIFY_CENTER);

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
        drawKey(dc, MODE_X, R3_Y, MODE_W, KH, modeLabel, Draw.FONT, false);
        drawRow(dc, r[2], R3_X + R3_W, R3_Y, R3_W);
        drawKey(dc, DEL_X, R3_Y, DEL_W, KH, "<", KFONT, false);

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
            if (x >= MODE_X && x < MODE_X + MODE_W) {
                _mode = (_mode + 1) % 3;
                WatchUi.requestUpdate();
            } else if (x >= DEL_X && x < DEL_X + DEL_W) {
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
        if (_text.length() >= maxLen) {
            gModel.showToast("Max " + maxLen + " chars");
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
        if (_text.length() == 0 && !(allowEmpty && onDone != null)) {
            gModel.showToast("Nothing to send");
            return;
        }
        if (onDone != null) {
            var t = _text;
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            onDone.invoke(t);
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

    // Start key read directly: claiming onSelect would also swallow screen taps.
    function onKey(evt) {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _v.send();
            return true;
        }
        return false;
    }

    function onPreviousPage() { _v.openCanned(); return true; }
    function onNextPage() { _v.append(" "); return true; }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
