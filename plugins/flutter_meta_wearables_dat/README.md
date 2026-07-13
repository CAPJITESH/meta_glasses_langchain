# flutter_meta_wearables_dat

Camera streaming/photo capture and a voice bridge for Meta smart glasses, built on
Meta's [Wearables Device Access Toolkit](https://wearables.developer.meta.com/docs/develop) (DAT).

Android only for now — iOS is stubbed (every method/event throws/errors immediately).

## Two separate hardware paths — read this before using both together

The camera and the mic/speaker do **not** go through the same channel:

- **Camera** (`MetaWearablesCamera`) talks to the real DAT SDK (`mwdat-core`/`mwdat-camera`):
  `Wearables` -> `DeviceSession` -> `Stream`.
- **Mic and speaker** (`MetaWearablesAudio`) are **not** part of the DAT streaming API. Per
  Meta's docs, DAT sessions share mic/speaker access with the system Bluetooth stack — they're
  reached through standard Android Bluetooth profiles via `AudioManager`/`AudioRecord`/`AudioTrack`,
  not any `mwdat-*` class:

  | Profile | Direction | Quality | Used for |
  |---|---|---|---|
  | A2DP | Output only | 44.1/48 kHz stereo | `speak()` — playback through the glasses speaker |
  | HFP (Bluetooth SCO) | Bidirectional | 8 kHz mono | `startListening()` — mic capture from the glasses |

**A2DP and HFP are mutually exclusive.** Turning on HFP to listen switches the glasses off A2DP;
output quality drops to 8kHz mono for the duration of that HFP session. `MetaWearablesAudio`
models this as one `GlassesAudioMode` at a time (`idle` -> `listening` -> `speaking`), not
independent mic/speaker states — you cannot get high-quality playback and mic capture at the
same instant. If your app needs both voice and camera at once, call `startListening()` and wait
for `audioState` to report `isRouteSettled == true` *before* calling `startStream()` — the plugin
enforces this internally when both are used together, but the settle delay (~1.5-2s) is real and
happens on the Bluetooth Classic link, not something the plugin can hide.

## Setup: DAT SDK credentials

The DAT SDK (`mwdat-core`, `mwdat-camera`, `mwdat-mockdevice`) is published to a private GitHub
Packages repo (`facebook/meta-wearables-dat-android`) and needs a GitHub personal access token
with `read:packages` scope to resolve. **Never put this token in any file in this repo.** Instead:

```properties
# ~/.gradle/gradle.properties (outside any git repo)
gpr.token=<your-read:packages-scoped-token>
```

or export `GITHUB_TOKEN` in your shell before building. `android/build.gradle` reads
`gpr.token`/`GITHUB_TOKEN` at build time and contains no secrets itself.

Device pairing happens out-of-band through the Meta AI companion app plus a developer-mode
toggle on the host phone — this plugin doesn't implement its own pairing UI, it just connects
to whatever glasses are already paired via `AutoDeviceSelector()`.

## Known limitations

- Mic input is capped at 8kHz mono — a Bluetooth HFP profile limitation, not something this
  plugin can improve.
- Listening and high-quality playback are sequential, never simultaneous.
- The glasses' native "Hey Meta" wake word is not exposed by DAT — `startListening()` must be
  triggered from your own app UI.
