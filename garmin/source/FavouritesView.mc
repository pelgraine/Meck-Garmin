using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Time;
using Toybox.Application;

// Favourites: the node's favourite contacts. Selecting a repeater or room
// logs in (password remembered per repeater in the watch's storage, typed
// on the keyboard the first time) and opens the admin screen.
class FavouritesView extends WatchUi.View {

    var _sel = 0;
    var _top = 0;
    var _rows = 1;
    var _y0 = 50;
    var _rowH = 18;
    var _tickOff = 0;
    var _tickW = 0;
    var _tickLoops = 0;
    var _fetched = false;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        if (!_fetched) {
            _fetched = true;
            gLink.favsFetch();
        }
        gSched.every(40, "marquee", method(:onTick));
    }

    function onHide() {
        gSched.cancel("marquee");
    }

    function onTick() {
        if (_tickW <= Draw.W) {
            _tickOff = 0;
            return;
        }
        _tickOff += 6;
        if (_tickOff > _tickW + 24) {
            _tickOff = 0;
            _tickLoops++;
            if (_tickLoops >= 3) {
                gSched.cancel("marquee");   // rest after three passes
            }
        }
        WatchUi.requestUpdate();
    }

    static function typeChar(t) {
        if (t == 1) { return "C"; }
        if (t == 2) { return "R"; }
        if (t == 3) { return "S"; }
        if (t == 4) { return "N"; }
        return "?";
    }

    // "5m", "3h", "2d" since a timestamp; "?" if none
    static function age(ts) {
        if (ts == null || ts == 0) { return "?"; }
        var d = Time.now().value() - ts;
        if (d < 0) { d = 0; }
        if (d < 3600) { return "" + (d / 60) + "m"; }
        if (d < 86400) { return "" + (d / 3600) + "h"; }
        return "" + (d / 86400) + "d";
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        _y0 = Draw.header(dc, "Favourites", true);
        _rowH = Draw.rowHeight(dc);
        _rows = (196 - _y0) / _rowH;
        if (_rows < 1) { _rows = 1; }

        var list = gModel.favs;
        if (list.size() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX, _y0 + 20, Draw.FONT, gModel.connected ? "Loading..." : "No node yet", Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (_sel >= list.size()) { _sel = (list.size() > 0) ? list.size() - 1 : 0; }
        if (_sel < _top) { _top = _sel; }
        if (_sel >= _top + _rows) { _top = _sel - _rows + 1; }

        for (var r = 0; r < _rows; r++) {
            var i = _top + r;
            if (i >= list.size()) { break; }
            var e = list[i];
            if (e == null) { continue; }
            var y = _y0 + r * _rowH;
            var selected = (i == _sel);
            var right = age(e.get(:last));
            var rw = dc.getTextWidthInPixels(right, Draw.FONT) + 4;
            var line = typeChar(e.get(:type)) + " " + e.get(:name);
            if (selected) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                _tickW = Draw.marqueeRow(dc, line, Draw.X + 2, y, Draw.W - 4 - rw, _rowH, _tickOff, 24);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(Draw.X + 2, y, Draw.FONT, Draw.fitTo(dc, line, Draw.W - 4 - rw), Graphics.TEXT_JUSTIFY_LEFT);
            }
            dc.setColor(selected ? Graphics.COLOR_BLACK : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.X + Draw.W - 2, y, Draw.FONT, right, Graphics.TEXT_JUSTIFY_RIGHT);
        }
        Draw.footer(dc, (gModel.favCount > 0) ? ("" + list.size() + "/" + gModel.favCount) : gModel.status);
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function move(d) {
        var n = gModel.favs.size();
        if (n == 0) { return; }
        _sel = _sel + d;
        if (_sel < 0) { _sel = n - 1; }
        if (_sel >= n) { _sel = 0; }
        _tickOff = 0;
        _tickLoops = 0;
        gSched.every(40, "marquee", method(:onTick));
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        if (y < _y0) { return -1; }
        var r = (y - _y0) / _rowH;
        var i = _top + r;
        if (r >= _rows || i >= gModel.favs.size()) { return -1; }
        return i;
    }

    // Select: repeaters and rooms can be administered; anything else is view-only.
    function open() {
        var list = gModel.favs;
        if (_sel < 0 || _sel >= list.size() || list[_sel] == null) { return; }
        var e = list[_sel];
        var t = e.get(:type);
        if (t != 2 && t != 3) {
            gModel.showToast("Not a repeater");
            return;
        }
        var key = "pw_" + gLink.hexOf(e.get(:pubkey).slice(0, 6));
        var saved = Application.Storage.getValue(key);
        if (saved != null && saved.length() > 0) {
            startAdmin(e, saved);
        } else {
            var cv = new ComposeView(-1, "");
            cv.title = "Password";
            cv.onDone = method(:gotPassword);
            _pending = e;
            WatchUi.pushView(cv, new ComposeDelegate(cv), WatchUi.SLIDE_UP);
        }
    }

    var _pending = null;

    function gotPassword(pw) {
        if (_pending == null || pw.length() == 0) { return; }
        startAdmin(_pending, pw);   // stored only after the repeater accepts it
        _pending = null;
    }

    // Hold Up: forget the saved password for the highlighted repeater and ask again.
    function reenter() {
        var list = gModel.favs;
        if (_sel < 0 || _sel >= list.size() || list[_sel] == null) { return; }
        var e = list[_sel];
        var t = e.get(:type);
        if (t != 2 && t != 3) {
            gModel.showToast("Not a repeater");
            return;
        }
        Application.Storage.deleteValue("pw_" + gLink.hexOf(e.get(:pubkey).slice(0, 6)));
        var cv = new ComposeView(-1, "");
        cv.title = "Password";
        cv.onDone = method(:gotPassword);
        _pending = e;
        WatchUi.pushView(cv, new ComposeDelegate(cv), WatchUi.SLIDE_UP);
    }

    function startAdmin(e, pw) {
        gModel.admin = {
            :pubkey => e.get(:pubkey), :prefix => gLink.hexOf(e.get(:pubkey).slice(0, 6)),
            :name => e.get(:name), :state => :logging_in, :sentAt => Time.now().value(),
            :pw => pw
        };
        gModel.cli = null;
        gLink.login(e.get(:pubkey), pw);
        var av = new AdminView();
        WatchUi.pushView(av, new AdminDelegate(av), WatchUi.SLIDE_LEFT);
    }
}

class FavouritesDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() { _v.move(1); return true; }
    function onPreviousPage() { _v.move(-1); return true; }
    function onMenu() { _v.reenter(); return true; }

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

// Repeater admin: after login, four actions. Replies show in a response
// list; neighbour replies are parsed into "(xxxx) Name  SNR  age" rows
// with names resolved by the node, marquee on the highlighted row.
class AdminView extends WatchUi.View {

    const TIMEOUT_S = 30;

    var _sel = 0;
    var _y0 = 50;
    var _rowH = 18;
    var _showResp = false;
    var _lines = [];       // response rows (strings) or parsed neighbour rows
    var _respSel = 0;
    var _respTop = 0;
    var _tickOff = 0;
    var _tickW = 0;
    var _tickLoops = 0;
    var _menu;

    function initialize() {
        View.initialize();
        _menu = [
            {:label => "View Neighbours",     :cmd => "neighbors",           :neigh => true},
            {:label => "Discover Neighbours", :cmd => "discover.neighbors",  :neigh => false},
            {:label => "Clock Sync",          :cmd => "clock sync",          :neigh => false},
            {:label => "Send Advert",         :cmd => "advert",              :neigh => false}
        ];
    }

    function onShow() {
        gSched.every(40, "marquee", method(:onTick));
        gSched.every(500, "admin", method(:tick));
    }

    function onHide() {
        gSched.cancel("marquee");
        gSched.cancel("admin");
    }

    function onTick() {
        if (_tickW <= Draw.W) {
            _tickOff = 0;
            return;
        }
        _tickOff += 6;
        if (_tickOff > _tickW + 24) {
            _tickOff = 0;
            _tickLoops++;
            if (_tickLoops >= 3) {
                gSched.cancel("marquee");   // rest after three passes
            }
        }
        WatchUi.requestUpdate();
    }

    // Timeouts for login and for a pending command.
    function tick() {
        var now = Time.now().value();
        var a = gModel.admin;
        if (a != null && a.get(:state) == :logging_in && now - a.get(:sentAt) >= TIMEOUT_S) {
            a.put(:state, :timeout);
            WatchUi.requestUpdate();
        }
        var c = gModel.cli;
        if (c != null && c.get(:state) == :pending && now - c.get(:sentAt) >= TIMEOUT_S) {
            c.put(:state, :timeout);
            WatchUi.requestUpdate();
        }
        if (c != null && c.get(:state) == :done && !_showResp && c.get(:shown) != true) {
            c.put(:shown, true);   // auto-open each reply once; Back then stays out
            buildResponse();
            _showResp = true;
            WatchUi.requestUpdate();
        } else if (_showResp) {
            refreshNames();
        }
    }

    // ---------------------------------------------------------------- drawing

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var a = gModel.admin;
        var name = (a != null) ? a.get(:name) : "Admin";
        _y0 = Draw.header(dc, name, true);
        _rowH = Draw.rowHeight(dc);

        if (_showResp) {
            drawResponse(dc);
            return;
        }

        var st = (a == null) ? "" : a.get(:state);
        var status;
        if (st == :logging_in) { status = "Logging in..."; }
        else if (st == :ok) { status = "Logged in"; }
        else if (st == :fail) { status = "Login failed - Start: retry"; }
        else if (st == :timeout) { status = "No reply - Start: retry"; }
        else { status = ""; }
        var c = gModel.cli;
        if (c != null && c.get(:state) == :pending) {
            status = c.get(:label) + "...";
        } else if (c != null && c.get(:state) == :timeout) {
            status = c.get(:label) + ": no reply";
        } else if (c != null && c.get(:state) == :error) {
            status = c.get(:label) + ": send failed";
        }
        dc.setColor((st == :ok) ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.X, _y0, Draw.FONT, Draw.fitTo(dc, status, Draw.W), Graphics.TEXT_JUSTIFY_LEFT);
        var y = _y0 + _rowH + 2;
        for (var i = 0; i < _menu.size(); i++) {
            if (i == _sel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor((st == :ok) ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(Draw.X + 2, y, Draw.FONT, _menu[i].get(:label), Graphics.TEXT_JUSTIFY_LEFT);
            y += _rowH;
        }
        if (c != null && c.get(:state) == :done) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Draw.CX, 208, Draw.FONT, "Hold Up: last reply", Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function drawResponse(dc) {
        var c = gModel.cli;
        var rows = (200 - _y0) / _rowH;
        if (rows < 1) { rows = 1; }
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.X, _y0, Draw.FONT, Draw.fitTo(dc, (c != null) ? c.get(:label) : "", Draw.W), Graphics.TEXT_JUSTIFY_LEFT);
        var listY = _y0 + _rowH;
        rows = rows - 1;
        if (_respSel >= _lines.size()) { _respSel = (_lines.size() > 0) ? _lines.size() - 1 : 0; }
        if (_respSel < _respTop) { _respTop = _respSel; }
        if (_respSel >= _respTop + rows) { _respTop = _respSel - rows + 1; }
        for (var r = 0; r < rows; r++) {
            var i = _respTop + r;
            if (i >= _lines.size()) { break; }
            var y = listY + r * _rowH;
            var line = _lines[i];
            if (i == _respSel) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRectangle(Draw.X, y, Draw.W, _rowH);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                _tickW = Draw.marqueeRow(dc, line, Draw.X + 2, y, Draw.W - 4, _rowH, _tickOff, 24);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(Draw.X + 2, y, Draw.FONT, Draw.fitTo(dc, line, Draw.W - 4), Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.CX, 208, Draw.FONT, "Back: menu", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Turn the reply text into rows. Neighbour replies: "hex:timestamp:snr*4"
    // per line -> "(xxxx) Name  SNR  age", names via the node's resolver.
    function buildResponse() {
        var c = gModel.cli;
        _lines = [];
        _respSel = 0;
        _respTop = 0;
        _tickOff = 0;
        if (c == null) { return; }
        var text = c.get(:text);
        var raw = split(text, "\n");
        if (!c.get(:neigh)) {
            for (var i = 0; i < raw.size(); i++) {
                if (raw[i].length() > 0) { _lines.add(raw[i]); }
            }
            if (_lines.size() == 0) { _lines.add("(empty reply)"); }
            return;
        }
        var count = 0;
        for (var i = 0; i < raw.size(); i++) {
            var ln = raw[i];
            if (ln.length() == 0) { continue; }
            var parts = split(ln, ":");
            var hexs = parts[0];
            var ts = (parts.size() > 1) ? parts[1].toNumber() : null;
            var snr4 = (parts.size() > 2) ? parts[2].toNumber() : null;
            if (hexs.length() < 2) { _lines.add(ln); continue; }
            var bytes = hexToBytes(hexs);
            var nm = gModel.names.hasKey(hexs) ? gModel.names.get(hexs) : null;
            if (nm == null && bytes.size() > 0) {
                gLink.resolve(bytes);
            }
            var short = (hexs.length() >= 4) ? hexs.substring(0, 4) : hexs;
            var snrStr = (snr4 == null) ? "" : snrText(snr4);
            var ageStr = (ts == null) ? "" : FavouritesView.age(ts);
            var label = (nm != null && nm.length() > 0) ? nm : "?";
            _lines.add("(" + short + ") " + label + "  " + snrStr + "  " + ageStr);
            count++;
        }
        _lines.add("Neighbours: " + count);
    }

    function snrText(q) {
        var whole = q / 4;
        var frac = ((q < 0 ? -q : q) % 4) * 25 / 10;
        var s = "" + whole + "." + frac;
        if (q < 0 && whole == 0) { s = "-" + s; }
        return s + "dB";
    }

    function hexToBytes(h) {
        var out = []b;
        var n = h.length() - (h.length() % 2);
        for (var i = 0; i + 2 <= n; i += 2) {
            var v = h.substring(i, i + 2).toNumberWithBase(16);
            if (v == null) { return out; }
            out = out.addAll([v & 0xFF]b);
        }
        return out;
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

    // Re-resolve names as replies arrive (rows were built with "?").
    function refreshNames() {
        var c = gModel.cli;
        if (c != null && c.get(:neigh) && _showResp) {
            var sel = _respSel;
            var top = _respTop;
            var off = _tickOff;
            buildResponse();
            _respSel = sel;
            _respTop = top;
            _tickOff = off;
        }
    }

    // ---------------------------------------------------------------- input

    function move(d) {
        if (_showResp) {
            var n = _lines.size();
            if (n == 0) { return; }
            _respSel = _respSel + d;
            if (_respSel < 0) { _respSel = 0; }
            if (_respSel >= n) { _respSel = n - 1; }
            _tickOff = 0;
            _tickLoops = 0;
            gSched.every(40, "marquee", method(:onTick));
        } else {
            _sel = (_sel + d + _menu.size()) % _menu.size();
        }
        WatchUi.requestUpdate();
    }

    function rowAt(y) {
        var listY = _y0 + _rowH + 2;
        if (y < listY) { return -1; }
        var i = (y - listY) / _rowH;
        return (i < _menu.size()) ? i : -1;
    }

    function run() {
        if (_showResp) { return; }
        var a = gModel.admin;
        if (a == null) { return; }
        var st = a.get(:state);
        if (st == :fail || st == :timeout) {
            retryPassword();
            return;
        }
        if (st != :ok) {
            gModel.showToast("Not logged in");
            return;
        }
        var m = _menu[_sel];
        gModel.cli = {:cmd => m.get(:cmd), :label => m.get(:label), :neigh => m.get(:neigh),
                      :state => :pending, :text => "", :sentAt => Time.now().value()};
        gLink.sendCli(a.get(:pubkey), m.get(:cmd));
        WatchUi.requestUpdate();
    }

    // Ask for the password again and retry the login.
    function retryPassword() {
        var cv = new ComposeView(-1, "");
        cv.title = "Password";
        cv.onDone = method(:gotPassword);
        WatchUi.pushView(cv, new ComposeDelegate(cv), WatchUi.SLIDE_UP);
    }

    function gotPassword(pw) {
        var a = gModel.admin;
        if (a == null || pw.length() == 0) { return; }
        a.put(:pw, pw);
        a.put(:state, :logging_in);
        a.put(:sentAt, Time.now().value());
        gLink.login(a.get(:pubkey), pw);
        WatchUi.requestUpdate();
    }

    function showLast() {
        var c = gModel.cli;
        if (c != null && c.get(:state) == :done) {
            buildResponse();
            _showResp = true;
            WatchUi.requestUpdate();
        }
    }

    function back() {
        if (_showResp) {
            _showResp = false;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }
}

class AdminDelegate extends WatchUi.BehaviorDelegate {
    var _v;

    function initialize(v) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onNextPage() { _v.move(1); return true; }
    function onPreviousPage() { _v.move(-1); return true; }
    function onMenu() { _v.showLast(); return true; }

    function onKey(evt) {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _v.run();
            return true;
        }
        return false;
    }

    function onBack() {
        if (_v.back()) {
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onTap(evt) {
        var c = evt.getCoordinates();
        var i = _v.rowAt(c[1]);
        if (i >= 0 && !_v._showResp) {
            _v._sel = i;
            _v.run();
        }
        return true;
    }
}
