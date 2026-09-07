using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Timer;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Channel view in the Meck Watch style: one line per message (incoming cut
// at the right edge, sent right-aligned with "..."), tap a line to marquee
// it, hold a line for the path overlay, bar at the bottom for a canned reply.
class ChannelView extends WatchUi.View {

    const BAR_X = 48;
    const BAR_Y = 190;
    const BAR_W = 144;
    const BAR_H = 26;
    const LIST_BOTTOM = 186;
    const TICK_GAP = 24;      // pixels between the two marquee copies

    var _idx;
    var _sel = -1;            // selected message (absolute index), -1 = none
    var _hist = 0;            // messages hidden below the window (history depth)
    var _start = 0;           // first message drawn
    var _shown = 0;           // messages drawn
    var _rows = 1;
    var _y0 = 50;
    var _rowH = 18;
    var _tick = -1;           // message index being marqueed, -1 = none
    var _tickOff = 0;
    var _tickW = 0;
    var _overlay = null;      // message dict in the overlay, or null
    var _hot = null;          // [x, y, w, h] of the overlay's action hotspot

    function initialize(idx) {
        View.initialize();
        _idx = idx;
        gModel.clearUnread(idx);
    }

    function onShow() {
        gModel.clearUnread(_idx);
    }

    function onHide() {
        stopTicker();
    }

    // ---------------------------------------------------------------- drawing

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, gModel.channelName(_idx), true);
        _rowH = Draw.rowHeight(dc);
        _rows = (LIST_BOTTOM - _y0) / _rowH;
        if (_rows < 1) { _rows = 1; }

        var msgs = gModel.messagesFor(_idx);
        var n = msgs.size();
        if (_hist > n - 1) { _hist = (n > 0) ? n - 1 : 0; }
        if (_hist < 0) { _hist = 0; }
        var end = n - _hist;
        _start = end - _rows;
        if (_start < 0) { _start = 0; }
        _shown = end - _start;

        if (_hist > 0) {
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX + 60, Draw.HEAD_Y, Draw.FONT, "-" + _hist, Graphics.TEXT_JUSTIFY_RIGHT);
        }

        for (var r = 0; r < _shown; r++) {
            var i = _start + r;
            var y = _y0 + r * _rowH;
            var m = msgs[i];
            var line = lineText(m);
            var selected = (i == _sel);
            if (selected) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            if (i == _tick) {
                _tickW = dc.getTextWidthInPixels(line, Draw.FONT);
                dc.setClip(Draw.X, y, Draw.W, _rowH);
                dc.drawText(Draw.X - _tickOff, y, Draw.FONT, line, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(Draw.X - _tickOff + _tickW + TICK_GAP, y, Draw.FONT, line, Graphics.TEXT_JUSTIFY_LEFT);
                dc.clearClip();
            } else if (m.get(:sent)) {
                dc.drawText(Draw.X + Draw.W, y, Draw.FONT, Draw.ellipsize(dc, line, Draw.W), Graphics.TEXT_JUSTIFY_RIGHT);
            } else {
                dc.drawText(Draw.X, y, Draw.FONT, Draw.fitTo(dc, line, Draw.W), Graphics.TEXT_JUSTIFY_LEFT);
            }
        }

        // compose bar; selected (via Down past the newest message) = inverted
        var barSel = (_sel == n);
        if (barSel) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
            dc.fillRectangle(BAR_X, BAR_Y, BAR_W, BAR_H);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(BAR_X, BAR_Y, BAR_W, BAR_H);
        }
        dc.drawText(BAR_X + 6, BAR_Y + (BAR_H - dc.getFontHeight(Draw.FONT)) / 2, Draw.FONT, "Tap to compose", Graphics.TEXT_JUSTIFY_LEFT);

        if (_overlay != null) {
            drawOverlay(dc, _overlay);
        }
        if (gModel.toast != null) {
            drawToast(dc, gModel.toast);
        }
    }

    static function drawToastStatic(dc, t) {
        var fh = dc.getFontHeight(Draw.FONT);
        var tw = dc.getTextWidthInPixels(t, Draw.FONT);
        var w = tw + 24;
        var h = fh + 12;
        var x = Draw.CX - w / 2;
        var y = 120 - h / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRoundedRectangle(x, y, w, h, 4);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, w, h, 4);
        dc.drawText(Draw.CX, y + 6, Draw.FONT, t, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Meck-style toast: boxed text centred on the screen.
    function drawToast(dc, t) {
        var fh = dc.getFontHeight(Draw.FONT);
        var tw = dc.getTextWidthInPixels(t, Draw.FONT);
        var w = tw + 24;
        var h = fh + 12;
        var x = Draw.CX - w / 2;
        var y = 120 - h / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRoundedRectangle(x, y, w, h, 4);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, w, h, 4);
        dc.drawText(Draw.CX, y + 6, Draw.FONT, t, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function lineText(m) {
        var s = m.get(:sender);
        if (s != null && s.length() > 0) {
            return s + ": " + m.get(:text);
        }
        return m.get(:text);
    }

    // Meck Watch path overlay: blue rounded box, "N hops, B-byte", "Rx: time",
    // the hop hashes wrapped by whole tokens, region bottom-left, action
    // bottom-right. Sent messages show Heard-by instead of the hop list.
    function drawOverlay(dc, m) {
        var bx = 36;
        var by = 58;
        var bw = 168;
        var bh = 134;
        var fh = dc.getFontHeight(Draw.FONT);
        var lh = fh + 1;
        var ix = bx + 6;
        var iw = bw - 12;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRoundedRectangle(bx, by, bw, bh, 6);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(bx, by, bw, bh, 6);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var y = by + 4;
        var bph = gModel.bph;
        var hops = m.get(:hops);
        var l1;
        if (m.get(:sent)) {
            var heard = m.get(:heard);
            l1 = (heard == null) ? "Sent, heard by: ?" : ("Heard by " + heard.get(:hashes).size() + ", " + heard.get(:repeats) + " rpt");
        } else if (hops == 0xFF) {
            l1 = "Direct";
        } else {
            l1 = "" + (hops / bph) + " hops, " + bph + "-byte";
        }
        dc.drawText(ix, y, Draw.FONT, Draw.fitTo(dc, l1, iw), Graphics.TEXT_JUSTIFY_LEFT);
        y += lh;
        dc.drawText(ix, y, Draw.FONT, "Rx: " + fmtTime(m.get(:rx)), Graphics.TEXT_JUSTIFY_LEFT);
        y += lh;

        var tokens = [];
        if (m.get(:sent)) {
            var heard2 = m.get(:heard);
            if (heard2 != null) {
                var hs = heard2.get(:hashes);
                var ss = heard2.get(:snrs);
                for (var k = 0; k < hs.size(); k++) {
                    var snr = (k < ss.size()) ? ss[k] : 0;
                    tokens.add(hex(hs[k]) + " " + (snr / 4) + "dB");
                }
            }
        } else {
            var path = m.get(:path);
            if (path != null) {
                for (var p = 0; p + bph <= path.size(); p += bph) {
                    tokens.add(hex(path.slice(p, p + bph)));
                }
            }
        }
        var maxY = by + bh - lh - 4;   // leave the bottom line for region/action
        var line = "";
        for (var t = 0; t < tokens.size() && y < maxY; t++) {
            var sep = (line.length() > 0) ? "," : "";
            var trial = line + sep + tokens[t];
            if (dc.getTextWidthInPixels(trial, Draw.FONT) <= iw) {
                line = trial;
            } else {
                dc.drawText(ix, y, Draw.FONT, line, Graphics.TEXT_JUSTIFY_LEFT);
                y += lh;
                line = tokens[t];
            }
        }
        if (line.length() > 0 && y < maxY) {
            dc.drawText(ix, y, Draw.FONT, Draw.fitTo(dc, line, iw), Graphics.TEXT_JUSTIFY_LEFT);
        }

        var bottomY = by + bh - lh - 2;
        var region = gModel.scopeName(m.get(:scope));
        if (region != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(ix, bottomY, Draw.FONT, Draw.fitTo(dc, region, iw - 70), Graphics.TEXT_JUSTIFY_LEFT);
        }
        var action = m.get(:sent) ? "[Again]" : "[Reply]";
        var aw = dc.getTextWidthInPixels(action, Draw.FONT);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx + bw - 6, bottomY, Draw.FONT, action, Graphics.TEXT_JUSTIFY_RIGHT);
        _hot = [bx + bw - 6 - aw - 6, bottomY - 4, aw + 12, lh + 8];
    }

    function hex(ba) {
        var s = "";
        for (var i = 0; i < ba.size(); i++) {
            s = s + ba[i].format("%02x");
        }
        return s;
    }

    function fmtTime(epoch) {
        if (epoch == null || epoch == 0) {
            return "?";
        }
        var g = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_MEDIUM);
        return "" + g.day + " " + g.month + " " + g.hour.format("%02d") + ":" + g.min.format("%02d");
    }

    // ---------------------------------------------------------------- marquee

    function startTicker(i) {
        _tick = i;
        _tickOff = 0;
        gSched.every(40, "marquee", method(:onTick));
        WatchUi.requestUpdate();
    }

    function stopTicker() {
        gSched.cancel("marquee");
        _tick = -1;
        _tickOff = 0;
        WatchUi.requestUpdate();
    }

    function onTick() {
        if (_tickW <= Draw.W) {
            _tickOff = 0;       // fits: nothing to scroll
            return;
        }
        _tickOff += 6;   // 3x the original speed
        if (_tickOff > _tickW + TICK_GAP) {
            _tickOff = 0;
        }
        WatchUi.requestUpdate();
    }

    // ---------------------------------------------------------------- input

    function rowAt(y) {
        if (y < _y0) { return -1; }
        var r = (y - _y0) / _rowH;
        if (r >= _shown) { return -1; }
        return _start + r;
    }

    function inBar(x, y) {
        return x >= BAR_X && x < BAR_X + BAR_W && y >= BAR_Y && y < BAR_Y + BAR_H;
    }

    function inHot(x, y) {
        if (_hot == null) { return false; }
        return x >= _hot[0] && x < _hot[0] + _hot[2] && y >= _hot[1] && y < _hot[1] + _hot[3];
    }

    function tapAt(x, y) {
        if (_overlay != null) {
            if (inHot(x, y)) {
                doAction();
            } else {
                closeOverlay();
            }
            return;
        }
        if (inBar(x, y)) {
            openCompose("");
            return;
        }
        var i = rowAt(y);
        if (i < 0) { return; }
        _sel = i;
        if (_tick == i) {
            stopTicker();
        } else {
            startTicker(i);
        }
    }

    function holdAt(x, y) {
        if (_overlay != null) { return; }
        var i = rowAt(y);
        if (i < 0) { return; }
        _sel = i;
        openOverlay(gModel.messagesFor(_idx)[i]);
    }

    // Selection runs over the messages and then the compose bar (index n).
    function move(d) {
        if (_overlay != null) { return; }
        var n = gModel.messagesFor(_idx).size();
        if (_sel < 0) {
            _sel = (n > 0) ? n - 1 - _hist : n;
        } else {
            _sel = _sel + d;
        }
        if (_sel < 0) { _sel = 0; }
        if (_sel > n) { _sel = n; }
        if (_sel < n) {
            // keep a message selection inside the window
            var end = n - _hist;
            if (_sel >= end) { _hist = n - 1 - _sel; }
            if (_sel < end - _rows) { _hist = n - _sel - _rows; }
            if (_hist < 0) { _hist = 0; }
        } else {
            _hist = 0;   // bar selected: show the newest messages
        }
        // Highlighting a line marquees it (long lines scroll, short ones stay).
        if (_sel < n) {
            startTicker(_sel);
        } else {
            stopTicker();
        }
        WatchUi.requestUpdate();
    }

    function page(d) {
        if (_overlay != null) { return; }
        _hist = _hist + d * _rows;
        if (_hist < 0) { _hist = 0; }
        WatchUi.requestUpdate();
    }

    // Start: on the overlay, its action; on a message, toggle the marquee
    // (same as tapping the line); on the bar, open the canned list.
    function select() {
        var n = gModel.messagesFor(_idx).size();
        if (_overlay != null) {
            doAction();
        } else if (_sel >= 0 && _sel < n) {
            if (_tick == _sel) {
                stopTicker();
            } else {
                startTicker(_sel);
            }
        } else {
            openCompose("");
        }
    }

    // Menu (hold Up): path overlay for the highlighted message, like the
    // watch's physical button.
    function menu() {
        var n = gModel.messagesFor(_idx).size();
        if (_overlay != null) { return; }
        if (_sel >= 0 && _sel < n) {
            openOverlay(gModel.messagesFor(_idx)[_sel]);
        } else if (_sel == n) {
            openCanned("");   // bar highlighted: straight to the canned list
        }
    }

    // Returns true if the back press was consumed (overlay closed).
    function back() {
        if (_overlay != null) {
            closeOverlay();
            return true;
        }
        return false;
    }

    function openOverlay(m) {
        stopTicker();
        _overlay = m;
        if (m.get(:sent)) {
            gLink.refreshSentTrack();
        }
        WatchUi.requestUpdate();
    }

    function closeOverlay() {
        _overlay = null;
        _hot = null;
        WatchUi.requestUpdate();
    }

    function doAction() {
        var m = _overlay;
        closeOverlay();
        if (m == null) { return; }
        if (m.get(:sent)) {
            gLink.sendChannelText(_idx, m.get(:text));   // Send Again
        } else {
            openCompose("@[" + m.get(:sender) + "] ");
        }
    }

    function openCanned(prefix) {
        stopTicker();
        var v = new CannedView(_idx, prefix);
        WatchUi.pushView(v, new CannedDelegate(v), WatchUi.SLIDE_UP);
    }

    function openCompose(prefix) {
        stopTicker();
        var v = new ComposeView(_idx, prefix);
        WatchUi.pushView(v, new ComposeDelegate(v), WatchUi.SLIDE_UP);
    }
}

class ChannelDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() { _v.move(1); return true; }
    function onPreviousPage() { _v.move(-1); return true; }
    // Start key read directly: claiming onSelect would also swallow screen taps.
    function onKey(evt) {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _v.select();
            return true;
        }
        return false;
    }
    function onMenu() { _v.menu(); return true; }

    function onBack() {
        if (_v.back()) {
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onTap(evt) {
        var c = evt.getCoordinates();
        _v.tapAt(c[0], c[1]);
        return true;
    }

    function onHold(evt) {
        var c = evt.getCoordinates();
        _v.holdAt(c[0], c[1]);
        return true;
    }

    function onSwipe(evt) {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_UP) { _v.page(1); return true; }
        if (d == WatchUi.SWIPE_DOWN) { _v.page(-1); return true; }
        return false;
    }
}
