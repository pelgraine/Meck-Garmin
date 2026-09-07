using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Timer;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Home: header with node name, time and battery, then the Meck tile grid.
// Four tiles, each with its own neon outline; the selected tile is filled.
class HomeView extends WatchUi.View {

    const TILE_W = 76;
    const TILE_H = 68;
    const GAP = 8;
    const GRID_X = 40;
    const GRID_Y = 62;

    var _sel = 0;
    var _scroll = 0;     // first grid row shown (0 or 1)
    var _tiles;

    function initialize() {
        View.initialize();
        _tiles = [
            {:label => "Messages", :color => 0x00FFFF},
            {:label => "Settings", :color => 0xFF6A3D},
            {:label => "Discover", :color => 0x7CFF00},
            {:label => "Trace",    :color => 0xE040FB},
            {:label => "Favourites", :color => 0x8040FF}
        ];
    }

    function onShow() {
        gSched.every(30000, "home", method(:tick));   // keep the clock fresh
    }

    function onHide() {
        gSched.cancel("home");
    }

    var _ticks = 0;

    function tick() {
        _ticks++;
        if (_ticks % 20 == 0) {         // every 10 min (30 s ticks)
            gLink.requestBattery();
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var fh = dc.getFontHeight(Draw.FONT);

        // clock in the top gap of the circle, medium font (largest on screen)
        var ct = System.getClockTime();
        var timeStr = ct.hour.format("%02d") + ":" + ct.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.CX, 4, Graphics.FONT_MEDIUM, timeStr, Graphics.TEXT_JUSTIFY_CENTER);

        // header line: node name | node volts (dark blue) | watch battery (green)
        var batt = System.getSystemStats().battery;
        var battStr = batt.format("%d") + "%";
        var battW = dc.getTextWidthInPixels(battStr, Draw.FONT);
        dc.setColor((batt < 20) ? Graphics.COLOR_RED : Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(198, 38, Draw.FONT, battStr, Graphics.TEXT_JUSTIFY_RIGHT);
        var rightEdge = 198 - battW - 6;
        if (gModel.nodeMv > 0) {
            var mv = gModel.nodeMv;
            var volts = "" + (mv / 1000) + "." + ((mv % 1000) / 10).format("%02d") + "v";
            var vW = dc.getTextWidthInPixels(volts, Draw.FONT);
            dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightEdge, 38, Draw.FONT, volts, Graphics.TEXT_JUSTIFY_RIGHT);
            rightEdge = rightEdge - vW - 6;
        }
        var name = (gModel.nodeName.length() > 0) ? gModel.nodeName : "Meck";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(42, 38, Draw.FONT, Draw.fitTo(dc, name, rightEdge - 42), Graphics.TEXT_JUSTIFY_LEFT);

        // date: day in the left margin, month in the right, small font
        // (one size below the clock, one above the header line)
        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dfh = dc.getFontHeight(Graphics.FONT_SMALL);
        dc.drawText(20, 120 - dfh / 2, Graphics.FONT_SMALL, g.day.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(221, 120 - dfh / 2, Graphics.FONT_SMALL, g.month.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);

        // tiles
        var unread = gModel.totalUnread();
        if (_sel >= 4) { _scroll = 1; }
        if (_sel < 2) { _scroll = 0; }
        for (var i = 0; i < _tiles.size(); i++) {
            var col = i % 2;
            var row = i / 2 - _scroll;
            if (row < 0 || row > 1) { continue; }
            var x = GRID_X + col * (TILE_W + GAP);
            var y = GRID_Y + row * (TILE_H + GAP);
            var c = _tiles[i].get(:color);
            if (i == _sel) {
                dc.setColor(c, c);
                dc.fillRoundedRectangle(x, y, TILE_W, TILE_H, 8);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawRoundedRectangle(x, y, TILE_W, TILE_H, 8);
                dc.setPenWidth(1);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(x + TILE_W / 2, y + TILE_H / 2 - fh / 2, Draw.FONT, _tiles[i].get(:label), Graphics.TEXT_JUSTIFY_CENTER);
            if (i == 0 && unread > 0) {
                dc.setColor((i == _sel) ? Graphics.COLOR_BLACK : c, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x + TILE_W - 6, y + 2, Draw.FONT, "" + unread, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }

        Draw.footer(dc, gModel.status);
        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
    }

    function tileAt(x, y) {
        for (var i = 0; i < _tiles.size(); i++) {
            var col = i % 2;
            var row = i / 2 - _scroll;
            if (row < 0 || row > 1) { continue; }
            var tx = GRID_X + col * (TILE_W + GAP);
            var ty = GRID_Y + row * (TILE_H + GAP);
            if (x >= tx && x < tx + TILE_W && y >= ty && y < ty + TILE_H) {
                return i;
            }
        }
        return -1;
    }

    function move(d) {
        _sel = (_sel + d + _tiles.size()) % _tiles.size();
        WatchUi.requestUpdate();
    }

    function open() {
        if (_sel == 0) {
            var p = new PickerView();
            WatchUi.pushView(p, new PickerDelegate(p), WatchUi.SLIDE_LEFT);
        } else if (_sel == 1) {
            var sv = new SettingsView();
            WatchUi.pushView(sv, new SettingsDelegate(sv), WatchUi.SLIDE_LEFT);
        } else if (_sel == 2) {
            var dv = new DiscoverView();
            WatchUi.pushView(dv, new DiscoverDelegate(dv), WatchUi.SLIDE_LEFT);
        } else if (_sel == 3) {
            var tv = new TraceView();
            WatchUi.pushView(tv, new TraceDelegate(tv), WatchUi.SLIDE_LEFT);
        } else {
            var fv = new FavouritesView();
            WatchUi.pushView(fv, new FavouritesDelegate(fv), WatchUi.SLIDE_LEFT);
        }
    }
}

class HomeDelegate extends WatchUi.BehaviorDelegate {
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

    function onTap(evt) {
        var c = evt.getCoordinates();
        var i = _v.tileAt(c[0], c[1]);
        if (i >= 0) {
            _v._sel = i;
            _v.open();
        }
        return true;
    }
}

// Back-only delegate for read-only screens.
class SimpleBackDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
