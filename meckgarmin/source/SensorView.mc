using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Sensor telemetry (Favourites > a sensor). Nothing is requested until
// Start is pressed; each press asks the sensor once. Readings show one per
// row as "Ch 10: 76%", Up/Down to scroll.
class SensorView extends WatchUi.View {

    var _top = 0;
    var _rows = 1;
    var _y0 = 50;
    var _rowH = 18;

    function initialize(e) {
        View.initialize();
        gModel.telem = {:pubkey => e.get(:pubkey), :name => e.get(:name), :state => :idle,
                        :rows => [], :at => 0, :sentAt => 0, :waitS => 30};
    }

    function onShow() {
        gSched.every(500, "telem", method(:tick));
    }

    function onHide() {
        gSched.cancel("telem");
    }

    // No reply within the node's estimate (plus 5 s; 30 s before it is known).
    function tick() {
        var t = gModel.telem;
        if (t != null && t.get(:state) == :pending
                && Time.now().value() - t.get(:sentAt) >= t.get(:waitS)) {
            t.put(:state, :timeout);
            WatchUi.requestUpdate();
        }
    }

    function refresh() {
        var t = gModel.telem;
        if (t == null || t.get(:state) == :pending) { return; }
        if (gLink.requestTelemetry(t.get(:pubkey))) {
            t.put(:state, :pending);
            t.put(:sentAt, Time.now().value());
            t.put(:waitS, 30);
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var t = gModel.telem;
        _y0 = Draw.header(dc, (t != null) ? t.get(:name) : "Sensor", true);
        _rowH = Draw.rowHeight(dc);
        if (t == null) { return; }

        var st = t.get(:state);
        var status;
        if (st == :pending) { status = "Requesting..."; }
        else if (st == :timeout) { status = "No reply"; }
        else if (st == :error) { status = "Request failed"; }
        else if (st == :ok) { status = "Updated " + clock(t.get(:at)); }
        else { status = "Start: request"; }
        dc.setColor((st == :ok) ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        Draw.text(dc, Draw.X, _y0, Draw.fitTo(dc, status, Draw.W), Graphics.TEXT_JUSTIFY_LEFT);

        var list = t.get(:rows);
        var y0 = _y0 + _rowH + 2;
        _rows = (200 - y0) / _rowH;
        if (_rows < 1) { _rows = 1; }
        if (_top > list.size() - _rows) { _top = list.size() - _rows; }
        if (_top < 0) { _top = 0; }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var r = 0; r < _rows; r++) {
            var i = _top + r;
            if (i >= list.size()) { break; }
            Draw.text(dc, Draw.X + 2, y0 + r * _rowH, Draw.fitTo(dc, list[i], Draw.W - 4), Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (st == :ok || st == :timeout || st == :error) {
            Draw.footer(dc, "Start: refresh");
        }
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function clock(ts) {
        var g = Gregorian.info(new Time.Moment(ts), Time.FORMAT_SHORT);
        return g.hour.format("%02d") + ":" + g.min.format("%02d");
    }

    function move(d) {
        var t = gModel.telem;
        if (t == null) { return; }
        var max = t.get(:rows).size() - _rows;
        _top += d;
        if (_top > max) { _top = max; }
        if (_top < 0) { _top = 0; }
        WatchUi.requestUpdate();
    }
}

class SensorDelegate extends WatchUi.BehaviorDelegate {
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
            _v.refresh();
            return true;
        }
        return false;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onTap(evt) {
        return true;
    }
}
