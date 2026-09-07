using Toybox.WatchUi;
using Toybox.Graphics;

// Node: what the watch knows about the node and the link.
class NodeView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var y = Draw.header(dc, "Node", true);
        var rowH = Draw.rowHeight(dc);
        var lines = [
            (gModel.nodeName.length() > 0) ? gModel.nodeName : "(no node)",
            "Link: " + gModel.status,
            "FW: " + ((gModel.fwVersion.length() > 0) ? gModel.fwVersion : "?"),
            "Channels: " + gModel.channels.size() + "/" + gModel.maxChannels,
            "Canned: " + gModel.canned.size(),
            "Msgs held: " + gModel.messageCount(),
            "Hash: " + gModel.bph + "-byte"
        ];
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size() && y + rowH <= 206; i++) {
            dc.drawText(Draw.X + 2, y, Draw.FONT, Draw.fitTo(dc, lines[i], Draw.W - 4), Graphics.TEXT_JUSTIFY_LEFT);
            y += rowH;
        }
    }
}

// Settings: a short list of actions.
class SettingsView extends WatchUi.View {

    var _sel = 0;
    var _y0 = 50;
    var _rowH = 18;
    var _items;

    function initialize() {
        View.initialize();
        _items = [];
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, "Settings", true);
        _rowH = Draw.rowHeight(dc);
        // info rows first (not actionable), then the actions
        _items = [
            "Node: " + ((gModel.nodeName.length() > 0) ? gModel.nodeName : "?"),
            "FW: " + ((gModel.fwVersion.length() > 0) ? gModel.fwVersion : "?"),
            "Link: " + gModel.status,
            "Ch " + gModel.channels.size() + "  Cnd " + gModel.canned.size() + "  Msg " + gModel.messageCount(),
            "Reconnect",
            "Clear messages",
            "Meck v0.2"
        ];
        for (var i = 0; i < _items.size(); i++) {
            var y = _y0 + i * _rowH;
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(Draw.X + 2, y, Draw.FONT, Draw.fitTo(dc, _items[i], Draw.W - 4), Graphics.TEXT_JUSTIFY_LEFT);
        }
        Draw.footer(dc, gModel.status);
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
        if (_sel == 4) {
            gModel.showToast("Reconnecting");
            gLink.reconnect();
        } else if (_sel == 5) {
            gModel.clearMessages();
            gModel.showToast("Messages cleared");
        }
    }
}

class SettingsDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() { _v.move(1); return true; }
    function onPreviousPage() { _v.move(-1); return true; }
    function onSelect() { _v.activate(); return true; }

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
