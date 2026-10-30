using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Timer;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Home: ring menu. Five arc segments on the rim, one per option, in the
// Up/Down cycle order clockwise from 12 o'clock. Only the selected segment
// is drawn in its tile colour; the rest are dark grey. Inside the ring:
// node name, node volts (dark blue) and watch battery (green), a big clock,
// the date, the selected option's name in the same colour, and the link
// status. Up/Down walk the highlight round the ring, Start opens.
class HomeView extends WatchUi.View {

    const RING_R     = 112;   // arc radius (screen radius is 120)
    const RING_SPAN  = 60;    // degrees per segment (72 per slot, 12 gap)
    const SEL_PEN    = 8;     // pen width of the selected segment
    const IDLE_PEN   = 3;     // pen width of the other four
    const INFO_Y     = 48;    // top of the name / volts / battery line
    const INFO_X     = 44;    // left edge of the name
    const INFO_R     = 196;   // right edge of the battery figure
    const CLOCK_CY   = 110;   // vertical centre of the clock digits' cell
    const DATE_CY    = 156;   // vertical centre of the date line
    const SEL_CY     = 176;   // vertical centre of the selected option line
    const STATUS_CY  = 196;   // vertical centre of the status line
    const CLOCK_FONT = Graphics.FONT_NUMBER_THAI_HOT;
    const LINE_FONT  = Graphics.FONT_TINY;    // date and selected option
    const MID        = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    var _sel = 0;
    var _tiles;

    function initialize() {
        View.initialize();
        // Outline colours taken from the Meck-P4 tiles (LVGL Material palette):
        // Maps blue, Web deep purple, Audio teal, Trace red, Notes yellow.
        _tiles = [
            {:label => "Messages",   :color => 0x2196F3},
            {:label => "Settings",   :color => 0x673AB7},
            {:label => "Discover",   :color => 0x00AA55},   // sea-green, on the panel grid
            {:label => "Trace",      :color => 0xFF0000},   // pure red
            {:label => "Favourites", :color => 0xFFEB3B}
        ];
    }

    function onShow() {
        gSched.every(60000, "home", method(:tick));   // keep the clock fresh (1 min)
    }

    function onHide() {
        gSched.cancel("home");
    }

    // Watch dimmed: stop redrawing so the CPU can doze. The BLE link stays
    // up, so the node keeps queuing messages.
    function onEnterSleep() {
        gSched.cancel("home");
    }

    // Watch woken (wrist raise or button): redraw, refresh battery, and pull
    // whatever arrived while dozing.
    function onExitSleep() {
        gSched.every(60000, "home", method(:tick));
        gLink.requestBattery();
        gLink.syncNow();
        WatchUi.requestUpdate();
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

        // ring: slot i is centred at 90 - 72i degrees (Garmin angles run
        // counter-clockwise from 3 o'clock, so 90 is 12 o'clock); each arc
        // is drawn clockwise from centre+30 to centre-30
        for (var i = 0; i < _tiles.size(); i++) {
            var c = 90 - 72 * i;
            var a0 = c + RING_SPAN / 2;
            var a1 = c - RING_SPAN / 2;
            if (a0 < 0) { a0 += 360; }
            if (a1 < 0) { a1 += 360; }
            if (i == _sel) {
                dc.setColor(_tiles[i].get(:color), Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(SEL_PEN);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(IDLE_PEN);
            }
            dc.drawArc(Draw.CX, 120, RING_R, Graphics.ARC_CLOCKWISE, a0, a1);
        }
        dc.setPenWidth(1);

        // info line: node name | node volts (dark blue) | watch battery (green)
        var batt = System.getSystemStats().battery;
        var battStr = batt.format("%d") + "%";
        var battW = dc.getTextWidthInPixels(battStr, Draw.FONT);
        dc.setColor((batt < 20) ? Graphics.COLOR_RED : Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(INFO_R, INFO_Y, Draw.FONT, battStr, Graphics.TEXT_JUSTIFY_RIGHT);
        var rightEdge = INFO_R - battW - 6;
        if (gModel.nodeMv > 0) {
            var mv = gModel.nodeMv;
            var volts = "" + (mv / 1000) + "." + ((mv % 1000) / 10).format("%02d") + "v";
            var vW = dc.getTextWidthInPixels(volts, Draw.FONT);
            dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightEdge, INFO_Y, Draw.FONT, volts, Graphics.TEXT_JUSTIFY_RIGHT);
            rightEdge = rightEdge - vW - 6;
        }
        var name = (gModel.nodeName.length() > 0) ? gModel.nodeName : "Meck";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(INFO_X, INFO_Y, Draw.FONT, Draw.fitTo(dc, name, rightEdge - INFO_X), Graphics.TEXT_JUSTIFY_LEFT);

        // clock, date, selected option, status: each line is centred on a
        // fixed y (the number font's cell carries padding below the digits,
        // so stacking by cell height opens a gap under the clock)
        var ct = System.getClockTime();
        var timeStr = ct.hour.format("%02d") + ":" + ct.min.format("%02d");
        dc.drawText(Draw.CX, CLOCK_CY, CLOCK_FONT, timeStr, MID);

        var g = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = "" + g.day_of_week + " " + g.day + " " + g.month;
        dc.drawText(Draw.CX, DATE_CY, LINE_FONT, dateStr, MID);

        var label = _tiles[_sel].get(:label);
        if (_sel == 0) {
            var unread = gModel.totalUnread();
            if (unread > 0) {
                label = label + "  " + unread;
            }
        }
        dc.setColor(_tiles[_sel].get(:color), Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.CX, SEL_CY, LINE_FONT, label, MID);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Draw.CX, STATUS_CY, Draw.FONT, Draw.fitTo(dc, gModel.status, 120), MID);

        if (gModel.toast != null) {
            ChannelView.drawToastStatic(dc, gModel.toast);
        }
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

    // Home is button-only: a tap is consumed and does nothing.
    function onTap(evt) {
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
