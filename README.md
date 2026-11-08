# Echo Tiles Rhythm

Android rhythm-analysis fork of [Sidhant’s EchoTiles](https://github.com/sidhant947/EchoTiles).

## Try it

Download the APK at **https://alpenchat.at/downloads/**. Install **Echo Tiles Rhythm**
next to the F-Droid original; it has a separate application ID
(`at.zeilhofer.echotiles.rhythm`). Add a local song, press **Analyze now**, wait for
analysis, then press play and tap START. The START tap hits the first real tile
and starts the music; there is no separate duplicate tile or countdown.
Re-analysis is available through the same button. Analysis can be cancelled.

## What changed

- Offline Android MediaExtractor/MediaCodec decoding on a worker thread, with
  progress and cancellation. MP3, AAC, FLAC, WAV and other device-supported
  formats use the system decoder; unsupported/corrupt/silent files show errors.
- Streaming 22.05 kHz mono analysis, 1024-sample Hann FFT, positive log spectral
  flux, adaptive local threshold and peak picking. No whole-song PCM buffer.
- Tiles follow actual detected onsets. Spectral brightness suggests a lane,
  with all four lanes used over the song. Since 1.3.1, the left thumb owns lanes
  0/1 and the right thumb owns lanes 2/3. A hold reserves its entire half plus
  a 100 ms release margin, so no chart requires crossing thumbs or holding
  one lane while tapping its neighbor with the same thumb. At most two tiles require a thumb at any
  instant, including holds plus taps. Extra accents are omitted while both
  thumbs are occupied; measured vocal/fade durations are preserved rather than
  repeatedly shortened into ordinary taps. Runtime input also limits holds to two.
  Version 1.1.1 also applies the lane balancing to
  existing saved charts automatically; **no re-analysis is required**.
  Retained notes keep their musical onset times and progressive scroll speed;
  this is onset detection, **not polyphonic pitch transcription**. Tempo is an
  approximate estimate and does not quantize or replace the detected timestamps.
- Progressive difficulty: onset spacing decreases from 380 ms near the beginning
  to 140 ms at the end. Visual scrolling rises smoothly from 0.5 to 1.25 screen
  heights/second (2.5×). Notes still arrive at the judgment line on their detected
  audio timestamps; the audio itself is not sped up. Sparse passages stay sparse.
- Version 1.3.0 follows quiet vocals and fading sounds using compact log-band
  spectral profiles, adaptive timbre tracking and relative decay thresholds.
  Changing dominant harmonics/vibrato no longer immediately cuts a held vocal.
  Steady broadband noise and actual silence do not become sliders. Measured
  sustains of at least **1 second** become holds; shorter notes remain taps.
  This is a heuristic for mixed music, not polyphonic source separation.
  Re-run **Analyze now** once for the new detector (v3 charts). Existing v1/v2
  charts remain playable and receive the two-thumb planning automatically.
  Hold until the tail reaches the line for the full bonus. Original forgiving
  release, movement and touch-cancellation behavior is retained.
- Version 1.3.1 restores the original live hold rewards: 220 points per held
  second, a combo increment at each 10% progress step, and 150 points plus two
  combo increments at completion. Fractional points carry between frames to
  avoid refresh-rate-dependent scoring. Pause and early release stop earning
  hold points; holding longer visibly increases the score before completion.
  Hand assignment also applies to saved charts without re-analysis.
- The START tile is the first real analyzed note. Its tap is scored immediately
  and is never discarded while audio prepares. Zero-time first notes and a
  first held note are covered by device tests without a second START tap.
- **Version 1.2.1 restores the original F-Droid 1.0.0 spatial hit test** from
  [upstream commit 6829d30](https://github.com/sidhant947/EchoTiles/blob/6829d30c6975e9ac213cb62f7e7e02c63b4dd1bb/lib/screens/game_screen.dart):
  bottom-anchored rectangles, 0.08 screen-height direct-tap padding, 0.18
  target-line tolerance, lowest candidate first, geometric rating thresholds
  0.05/0.11, and missed-tile boundary at y > 1.02. Painting and input share
  identical bounds. There is no independent millisecond hit gate, timestamp
  correction, cross-lane tolerance or premature beat-based miss timeout.
  The judgment line remains at 55% from the top (45% from the bottom).
- Versioned JSON charts are saved in app-private files and reused after restart.
  Local file size/modification time is checked when loading from disk. Analyze
  again if a content-URI recording has been replaced. Songs longer than one hour
  are rejected to bound analysis resources.
- A monotonic playback clock eases audio drift at at most ±10% rather than
  snapping on each sample; position queries run at 10 Hz instead of each vsync.
  Tiles repaint at vsync without rebuilding the widget tree. The opaque HUD
  updates at 10 Hz and no longer blurs the moving background.
- Pause/background transitions freeze the game clock. Muting still advances
  playback. Device tests complete tap/hold tracks and exercise overlapping two-thumb
  holds plus immediate startup at audio time zero.

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
pause while holding, tap on still-visible tiles after the former timing window,
and verify live hold rewards, frozen scoring during pause/after release, exact
completion rewards, and that early slider release allows the song to finish.

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
