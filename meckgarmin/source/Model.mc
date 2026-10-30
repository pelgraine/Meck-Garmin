using Toybox.WatchUi;
using Toybox.System;
using Toybox.Timer;
using Toybox.Application;
using Toybox.Lang;

// Everything the screens draw comes from here. The link fills it in; the
// views read it. Messages are kept per channel, oldest first, capped.
class Model {

    var status = "Starting";     // one-line link status shown in footers
    var connected = false;
    var meckExt = true;          // false after a node refuses the watch hello (standard MeshCore)
    var nodeName = "";
    var fwVersion = "";
    var nodeKey = "";            // hex of the node's public key prefix; keys the per-node region store
    var regions = {};            // channel name -> send region ("*" = all regions, else a region name)
    var nodeMv = 0;              // node battery, millivolts (0 = unknown)
    var manufacturer = "";
    var maxChannels = 0;
    var bph = 1;                 // bytes per hop in hop lists (from the node)
    var channels = [];           // [{:idx, :name}] in node order, unused slots skipped
    var canned = [];             // canned message strings, unused slots skipped
    var cannedSlots = null;      // the watch's own five slots (standard nodes), loaded on first use
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
    var favUnsupported = false;  // node refused the favourites command (firmware without it)
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

    // ---- per-channel send regions (standard nodes) ----
    // A standard node keeps no per-channel region, so the watch keeps its
    // own, per node and channel name, in Storage: absent = node default,
    // "*" = all regions (unscoped), anything else = a region name.

    function loadRegions() {
        regions = {};
        if (nodeKey.length() == 0) { return; }
        try {
            var v = Application.Storage.getValue("reg_" + nodeKey);
            if (v instanceof Lang.Dictionary) { regions = v; }
        } catch (ex) {
        }
    }

    // null = node default, "*" = all regions, else the region name.
    function regionFor(idx) {
        var nm = channelName(idx);
        return regions.hasKey(nm) ? regions.get(nm) : null;
    }

    function setRegion(idx, value) {
        var nm = channelName(idx);
        if (value == null) {
            regions.remove(nm);
        } else {
            regions.put(nm, value);
        }
        if (nodeKey.length() > 0) {
            try {
                Application.Storage.setValue("reg_" + nodeKey, regions);
            } catch (ex) {
            }
        }
        WatchUi.requestUpdate();
    }

    // Short form for lists: "default", "all", or the name.
    function regionLabel(idx) {
        var r = regionFor(idx);
        if (r == null) { return "default"; }
        if ("*".equals(r)) { return "all"; }
        return r;
    }

    // ---- watch-side canned messages (standard nodes) ----
    // A standard node has no canned slots, so the watch keeps five of its own
    // in Storage, the same five for every standard node. "" = empty slot.

    const CANNED_SLOTS = 5;

    function slots() {
        if (cannedSlots == null) {
            cannedSlots = ["", "", "", "", ""];
            try {
                var v = Application.Storage.getValue("canned");
                if (v instanceof Lang.Array) {
                    for (var i = 0; i < CANNED_SLOTS && i < v.size(); i++) {
                        if (v[i] instanceof Lang.String) { cannedSlots[i] = v[i]; }
                    }
                }
            } catch (ex) {
            }
        }
        return cannedSlots;
    }

    function setSlot(i, text) {
        var s = slots();
        s[i] = text;
        try {
            Application.Storage.setValue("canned", s);
        } catch (ex) {
        }
        if (connected && !meckExt) {
            useWatchCanned();
        }
        WatchUi.requestUpdate();
    }

    // On a standard node the canned list is the watch's non-empty slots, in order.
    function useWatchCanned() {
        var s = slots();
        var out = [];
        for (var i = 0; i < s.size(); i++) {
            if (s[i].length() > 0) { out.add(s[i]); }
        }
        canned = out;
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
