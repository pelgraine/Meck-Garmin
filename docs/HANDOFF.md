# Meck Garmin -- project record

Garmin Connect IQ app (fenix 7S) that talks directly to a Meck node over
Bluetooth using the MeshCore companion protocol. No phone. Written for E by
Claude across one long conversation (September 2026); this file is the
record of what was established, decided, and left open, so nothing depends
on that conversation surviving.

Repository layout:

- `garmin/` -- the Meck app (Connect IQ, Monkey C). Build with the Garmin
  SDK and sideload; see `docs/BUILD.md`.
- `firmware/meck/` -- copies of the four Meck files as delivered, with all
  changes behind flags. The live versions are committed in the Meck repo
  (dev branch); these are here for reference and diffing.
- `spike/` -- the MeckSpike probe app that proved the pipe. Historical.
- `docs/` -- this file, the build guide, and the first crash log.

---

## 1. What was proven on hardware

- A Garmin fenix 7S can connect directly to a Meck node (T-Deck Max, Meck
  dev v1.13) over BLE and speak the standard MeshCore companion protocol.
  The original handoff document's "X25519 wall" never applied: the
  companion protocol carries plaintext frames both ways and the node does
  all mesh crypto. The same frame protocol runs over bare USB serial and
  raw TCP, which is the structural proof.
- Pairing: the Garmin can establish an encrypted link but cannot enter a
  PIN (Connect IQ has no passkey callback; verified from the BleDelegate
  API page). MeshCore's ESP32 BLE demands PIN-verified (MITM) bonding on
  both UART characteristics. Resolved on the node side with the
  `MECK_BLE_JUST_WORKS` flag.
- MTU: the Garmin never negotiates a larger ATT MTU (23 in every run), so
  the watch sees 20 bytes per notification. Resolved with tagged slicing on
  the node (`MECK_BLE_SMALL_MTU_SPLIT`) and reassembly on the watch.
- Full session verified: device query, app start, watch hello, channel
  fetch, canned slot fetch, message sync with the rich frame, sending from
  the watch (long writes sliced), Sent!/Heard-by, path overlay, keyboard.
- Discover and Trace screens delivered; Trace uses the standard command and
  push, Discover uses two Meck extension commands. Both awaiting E's
  hardware test at the time of writing.

## 2. Node firmware changes (Meck, dev branch)

All behind build flags in `[env:meck_max_ble]` (`variants/lilygo_tdeck_max/platformio.ini`):

    -D BLE_DEBUG_LOGGING=1        ; diagnostics only; prints "BLE:" lines
    -D MECK_BLE_JUST_WORKS=1      ; accept encrypted-but-unverified links
    -D MECK_BLE_SMALL_MTU_SPLIT=1 ; slice frames for peers with ATT MTU <= 23
    -D MECK_WATCH_EXT=1           ; Meck-only commands for a thin client

With every flag off, the files compile to what was there before (checked
mechanically, except one hoisting of two lookups in `onChannelMessageRecv`
with no behavioural change).

### `src/helpers/esp32/SerialBLEInterface.{cpp,h}`

- `MECK_BLE_JUST_WORKS`: `ESP_LE_AUTH_REQ_SC_BOND` instead of
  `..._SC_MITM_BOND`; characteristic permissions `READ_ENCRYPTED` /
  `WRITE_ENCRYPTED` instead of `..._ENC_MITM`. Static PIN stays set but is
  never asked for. Phones connect without a PIN too.
- `MECK_BLE_SMALL_MTU_SPLIT`: when `getPeerMTU(last_conn_id) <=
  MECK_BLE_SPLIT_MAX_MTU` (23), every outgoing frame goes as slices with one
  tag byte: `F0` first, `F1` middle, `F2` last, `F3` single. Incoming writes
  starting with a tag byte are reassembled in `onWrite`. Tags cannot
  collide: commands are < 0x80, pushes stop at 0x90. One slice per loop
  pass keeps `BLE_WRITE_MIN_INTERVAL` pacing.
- Two bugs fixed unconditionally (a bonded peer that encrypts at connect
  time reaches `onAuthenticationComplete` before `onConnect`):
  - stale peer address: `_remote_bda` is now taken from `cmpl.bd_addr` in
    `onAuthenticationComplete`, so the conn-param / PHY / DLE requests no
    longer fail with "Invalid connection remote_bda".
  - connected-state loss: `_auth_ok` flag; the loop guard restores
    `deviceConnected` once the GATT connect event has landed. Without this,
    every reply to the watch was silently dropped by `writeFrame`.

### `examples/companion_radio/MyMesh.{cpp,h}` (`MECK_WATCH_EXT`)

Codes (commands from 0x70, responses from 0x60; standard responses stop at
28, pushes start at 0x80):

    CMD_MECK_HELLO           0x70  [ver]  -> RESP_MECK_INFO 0x60 [ext_ver][canned_slots][bph][scope_count]
    CMD_MECK_GET_CANNED      0x71  [slot] -> RESP_MECK_CANNED 0x61 [slot][text]
    CMD_MECK_GET_SENT_TRACK  0x72  [n]    -> RESP_MECK_SENT_TRACK 0x62 [n][active][fp*12][repeats][bph][count][hash*bph*count][snr*count]
    CMD_MECK_GET_SCOPE       0x73  [idx]  -> RESP_MECK_SCOPE 0x64 [idx][name]
    CMD_MECK_DISCOVER_START  0x74         -> OK   (node's startDiscovery(), 30 s)
    CMD_MECK_DISCOVER_GET    0x75  [n]    -> RESP_MECK_DISCOVER 0x65 [n][active][count] (+ [type][snr*4][path_len][known][pubkey:2][name] if n < count)
    RESP_MECK_CHANNEL_MSG    0x63  [snr*4][scope_idx][path_len][channel_idx][txt_type][timestamp:4][path bytes][text]

Behaviour:
- `_meck_client` is set by HELLO, cleared by any `CMD_APP_START`.
- While set: `logRxRaw` sends no packet-log pushes (the watch was being
  flooded with code 0x88 frames); channel messages are queued as
  `RESP_MECK_CHANNEL_MSG` (region index + raw hop list, the same data the
  node's own screen gets).
- `CMD_SYNC_NEXT_MESSAGE` converts queued 0x63 frames back to V3/V1 for a
  non-watch client, so a phone connecting later reads them.
- `Frame::isChannelMsg()` includes 0x63 for offline-queue eviction.
- Sent-track reads the existing `_sent_track[]` (companion sends are
  recorded there by `sendFloodScoped`), same 10-minute expiry as the
  node's Heard-by.

## 3. Standard protocol facts used by the app (from MyMesh.cpp)

- `CMD_DEVICE_QEURY 22 [app_ver]` sets `app_target_ver`; V3 message frames
  need >= 3. Reply `RESP_CODE_DEVICE_INFO 13`: [fw_code][max_contacts/2][max_channels][pin:4][build:12][manufacturer:40][fw version:20].
- `CMD_APP_START 1 [7 reserved][app name]` -> `RESP_CODE_SELF_INFO 5`: node name from byte 58.
- `CMD_GET_CHANNEL 31 [idx]` -> `RESP_CODE_CHANNEL_INFO 18 [idx][name:32][secret:16]`, or ERR when absent.
- `PUSH_CODE_MSG_WAITING 0x83` -> `CMD_SYNC_NEXT_MESSAGE 10` until `RESP_CODE_NO_MORE_MESSAGES 10`.
- V3 channel frame 17: [snr*4][res][res][ch][path_len][txt_type][ts:4][text]; text is "sender: body". path_len 0xFF = not flood. Node-typed sends arrive this way too (`queueSentChannelMessage`).
- `CMD_SEND_CHANNEL_TXT_MSG 3 [txt_type=0][ch][ts:4][text]` -> OK/ERR.
- `CMD_SEND_TRACE_PATH 36 [tag:4][auth:4][flags][path bytes]`; flags & 3 = hash width code (0 = 1 byte, 1 = 2 bytes). Reply `RESP_CODE_SENT 6`. Result `PUSH_CODE_TRACE_DATA 0x89 [res][path_len][flags][tag:4][auth:4][hashes][snr per hop][final snr]`.
- `CMD_GET_BATT_AND_STORAGE 20` -> `12 [mV:2][used:4][total:4]`.
- Hash byte order in typed paths: as written ("3601" = 0x36 0x01).
- Region scope on sends: the node keeps `send_scope`, set by phone apps via
  `CMD_SET_FLOOD_SCOPE_KEY 54`, which outranks the channel's own region and
  persists in RAM. A stale phone value made a watch send go out unscoped.
  The app clears it (`[54][0]`) at session start and before every send, so
  the node falls to channel region, then device default, as for node-typed
  messages.

## 4. Garmin / Connect IQ facts established

- fenix 7S, firmware 27.18, Connect IQ 6.0.2 at time of testing. SDK 9.2.0.
- BLE: `Toybox.BluetoothLowEnergy`. Bonding APIs exist (`getBondedDevices`
  4.2.5, `onEncryptionStatus` 4.2.5 both list the 7S). `Device.requestBond()`
  fails with a fatal "System Error: Failed invoking <symbol>" on this
  firmware even though `has` reports it; do not call it. Setting
  `CONNECTION_STRATEGY_SECURE_PAIR_BOND` before connecting made the UART
  service invisible to discovery on Meck; the default strategy with
  on-demand pairing (write refused with status 18, then encryption) works.
- `Device.getServices()` returns an Iterator, not an array.
- Only one GATT operation may be in flight; the link queues commands.
- Status codes: 0 success, 18 insufficient authentication, 19 insufficient
  encryption, 100 bond fail.
- Emoji render from the system font (the node name's seedling drew from
  the first scan result). No emoji picker is wanted.
- Input: claiming `onSelect` in a BehaviorDelegate makes the watch deliver
  screen taps as Start presses, so `onTap` never sees coordinates. Read
  Start via `onKey` (`WatchUi.KEY_ENTER`) instead; taps then reach `onTap`.
- Timers: the watch caps concurrent `Timer.Timer` objects ("Too Many
  Timers Error" on send when the link, toast and a screen each held one).
  The app now has exactly one timer, wrapped by `Sched.mc`.
- Monkey C compiler quirks hit: indexing a literal-empty array is a
  compile error even if a loop fills it (keep the first element separately);
  start concatenations with a string; casts `as Ble.ScanResult` needed on
  iterator results; "container access" warnings are harmless.
- Sideloading: `.prg` into `GARMIN/APPS` via OpenMTP on a Mac (the watch is
  MTP-only, no Finder mount); log file `GARMIN/APPS/LOGS/<PRGNAME>.TXT`;
  crashes in `GARMIN/APPS/LOGS/CIQ_LOG.YML`.

## 5. The app (garmin/)

Files: `MeckApp` (entry, globals), `Model` (data + toast), `NodeLink` (BLE,
protocol, queue, slicing, parsers), `Draw` (layout helpers), `HomeView`,
`PickerView`, `ChannelView` (list, marquee, overlay), `CannedView`,
`ComposeView` (keyboard), `DiscoverView`, `TraceView`, `InfoViews`
(Settings).

Session order on connect: device query (v3) -> app start ("MeckWatch") ->
watch hello -> get every channel -> get every canned slot -> battery ->
sync loop. Scope names are fetched lazily when first seen. Long commands
are sliced with the same tags the node uses. Reconnects after a drop.

Screens and controls (fenix 7S, touch + five buttons):
- Home: clock in the top gap; node name, node volts (dark blue), watch
  battery (green); tiles Messages (unread badge), Settings, Discover, Trace
  in the icon's colours; link status at the bottom. Up/Down, Start, tap.
- Channels: green selected row, blue unread counts. Back returns home.
- Channel: one line per message; incoming cut at the edge, own messages
  right-aligned with "..." and the node name; Up/Down highlight and
  auto-marquee long lines; Start pauses the marquee; hold Up (Menu) or
  hold a line opens the path overlay; Down past the newest message
  highlights the compose bar; hold Up on the bar opens the canned list;
  swipe pages history ("-N" in the header).
- Path overlay (Meck Watch layout): "N hops, B-byte" / "Direct", "Rx:
  time", hop hashes wrapped by whole tokens, region bottom-left, [Reply]
  bottom-right; sent messages show Heard-by with hash and SNR and [Again].
- Compose: channel name top; single-line draft with Send at its right;
  Up opens the canned list, Down inserts a space, Start sends;
  QWERTY rows 20-22 x 36 px in the wide middle band; mode key lower /
  UPPER / 123 (30px wide, out to the circle edge); delete (likewise);
  Cnd (canned list, draft as prefix) and space at
  the bottom. 133-character cap.
- Canned: list, tap or Start sends. Reply prefills "@[sender] ".
- Discover: starts a scan on open, polls once a second while active;
  rows "type name  NdB|Nh [+]"; hold to rescan.
- Trace: hex pad (0-9, a-f, comma, delete, Run); last path remembered in
  Storage; results list per-hop hash and SNR, "Here" final SNR, elapsed
  ms; 30 s timeout.
- Settings: node name, firmware, link, counts; Reconnect; Clear messages.
- Toasts: "Sent!", then "Heard by N" as echoes arrive (re-checked 4 s and
  10 s after a send).

## 6. Decisions made

- Marquee for long lines (not expand-in-place).
- v1 scope: channels only. No DMs, no contacts, no emoji picker.
- Canned messages mirror the node's slots (edited on the node).
- Full path overlay in v1 (hence the Meck extensions).
- Tiles: Messages, Settings, Discover, Trace.
- Trace paths are typed as hex, not built from contacts.
- Node battery shown as volts (fuel gauge vs linear curve differ).
- Node battery refresh every 10 minutes on the home screen.

## 7. Open items and next steps

- Persistence: cache channels, canned slots and message history in
  `Application.Storage` so launches after the first are instant and
  messages survive closing the app (first-connect currently takes a few
  seconds while every channel and slot is fetched).
- Pixel font: Connect IQ supports custom bitmap fonts; the Meck Watch
  6x8 face at 2x would give the same 20-column grid on 240 px.
- Security: "just works" pairing means any device in range can pair while
  the node's BLE is on. Proposed mitigation: after the first bond, the
  node advertises only to the bonded device (ESP32 whitelist) until the
  user clears it on the node. Modest firmware change; not started.
- Standard-only fallback in the app when the watch hello is refused (would
  work against any node that has the two BLE changes).
- Upstreaming the slicing to MeshCore as a small-MTU-peer option.
- Spike-side leftover: nothing; the app supersedes it.
- Other Garmin models: bonding APIs date from late 2023 firmware; screen
  shapes and memory vary; button-only navigation already works.

## 8. Working rules that were in force

- No unsolicited changes; ask before acting; answer questions first.
- Evidence before assertion; checks shown in the same message; uploads
  are the only reliable base for firmware patches; complete files, not
  diffs; verify brace and #if balance; ASCII in added lines; UK spelling;
  no em dashes.
- E is a non-coder and does the flashing, building and testing; Claude
  writes the code and hands over files with the full steps each time.
