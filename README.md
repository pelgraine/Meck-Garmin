# Meck Garmin

Connect IQ app for the Garmin fenix 7S that talks directly to a Meck node
over BLE with the MeshCore companion protocol -- no phone in between.

- `garmin/` -- the app. See `docs/BUILD.md`.
- `firmware/meck/` -- reference copies of the Meck files carrying the
  node-side changes (all behind build flags). Live copies are in the Meck
  repo, dev branch.
- `spike/` -- the MeckSpike probe that proved the pipe (historical).
- `docs/HANDOFF.md` -- everything established, decided and left open.

Private; personal use. See HANDOFF.md section 7 for the security caveat.
