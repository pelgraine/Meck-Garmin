using Toybox.WatchUi;
using Toybox.Graphics;

// Channel picker: header "Channels", one row per channel with the unread
// count right-aligned in blue, selected row filled green with dark text.
class PickerView extends WatchUi.View {

    var _sel = 0;        // selected channel (index into gModel.channels)
    var _top = 0;        // first visible row
    var _rows = 1;       // rows that fit
    var _y0 = 50;
    var _rowH = 18;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, "Channels", true);
        _rowH = Draw.rowHeight(dc);
        _rows = (196 - _y0) / _rowH;
        if (_rows < 1) { _rows = 1; }

        var chans = gModel.channels;
        if (chans.size() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX, _y0 + 20, Draw.FONT, gModel.connected ? "Loading..." : "No node yet", Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (_sel >= chans.size()) { _sel = (chans.size() > 0) ? chans.size() - 1 : 0; }
        if (_sel < _top) { _top = _sel; }
        if (_sel >= _top + _rows) { _top = _sel - _rows + 1; }

        for (var r = 0; r < _rows; r++) {
            var i = _top + r;
            if (i >= chans.size()) { break; }
            var y = _y0 + r * _rowH;
            var name = chans[i].get(:name);
            var n = gModel.unreadFor(chans[i].get(:idx));
            var badge = (n > 0) ? ("" + n) : "";
            var badgeW = (n > 0) ? dc.getTextWidthInPixels(badge, Draw.FONT) + 6 : 0;
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_GREEN);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(Draw.X + 2, y, Draw.FONT, Draw.ellipsize(dc, name, Draw.W - 4 - badgeW), Graphics.TEXT_JUSTIFY_LEFT);
            if (n > 0) {
                dc.setColor((i == _sel) ? Graphics.COLOR_BLACK : Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(Draw.X + Draw.W - 2, y, Draw.FONT, badge, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }
        Draw.footer(dc, gModel.status);
    }

    function move(d) {
        var n = gModel.channels.size();
        if (n == 0) { return; }
        _sel = _sel + d;
        if (_sel < 0) { _sel = n - 1; }        // wraps, like the watch's button move
        if (_sel >= n) { _sel = 0; }
        WatchUi.requestUpdate();
    }

    function page(d) {
        var n = gModel.channels.size();
        if (n == 0) { return; }
        _top = _top + d * _rows;
        if (_top < 0) { _top = 0; }
        if (_top > n - 1) { _top = n - 1; }
        if (_sel < _top) { _sel = _top; }
        if (_sel >= _top + _rows) { _sel = _top + _rows - 1; }
        if (_sel >= n) { _sel = n - 1; }
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        if (y < _y0) { return -1; }
        var r = (y - _y0) / _rowH;
        var i = _top + r;
        if (r >= _rows || i >= gModel.channels.size()) { return -1; }
        return i;
    }

    function open() {
        if (_sel < gModel.channels.size()) {
            var idx = gModel.channels[_sel].get(:idx);
            var v = new ChannelView(idx);
            WatchUi.pushView(v, new ChannelDelegate(v), WatchUi.SLIDE_LEFT);
        }
    }
}

class PickerDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() { _v.move(1); return true; }
    function onPreviousPage() { _v.move(-1); return true; }
    function onSelect() { _v.open(); return true; }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onTap(evt) {
        var c = evt.getCoordinates();
        var i = _v.rowAt(c[1]);
        if (i >= 0) {
            _v._sel = i;
            _v.open();
        }
        return true;
    }

    function onSwipe(evt) {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_UP) { _v.page(1); return true; }
        if (d == WatchUi.SWIPE_DOWN) { _v.page(-1); return true; }
        return false;
    }
}
