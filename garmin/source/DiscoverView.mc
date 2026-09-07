using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Timer;

// Discover: the node's DiscoveryScreen on the watch. Opening it starts a
// scan if none has run; while the scan is active the list is polled once a
// second. Rows: type letter, name, then SNR (live response) or hop count
// (cached) with "[+]" when the node already has it as a contact.
class DiscoverView extends WatchUi.View {

    var _sel = 0;
    var _top = 0;
    var _rows = 1;
    var _y0 = 50;
    var _rowH = 18;
    var _timer;
    var _started = false;

    function initialize() {
        View.initialize();
        _timer = new Timer.Timer();
    }

    function onShow() {
        if (!_started && gModel.discovered.size() == 0 && !gModel.discoverActive) {
            _started = true;
            gLink.discoverStart();
        }
        _timer.start(method(:tick), 1000, true);
    }

    function onHide() {
        _timer.stop();
    }

    function tick() {
        if (gModel.discoverActive) {
            gLink.discoverPoll();
        }
        WatchUi.requestUpdate();
    }

    function rescan() {
        _sel = 0;
        _top = 0;
        gLink.discoverStart();
        WatchUi.requestUpdate();
    }

    static function typeChar(t) {
        if (t == 1) { return "C"; }   // chat
        if (t == 2) { return "R"; }   // repeater
        if (t == 3) { return "S"; }   // room
        if (t == 4) { return "N"; }   // sensor
        return "?";
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, "Discover", true);
        _rowH = Draw.rowHeight(dc);

        // scan status line (green, like the node)
        var n = gModel.discoverCount;
        var st = gModel.discoverActive ? ("Scanning... " + n + " found") : ("Scan done: " + n + " found");
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.X, _y0, Draw.FONT, Draw.fitTo(dc, st, Draw.W), Graphics.TEXT_JUSTIFY_LEFT);
        var listY = _y0 + _rowH;
        _rows = (196 - listY) / _rowH;
        if (_rows < 1) { _rows = 1; }

        var list = gModel.discovered;
        if (list.size() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX, listY + 12, Draw.FONT, gModel.discoverActive ? "Listening for" : "No nodes found", Graphics.TEXT_JUSTIFY_CENTER);
            if (gModel.discoverActive) {
                dc.drawText(Draw.CX, listY + 12 + _rowH, Draw.FONT, "adverts...", Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
        if (_sel >= list.size()) { _sel = (list.size() > 0) ? list.size() - 1 : 0; }
        if (_sel < _top) { _top = _sel; }
        if (_sel >= _top + _rows) { _top = _sel - _rows + 1; }

        for (var r = 0; r < _rows; r++) {
            var i = _top + r;
            if (i >= list.size()) { break; }
            var e = list[i];
            if (e == null) { continue; }
            var y = listY + r * _rowH;
            var selected = (i == _sel);
            if (selected) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            var prefix = (selected ? ">" : " ") + typeChar(e.get(:type)) + " ";
            var right;
            if (e.get(:snr) != 0) {
                right = "" + (e.get(:snr) / 4) + "dB";
            } else {
                right = "" + (e.get(:hops) & 63) + "h";
            }
            if (e.get(:known)) {
                right = right + " [+]";
            }
            var rw = dc.getTextWidthInPixels(right, Draw.FONT) + 4;
            var pw = dc.getTextWidthInPixels(prefix, Draw.FONT);
            dc.drawText(Draw.X, y, Draw.FONT, prefix, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(Draw.X + pw, y, Draw.FONT, Draw.ellipsize(dc, e.get(:name), Draw.W - pw - rw), Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(Draw.X + Draw.W, y, Draw.FONT, right, Graphics.TEXT_JUSTIFY_RIGHT);
        }

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.CX, 208, Draw.FONT, "Hold: Rescan", Graphics.TEXT_JUSTIFY_CENTER);
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function move(d) {
        var n = gModel.discovered.size();
        if (n == 0) { return; }
        _sel = _sel + d;
        if (_sel < 0) { _sel = 0; }
        if (_sel > n - 1) { _sel = n - 1; }
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        var listY = _y0 + _rowH;
        if (y < listY) { return -1; }
        var r = (y - listY) / _rowH;
        var i = _top + r;
        if (r >= _rows || i >= gModel.discovered.size()) { return -1; }
        return i;
    }
}

class DiscoverDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() { _v.move(1); return true; }
    function onPreviousPage() { _v.move(-1); return true; }
    function onMenu() { _v.rescan(); return true; }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onTap(evt) {
        var c = evt.getCoordinates();
        var i = _v.rowAt(c[1]);
        if (i >= 0) {
            _v._sel = i;
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onHold(evt) {
        _v.rescan();
        return true;
    }
}
