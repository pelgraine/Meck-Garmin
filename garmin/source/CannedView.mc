using Toybox.WatchUi;
using Toybox.Graphics;

// Canned messages, one per row, filling the screen (Meck Watch style).
// Selecting a row sends prefix + text on the channel and returns.
class CannedView extends WatchUi.View {

    var _idx;
    var _prefix;
    var _sel = 0;
    var _top = 0;
    var _rows = 1;
    var _y0 = 50;
    var _rowH = 18;

    function initialize(idx, prefix) {
        View.initialize();
        _idx = idx;
        _prefix = prefix;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var title = (_prefix.length() > 0) ? "Reply" : "Canned";
        if (_idx < 0) { title = "Canned (view)"; }
        _y0 = Draw.header(dc, title, true);
        _rowH = Draw.rowHeight(dc);
        _rows = (206 - _y0) / _rowH;
        if (_rows < 1) { _rows = 1; }

        var list = gModel.canned;
        if (list.size() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX, _y0 + 20, Draw.FONT, "No canned messages", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (_sel >= list.size()) { _sel = list.size() - 1; }
        if (_sel < _top) { _top = _sel; }
        if (_sel >= _top + _rows) { _top = _sel - _rows + 1; }

        for (var r = 0; r < _rows; r++) {
            var i = _top + r;
            if (i >= list.size()) { break; }
            var y = _y0 + r * _rowH;
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(Draw.X + 2, y, Draw.FONT, Draw.fitTo(dc, list[i], Draw.W - 4), Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function move(d) {
        var n = gModel.canned.size();
        if (n == 0) { return; }
        _sel = _sel + d;
        if (_sel < 0) { _sel = n - 1; }
        if (_sel >= n) { _sel = 0; }
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        if (y < _y0) { return -1; }
        var r = (y - _y0) / _rowH;
        var i = _top + r;
        if (r >= _rows || i >= gModel.canned.size()) { return -1; }
        return i;
    }

    function send() {
        var list = gModel.canned;
        if (_idx < 0) {
            gModel.showToast("Open a channel first");
            return;
        }
        if (_sel < 0 || _sel >= list.size()) { return; }
        gLink.sendChannelText(_idx, _prefix + list[_sel]);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class CannedDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() { _v.move(1); return true; }
    function onPreviousPage() { _v.move(-1); return true; }
    function onSelect() { _v.send(); return true; }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onTap(evt) {
        var c = evt.getCoordinates();
        var i = _v.rowAt(c[1]);
        if (i >= 0) {
            _v._sel = i;
            _v.send();
        }
        return true;
    }
}
