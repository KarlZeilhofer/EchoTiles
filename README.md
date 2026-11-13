# Echo Tiles Rhythm

Android rhythm-analysis fork of [Sidhant’s EchoTiles](https://github.com/sidhant947/EchoTiles).

## Try version 1.5.2

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
separation or polyphonic pitch transcription. Completely silent recordings are rejected.

Analysis schema **v4** saves onset evidence, salience, duration and two-band
attack flags independently of either chart. Older schemas are rejected by the
app cache and re-analysed automatically on play. Changing A/B reuses the same
evidence without decoding again. Planning runs in a Dart isolate. Source
path and local file size/modification time must still match the cache. If a
content-URI recording is replaced, remove/re-add it to invalidate its analysis.
Engine/schema changes must bump `SongAnalysis.version` to invalidate old data.

- **A:** keeps the prior onset-spacing gate, 380 → 140 ms over the song, and
  the prior scroll curve `0.5 * (1 + 1.5 * progress^2.5)` screen heights/second.
- **B:** uses fixed, song-independent quotas in consecutive 10-second windows.
  The first window rate is **15 tiles/10 seconds**, the final window rate
  **37.5 tiles/10 seconds**. Intermediate rates rise in equal steps. Each
  full window rounds its count to whole tiles; a partial final window is scaled
  to its actual duration. A two-minute song has counts
  `15, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35, 38`. Neither
  BPM nor the number of detected attacks changes the quota.
- Each window is divided into paced slots. B prefers measured onsets inside
  each slot and locally fits tempo/phase to rank them. If no playable attack is
  available, a beat-grid tile fills the slot, including in quiet passages.
  Four beats/bar is a ranking assumption. Real onsets keep their timestamps;
  supplemental notes use metrical subdivisions. There is no quota underfill.
- One thumb stays available while a sustain is held. A second overlapping
  sustain becomes a tap so it cannot block the fixed pace. The first vocal
  keeps its measured tail, capped at four seconds. Strong measured two-band
  attacks can still consume two adjacent slots as simultaneous taps on
  opposite hands. START remains single.
- B’s visual speed rises linearly from 0.5 to 1.25 screen heights/second.
  Positions use the integral of that speed, so every head and tail moves the
  same distance per frame and crosses the line at its assigned audio time
  (measured attack or supplemental beat-grid position).

## Input, sliders and rendering

The left thumb owns lanes 0/1, the right thumb lanes 2/3. A hold reserves its
whole half and a 100 ms release margin. No chart needs a third thumb or crossing
thumbs. Lane balancing uses all four lanes. Sustains below 1 second are taps;
longer sustains become sliders capped at **4 seconds**, including cached data.

Perfect hits earn the full tap/combo reward and 220 points/second while held.
Great hits earn 80% and Good hits 50% of the entire reward, including combo,
hold ticks and release bonuses. A hold retains the grade of its initial hit.
Perfect completion gives 150 points; Great 120; Good 75. Combo progress itself
is unchanged. Equal combos and durations therefore always reward greater accuracy.
Held sliders increment the combo at 10% steps.
Release at the tail for the graded completion bonus and two combo increments. Holding
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

Score gains appear above the original contact in glowing, metallic gold with
bright highlights and animated sparkles. Since 1.5.1 the numbers are 50% larger
(37.5 logical pixels) and stay at that position instead of flying to the score.
Tap gains disappear within 300 ms, fading over the final 100 ms. A held slider
keeps its live, growing gain label visible until release; the final gain and
bonus then fade at the same position within 300 ms. A separate paint-only ticker
updates the feedback without rebuilding gameplay or intercepting taps.
Animation pauses with the game, and score accounting remains immediate.

Custom songs can only be removed after a confirmation dialog showing the song
name. Drag the red thumb from the left to the right end, then release it.
Taps on the track, incomplete/reversed drags, cancellation and dismissing the
dialog do not delete anything. Only a physical pointer-up at the end confirms;
a cancelled drag must not be treated as a successful drag-end. Confirmation
removes the library entry and its cached analysis, while keeping the audio file.

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
# AOT profile check for tight release timing:
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/startup_flow_test.dart -d emulator-5554
flutter build apk --release
```

Tests cover detection, musical timing, exact 10-second quotas across tempos, lengths and sparse passages, simultaneous
accents, free-thumb subdivisions, 4-second caps, original tap geometry, live
scoring, pause, release deadlines, actual audio completion, automatic analysis
upgrades, and sharing a cache between A/B. Device tests decode WAV and MP3, verify live gold rewards against actual scoring,
and verify that deletion needs a completed confirmation gesture and preserves
the audio file.

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
