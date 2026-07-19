# Scrolling Capture Architecture

## Product decision

ClearshotX should treat scrolling capture as a **pixel-streaming document mosaic**, not as a sequence of ordinary screenshots and not as a general panorama.

For arbitrary macOS apps there is no public API that returns the off-screen contents or scroll position of another app. The dependable cross-app path is therefore:

1. Let the user draw, resize, move, and explicitly confirm a fixed viewport inside one display.
2. Stream that rectangle with ScreenCaptureKit while the user scrolls naturally.
3. Select useful keyframes and reject duplicates, animation, resize, and low-confidence matches.
4. Estimate the one-dimensional vertical displacement between accepted frames.
5. Append only newly revealed pixels.
6. Emit fixed top/bottom chrome once, finalize the image once, then use the existing capture store and quick-access overlay.

This constrained model is deliberate. General feature/homography panorama stitching spends much more CPU and can bend crisp UI geometry; a scrolling surface should translate along one axis.

## Evidence behind the design

- Apple describes ScreenCaptureKit as its high-performance native screen-streaming API, backed by GPU-efficient capture. `SCStream` produces `CMSampleBuffer` frames and can capture a configured `sourceRect`. [ScreenCaptureKit overview](https://developer.apple.com/documentation/screencapturekit) and [WWDC22: Meet ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/)
- A stream configuration controls output resolution, frame interval, pixel format, and queue depth. Apple says the default queue depth is three and warns not to exceed eight; a scrolling capture should stay at three because stale frames are harmful and memory is more valuable than maximum video FPS. [Apple sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) and [`queueDepth`](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth)
- ScreenCaptureKit frame metadata exposes status, content geometry, scale, and dirty rectangles. Incomplete frames must be discarded; dirty rectangles are a cheap early signal for unchanged frames, but image registration remains authoritative because dirty rectangles report redraws rather than document displacement. [`dirtyRects`](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/dirtyrects) and [WWDC22 advanced session](https://developer.apple.com/videos/play/wwdc2022/10155/)
- Template matching is the appropriate registration family when the transform is a translation and adjacent viewports overlap. [OpenCV template matching](https://docs.opencv.org/master/de/da9/tutorial_template_matching.html)
- Browser-native full-page capture is a useful optional fast path, not the product foundation. Chromium's DevTools Protocol exposes `Page.captureScreenshot` with `captureBeyondViewport`, but it only applies to Chromium pages under a debugging connection. [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/1-3/Page/)
- Synthetic scrolling via posted Quartz scroll events is technically possible, but different apps interpret wheel units and momentum differently. Apple explicitly notes that large wheel values can have unexpected results. Manual scrolling should ship first; assisted scrolling can be an opt-in adapter after permission and compatibility work. [`CGEvent` scrolling](https://developer.apple.com/documentation/coregraphics/cgeventcreatescrollwheelevent)

## CleanShot X public behavior comparison

CleanShot X is proprietary, so its internal capture and stitching implementation cannot be verified from public material. The architecture here does not claim or attempt to reproduce private internals. We did, however, check its documented product surface and publicly observable workflow before choosing the next slice:

- CleanShot's URL API models scrolling capture as an explicit mode with a user-supplied rectangle and display, followed separately by `start` and optional `autoscroll`. That supports keeping selection, stream lifecycle, and assisted scrolling as separate components. [CleanShot URL API](https://cleanshot.com/docs-api)
- Its public changelog shows Auto-Scroll arrived after scrolling capture and has received separate fixes, while the core feature has repeatedly received stitching-algorithm, misalignment, cursor, and preview improvements. This reinforces shipping a robust manual capture path first and treating automation as an adapter. [CleanShot changelog](https://cleanshot.com/changelog)
- Public walkthroughs show the interaction as select an outline, start capture, scroll manually or choose Auto-Scroll, watch a live result preview, then explicitly finish. They also document real failure pressure from sticky menus, scrollbars, fast movement, animation, and non-vertical motion. [Scrolling capture walkthrough](https://scottwillsey.com/cleanshotx-scrolling-screenshots/) and [public review](https://sspai.com/post/60301)

The product target is therefore behavioral parity where it is valuable—explicit region, live progress, manual/automatic modes, safe finish and partial recovery—implemented on top of independently reasoned, testable platform primitives.

## Runtime pipeline

```text
Region selection
      │
      ▼
SCStream (15 fps, queueDepth 3, BGRA, cursor hidden)
      │ complete frames + metadata
      ▼
Frame gate
  ├─ size/scale changed ───────────────► stop with recovery message
  ├─ no meaningful dirty area ────────► drop
  ├─ backpressure / analysis busy ────► replace pending frame with newest
  └─ candidate frame
      │
      ▼
Luma downsample (bounded to 192×320)
      │
      ▼
Vertical registration
  ├─ same-position difference tiny ───► duplicate
  ├─ score/confidence insufficient ───► reject and keep last accepted reference
  └─ reliable positive displacement
      │
      ▼
Strip compositor
  ├─ append only newly revealed rows
  ├─ fixed header once / latest footer once
  └─ enforce height and pixel-count limits
      │
      ▼
One final Core Graphics render → CaptureStore → Quick Access
```

## Infrastructure now in the project

`ScrollingCaptureFrameAnalyzer` performs bounded one-axis luma registration. It reports duplicate, aligned, or rejected with a normalized difference and a confidence score. It ignores narrow side bands where scrollbars usually animate.

`ScrollingCaptureSession` is the transactional state machine. It never advances its reference on rejected frames, requires stable frame dimensions, applies hard output limits, and exposes progress suitable for a floating HUD.

`ScrollingCaptureRegionResolver` converts an AppKit global selection into a pixel-aligned, display-local ScreenCaptureKit rectangle. It rejects cross-display selections and records exact native output dimensions, including Retina scaling and offset display layouts.

`ScrollingCaptureFrameSource` owns the live `SCStream`. It excludes this app's windows, accepts only complete frames of the expected native pixel size, preserves ScreenCaptureKit metadata, and converts gated pixel buffers to `CGImage` off the callback queue. A 30 fps acquisition cadence preserves adjacent overlap during quick trackpad movement while latest-wins backpressure prevents a stale frame queue. Its lifecycle is guarded against overlapping starts and suppresses failure reporting during an intentional stop. Pause disables delivery before image conversion, and a delivery generation prevents a queued pre-pause frame from leaking into the resumed session.

`LatestValueProcessor` provides bounded backpressure. While analysis is busy, it keeps only the newest pending frame, so capture latency and memory cannot grow with the stream duration.

`ScrollingCaptureCoordinator` now connects selection, streaming, stitching, bounded preview rendering, final rendering, storage, and Quick Access as one guarded lifecycle. It serializes pause/resume/finish/cancel/error completion, assembles the final bitmap off the main actor, preserves a valid partial capture after a stream or analysis failure when at least one frame exists, and ignores stale callbacks using a per-capture identity. Resume rebases registration on the first settled frame without appending duplicate rows.

`ScrollingCaptureRegionSelectionManager` is intentionally separate from ordinary Region Capture. Mouse-up preserves the selection instead of committing it; eight resize targets, whole-frame movement, keyboard nudging, native-pixel dimensions, and explicit Start/Cancel controls remain available until confirmation. The target app is restored to the foreground before streaming begins, and the locked selection overlay overlaps handoff to the live capture UI so the frame never flashes away.

`ScrollingCaptureHUDManager` presents an app-excluded, non-activating experience around the selected region: the crop frame remains visible, the desktop outside it stays dimmed, a narrow live-result sidecar grows independently, and compact Cancel/Pause/Done controls remain anchored to the selection. None of these surfaces enter the ScreenCaptureKit stream or take scrolling focus from the target app.

`ScrollingCapturePreviewBuilder` incrementally updates a downsampled representation only when the compositor accepts new rows. Its decoded size is permanently capped at 240×280 pixels, so live feedback does not retain or repeatedly render the full-resolution output and duplicate/rejected frames do not trigger redundant UI work. Preview resolution is therefore independent from output resolution: accepted strips are always cropped and composed from native ScreenCaptureKit frames without rescaling.

`ScrollingCaptureFrameAnalyzer` caches the accepted reference as a small luma plane. Each incoming frame is downsampled once for registration and an accepted candidate is promoted without reconverting the previous native frame. The compositor still receives the untouched native image, reducing analysis work without trading away output detail.

The compositor keeps the initial viewport body plus only the newly revealed strip from each accepted frame. This avoids retaining duplicate frames and avoids repeatedly reallocating an ever-growing bitmap. A configured fixed header is retained from the first frame; a fixed footer is replaced and emitted from the final accepted frame.

Regression tests cover exact displacement, duplicate rejection, ambiguous content, overlap removal, fixed bands, resizing, output limits, multi-display geometry, Retina pixel alignment, frame completeness, and latest-frame backpressure using deterministic inputs.

## Next implementation slices

### Completed: frame-source adapter

- Converts the selected AppKit global rectangle to a single display-local top-left `sourceRect`.
- Configures `SCStream` for native pixel size, BGRA, cursor hidden, 15 fps, and queue depth 3.
- Reads `SCFrameStatus.complete`, scale/content metadata, and dirty rectangles.
- Uses a serial processing queue with a one-frame latest-wins mailbox.
- Converts only complete, correctly sized `CVPixelBuffer` frames to `CGImage`.

### Completed: capture coordinator, HUD, and lifecycle

- Reuses the existing region selector and validates the result as a single-display stream region.
- Adds a menu entry and excluded-app floating HUD with preparation, capture, guidance, finishing, Finish, and Cancel states.
- Starts with user-driven scrolling and keeps focus in the target app; HUD buttons avoid requiring Input Monitoring permission for global key interception.
- Keeps the first accepted frame immediately and shows “scroll a little slower” only after a sustained rejection streak.
- Stops safely on output limits, analysis errors, stream failure, finish, or cancel; failures finalize a valid partial capture when possible.

### Completed: live preview and capture controls

- Adds a bounded, downsampled live mosaic preview without rendering the full output on every accepted frame.
- Adds Pause/Resume with source-level frame suppression and a safe registration rebase, so users can interact with expandable sections without feeding transitional frames into the mosaic.

### 1. Recovery and keyboard controls

- Add an optional, explicitly permissioned keyboard-control adapter for Finish/Cancel; keep HUD buttons as the universal path.
- Surface “saved partial capture” distinctly from a normal finish when the stream ends unexpectedly.

### 2. Fixed and dynamic content handling

- Add calibration over the first two reliable scroll steps. Compare same-coordinate rows with displacement-aligned rows to identify contiguous fixed top/bottom bands.
- Mask scrollbars, video, caret blinking, sticky chat buttons, and other independently changing islands during registration.
- If fixed content occupies too much of the viewport or the page is textureless/repetitive, ask the user to narrow the region rather than manufacture a bad seam.
- Add a seam audit pass around every join. Flag high residual differences and keep the last valid partial result.

### 3. Large-output storage

The current compositor is intentionally sufficient for the first end-to-end feature but a final `CGImage` still requires contiguous decoded memory. Before removing the 80-million-pixel guardrail, introduce a tile-backed temporary store:

- materialize accepted strips into fixed-height lossless tiles;
- keep only analysis planes and the active tile in RAM;
- assemble/encode on finish with explicit cancellation and disk-space checks;
- retain the existing maximum dimension and maximum pixel-count policy because decoders and editors also need safe limits.

### 4. Optional adapters

- Chromium adapter: when the user explicitly chooses a debuggable Chromium tab, use CDP full-page capture and bypass visual stitching.
- Assisted scroll adapter: opt-in synthetic scrolling with per-app compatibility profiles, focus verification, and immediate cancellation on user input.
- Accessibility adapter: use semantic scroll values only where the target exposes reliable accessibility scroll areas; never make this a prerequisite for manual mode.

## Quality gates before shipping

- Pixel-perfect synthetic corpus: text, grids, code, photos, alternating/repeated rows, dark/light themes, 1×/2× scale.
- Real-app matrix: Safari, Chrome, Finder list view, Mail, Notes, Preview PDF, Xcode, Terminal, Slack/Discord-like virtualized lists, and spreadsheets.
- Fault tests: resize, zoom, display migration, overlays, sticky headers/footers, lazy loading, video/GIFs, trackpad momentum, upward scroll, reaching the end, and permission revocation.
- Performance targets on Apple silicon: analysis under 12 ms for a gated frame, no unbounded frame queue, less than one viewport of transient analysis memory, and no UI work on the stream callback queue.
- Acceptance: no duplicated rows, no missing rows, no visible seam at 100% zoom, deterministic partial output after interruption, and memory bounded by the configured output policy.
