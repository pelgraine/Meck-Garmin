using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;

// Rolling on-screen status log. Every stage of the Bluetooth
// conversation appends a line here, and the same line goes to the
// app log file if one exists (GARMIN/APPS/LOGS/MECKSPIKE.TXT).
class StatusLog {
    static var lines = ["MeckSpike v0.1"];

    static function add(text) {
        System.println(text);
        lines.add(text);
        if (lines.size() > 10) {
            lines = lines.slice(1, lines.size());
        }
        WatchUi.requestUpdate();
    }
}

class SpikeView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var y = 18;
        for (var i = 0; i < StatusLog.lines.size(); i++) {
            dc.drawText(12, y, Graphics.FONT_XTINY, StatusLog.lines[i],
                        Graphics.TEXT_JUSTIFY_LEFT);
            y += 20;
        }
    }
}

class SpikeInputDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // Pressing Start/Enter restarts the scan if the app is idle.
    function onSelect() {
        if (gBle != null) {
            gBle.restart();
        }
        return true;
    }
}
