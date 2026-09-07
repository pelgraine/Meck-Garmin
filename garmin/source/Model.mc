using Toybox.WatchUi;
using Toybox.System;
using Toybox.Timer;
using Toybox.Application;

// Everything the screens draw comes from here. The link fills it in; the
// views read it. Messages are kept per channel, oldest first, capped.
class Model {

    var status = "Starting";     // one-line link status shown in footers
    var connected = false;
    var nodeName = "";
    var fwVersion = "";
    var nodeMv = 0;              // node battery, millivolts (0 = unknown)
    var manufacturer = "";
    var maxChannels = 0;
    var bph = 1;                 // bytes per hop in hop lists (from the node)
    var channels = [];           // [{:idx, :name}] in node order, unused slots skipped
    var canned = [];             // canned message strings, unused slots skipped
    var scopes = {};             // scope idx -> name
    var msgs = {};               // channel idx -> array of message dicts
    var unread = {};             // channel idx -> count

    const MAX_PER_CHANNEL = 40;

    var toast = null;            // transient message drawn by the channel view
    var discovered = [];         // Discover results, index = node entry number
    var discoverActive = false;
    var discoverCount = 0;
    var trace = null;            // current trace: {:state, :tag, :sentAt, :bph, :hashes, :snrs, :final, :ms}
    var favs = [];               // favourite contacts: {:type, :last, :pubkey, :name}
    var favCount = 0;
    var names = {};              // pubkey prefix hex -> contact name (resolved by the node)
    var admin = null;            // repeater session: {:pubkey, :prefix, :name, :state, :sentAt}
    var cli = null;              // last CLI command: {:cmd, :label, :state, :text, :sentAt}

    // Meck-style toast: shown centred for 2.5 seconds.
    function showToast(t) {
        toast = t;
        gSched.after(2500, "toast", method(:clearToast));
        WatchUi.requestUpdate();
    }

    function clearToast() {
        toast = null;
        WatchUi.requestUpdate();
    }

    function setStatus(s) {
        status = s;
        System.println("[link] " + s);
        WatchUi.requestUpdate();
    }

    function channelName(idx) {
        for (var i = 0; i < channels.size(); i++) {
            if (channels[i].get(:idx) == idx) {
                return channels[i].get(:name);
            }
        }
        return "Ch " + idx;
    }

    function messagesFor(idx) {
        if (msgs.hasKey(idx)) {
            return msgs.get(idx);
        }
        return [];
    }

    // m is a dictionary; see NodeLink.parseChannelMsg for the keys.
    function addMessage(idx, m, countUnread) {
        var a = messagesFor(idx);
        a.add(m);
        if (a.size() > MAX_PER_CHANNEL) {
            a = a.slice(a.size() - MAX_PER_CHANNEL, a.size());
        }
        msgs.put(idx, a);
        if (countUnread) {
            var n = unread.hasKey(idx) ? unread.get(idx) : 0;
            unread.put(idx, n + 1);
        }
        WatchUi.requestUpdate();
    }

    function totalUnread() {
        var t = 0;
        var ks = unread.keys();
        for (var i = 0; i < ks.size(); i++) {
            t += unread.get(ks[i]);
        }
        return t;
    }

    function messageCount() {
        var t = 0;
        var ks = msgs.keys();
        for (var i = 0; i < ks.size(); i++) {
            t += msgs.get(ks[i]).size();
        }
        return t;
    }

    // ---- repeater admin ----
    function adminResult(ok) {
        if (admin == null) { return; }
        admin.put(:state, ok ? :ok : :fail);
        if (ok && admin.get(:pw) != null) {
            // remembered per repeater only once the repeater has accepted it
            Application.Storage.setValue("pw_" + admin.get(:prefix), admin.get(:pw));
        }
        WatchUi.requestUpdate();
    }

    function cliReply(prefixHex, text) {
        if (cli == null || cli.get(:state) != :pending) { return; }
        cli.put(:text, text);
        cli.put(:state, :done);
        WatchUi.requestUpdate();
    }

    function cliFailed() {
        if (cli == null) { return; }
        cli.put(:state, :error);
        WatchUi.requestUpdate();
    }

    function clearMessages() {
        msgs = {};
        unread = {};
        WatchUi.requestUpdate();
    }

    function unreadFor(idx) {
        return unread.hasKey(idx) ? unread.get(idx) : 0;
    }

    function clearUnread(idx) {
        unread.put(idx, 0);
    }

    // Region name for a scope index, following the node's own rules:
    // 0xFF = unscoped (no line), 0xFE = scoped but unknown.
    function scopeName(idx) {
        if (idx == 0xFF) {
            return null;
        }
        if (idx == 0xFE) {
            return "(reg unknown)";
        }
        if (scopes.hasKey(idx)) {
            return scopes.get(idx);
        }
        return null;
    }
}
