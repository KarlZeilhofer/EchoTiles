# Echo Tiles Rhythm

Android rhythm-analysis fork of [Sidhant’s EchoTiles](https://github.com/sidhant947/EchoTiles).

## Try version 1.4.0

Download the APK at **https://alpenchat.at/downloads/** and install over the
existing test app. It has a separate application ID
(`at.zeilhofer.echotiles.rhythm`) from F-Droid. Add a song and press play.
Missing or outdated analysis starts automatically with a cancellable progress
bar. The START tap plays the first real tile and starts the music.

Settings → Tile generation selects **Variant A** or **Variant B**. B is the
default for this update. A keeps the previous selection and acceleration;
both variants keep sliders between 1 and 4 seconds and use separate screen
halves for the two thumbs.

## Audio analysis and variants

Android MediaExtractor/MediaCodec decodes MP3, AAC, FLAC, WAV and other
system-supported formats on a worker thread. Streaming mono 22.05 kHz audio,
a 1024-sample Hann FFT, positive log spectral flux, adaptive thresholds and
peak picking produce actual onset candidates. Compact spectral profiles track
quiet vocals and audible decay. This is a mixed-music heuristic, not source
separation or polyphonic pitch transcription. Silence does not invent notes.

Analysis schema **v4** saves onset evidence, salience, duration and two-band
attack flags independently of either chart. Older schemas are rejected by the
app cache and re-analysed automatically on play. Changing A/B reuses the same
evidence without decoding again. Planning runs in a Dart isolate. Source
path and local file size/modification time must still match the cache. If a
content-URI recording is replaced, remove/re-add it to invalidate its analysis.
Engine/schema changes must bump `SongAnalysis.version` to invalidate old data.

- **A:** keeps the prior onset-spacing gate, 380 → 140 ms over the song, and
  the prior scroll curve `0.5 * (1 + 1.5 * progress^2.5)` screen heights/second.
- **B:** locally fits tempo and phase in 10-second sections and prefers whole,
  half and quarter bars before finer/off-grid accents. Four beats per bar is
  a ranking assumption, not automatic time-signature transcription. The grid
  ranks measured onsets; timestamps are never snapped or fabricated.
- B’s target tile rate starts at approximately one per four beats and rises
  linearly to 2.5×. Each 10-second budget integrates this rate, carrying only
  fractional rounding. Quiet passages or occupied thumbs may stay below the
  target; missed quotas do not accumulate and flood the next passage.
- B allows extra accents beside a held note on the free thumb. Strong attacks
  with independent low and high spectral energy can produce two simultaneous
  taps, one per hand, within the same tile budget. The first START stays single.
- B’s visual speed rises linearly from 0.5 to 1.25 screen heights/second.
  Positions use the integral of that speed, so every head and tail moves the
  same distance per frame and crosses the line at its measured audio time.

## Input, sliders and rendering

The left thumb owns lanes 0/1, the right thumb lanes 2/3. A hold reserves its
whole half and a 100 ms release margin. No chart needs a third thumb or crossing
thumbs. Lane balancing uses all four lanes. Sustains below 1 second are taps;
longer sustains become sliders capped at **4 seconds**, including cached data.

Held sliders earn 220 points/second and combo increments at 10% steps.
Release at the tail for 150 completion points and two combo increments. Holding
more than **100 ms past the musical end loses**, including the final note after
audio ends. Points stop at the musical end; release is required for the bonus.
Pause freezes the deadline. Late up/move/cancel events cannot bypass it between
frames. Earlier release retains the original partial-reward behavior.

Ordinary taps retain the F-Droid 1.0.0 spatial hit rules from
[upstream 6829d30](https://github.com/sidhant947/EchoTiles/blob/6829d30c6975e9ac213cb62f7e7e02c63b4dd1bb/lib/screens/game_screen.dart):
bottom-anchored rectangles, 0.08 screen-height direct-tap padding, 0.18 target-line
tolerance, lowest candidate first, rating thresholds 0.05/0.11, missed boundary
y > 1.02. Painting and input share bounds. The judgment line is 45% from the
bottom. No millisecond hit gate is applied to ordinary taps.

A monotonic clock slews audio drift at at most ±10%; native position polling
runs at 10 Hz, tiles repaint at vsync, and the HUD updates at 10 Hz. Pause and
backgrounding freeze playback; muting still advances the music.

## Build and verify

Flutter 3.47.9 / Dart 3.13.7, Java 21, Android SDK 36, NDK 28.2.13676358.

```sh
flutter pub get
flutter analyze
flutter test
cd android && ./gradlew :app:testDebugUnitTest
cd ..
flutter test integration_test -d emulator-5554
flutter build apk --release
```

Tests cover detection, musical timing, 10-second density budgets, simultaneous
accents, free-thumb subdivisions, 4-second caps, original tap geometry, live
scoring, pause, release deadlines, actual audio completion, automatic analysis
upgrades, and sharing a cache between A/B. Device tests decode WAV and MP3.

Release signing uses `android/key.properties` when supplied; otherwise this
experimental fork uses the local Android debug key. The
`tools/rhythm-test-workflow.yml` template builds without upstream signing
secrets. Installing it into `.github/workflows` requires workflow permission.
The `web-downloads/index.html` template is published alongside the APK and
SHA256SUMS in the existing Alpenchat web root.

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
