using Toybox.WatchUi;
using Toybox.Graphics;

// Settings > Channel regions: the send region the watch applies per channel
// on a standard node (a Meck node keeps its own, so this screen is not
// offered there). One row per channel, the setting right-aligned in blue:
// "default" (node's own default), "all" (unscoped), or a region name.
// Start on a row opens the choice list for that channel.
class RegionView extends WatchUi.View {

    var _sel = 0;
    var _top = 0;
    var _rows = 1;
    var _y0 = 50;
    var _rowH = 18;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, "Channel regions", true);
        _rowH = Draw.rowHeight(dc);
        _rows = (196 - _y0) / _rowH;
        if (_rows < 1) { _rows = 1; }

        var chans = gModel.channels;
        if (chans.size() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX, _y0 + 20, Draw.FONT, "No channels", Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (_sel >= chans.size()) { _sel = (chans.size() > 0) ? chans.size() - 1 : 0; }
        if (_sel < _top) { _top = _sel; }
        if (_sel >= _top + _rows) { _top = _sel - _rows + 1; }

        for (var r = 0; r < _rows; r++) {
            var i = _top + r;
            if (i >= chans.size()) { break; }
            var y = _y0 + r * _rowH;
            var name = chans[i].get(:name);
            var label = gModel.regionLabel(chans[i].get(:idx));
            var labelW = dc.getTextWidthInPixels(label, Draw.FONT) + 6;
            if (labelW > Draw.W / 2) {
                label = Draw.ellipsize(dc, label, Draw.W / 2 - 6);
                labelW = dc.getTextWidthInPixels(label, Draw.FONT) + 6;
            }
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(Draw.X + 2, y, Draw.FONT, Draw.ellipsize(dc, name, Draw.W - 4 - labelW), Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor((i == _sel) ? Graphics.COLOR_BLACK : Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.X + Draw.W - 2, y, Draw.FONT, label, Graphics.TEXT_JUSTIFY_RIGHT);
        }
        Draw.footer(dc, "Start: change");
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function move(d) {
        var n = gModel.channels.size();
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
        if (r >= _rows || i >= gModel.channels.size()) { return -1; }
        return i;
    }

    function open() {
        if (_sel < gModel.channels.size()) {
            var idx = gModel.channels[_sel].get(:idx);
            var v = new RegionChoiceView(idx);
            WatchUi.pushView(v, new RegionChoiceDelegate(v), WatchUi.SLIDE_LEFT);
        }
    }
}

class RegionDelegate extends WatchUi.BehaviorDelegate {
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
            _v.open();
            return true;
        }
        return false;
    }

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
}

// The three choices for one channel. "Type a name" swaps this screen for
// the keyboard;
// the typed name is stored as is (a leading "#" is allowed; "!" private
// regions need a key the watch cannot derive, so they are refused).
class RegionChoiceView extends WatchUi.View {

    var _idx;
    var _sel = 0;
    var _y0 = 50;
    var _rowH = 18;
    var _items;

    function initialize(idx) {
        View.initialize();
        _idx = idx;
        _items = ["Node default", "All regions", "Type a name"];
        var r = gModel.regionFor(idx);
        if (r != null) {
            _sel = "*".equals(r) ? 1 : 2;
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, gModel.channelName(_idx), true);
        _rowH = Draw.rowHeight(dc);
        for (var i = 0; i < _items.size(); i++) {
            var y = _y0 + i * _rowH;
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(Draw.X + 2, y, Draw.FONT, _items[i], Graphics.TEXT_JUSTIFY_LEFT);
        }
        Draw.footer(dc, "Now: " + gModel.regionLabel(_idx));
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function move(d) {
        _sel = (_sel + d + _items.size()) % _items.size();
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        if (y < _y0) { return -1; }
        var i = (y - _y0) / _rowH;
        return (i < _items.size()) ? i : -1;
    }

    function activate() {
        if (_sel == 0) {
            gModel.setRegion(_idx, null);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (_sel == 1) {
            gModel.setRegion(_idx, "*");
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            var r = gModel.regionFor(_idx);
            var cv = new ComposeView(-1, (r != null && !"*".equals(r)) ? r : "");
            cv.title = "Region";
            cv.onDone = method(:gotName);
            // Replace this screen with the keyboard, so Send (which pops the
            // keyboard) lands back on the channel list in one step.
            WatchUi.switchToView(cv, new ComposeDelegate(cv), WatchUi.SLIDE_UP);
        }
    }

    // Called by the keyboard after it has popped itself; the channel list is
    // on screen by then. Spaces typed at either end (the Down key inserts
    // one) are dropped.
    function gotName(t) {
        while (t.length() > 0 && t.substring(0, 1).equals(" ")) {
            t = t.substring(1, t.length());
        }
        while (t.length() > 0 && t.substring(t.length() - 1, t.length()).equals(" ")) {
            t = t.substring(0, t.length() - 1);
        }
        if (t.length() == 0) {
            gModel.showToast("Nothing typed");
            return;
        }
        if (t.substring(0, 1).equals("!")) {
            gModel.showToast("Private regions unsupported");
            return;
        }
        gModel.setRegion(_idx, t);
    }
}

class RegionChoiceDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() { _v.move(1); return true; }
    function onPreviousPage() { _v.move(-1); return true; }
    function onKey(evt) {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _v.activate();
            return true;
        }
        return false;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onTap(evt) {
        var c = evt.getCoordinates();
        var i = _v.rowAt(c[1]);
        if (i >= 0) {
            _v._sel = i;
            _v.activate();
        }
        return true;
    }
}
