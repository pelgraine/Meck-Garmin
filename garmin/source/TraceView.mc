using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Timer;
using Toybox.Time;
using Toybox.Application;

// Trace: type a repeater chain as comma-separated hex hashes (e.g.
// 3601,2198,2665,2198,3601), Run, wait up to 30 s for per-hop SNRs.
// Hash width follows the tokens: 2 hex digits = 1 byte, 4 = 2 bytes.
class TraceView extends WatchUi.View {

    const BOX_X = 36;  const BOX_Y = 30;  const BOX_W = 168; const BOX_H = 24;
    const GX = 32;     const GY = 58;     const KW = 44;     const KH = 28;
    const TIMEOUT_S = 30;
    const KEY_LAST_PATH = "trace_path";

    var _path = "";
    var _keys;            // 5 rows x 4 columns; "Run" spans the last two cells
    var _timer;
    var _showResults = false;

    function initialize() {
        View.initialize();
        _timer = new Timer.Timer();
        _keys = [
            ["1", "2", "3", "a"],
            ["4", "5", "6", "b"],
            ["7", "8", "9", "c"],
            ["0", ",", "d", "e"],
            ["f", "<", "Run", "Run"]
        ];
        var saved = Application.Storage.getValue(KEY_LAST_PATH);
        if (saved != null) {
            _path = saved;
        }
    }

    function onShow() {
        _timer.start(method(:tick), 500, true);
    }

    function onHide() {
        _timer.stop();
    }

    function tick() {
        var t = gModel.trace;
        if (t != null && t.get(:state) == :running) {
            if (Time.now().value() - t.get(:sentAt) >= TIMEOUT_S) {
                t.put(:state, :timeout);
            }
            WatchUi.requestUpdate();
        }
    }

    // ---------------------------------------------------------------- drawing

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var fh = dc.getFontHeight(Draw.FONT);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.CX, 8, Draw.FONT, "Trace Path", Graphics.TEXT_JUSTIFY_CENTER);

        if (_showResults) {
            drawResults(dc);
            return;
        }

        // path box
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(BOX_X, BOX_Y, BOX_W, BOX_H, 4);
        var shown = tail(dc, _path + "_", BOX_W - 8);
        dc.drawText(BOX_X + 4, BOX_Y + (BOX_H - fh) / 2, Draw.FONT, shown, Graphics.TEXT_JUSTIFY_LEFT);

        // hex pad
        for (var r = 0; r < 5; r++) {
            for (var c = 0; c < 4; c++) {
                var label = _keys[r][c];
                var x = GX + c * KW;
                var y = GY + r * KH;
                var w = KW;
                if (label.equals("Run")) {
                    if (c == 3) { continue; }
                    w = KW * 2;
                }
                var accent = label.equals("Run");
                var kfh = dc.getFontHeight(Graphics.FONT_SMALL);
                if (accent) {
                    dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_BLUE);
                    dc.fillRoundedRectangle(x, y, w - 2, KH - 2, 3);
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                } else {
                    dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                    dc.drawRoundedRectangle(x, y, w - 2, KH - 2, 3);
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                }
                dc.drawText(x + w / 2, y + (KH - kfh) / 2, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function drawResults(dc) {
        var t = gModel.trace;
        var rowH = Draw.rowHeight(dc);
        var y = 30;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (t == null) {
            dc.drawText(Draw.CX, y + 20, Draw.FONT, "No trace yet", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var st = t.get(:state);
        if (st == :running) {
            var el = Time.now().value() - t.get(:sentAt);
            dc.drawText(Draw.CX, y, Draw.FONT, "Tracing... " + el + "s", Graphics.TEXT_JUSTIFY_CENTER);
            var barW = 140;
            var fill = barW * el / TIMEOUT_S;
            if (fill > barW) { fill = barW; }
            dc.drawRectangle(Draw.CX - barW / 2, y + rowH + 4, barW, 8);
            dc.fillRectangle(Draw.CX - barW / 2, y + rowH + 4, fill, 8);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX, 208, Draw.FONT, "Back: pad", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (st == :timeout) {
            dc.drawText(Draw.CX, y, Draw.FONT, "No result (30s)", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX, y + rowH, Draw.FONT, Draw.fitTo(dc, _path, Draw.W), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(Draw.CX, 208, Draw.FONT, "Start: Again", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        // done
        var hashes = t.get(:hashes);
        var snrs = t.get(:snrs);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.CX, y, Draw.FONT, "" + hashes.size() + " hops, " + t.get(:ms) + "ms", Graphics.TEXT_JUSTIFY_CENTER);
        y += rowH + 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < hashes.size() && y + rowH <= 196; i++) {
            var snr = (i < snrs.size()) ? snrs[i] : 0;
            dc.drawText(Draw.X + 8, y, Draw.FONT, "" + (i + 1) + ". " + hex(hashes[i]), Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(Draw.X + Draw.W - 8, y, Draw.FONT, snrText(snr), Graphics.TEXT_JUSTIFY_RIGHT);
            y += rowH;
        }
        if (y + rowH <= 206) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.X + 8, y, Draw.FONT, "Here", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(Draw.X + Draw.W - 8, y, Draw.FONT, snrText(t.get(:final)), Graphics.TEXT_JUSTIFY_RIGHT);
        }
        dc.drawText(Draw.CX, 208, Draw.FONT, "Start: Again", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function snrText(q) {
        // q is SNR*4; show one decimal
        var whole = q / 4;
        var frac = (q < 0 ? -q : q) % 4;
        var dec = (frac * 25);
        var s = "" + whole + "." + (dec / 10);
        if (q < 0 && whole == 0) { s = "-" + s; }
        return s + "dB";
    }

    function hex(ba) {
        var s = "";
        for (var i = 0; i < ba.size(); i++) {
            s = s + ba[i].format("%02x");
        }
        return s;
    }

    function tail(dc, s, w) {
        var n = s.length();
        var start = 0;
        while (start < n && dc.getTextWidthInPixels(s.substring(start, n), Draw.FONT) > w) {
            start++;
        }
        return s.substring(start, n);
    }

    // ---------------------------------------------------------------- input

    function tapAt(x, y) {
        if (_showResults) {
            return;
        }
        if (x < GX || y < GY) { return; }
        var c = (x - GX) / KW;
        var r = (y - GY) / KH;
        if (c > 3 || r > 4) { return; }
        var label = _keys[r][c];
        if (label.equals("<")) {
            if (_path.length() > 0) {
                _path = _path.substring(0, _path.length() - 1);
            }
        } else if (label.equals("Run")) {
            run();
            return;
        } else {
            if (_path.length() < 79) {
                _path = _path + label;
            }
        }
        WatchUi.requestUpdate();
    }

    // Parse "3601,2198,..." into bytes; all tokens must be 2 or 4 hex digits.
    function run() {
        var tokens = split(_path, ",");
        if (tokens.size() == 0) {
            gModel.showToast("Type a path first");
            return;
        }
        var bph = 0;
        var bytes = []b;
        for (var i = 0; i < tokens.size(); i++) {
            var tk = tokens[i];
            if (tk.length() == 0) { continue; }
            var w = (tk.length() == 4) ? 2 : ((tk.length() == 2) ? 1 : 0);
            if (w == 0 || (bph != 0 && w != bph)) {
                gModel.showToast("Bad hash: " + tk);
                return;
            }
            bph = w;
            var v = tk.toNumberWithBase(16);
            if (v == null) {
                gModel.showToast("Bad hash: " + tk);
                return;
            }
            if (bph == 2) {
                bytes = bytes.addAll([(v >> 8) & 0xFF, v & 0xFF]b);
            } else {
                bytes = bytes.addAll([v & 0xFF]b);
            }
        }
        if (bytes.size() == 0 || bytes.size() / bph > 16) {
            gModel.showToast("1 to 16 hops");
            return;
        }
        Application.Storage.setValue(KEY_LAST_PATH, _path);
        if (gLink.sendTrace(bytes, bph)) {
            _showResults = true;
            WatchUi.requestUpdate();
        }
    }

    function split(s, sep) {
        var out = [];
        var rest = s;
        var i = rest.find(sep);
        while (i != null) {
            out.add(rest.substring(0, i));
            rest = rest.substring(i + 1, rest.length());
            i = rest.find(sep);
        }
        out.add(rest);
        return out;
    }

    // Returns true if Back was consumed (results -> pad).
    function back() {
        if (_showResults) {
            _showResults = false;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function select() {
        run();
    }
}

class TraceDelegate extends WatchUi.BehaviorDelegate {
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

    function onSelect() { _v.select(); return true; }

    function onBack() {
        if (_v.back()) {
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
