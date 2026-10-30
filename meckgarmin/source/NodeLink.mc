using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;
using Toybox.Time;
using Toybox.StringUtil;
using Toybox.Math;
using Toybox.Cryptography;

// Protocol codes. Standard MeshCore companion codes plus the Meck watch
// extensions (MECK_WATCH_EXT). All layouts verified against Meck's MyMesh.cpp.
module Proto {
    const CMD_APP_START            = 1;
    const CMD_SEND_TXT_MSG         = 2;
    const CMD_SEND_CHANNEL_TXT_MSG = 3;
    const CMD_ADD_UPDATE_CONTACT   = 9;
    const CMD_SYNC_NEXT_MESSAGE    = 10;
    const CMD_GET_BATT_AND_STORAGE = 20;
    const CMD_DEVICE_QUERY         = 22;
    const CMD_SEND_LOGIN           = 26;
    const CMD_GET_CHANNEL          = 31;
    const CMD_SEND_TRACE_PATH      = 36;
    const CMD_SET_FLOOD_SCOPE_KEY  = 54;
    const CMD_SEND_CONTROL_DATA    = 55;
    const CMD_MECK_HELLO           = 0x70;
    const CMD_MECK_GET_CANNED      = 0x71;
    const CMD_MECK_GET_SENT_TRACK  = 0x72;
    const CMD_MECK_GET_SCOPE       = 0x73;
    const CMD_MECK_DISCOVER_START  = 0x74;
    const CMD_MECK_DISCOVER_GET    = 0x75;
    const CMD_MECK_GET_FAV         = 0x76;
    const CMD_MECK_RESOLVE         = 0x77;

    const RESP_OK                  = 0;
    const RESP_ERR                 = 1;
    const RESP_SELF_INFO           = 5;
    const RESP_SENT                = 6;
    const RESP_CONTACT_MSG         = 7;
    const RESP_CHANNEL_MSG         = 8;
    const RESP_NO_MORE_MESSAGES    = 10;
    const RESP_BATT_AND_STORAGE    = 12;
    const RESP_DEVICE_INFO         = 13;
    const RESP_CONTACT_MSG_V3      = 16;
    const RESP_CHANNEL_MSG_V3      = 17;
    const RESP_CHANNEL_INFO        = 18;
    const RESP_MECK_INFO           = 0x60;
    const RESP_MECK_CANNED         = 0x61;
    const RESP_MECK_SENT_TRACK     = 0x62;
    const RESP_MECK_CHANNEL_MSG    = 0x63;
    const RESP_MECK_SCOPE          = 0x64;
    const RESP_MECK_DISCOVER       = 0x65;
    const RESP_MECK_FAV            = 0x66;
    const RESP_MECK_RESOLVE        = 0x67;
    const PUSH_MSG_WAITING         = 0x83;
    const PUSH_LOGIN_SUCCESS       = 0x85;
    const PUSH_LOGIN_FAIL          = 0x86;
    const PUSH_NEW_ADVERT          = 0x8A;
    const PUSH_CONTROL_DATA        = 0x8E;
    const CTL_DISCOVER_REQ         = 0x80;
    const CTL_DISCOVER_RESP        = 0x90;
    const ADV_TYPE_REPEATER        = 2;
    const ADV_TYPE_ROOM            = 3;
    const TXT_TYPE_CLI             = 1;
    const PUSH_TRACE_DATA          = 0x89;

    const SLICE_MAX                = 18;   // payload bytes per 20-byte packet after tag + length
}

// Owns the Bluetooth connection to the node and speaks the companion
// protocol over it. Commands go out one at a time through a queue; every
// non-push reply completes the command in flight and releases the next.
class NodeLink extends Ble.BleDelegate {

    var _svcUuid;
    var _rxUuid;      // node RX: we write commands here
    var _txUuid;      // node TX: node notifies replies here
    var _device = null;
    var _rxChar = null;
    var _txChar = null;
    var _ready = false;       // notifications on, link usable
    var _subscribing = false;

    var _rxBuf = null;        // slice reassembly (null = not mid-frame)
    var _q = [];              // queued command frames (ByteArray)
    var _inflight = null;     // frame awaiting its reply
    var _txSlices = null;     // remaining slices of the frame being written
    var _writeBusy = false;
    var _awaitEnc = false;    // write refused for security; retry after encryption
    var _syncPending = false; // node signalled messages waiting
    var _scopeReq = {};       // scope idx -> true once requested

    function initialize() {
        BleDelegate.initialize();
        _svcUuid = Ble.stringToUuid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
        _rxUuid  = Ble.stringToUuid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
        _txUuid  = Ble.stringToUuid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
    }

    // ---------------------------------------------------------------- lifecycle

    function start() {
        Ble.setDelegate(self);
        gModel.setStatus("Registering...");
        try {
            Ble.registerProfile({
                :uuid => _svcUuid,
                :characteristics => [
                    {:uuid => _txUuid, :descriptors => [Ble.cccdUuid()]},
                    {:uuid => _rxUuid}
                ]
            });
        } catch (ex) {
            gModel.setStatus("Profile failed");
        }
    }

    function shutdown() {
        gSched.cancel("timeout");
        gSched.cancel("rescan");
        gSched.cancel("heard1");
        gSched.cancel("heard2");
        Ble.setScanState(Ble.SCAN_STATE_OFF);
        if (_device != null) {
            Ble.unpairDevice(_device);
        }
    }

    function onProfileRegister(uuid, status) {
        if (status == Ble.STATUS_SUCCESS) {
            startScan();
        } else {
            gModel.setStatus("Profile err " + status);
        }
    }

    function startScan() {
        gModel.setStatus("Scanning...");
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
    }

    function onScanResults(scanResults) {
        if (_device != null) {
            return;
        }
        for (var r = scanResults.next(); r != null; r = scanResults.next()) {
            var sr = r as Ble.ScanResult;
            if (matches(sr)) {
                var nm = sr.getDeviceName();
                gModel.setStatus("Found " + (nm == null ? "node" : nm));
                Ble.setScanState(Ble.SCAN_STATE_OFF);
                try {
                    _device = Ble.pairDevice(sr);
                } catch (ex) {
                    gModel.setStatus("Connect failed");
                }
                return;
            }
        }
    }

    function matches(r) {
        var nm = r.getDeviceName();
        if (nm != null && nm.find("MeshCore-") == 0) {
            return true;
        }
        var it = r.getServiceUuids();
        for (var u = it.next(); u != null; u = it.next()) {
            if (u.equals(_svcUuid)) {
                return true;
            }
        }
        return false;
    }

    function onConnectedStateChanged(device, state) {
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            gModel.setStatus("Connected");
            _device = device;
            subscribe();
        } else if (state == Ble.CONNECTION_STATE_DISCONNECTED) {
            gModel.setStatus("Disconnected");
            gModel.connected = false;
            _device = null;
            _rxChar = null;
            _txChar = null;
            _ready = false;
            _subscribing = false;
            _inflight = null;
            _txSlices = null;
            _writeBusy = false;
            _awaitEnc = false;
            _q = [];
            _rxBuf = null;
            gSched.cancel("timeout");
            gSched.after(2000, "rescan", method(:startScan));
        } else {
            gModel.setStatus("Conn state " + state);
        }
    }

    function onEncryptionStatus(device, status) {
        System.println("[link] encryption status " + status);
        if (status == Ble.STATUS_SUCCESS) {
            if (!_ready) {
                _awaitEnc = false;   // the probe write set it; the session restarts from subscribe()
                subscribe();
            } else if (_awaitEnc && _inflight != null) {
                _awaitEnc = false;
                writeFrame(_inflight);
            }
        } else {
            gModel.setStatus("Encrypt err " + status);
        }
    }

    // Turn on notifications from the node's TX characteristic. Called once on
    // connect; called again after encryption only if the first attempt failed.
    function subscribe() {
        if (_ready || _subscribing || _device == null) {
            return;
        }
        var svc = _device.getService(_svcUuid);
        if (svc == null) {
            gModel.setStatus("No UART service");
            return;
        }
        _txChar = svc.getCharacteristic(_txUuid);
        _rxChar = svc.getCharacteristic(_rxUuid);
        if (_txChar == null || _rxChar == null) {
            gModel.setStatus("Chars missing");
            return;
        }
        var cccd = _txChar.getDescriptor(Ble.cccdUuid());
        if (cccd == null) {
            gModel.setStatus("CCCD missing");
            return;
        }
        _subscribing = true;
        try {
            cccd.requestWrite([0x01, 0x00]b);
        } catch (ex) {
            _subscribing = false;
            gModel.setStatus("Notify req failed");
        }
    }

    function onDescriptorWrite(descriptor, status) {
        _subscribing = false;
        System.println("[link] notify enable status " + status);
        if (status == Ble.STATUS_SUCCESS) {
            _ready = true;
            gModel.connected = true;
            beginSession();
        } else if (status == 18 || status == 19) {
            // The node wants an encrypted link before it will turn notifications
            // on (nRF52 nodes guard this descriptor; ESP32 nodes leave it open).
            // The watch is not seen to pair after a refused descriptor write, but
            // it does pair after a refused command write, so send one now. Its
            // reply (18) lands in onCharacteristicWrite, which waits for
            // onEncryptionStatus; that then re-runs subscribe() while _ready is
            // still false, and the notify-enable succeeds on the encrypted link.
            gModel.setStatus("Pairing...");
            _txSlices = null;
            writeChunk([Proto.CMD_DEVICE_QUERY, 3]b);
        } else {
            gModel.setStatus("Pairing...");
        }
    }

    // ---------------------------------------------------------------- session

    function beginSession() {
        gModel.setStatus("Handshake...");
        _q = [];
        _inflight = null;
        enqueue([Proto.CMD_DEVICE_QUERY, 3]b);
        // APP_START: [1][7 reserved]["MeckWatch"]
        enqueue([Proto.CMD_APP_START, 0, 0, 0, 0, 0, 0, 0,
                 0x4D, 0x65, 0x63, 0x6B, 0x57, 0x61, 0x74, 0x63, 0x68]b);
        enqueue([Proto.CMD_MECK_HELLO, 1]b);
        // Clear any scope a phone app left set on the node, so watch sends use
        // the channel's own region (then the device default) like node-typed ones.
        enqueue([Proto.CMD_SET_FLOOD_SCOPE_KEY, 0]b);
        pump();
    }

    // Channels (count from device info), canned slots (Meck only), battery,
    // then the message sync.
    function finishHandshake(cannedSlots) {
        for (var c = 0; c < gModel.maxChannels; c++) {
            _q.add([Proto.CMD_GET_CHANNEL, c]b);
        }
        for (var s = 0; s < cannedSlots; s++) {
            _q.add([Proto.CMD_MECK_GET_CANNED, s]b);
        }
        _q.add([Proto.CMD_GET_BATT_AND_STORAGE]b);
        _syncPending = true;   // runs after the queue drains
        pump();
    }

    function enqueue(frame) {
        _q.add(frame);
        pump();
    }

    // Send the next command if nothing is in flight.
    function pump() {
        if (!_ready || _inflight != null || _writeBusy) {
            return;
        }
        if (_q.size() == 0) {
            if (_syncPending) {
                _syncPending = false;
                _q.add([Proto.CMD_SYNC_NEXT_MESSAGE]b);
            } else {
                return;
            }
        }
        _inflight = _q[0];
        _q = _q.slice(1, _q.size());
        writeFrame(_inflight);
        gSched.after(5000, "timeout", method(:onTimeout));
    }

    function onTimeout() {
        if (_inflight != null) {
            System.println("[link] timeout on cmd " + _inflight[0]);
            _inflight = null;
            _txSlices = null;
            _writeBusy = false;
            pump();
        }
    }

    // Write one frame. Frames longer than a packet go as tagged slices
    // (F0 first, F1 middle, F2 last); short ones go untagged.
    function writeFrame(frame) {
        if (frame.size() <= Proto.SLICE_MAX) {
            _txSlices = null;
            writeChunk(frame);
            return;
        }
        var first = null;
        var rest = [];
        var off = 0;
        while (off < frame.size()) {
            var n = frame.size() - off;
            if (n > Proto.SLICE_MAX) {
                n = Proto.SLICE_MAX;
            }
            var last = (off + n >= frame.size());
            var tag = (off == 0) ? 0xF0 : (last ? 0xF2 : 0xF1);
            var chunk = [tag, n]b;
            chunk = chunk.addAll(frame.slice(off, off + n));
            if (first == null) {
                first = chunk;
            } else {
                rest.add(chunk);
            }
            off += n;
        }
        _txSlices = rest;
        writeChunk(first);
    }

    function writeChunk(bytes) {
        _writeBusy = true;
        try {
            _rxChar.requestWrite(bytes, {:writeType => Ble.WRITE_TYPE_WITH_RESPONSE});
        } catch (ex) {
            _writeBusy = false;
            gModel.setStatus("Write failed");
        }
    }

    function onCharacteristicWrite(characteristic, status) {
        _writeBusy = false;
        if (status == Ble.STATUS_SUCCESS) {
            if (_txSlices != null && _txSlices.size() > 0) {
                var next = _txSlices[0];
                _txSlices = _txSlices.slice(1, _txSlices.size());
                writeChunk(next);
            }
            return;
        }
        if (status == 18 || status == 19) {
            // Not yet encrypted: the watch pairs now; retry after onEncryptionStatus.
            System.println("[link] write status " + status + ", waiting for encryption");
            _awaitEnc = true;
            _txSlices = null;
            gModel.setStatus("Pairing...");
            return;
        }
        System.println("[link] write status " + status);
        _inflight = null;
        _txSlices = null;
        gSched.cancel("timeout");
        pump();
    }

    // ---------------------------------------------------------------- receive

    function onCharacteristicChanged(characteristic, value) {
        if (value == null || value.size() < 1) {
            return;
        }
        var tag = value[0];
        if (tag >= 0xF0 && tag <= 0xF3) {
            try {
                if (tag == 0xF0 || tag == 0xF3) {
                    _rxBuf = []b;
                }
                if (_rxBuf == null || value.size() < 2) {
                    return;
                }
                var n = value[1];
                if (n > value.size() - 2) { n = value.size() - 2; }
                _rxBuf = _rxBuf.addAll(value.slice(2, 2 + n));
                if (tag == 0xF2 || tag == 0xF3) {
                    var frame = _rxBuf;
                    _rxBuf = null;
                    handleFrame(frame);
                }
            } catch (ex) {
                _rxBuf = null;
            }
            return;
        }
        handleFrame(value);
    }

    function handleFrame(f) {
        var code = f[0];
        if (code >= 0x80) {
            if (code == Proto.PUSH_MSG_WAITING) {
                _syncPending = true;
                pump();
            } else if (code == Proto.PUSH_TRACE_DATA) {
                parseTraceResult(f);
            } else if (code == Proto.PUSH_LOGIN_SUCCESS) {
                gModel.adminResult(true);
            } else if (code == Proto.PUSH_LOGIN_FAIL) {
                gModel.adminResult(false);
            } else if (code == Proto.PUSH_CONTROL_DATA) {
                parseControlData(f);
            } else if (code == Proto.PUSH_NEW_ADVERT) {
                // A Meck node applies its own auto-add settings; nothing to do.
                // A standard node expects the app to decide: add repeaters only,
                // by sending the pushed contact back as an add-contact command
                // (the two frames share the same body).
                if (!gModel.meckExt && f.size() >= 34 && f[33] == Proto.ADV_TYPE_REPEATER) {
                    var add = [Proto.CMD_ADD_UPDATE_CONTACT]b;
                    add = add.addAll(f.slice(1, f.size()));
                    enqueue(add);
                    gModel.showToast("Added repeater");
                }
            }
            return;   // other pushes ignored
        }
        // A reply: it completes whatever is in flight.
        gSched.cancel("timeout");
        var cmd = (_inflight != null) ? _inflight[0] : -1;
        var sub = (_inflight != null && _inflight.size() > 1) ? _inflight[1] : -1;
        _inflight = null;

        if (code == Proto.RESP_DEVICE_INFO) {
            // [13][fw_code][max_contacts/2][max_channels][pin:4][build:12][manufacturer:40][fw version:20]
            if (f.size() > 3) {
                gModel.maxChannels = f[3];
            }
            if (f.size() >= 60) {
                gModel.manufacturer = bytesToString(f, 20, 40);
            }
            if (f.size() >= 80) {
                gModel.fwVersion = bytesToString(f, 60, 20);
            }
        } else if (code == Proto.RESP_SELF_INFO) {
            // [5][type][tx_pwr][max_tx][pubkey:32][lat:4][lon:4][...][name from 58]
            if (f.size() >= 36) {
                gModel.nodeKey = hexOf(f.slice(4, 10));
                gModel.loadRegions();
            }
            if (f.size() > 58) {
                gModel.nodeName = bytesToString(f, 58, f.size() - 58);
            }
            gModel.setStatus("Node: " + gModel.nodeName);
        } else if (code == Proto.RESP_MECK_INFO) {
            gModel.meckExt = true;
            var slots = (f.size() > 2) ? f[2] : 10;
            if (f.size() > 3) {
                gModel.bph = f[3];
            }
            finishHandshake(slots);
        } else if (code == Proto.RESP_CHANNEL_INFO) {
            if (f.size() >= 34) {
                var nm = bytesToString(f, 2, 32);
                if (nm.length() > 0) {
                    gModel.channels.add({:idx => f[1], :name => nm});
                }
            }
        } else if (code == Proto.RESP_MECK_CANNED) {
            if (f.size() > 2) {
                gModel.canned.add(bytesToString(f, 2, f.size() - 2));
            }
        } else if (code == Proto.RESP_MECK_SCOPE) {
            if (f.size() >= 2) {
                var sn = (f.size() > 2) ? bytesToString(f, 2, f.size() - 2) : "";
                gModel.scopes.put(f[1], sn);
            }
        } else if (code == Proto.RESP_MECK_CHANNEL_MSG
                   || code == Proto.RESP_CHANNEL_MSG_V3
                   || code == Proto.RESP_CHANNEL_MSG) {
            parseChannelMsg(f, code);
            _syncPending = true;   // ask for the next one
        } else if (code == Proto.RESP_CONTACT_MSG_V3 || code == Proto.RESP_CONTACT_MSG) {
            parseContactMsg(f, code);
            _syncPending = true;   // keep draining the queue past DMs
        } else if (code == Proto.RESP_MECK_FAV) {
            parseFav(f);
        } else if (code == Proto.RESP_MECK_RESOLVE) {
            // [plen][prefix][name]
            if (f.size() >= 2) {
                var plen = f[1];
                if (f.size() >= 2 + plen) {
                    var key = hexOf(f.slice(2, 2 + plen));
                    var nm = (f.size() > 2 + plen) ? bytesToString(f, 2 + plen, f.size() - 2 - plen) : "";
                    gModel.names.put(key, nm);
                }
            }
        } else if (code == Proto.RESP_NO_MORE_MESSAGES) {
            _syncPending = false;
            gModel.setStatus("Synced");
        } else if (code == Proto.RESP_MECK_SENT_TRACK) {
            parseSentTrack(f);
        } else if (code == Proto.RESP_MECK_DISCOVER) {
            parseDiscover(f);
        } else if (code == Proto.RESP_BATT_AND_STORAGE) {
            // [12][millivolts:2 LE][storage used:4][storage total:4]
            if (f.size() >= 3) {
                gModel.nodeMv = f.decodeNumber(Lang.NUMBER_FORMAT_UINT16, {:offset => 1, :endianness => Lang.ENDIAN_LITTLE});
            }
        } else if (code == Proto.RESP_OK) {
            if (cmd == Proto.CMD_SEND_CHANNEL_TXT_MSG) {
                gModel.showToast("Sent!");
                if (!gModel.meckExt) { WatchUi.requestUpdate(); pump(); return; }
                _q.add([Proto.CMD_MECK_GET_SENT_TRACK, 0]b);   // learn the fingerprint
                // Echoes from repeaters arrive over the next few seconds.
                gSched.after(4000, "heard1", method(:refreshSentTrack));
                gSched.after(10000, "heard2", method(:refreshSentTrack));
            }
        } else if (code == Proto.RESP_ERR) {
            System.println("[link] err " + ((f.size() > 1) ? f[1] : 0) + " for cmd " + cmd);
            if (cmd == Proto.CMD_MECK_HELLO) {
                // Not a Meck node: standard companion protocol only.
                gModel.meckExt = false;
                gModel.useWatchCanned();   // the watch's own slots stand in for the node's
                gModel.setStatus("Standard node");
                finishHandshake(0);
            } else if (cmd == Proto.CMD_SEND_LOGIN) {
                gModel.adminResult(false);
            } else if (cmd == Proto.CMD_MECK_GET_FAV) {
                // Standard node whose firmware has no favourites command.
                _favBusy = false;
                gModel.favUnsupported = true;
            } else if (cmd == Proto.CMD_SET_FLOOD_SCOPE_KEY && sub == 1) {
                // Standard firmware before v12 has no "all regions" sub-command.
                // Clear the override instead, so the node sends on its own
                // default; the channel message is still queued behind it.
                gModel.showToast("No all-regions on node");
                var nq = [[Proto.CMD_SET_FLOOD_SCOPE_KEY, 0]b];
                for (var i = 0; i < _q.size(); i++) { nq.add(_q[i]); }
                _q = nq;
            } else if (cmd == Proto.CMD_SEND_TXT_MSG) {
                gModel.cliFailed();
            }
        }
        WatchUi.requestUpdate();
        pump();
    }

    // Rich frame 0x63: [snr*4][scope][path_len][ch][txt][ts:4][path bytes][text]
    // V3 frame 17:     [snr*4][res][res][ch][path_len][txt][ts:4][text]
    // V1 frame 8:      [ch][path_len][txt][ts:4][text]
    function parseChannelMsg(f, code) {
        var snr = 0;
        var scope = 0xFF;
        var ch;
        var pathLen;
        var ts;
        var path = null;
        var textOff;
        if (code == Proto.RESP_MECK_CHANNEL_MSG) {
            if (f.size() < 10) { return; }
            snr = toSigned(f[1]);
            scope = f[2];
            pathLen = f[3];
            ch = f[4];
            ts = u32le(f, 6);
            var plen = (pathLen != 0xFF) ? pathLen : 0;
            if (plen > 0 && 10 + plen <= f.size()) {
                path = f.slice(10, 10 + plen);
            }
            textOff = 10 + plen;
        } else if (code == Proto.RESP_CHANNEL_MSG_V3) {
            if (f.size() < 10) { return; }
            snr = toSigned(f[1]);
            ch = f[4];
            pathLen = f[5];
            ts = u32le(f, 7);
            textOff = 11;
        } else {
            if (f.size() < 7) { return; }
            ch = f[1];
            pathLen = f[2];
            ts = u32le(f, 4);
            textOff = 8;
        }
        var text = (textOff < f.size()) ? bytesToString(f, textOff, f.size() - textOff) : "";
        text = flatten(text);
        var sender = "";
        var body = text;
        var sep = text.find(": ");
        if (sep != null) {
            sender = text.substring(0, sep);
            body = text.substring(sep + 2, text.length());
        }
        var sent = (gModel.nodeName.length() > 0 && sender.equals(gModel.nodeName));
        var m = {
            :ch => ch, :sender => sender, :text => body, :ts => ts,
            :hops => pathLen, :path => path, :snr => snr, :scope => scope,
            :sent => sent, :fp => null, :heard => null,
            :rx => Time.now().value()
        };
        gModel.addMessage(ch, m, !sent);
        if (gModel.meckExt && scope < 0xFE && !gModel.scopes.hasKey(scope) && !_scopeReq.hasKey(scope)) {
            _scopeReq.put(scope, true);
            _q.add([Proto.CMD_MECK_GET_SCOPE, scope]b);
        }
    }

    // 0x62: [n][active][fp*12][repeats][bph][count][hash*bph*count][snr*count]
    function parseSentTrack(f) {
        if (f.size() < 3 || f[2] == 0) {
            return;
        }
        if (f.size() < 18) {
            return;
        }
        var fp = f.slice(3, 15);
        var repeats = f[15];
        var bph = f[16];
        var count = f[17];
        var hashes = [];
        var snrs = [];
        var off = 18;
        for (var i = 0; i < count; i++) {
            if (off + bph <= f.size()) {
                hashes.add(f.slice(off, off + bph));
            }
            off += bph;
        }
        for (var j = 0; j < count; j++) {
            if (off < f.size()) {
                snrs.add(toSigned(f[off]));
            }
            off++;
        }
        var heard = {:repeats => repeats, :bph => bph, :hashes => hashes, :snrs => snrs};
        // Attach to the sent message with this fingerprint, or to the most
        // recent sent message that has none yet (the one we just sent).
        var keys = gModel.msgs.keys();
        var newest = null;
        for (var k = 0; k < keys.size(); k++) {
            var a = gModel.msgs.get(keys[k]);
            for (var x = a.size() - 1; x >= 0; x--) {
                var m = a[x];
                if (!m.get(:sent)) { continue; }
                var mfp = m.get(:fp);
                if (mfp != null && bytesEqual(mfp, fp)) {
                    m.put(:heard, heard);
                    heardToast(m, heard);
                    WatchUi.requestUpdate();
                    return;
                }
                if (mfp == null && (newest == null || m.get(:rx) > newest.get(:rx))) {
                    newest = m;
                }
            }
        }
        if (newest != null) {
            newest.put(:fp, fp);
            newest.put(:heard, heard);
            heardToast(newest, heard);
            WatchUi.requestUpdate();
        }
    }

    // "Heard by N" for a message sent in the last 20 seconds, once echoes exist.
    function heardToast(m, heard) {
        var n = heard.get(:hashes).size();
        if (n > 0 && (Time.now().value() - m.get(:rx)) <= 20) {
            gModel.showToast("Heard by " + n);
        }
    }

    // ---------------------------------------------------------------- actions

    // Send text on a channel. Recorded locally at once; fingerprint and
    // Heard-by arrive via the sent-track query after the node says OK.
    function sendChannelText(chIdx, text) {
        if (!_ready) {
            gModel.setStatus("Not connected");
            return;
        }
        var ts = Time.now().value();
        var frame = [Proto.CMD_SEND_CHANNEL_TXT_MSG, 0, chIdx, 0, 0, 0, 0]b;
        frame.encodeNumber(ts, Lang.NUMBER_FORMAT_UINT32, {:offset => 3, :endianness => Lang.ENDIAN_LITTLE});
        frame = frame.addAll(stringToBytes(text));
        var m = {
            :ch => chIdx, :sender => gModel.nodeName, :text => text, :ts => ts,
            :hops => 0xFF, :path => null, :snr => 0, :scope => 0xFF,
            :sent => true, :fp => null, :heard => null, :rx => ts
        };
        if (!gModel.meckExt) {
            m.put(:fp, []b);   // no sent-track on a standard node; leave Heard-by blank
        }
        gModel.addMessage(chIdx, m, false);
        _q.add(scopeFrameFor(chIdx));
        enqueue(frame);
    }

    // Command 54 frame sent ahead of every channel message. A Meck node keeps
    // its own per-channel regions, so the override is just cleared (sub-command
    // 0, no key) and the node applies its channel region or device default; a
    // standard node has no per-channel region, so the watch's own setting is
    // applied: node default = clear, all regions = sub-command 1 (firmware
    // v12+), a named region = sub-command 0 plus the region's 16-byte key.
    function scopeFrameFor(chIdx) {
        if (!gModel.meckExt) {
            var r = gModel.regionFor(chIdx);
            if (r != null) {
                if ("*".equals(r)) {
                    return [Proto.CMD_SET_FLOOD_SCOPE_KEY, 1]b;
                }
                var frame = [Proto.CMD_SET_FLOOD_SCOPE_KEY, 0]b;
                return frame.addAll(regionKey(r));
            }
        }
        return [Proto.CMD_SET_FLOOD_SCOPE_KEY, 0]b;
    }

    // Transport key for a public region: the first 16 bytes of SHA-256 over
    // "#" + name (TransportKeyStore::getAutoKeyFor on the node; the phone
    // apps derive it the same way). A name already starting with "#" is used
    // as typed.
    function regionKey(name) {
        var tagged = name.substring(0, 1).equals("#") ? name : ("#" + name);
        var h = new Cryptography.Hash({:algorithm => Cryptography.HASH_SHA256});
        h.update(stringToBytes(tagged));
        var d = h.digest();
        return d.slice(0, 16);
    }

    // Drop the link and start again (Settings > Reconnect).
    function reconnect() {
        gSched.cancel("rescan");
        Ble.setScanState(Ble.SCAN_STATE_OFF);
        if (_device != null) {
            Ble.unpairDevice(_device);   // triggers onConnectedStateChanged(DISCONNECTED) -> rescan
        } else {
            startScan();
        }
    }

    // Node battery refresh (home screen, once a minute).
    function requestBattery() {
        if (_ready) {
            enqueue([Proto.CMD_GET_BATT_AND_STORAGE]b);
        }
    }

    // ---- Contact messages (DMs and CLI replies) ----
    // V3 (16): [snr*4][res][res][prefix:6][path_len][txt_type][ts:4][text]
    // V1 (7):  [prefix:6][path_len][txt_type][ts:4][text]
    function parseContactMsg(f, code) {
        var prefix;
        var txt;
        var off;
        if (code == Proto.RESP_CONTACT_MSG_V3) {
            if (f.size() < 16) { return; }
            prefix = f.slice(4, 10);
            txt = f[11];
            off = 16;
        } else {
            if (f.size() < 13) { return; }
            prefix = f.slice(1, 7);
            txt = f[8];
            off = 13;
        }
        if (txt != Proto.TXT_TYPE_CLI) {
            return;   // plain DMs are out of scope for v1
        }
        var text = (off < f.size()) ? bytesToString(f, off, f.size() - off) : "";
        gModel.cliReply(hexOf(prefix), text);
    }

    // ---- Favourites ----
    var _favBusy = false;

    function favsFetch() {
        if (!_ready || _favBusy) {
            return;
        }
        gModel.favs = [];
        gModel.favUnsupported = false;
        _favBusy = true;
        enqueue([Proto.CMD_MECK_GET_FAV, 0]b);
    }

    // 0x66: [n][count] then, if n < count: [type][last_advert:4][pubkey:32][name]
    function parseFav(f) {
        if (f.size() < 3) { _favBusy = false; return; }
        var n = f[1];
        var count = f[2];
        gModel.favCount = count;
        if (n < count && f.size() >= 40) {
            var e = {
                :type => f[3], :last => u32le(f, 4), :pubkey => f.slice(8, 40),
                :name => (f.size() > 40) ? bytesToString(f, 40, f.size() - 40) : ""
            };
            while (gModel.favs.size() <= n) {
                gModel.favs.add(null);
            }
            gModel.favs[n] = e;
        }
        if (n + 1 < count) {
            _q.add([Proto.CMD_MECK_GET_FAV, n + 1]b);
        } else {
            _favBusy = false;
        }
        WatchUi.requestUpdate();
    }

    // Ask the node for the contact name behind a pubkey prefix (once each).
    var _resolveReq = {};

    function resolve(prefixBytes) {
        var key = hexOf(prefixBytes);
        if (!_ready || gModel.names.hasKey(key) || _resolveReq.hasKey(key)) {
            return;
        }
        _resolveReq.put(key, true);
        var frame = [Proto.CMD_MECK_RESOLVE, prefixBytes.size()]b;
        frame = frame.addAll(prefixBytes);
        enqueue(frame);
    }

    // ---- Repeater admin ----
    // Standard login: [26][pubkey:32][password]. Result arrives as a push.
    function login(pubkey, password) {
        if (!_ready) {
            gModel.setStatus("Not connected");
            return false;
        }
        var frame = [Proto.CMD_SEND_LOGIN]b;
        frame = frame.addAll(pubkey);
        frame = frame.addAll(stringToBytes(password));
        enqueue(frame);
        return true;
    }

    // CLI command to a logged-in repeater: standard text send, type 1.
    // [2][txt_type=1][attempt=0][ts:4][pubkey prefix:6][text]
    function sendCli(pubkey, text) {
        if (!_ready) {
            gModel.setStatus("Not connected");
            return false;
        }
        var ts = Time.now().value();
        var frame = [Proto.CMD_SEND_TXT_MSG, Proto.TXT_TYPE_CLI, 0, 0, 0, 0, 0]b;
        frame.encodeNumber(ts, Lang.NUMBER_FORMAT_UINT32, {:offset => 3, :endianness => Lang.ENDIAN_LITTLE});
        frame = frame.addAll(pubkey.slice(0, 6));
        frame = frame.addAll(stringToBytes(text));
        enqueue(frame);
        return true;
    }

    function hexOf(ba) {
        var s = "";
        for (var i = 0; i < ba.size(); i++) {
            s = s + ba[i].format("%02x");
        }
        return s;
    }

    // ---- Discover ----
    var _discBusy = false;    // a poll round (entries 0..count-1) is in progress
    var _discTag = null;      // standard node: the 4 tag bytes our request carried

    function discoverStart() {
        if (!_ready) {
            gModel.setStatus("Not connected");
            return;
        }
        gModel.discovered = [];
        gModel.discoverCount = 0;
        gModel.discoverActive = true;
        if (!gModel.meckExt) {
            // Standard node: send Meck's discovery request ourselves through the
            // standard control-data command, zero hop, asking repeaters and room
            // servers: [55][0x80][filter][tag:4][since:4 = 0, any firmware].
            // Replies come back as 0x8E pushes (parseControlData) for 30 s.
            var tag = (Math.rand() & 0x7FFFFFFF) | 1;
            _discTag = [0, 0, 0, 0]b;
            _discTag.encodeNumber(tag, Lang.NUMBER_FORMAT_UINT32, {:offset => 0, :endianness => Lang.ENDIAN_LITTLE});
            var frame = [Proto.CMD_SEND_CONTROL_DATA, Proto.CTL_DISCOVER_REQ,
                         (1 << Proto.ADV_TYPE_REPEATER) | (1 << Proto.ADV_TYPE_ROOM)]b;
            frame = frame.addAll(_discTag);
            frame = frame.addAll([0, 0, 0, 0]b);
            enqueue(frame);
            gSched.after(30000, "discEnd", method(:discoverEnd));
            return;
        }
        _q.add([Proto.CMD_MECK_DISCOVER_START]b);
        discoverPoll();
    }

    // Standard node, end of the 30 s window. Names are asked for now rather
    // than as replies arrive, so the lookups do not compete with the replies
    // for the node's small outgoing queue. A key that had no contact name last
    // time is asked again, in case the node has added it since.
    function discoverEnd() {
        if (gModel.meckExt) {
            return;
        }
        gModel.discoverActive = false;
        for (var i = 0; i < gModel.discovered.size(); i++) {
            var e = gModel.discovered[i];
            if (e == null || e.get(:pubkey) == null) { continue; }   // left from a Meck scan
            var pk = e.get(:pubkey);
            var k = hexOf(pk);
            if (gModel.names.hasKey(k) && gModel.names.get(k).length() == 0) {
                gModel.names.remove(k);
                _resolveReq.remove(k);
            }
            resolve(pk);
        }
        WatchUi.requestUpdate();
    }

    // 0x8E: [snr*4][rssi][path_len][payload]. A discovery reply's payload is
    // [0x90 | type][snr*4 the replier heard us at][tag:4][pubkey:32]. Kept
    // like Meck: our tag only, full keys only, up to 20, a repeat updates SNR,
    // name shown as the first 4 key bytes in hex until the node resolves it.
    function parseControlData(f) {
        if (gModel.meckExt || !gModel.discoverActive || _discTag == null) {
            return;
        }
        if (f.size() < 42 || (f[4] & 0xF0) != Proto.CTL_DISCOVER_RESP) {
            return;
        }
        if (!bytesEqual(f.slice(6, 10), _discTag)) {
            return;
        }
        var pk = f.slice(10, 42);
        var snr = toSigned(f[5]);
        for (var i = 0; i < gModel.discovered.size(); i++) {
            var d = gModel.discovered[i];
            if (d == null || d.get(:pubkey) == null) { continue; }   // left from a Meck scan
            if (bytesEqual(d.get(:pubkey), pk)) {
                d.put(:snr, snr);
                WatchUi.requestUpdate();
                return;
            }
        }
        if (gModel.discovered.size() >= 20) {
            return;
        }
        var nm = "";
        for (var b = 10; b < 14; b++) {
            nm = nm + f[b].format("%02X");
        }
        gModel.discovered.add({
            :type => f[4] & 0x0F, :snr => snr, :hops => f[3], :known => false,
            :prefix => f.slice(10, 12), :pubkey => pk, :key => hexOf(pk), :name => nm
        });
        gModel.discoverCount = gModel.discovered.size();
        WatchUi.requestUpdate();
    }

    // One round: entry 0 carries active/count; each entry queues the next.
    function discoverPoll() {
        if (!_ready || _discBusy) {
            return;
        }
        _discBusy = true;
        enqueue([Proto.CMD_MECK_DISCOVER_GET, 0]b);
    }

    // 0x65: [n][active][count] then, if n < count: [type][snr*4][path_len][known][pubkey:2][name]
    function parseDiscover(f) {
        if (f.size() < 4) { _discBusy = false; return; }
        var n = f[1];
        gModel.discoverActive = (f[2] != 0);
        var count = f[3];
        gModel.discoverCount = count;
        if (n < count && f.size() >= 10) {
            var e = {
                :type => f[4], :snr => toSigned(f[5]), :hops => f[6], :known => (f[7] != 0),
                :prefix => f.slice(8, 10),
                :name => (f.size() > 10) ? bytesToString(f, 10, f.size() - 10) : ""
            };
            while (gModel.discovered.size() <= n) {
                gModel.discovered.add(null);
            }
            gModel.discovered[n] = e;
        }
        if (gModel.discovered.size() > count) {
            gModel.discovered = gModel.discovered.slice(0, count);
        }
        if (n + 1 < count) {
            _q.add([Proto.CMD_MECK_DISCOVER_GET, n + 1]b);
        } else {
            _discBusy = false;
        }
        WatchUi.requestUpdate();
    }

    // ---- Trace ----
    // path: ByteArray of hashes; bph: 1 or 2 bytes per hop. Standard command:
    // [36][tag:4][auth:4][flags][path...] with flags low bits = hash width code.
    function sendTrace(path, bph) {
        if (!_ready) {
            gModel.setStatus("Not connected");
            return false;
        }
        var tag = (Math.rand() & 0x7FFFFFFF) | 1;
        var auth = (Math.rand() & 0x7FFFFFFF) | 1;
        var frame = [Proto.CMD_SEND_TRACE_PATH, 0, 0, 0, 0, 0, 0, 0, 0, (bph == 2) ? 1 : 0]b;
        frame.encodeNumber(tag, Lang.NUMBER_FORMAT_UINT32, {:offset => 1, :endianness => Lang.ENDIAN_LITTLE});
        frame.encodeNumber(auth, Lang.NUMBER_FORMAT_UINT32, {:offset => 5, :endianness => Lang.ENDIAN_LITTLE});
        frame = frame.addAll(path);
        gModel.trace = {:state => :running, :tag => tag, :sentAt => Time.now().value(),
                        :bph => bph, :hashes => [], :snrs => [], :final => 0, :ms => 0};
        enqueue(frame);
        return true;
    }

    // 0x89: [res][path_len][flags][tag:4][auth:4][hashes:path_len][snrs:hops][final snr]
    function parseTraceResult(f) {
        if (f.size() < 12) { return; }
        var t = gModel.trace;
        if (t == null) { return; }
        var pathLen = f[2];
        var sz = f[3] & 0x03;
        var tag = u32le(f, 4);
        if (tag != t.get(:tag)) { return; }   // not ours
        var bph = 1 << sz;
        var hops = (sz > 0) ? (pathLen >> sz) : pathLen;
        var off = 12;
        var hashes = [];
        for (var i = 0; i < hops && off + bph <= f.size(); i++) {
            hashes.add(f.slice(off, off + bph));
            off += bph;
        }
        var snrs = [];
        for (var j = 0; j < hops && off < f.size(); j++) {
            snrs.add(toSigned(f[off]));
            off++;
        }
        var fin = (off < f.size()) ? toSigned(f[off]) : 0;
        t.put(:state, :done);
        t.put(:hashes, hashes);
        t.put(:snrs, snrs);
        t.put(:final, fin);
        t.put(:ms, (Time.now().value() - t.get(:sentAt)) * 1000);
        WatchUi.requestUpdate();
    }

    // Ask the node for any queued messages now (called on wake).
    function syncNow() {
        if (_ready) {
            _syncPending = true;
            pump();
        }
    }

    // Refresh Heard-by for recent sends (tracking slots 0..3).
    function refreshSentTrack() {
        if (!_ready || !gModel.meckExt) {
            return;
        }
        for (var n = 0; n < 4; n++) {
            _q.add([Proto.CMD_MECK_GET_SENT_TRACK, n]b);
        }
        pump();
    }

    // ---------------------------------------------------------------- helpers

    function u32le(f, off) {
        return f.decodeNumber(Lang.NUMBER_FORMAT_UINT32, {:offset => off, :endianness => Lang.ENDIAN_LITTLE});
    }

    // Replace line breaks with spaces: Garmin draws "\n" as a real line break,
    // which would paint one message across several rows.
    function flatten(s) {
        var i = s.find("\n");
        while (i != null) {
            s = s.substring(0, i) + " " + s.substring(i + 1, s.length());
            i = s.find("\n");
        }
        i = s.find("\r");
        while (i != null) {
            s = s.substring(0, i) + " " + s.substring(i + 1, s.length());
            i = s.find("\r");
        }
        return s;
    }

    function toSigned(b) {
        return (b > 127) ? b - 256 : b;
    }

    function bytesEqual(a, b) {
        if (a.size() != b.size()) { return false; }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) { return false; }
        }
        return true;
    }

    // UTF-8 bytes (NUL-padded allowed) -> String
    function bytesToString(f, off, len) {
        var end = off + len;
        if (end > f.size()) { end = f.size(); }
        while (end > off && f[end - 1] == 0) { end--; }
        if (end <= off) { return ""; }
        var ba = f.slice(off, end);
        try {
            var s = StringUtil.convertEncodedString(ba, {
                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
            });
            if (s != null) { return s; }
        } catch (ex) {
        }
        var out = "";
        for (var i = 0; i < ba.size(); i++) {
            var c = ba[i];
            if (c >= 32 && c < 127) { out = out + c.toChar().toString(); }
        }
        return out;
    }

    function stringToBytes(s) {
        try {
            var ba = StringUtil.convertEncodedString(s, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            });
            if (ba != null) { return ba; }
        } catch (ex) {
        }
        var out = []b;
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var v = chars[i].toNumber();
            if (v < 128) { out = out.addAll([v]b); }
        }
        return out;
    }
}
