using Toybox.WatchUi;
using Toybox.Graphics;

// Node list: shown when the app starts and from Settings > Switch node.
// Rows are the MeshCore nodes heard while scanning, then "Scan again".
// Start (or a tap) on a node connects to it; that node is then the only one
// the watch reconnects to until the app closes or Switch node is used.
class NodeListView extends WatchUi.View {

    var _sel = 0;
    var _top = 0;
    var _rows = 1;
    var _y0 = 50;
    var _rowH = 18;
    var _atStart;      // true = the app's first screen (pick goes to Home)

    function initialize(atStart) {
        View.initialize();
        _atStart = atStart;
    }

    function count() {
        return gLink.foundNodes().size() + 1;   // + "Scan again"
    }

    function labelFor(i) {
        var nodes = gLink.foundNodes();
        if (i >= nodes.size()) { return "Scan again"; }
        var nm = nodes[i].getDeviceName();
        return (nm == null) ? "(no name)" : nm;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, "Nodes", true);
        _rowH = Draw.rowHeight(dc);
        var n = count();
        if (_sel >= n) { _sel = n - 1; }
        _rows = (196 - _y0) / _rowH;
        if (_rows < 1) { _rows = 1; }
        if (_sel < _top) { _top = _sel; }
        if (_sel >= _top + _rows) { _top = _sel - _rows + 1; }
        for (var r = 0; r < _rows; r++) {
            var i = _top + r;
            if (i >= n) { break; }
            var y = _y0 + r * _rowH;
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            Draw.text(dc, Draw.X + 2, y, Draw.ellipsize(dc, labelFor(i), Draw.W - 4), Graphics.TEXT_JUSTIFY_LEFT);
        }
        Draw.footer(dc, gModel.status);
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function move(d) {
        var n = count();
        _sel = (_sel + d + n) % n;
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        if (y < _y0) { return -1; }
        var r = (y - _y0) / _rowH;
        var i = _top + r;
        return (r < _rows && i < count()) ? i : -1;
    }

    function activate() {
        var nodes = gLink.foundNodes();
        if (_sel >= nodes.size()) {
            _sel = 0;
            _top = 0;
            gLink.rescanList();
            return;
        }
        gLink.pickNode(nodes[_sel]);
        if (_atStart) {
            var hv = new HomeView();
            WatchUi.switchToView(hv, new HomeDelegate(hv), WatchUi.SLIDE_LEFT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}

class NodeListDelegate extends WatchUi.BehaviorDelegate {
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
            _v.activate();
            return true;
        }
        return false;
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
