using Toybox.WatchUi;
using Toybox.Graphics;

// Settings > Canned messages (Meck Watch layout): five numbered slots, the
// same five for every standard node. A filled slot shows its text, an empty
// one "(tap to edit)". Start or a tap opens the keyboard pre-filled with the
// slot's text, capped at 40 characters; Send saves it, and sending an empty
// draft clears the slot. The keyboard returns here when it closes.
class CannedEditView extends WatchUi.View {

    const MAX_CHARS = 40;

    var _sel = 0;
    var _y0 = 50;
    var _rowH = 18;
    var _editing = -1;   // slot being edited while the keyboard is open

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, "Canned messages", true);
        _rowH = Draw.rowHeight(dc);
        var s = gModel.slots();
        for (var i = 0; i < s.size(); i++) {
            var y = _y0 + i * _rowH;
            var empty = (s[i].length() == 0);
            var text = (i + 1) + "  " + (empty ? "(tap to edit)" : s[i]);
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(empty ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(empty ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(Draw.X + 2, y, Draw.FONT, Draw.fitTo(dc, text, Draw.W - 4), Graphics.TEXT_JUSTIFY_LEFT);
        }
        Draw.footer(dc, "Start: edit");
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function move(d) {
        var n = gModel.slots().size();
        _sel = (_sel + d + n) % n;
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        if (y < _y0) { return -1; }
        var i = (y - _y0) / _rowH;
        return (i < gModel.slots().size()) ? i : -1;
    }

    function edit() {
        _editing = _sel;
        var cv = new ComposeView(-1, gModel.slots()[_sel]);
        cv.title = "Canned " + (_sel + 1);
        cv.maxLen = MAX_CHARS;
        cv.allowEmpty = true;
        cv.onDone = method(:gotText);
        WatchUi.pushView(cv, new ComposeDelegate(cv), WatchUi.SLIDE_UP);
    }

    // Called by the keyboard after it has popped itself; this list is on
    // screen again. Empty text clears the slot.
    function gotText(t) {
        if (_editing < 0) { return; }
        gModel.setSlot(_editing, t);
        _editing = -1;
    }
}

class CannedEditDelegate extends WatchUi.BehaviorDelegate {
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
            _v.edit();
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
            _v.edit();
        }
        return true;
    }
}
