using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Lang;

// Talks the MeshCore companion protocol over the node's Nordic UART
// Service (NUS). Protocol facts verified against Meck dev @ c40e5e2:
//
//   - Service 6E400001-..., RX char ...0002 (we write commands),
//     TX char ...0003 (node notifies replies)  [SerialBLEInterface.cpp]
//   - One BLE write == one command frame; one notify == one reply
//     frame; no extra framing bytes             [onWrite/checkRecvFrame]
//   - CMD_APP_START: [0x01][7 reserved bytes][app name]  [MyMesh.cpp:1790]
//   - RESP_CODE_SELF_INFO reply: [0x05][adv][txpwr][max], 32-byte
//     public key, lat(4) lon(4), 4 pref bytes, freq(4) bw(4) sf cr,
//     then the node name from byte 58 to end of frame
//   - Node advertises as "MeshCore-<node name>"  [BLE_NAME_PREFIX]
//   - The link itself requires encrypted MITM bonding with a static
//     PIN (SC_MITM_BOND, ENC_MITM characteristic permissions), which
//     is exactly what this spike is testing from the Garmin side.
class SpikeBle extends Ble.BleDelegate {

    var _svcUuid;
    var _rxUuid;    // node's RX characteristic: commands go here
    var _txUuid;    // node's TX characteristic: replies arrive here
    var _device = null;
    var _rxChar = null;
    var _done = false;
    var _rxBuf = null;   // reassembly buffer for sliced frames (null = not mid-frame)

    function initialize() {
        BleDelegate.initialize();
        _svcUuid = Ble.stringToUuid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
        _rxUuid  = Ble.stringToUuid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
        _txUuid  = Ble.stringToUuid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
    }

    function start() {
        Ble.setDelegate(self);

        // Default connection strategy: no pairing forced at connect time.
        // Pairing is left to happen on demand, when the node refuses an
        // operation on a protected characteristic (as observed on the G2).
        StatusLog.add("Pairing: on demand");

        StatusLog.add("Registering profile...");
        try {
            Ble.registerProfile({
                :uuid => _svcUuid,
                :characteristics => [
                    {:uuid => _txUuid, :descriptors => [Ble.cccdUuid()]},
                    {:uuid => _rxUuid}
                ]
            });
        } catch (ex) {
            StatusLog.add("Profile reg threw");
        }
    }

    function restart() {
        if (_done || _device != null) {
            return;
        }
        StatusLog.add("Rescanning...");
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
    }

    function shutdown() {
        Ble.setScanState(Ble.SCAN_STATE_OFF);
        if (_device != null) {
            Ble.unpairDevice(_device);
        }
    }

    // ---- scanning ----

    function onProfileRegister(uuid, status) {
        StatusLog.add("Profile: " + status);
        if (status == Ble.STATUS_SUCCESS) {
            StatusLog.add("Scanning for MeshCore-*");
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        }
    }

    function onScanResults(scanResults) {
        if (_device != null) {
            return;
        }
        for (var r = scanResults.next(); r != null; r = scanResults.next()) {
            var sr = r as Ble.ScanResult;
            if (matches(sr)) {
                var nm = sr.getDeviceName();
                StatusLog.add("Found: " + (nm == null ? "(no name)" : nm));
                Ble.setScanState(Ble.SCAN_STATE_OFF);
                StatusLog.add("Connecting/pairing...");
                try {
                    _device = Ble.pairDevice(sr);
                } catch (ex) {
                    StatusLog.add("pairDevice threw");
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

    // ---- connection and security ----

    function onConnectedStateChanged(device, state) {
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            StatusLog.add("Connected");
            _device = device;
            subscribe();
        } else if (state == Ble.CONNECTION_STATE_DISCONNECTED) {
            StatusLog.add("Disconnected");
            _device = null;
            _rxChar = null;
        } else {
            // e.g. rejected for insufficient security (state 2)
            StatusLog.add("Conn state: " + state);
        }
    }

    function onEncryptionStatus(device, status) {
        StatusLog.add("Encrypt: " + status);
        if (status == Ble.STATUS_SUCCESS) {
            subscribe();
        }
    }

    // ---- the actual test ----

    function subscribe() {
        var svc = _device.getService(_svcUuid);
        if (svc == null) {
            StatusLog.add("UART svc missing!");
            listServices();
            return;
        }
        var txChar = svc.getCharacteristic(_txUuid);
        _rxChar = svc.getCharacteristic(_rxUuid);
        if (txChar == null || _rxChar == null) {
            StatusLog.add("Chars missing!");
            return;
        }
        var cccd = txChar.getDescriptor(Ble.cccdUuid());
        if (cccd == null) {
            StatusLog.add("CCCD missing!");
            return;
        }
        StatusLog.add("Enabling notify...");
        try {
            cccd.requestWrite([0x01, 0x00]b);
        } catch (ex) {
            StatusLog.add("CCCD write threw");
        }
    }

    // Print every service the watch discovered on this device, so a
    // missing UART service can be told apart from an empty discovery.
    // Device.getServices() returns an Iterator (Garmin API docs).
    function listServices() {
        try {
            var it = _device.getServices();
            if (it == null) {
                StatusLog.add("getServices: null");
                return;
            }
            var n = 0;
            for (var s = it.next(); s != null; s = it.next()) {
                var svc = s as Ble.Service;
                var u = svc.getUuid().toString();
                StatusLog.add(" svc " + u.substring(0, 13));
                n++;
            }
            StatusLog.add("Svcs listed: " + n);
        } catch (ex) {
            StatusLog.add("listServices threw");
        }
    }

    function onDescriptorWrite(descriptor, status) {
        StatusLog.add("Notify on: " + status);
        if (status == Ble.STATUS_SUCCESS) {
            sendAppStart();
        }
    }

    // CMD_APP_START = 0x01, seven reserved bytes, then "SPIKE".
    function sendAppStart() {
        var f = [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                 0x53, 0x50, 0x49, 0x4B, 0x45]b;
        StatusLog.add("TX APP_START " + f.size() + "B");
        try {
            _rxChar.requestWrite(f, {:writeType => Ble.WRITE_TYPE_WITH_RESPONSE});
        } catch (ex) {
            StatusLog.add("Cmd write threw");
        }
    }

    function onCharacteristicWrite(characteristic, status) {
        StatusLog.add("TX status: " + status);
    }

    // Frames from a node built with MECK_BLE_SMALL_MTU_SPLIT arrive as slices
    // with one leading tag byte: F0 first, F1 middle, F2 last, F3 single.
    // Strip the tag, collect until last/single, then handle as one frame.
    // Untagged notifications (a node without the flag) pass straight through.
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
                if (_rxBuf == null) {
                    StatusLog.add("slice w/o start");
                    return;
                }
                _rxBuf = _rxBuf.addAll(value.slice(1, value.size()));
                if (tag == 0xF2 || tag == 0xF3) {
                    var frame = _rxBuf;
                    _rxBuf = null;
                    handleFrame(frame);
                }
            } catch (ex) {
                StatusLog.add("reassembly threw");
                _rxBuf = null;
            }
            return;
        }
        handleFrame(value);
    }

    function handleFrame(value) {
        StatusLog.add("RX " + value.size() + "B code=" + value[0]);
        if (value[0] == 5) { // RESP_CODE_SELF_INFO
            _done = true;
            if (value.size() > 58) {
                var nm = "";
                for (var i = 58; i < value.size(); i++) {
                    var c = value[i];
                    if (c >= 32 && c < 127) {
                        nm = nm + c.toChar().toString();
                    }
                }
                StatusLog.add("Node: " + nm);
            } else {
                StatusLog.add("(reply truncated)");
            }
            StatusLog.add("*** SPIKE SUCCESS ***");
        }
    }
}
