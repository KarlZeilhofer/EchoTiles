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
- Tiles follow actual detected onsets. Spectral brightness suggests a lane, then
  a deterministic allocator uses all four lanes in each group of four notes and
  avoids consecutive notes in the same lane. Holds reserve their lanes; other
  onsets use free lanes, with old holds shortened only if all four are occupied.
  Version 1.1.1 also applies the lane balancing to
  existing saved charts automatically; **no re-analysis is required**.
  Musical onset times, density and progressive scroll speed are preserved;
  this is onset detection, **not polyphonic pitch transcription**. Tempo is an
  approximate estimate and does not quantize or replace the detected timestamps.
- Progressive difficulty: onset spacing decreases from 380 ms near the beginning
  to 140 ms at the end. Visual scrolling rises smoothly from 0.5 to 1.25 screen
  heights/second (2.5×). Notes still arrive at the judgment line on their detected
  audio timestamps; the audio itself is not sped up. Sparse passages stay sparse.
- Version 1.2.0 detects dominant sustained tones using narrow-band energy,
  stable spectral peaks, relative RMS decay and pitch changes. Sustains of at
  least 400 ms become holds; short decaying hits and broadband noise stay taps.
  This is a conservative estimate in mixed music, not polyphonic transcription.
  Re-run **Analyze now** once to add durations to an older chart (v1 charts
  remain playable). Slider head and tail use the detected onset and offset;
  their spatial length scales with the current scroll speed. Hold one finger
  until the tail reaches the line; releasing up to 120 ms early is tolerated.
  After a pause, held lanes can be re-grabbed within 500 ms.
- Single-tap and hold starts use the same musical timing judgment.
  PERFECT/ GREAT/ GOOD timing windows are 50/100/220 ms. The tile's center mark
  crosses the judgment line at the onset. The line sits at 55% of playfield
  height from the top (45% from the bottom), shared by rendering and timing. Touch hardware timestamps compensate
  up to 120 ms of input dispatch delay; misses wait for that grace period.
  A small lane-edge tolerance and 80 ms same-lane bounce suppression prevent
  accidental extra failures.
- Versioned JSON charts are saved in app-private files and reused after restart.
  Local file size/modification time is checked when loading from disk. Analyze
  again if a content-URI recording has been replaced. Songs longer than one hour
  are rejected to bound analysis resources.
- A monotonic playback clock eases audio drift at at most ±10% rather than
  snapping on each sample; position queries run at 10 Hz instead of each vsync.
  Tiles repaint at vsync without rebuilding the widget tree. The opaque HUD
  updates at 10 Hz and no longer blurs the moving background.
- Pause/background transitions freeze the game clock. Muting still advances
  playback. Device tests play an entire synthetic click track to completion.

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
flutter test integration_test -d emulator-5554
```

The native tests check synthetic beat alignment, tempo, silence, edge notes,
progressive density, measured sustain lengths, pitch changes and noise rejection.
Device tests decode WAV/MP3, complete both a tap track and a hold track, verify
pause/re-grab, and check that releasing a slider early ends the run.

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