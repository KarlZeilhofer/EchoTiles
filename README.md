# Echo Tiles Rhythm

Android rhythm-analysis fork of [Sidhant’s EchoTiles](https://github.com/sidhant947/EchoTiles).

## Try it

Download the APK at **https://alpenchat.at/downloads/**. Install **Echo Tiles Rhythm**
next to the F-Droid original; it has a separate application ID
(`at.zeilhofer.echotiles.rhythm`). Add a local song, press **Analyze now**, wait for
analysis, then press play and tap START. There is a two-second visual lead-in.
Re-analysis is available through the same button. Analysis can be cancelled.

## What changed

- Offline Android MediaExtractor/MediaCodec decoding on a worker thread, with
  progress and cancellation. MP3, AAC, FLAC, WAV and other device-supported
  formats use the system decoder; unsupported/corrupt/silent files show errors.
- Streaming 22.05 kHz mono analysis, 1024-sample Hann FFT, positive log spectral
  flux, adaptive local threshold and peak picking. No whole-song PCM buffer.
- Tiles follow actual detected onsets. Spectral brightness assigns four lanes;
  this is onset detection, **not polyphonic pitch transcription**. Tempo is an
  approximate estimate and does not quantize or replace the detected timestamps.
- Progressive difficulty: onset spacing decreases from 380 ms near the beginning
  to 140 ms at the end. Visual scrolling rises smoothly from 0.5 to 1.25 screen
  heights/second (2.5×). Notes still arrive at the judgment line on their detected
  audio timestamps; the audio itself is not sped up. Sparse passages stay sparse.
- This mode uses single-tap notes rather than randomly generated holds/chords.
  PERFECT/ GREAT/ GOOD timing windows are 50/100/160 ms; later misses end the run.
- Versioned JSON charts are saved in app-private files and reused after restart.
  Local file size/modification time is checked when loading from disk. Analyze
  again if a content-URI recording has been replaced. Songs longer than one hour
  are rejected to bound analysis resources.
- Pause/background transitions freeze the game clock; playback position updates
  keep the interpolated visual clock aligned. Muting still advances playback.

## Build and verify

Flutter **3.47.9** / Dart **3.13.7**, Java **21**, Android SDK 36 and NDK
28.2.13676358. Flutter/Gradle download missing Android components as needed.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
cd android && ./gradlew :app:testDebugUnitTest
```

With an Android emulator/device connected:

```sh
flutter test integration_test/rhythm_flow_test.dart -d emulator-5554
```

The native tests check synthetic beat alignment, tempo, silence, edge notes and
increasing note density. The device test decodes synthetic WAV and the bundled
MP3, checks chart caching, and opens/pauses the game through the actual UI.

Release signing uses `android/key.properties` when supplied; otherwise this
experimental fork uses the local Android debug key. Never replace the original
F-Droid app with this build. The `tools/rhythm-test-workflow.yml` template builds this fork and uploads a
test artifact without upstream signing secrets. It can be installed into
`.github/workflows` with a GitHub credential that has workflow permission.
The `web-downloads/index.html` template is deployed alongside the APK and a
SHA256SUMS file to the existing Alpenchat web root.

---

# Echo Tiles

Whether you love EDM, classical piano, pop hits, or indie beats, tap along to the music you already own—completely offline, private, and ad-free.

---

# Music Credits

- "Brain Dance" Kevin MacLeod (incompetech.com)  
  Licensed under Creative Commons: By Attribution 4.0 License  
  http://creativecommons.org/licenses/by/4.0/

---

# License

GPL v3