using Toybox.WatchUi;
using Toybox.Graphics;

// Settings > Radio (Meck-P4 only): the node's radio preset. The current one
// shows "on" right-aligned in blue; Start on a row applies it at once.
class RadioView extends WatchUi.View {

    var _sel = 0;
    var _y0 = 50;
    var _rowH = 18;
    var _presets;

    function initialize() {
        View.initialize();
        _presets = gModel.radioPresets();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, "Radio", true);
        _rowH = Draw.rowHeight(dc);
        for (var i = 0; i < _presets.size(); i++) {
            var y = _y0 + i * _rowH;
            var label = gModel.radioIs(_presets[i]) ? "on" : "";
            var labelW = Draw.width(dc, label) + 6;
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            Draw.text(dc, Draw.X + 2, y, Draw.ellipsize(dc, _presets[i].get(:name), Draw.W - 4 - labelW), Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor((i == _sel) ? Graphics.COLOR_BLACK : Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            Draw.text(dc, Draw.X + Draw.W - 2, y, label, Graphics.TEXT_JUSTIFY_RIGHT);
        }
        Draw.footer(dc, "Start: apply");
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function move(d) {
        var n = _presets.size();
        _sel = (_sel + d + n) % n;
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        if (y < _y0) { return -1; }
        var i = (y - _y0) / _rowH;
        return (i < _presets.size()) ? i : -1;
    }

    function apply() {
        if (!gModel.isP4()) {
            gModel.showToast("Not connected");
            return;
        }
        gModel.showToast("Applying...");
        gLink.setRadio(gModel.radioPresets()[_sel]);
    }
}

class RadioDelegate extends WatchUi.BehaviorDelegate {
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
            _v.apply();
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
            _v.apply();
        }
        return true;
    }
}
