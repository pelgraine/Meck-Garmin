# Building and installing the Meck app

## One-time Mac setup

1. Install VS Code.
2. Install Java (adoptium.net, macOS installer for your chip).
3. Garmin Connect IQ SDK Manager (developer.garmin.com/connect-iq/sdk/):
   sign in, download the latest SDK and make it active, download the
   fenix 7S device files.
4. VS Code: install the "Monkey C" extension by Garmin. Restart.
5. Cmd+Shift+P -> "Monkey C: Verify Installation".

## Build

1. VS Code: File > Open Folder -> the `garmin` folder of this repo.
2. Cmd+Shift+P -> "Monkey C: Build for Device". The manifest lists only
   the fenix 7S, so it goes straight to the output folder; accept it. The
   first build generates a developer key; keep it.
3. Expect a long list of "Cannot determine if container access is using
   container type" warnings and no ERROR lines. The `.prg` lands in the
   project folder (default name `meckgarmin.prg`).

## Install on the watch

The fenix 7S is an MTP device; it does not appear in Finder.

1. Quit Garmin Express completely (check Activity Monitor for its service).
2. Open OpenMTP (openmtp.ganeshrvel.com) with the watch on its cable.
3. Drag the `.prg` into `GARMIN/APPS`. Overwrite if asked.
4. Optional log capture: create an empty `GARMIN/APPS/LOGS/MECKGARMIN.TXT`
   (name must match the `.prg`). Crashes write `GARMIN/APPS/LOGS/CIQ_LOG.YML`.
5. Eject. The app appears as "Meck" in the activity list (press Start).
   Installed `.prg` files vanish from APPS on the next mount; that is normal.

## Node side

The node must run Meck with these flags in `[env:meck_max_ble]`:

    -D MECK_BLE_JUST_WORKS=1
    -D MECK_BLE_SMALL_MTU_SPLIT=1
    -D MECK_WATCH_EXT=1
    -D BLE_DEBUG_LOGGING=1     ; optional diagnostics

BLE on at the node, phone Bluetooth off (the node accepts one connection),
then open Meck on the watch. The home screen footer walks through
Scanning, Found, Connected, Handshake, Node: <name>, Synced.
