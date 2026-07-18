# Scrolling Capture Architecture

## Product decision

ClearshotX should treat scrolling capture as a **pixel-streaming document mosaic**, not as a sequence of ordinary screenshots and not as a general panorama.

For arbitrary macOS apps there is no public API that returns the off-screen contents or scroll position of another app. The dependable cross-app path is therefore:

1. Let the user select a fixed viewport inside one display.
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

The compositor keeps the initial viewport body plus only the newly revealed strip from each accepted frame. This avoids retaining duplicate frames and avoids repeatedly reallocating an ever-growing bitmap. A configured fixed header is retained from the first frame; a fixed footer is replaced and emitted from the final accepted frame.

Regression tests cover exact displacement, duplicate rejection, ambiguous content, overlap removal, fixed bands, resizing, and output limits using deterministic synthetic documents.

## Next implementation slices

### 1. Frame-source adapter

- Convert the selected AppKit global rectangle to a single display-local top-left `sourceRect`.
- Configure `SCStream` for native pixel size, BGRA, cursor hidden, 15 fps, and queue depth 3.
- Read `SCFrameStatus.complete`, scale/content metadata, and dirty rectangles.
- Use a single serial analysis queue with a one-frame latest-wins mailbox. Never let frame delivery queue behind CPU work.
- Convert only gated `CVPixelBuffer` frames to `CGImage`; keep all earlier checks buffer-native.

### 2. Capture HUD and lifecycle

- Reuse region selection, but require the scrolling region to stay on one display.
- Show an excluded-app floating HUD outside the selected region with status: Ready, Scroll, Capturing, Paused, Limit reached, Finish, Cancel.
- Start with user-driven scrolling. Accept Space/Return to finish and Escape to cancel.
- Keep the first accepted frame immediately. During fast/blurred movement, reject silently; show a “scroll a little slower” hint only after a streak of low-confidence frames.
- On window resize, display-scale change, selected content disappearing, or stream failure, stop safely and offer the valid partial capture.

### 3. Fixed and dynamic content handling

- Add calibration over the first two reliable scroll steps. Compare same-coordinate rows with displacement-aligned rows to identify contiguous fixed top/bottom bands.
- Mask scrollbars, video, caret blinking, sticky chat buttons, and other independently changing islands during registration.
- If fixed content occupies too much of the viewport or the page is textureless/repetitive, ask the user to narrow the region rather than manufacture a bad seam.
- Add a seam audit pass around every join. Flag high residual differences and keep the last valid partial result.

### 4. Large-output storage

The current compositor is intentionally sufficient for the first end-to-end feature but a final `CGImage` still requires contiguous decoded memory. Before removing the 80-million-pixel guardrail, introduce a tile-backed temporary store:

- materialize accepted strips into fixed-height lossless tiles;
- keep only analysis planes and the active tile in RAM;
- assemble/encode on finish with explicit cancellation and disk-space checks;
- retain the existing maximum dimension and maximum pixel-count policy because decoders and editors also need safe limits.

### 5. Optional adapters

- Chromium adapter: when the user explicitly chooses a debuggable Chromium tab, use CDP full-page capture and bypass visual stitching.
- Assisted scroll adapter: opt-in synthetic scrolling with per-app compatibility profiles, focus verification, and immediate cancellation on user input.
- Accessibility adapter: use semantic scroll values only where the target exposes reliable accessibility scroll areas; never make this a prerequisite for manual mode.

## Quality gates before shipping

- Pixel-perfect synthetic corpus: text, grids, code, photos, alternating/repeated rows, dark/light themes, 1×/2× scale.
- Real-app matrix: Safari, Chrome, Finder list view, Mail, Notes, Preview PDF, Xcode, Terminal, Slack/Discord-like virtualized lists, and spreadsheets.
- Fault tests: resize, zoom, display migration, overlays, sticky headers/footers, lazy loading, video/GIFs, trackpad momentum, upward scroll, reaching the end, and permission revocation.
- Performance targets on Apple silicon: analysis under 12 ms for a gated frame, no unbounded frame queue, less than one viewport of transient analysis memory, and no UI work on the stream callback queue.
- Acceptance: no duplicated rows, no missing rows, no visible seam at 100% zoom, deterministic partial output after interruption, and memory bounded by the configured output policy.
