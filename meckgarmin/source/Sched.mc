using Toybox.Timer;
using Toybox.System;
using Toybox.Lang;

// One Timer for the whole app. Garmin limits how many timers may exist at
// once and the app crashed with "Too Many Timers" when the link, the toast
// and a screen all wanted one. Everything now asks this scheduler instead:
//   gSched.after(ms, id, method)   run once
//   gSched.every(ms, id, method)   run repeatedly
//   gSched.cancel(id)
// Ids are strings; scheduling an id that already exists replaces it.
class Sched {

    var _timer;
    var _entries = [];   // {:id, :due, :period, :cb}

    function initialize() {
        _timer = new Timer.Timer();
    }

    function after(ms, id, cb) {
        cancel(id);
        _entries.add({:id => id, :due => System.getTimer() + ms, :period => 0, :cb => cb});
        arm();
    }

    function every(ms, id, cb) {
        cancel(id);
        _entries.add({:id => id, :due => System.getTimer() + ms, :period => ms, :cb => cb});
        arm();
    }

    function cancel(id) {
        var keep = [];
        for (var i = 0; i < _entries.size(); i++) {
            if (!_entries[i].get(:id).equals(id)) {
                keep.add(_entries[i]);
            }
        }
        _entries = keep;
        arm();
    }

    // (Re)start the single timer for the soonest due entry.
    function arm() {
        _timer.stop();
        if (_entries.size() == 0) {
            return;
        }
        var now = System.getTimer();
        var next = -1;
        for (var i = 0; i < _entries.size(); i++) {
            var d = _entries[i].get(:due) - now;
            if (next < 0 || d < next) {
                next = d;
            }
        }
        if (next < 20) { next = 20; }
        if (next > 5000) { next = 5000; }
        _timer.start(method(:fire), next, false);
    }

    function fire() {
        var now = System.getTimer();
        var run = [];
        var keep = [];
        for (var i = 0; i < _entries.size(); i++) {
            var e = _entries[i];
            if (e.get(:due) <= now) {
                run.add(e);
                if (e.get(:period) > 0) {
                    e.put(:due, now + e.get(:period));
                    keep.add(e);
                }
            } else {
                keep.add(e);
            }
        }
        _entries = keep;
        for (var r = 0; r < run.size(); r++) {
            run[r].get(:cb).invoke();
        }
        arm();
    }
}
