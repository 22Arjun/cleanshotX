# Scrolling Region Capture — Implementation Spec

## Goal
Replace the current manual-scroll-driven capture loop with an app-driven auto-scroll capture pipeline. The app controls scroll timing and distance; the user no longer has to scroll at a specific speed. Target: reliable stitched captures at any content type, full native resolution preserved end-to-end.

## Why the rewrite
Current implementation captures frames on a fixed timer while the user scrolls manually, so frame overlap depends on human scroll speed. Fast scroll → insufficient overlap → stitching fails. This is an architecture problem, not a tuning problem. Fix: synthetic scroll events driven by the app, with capture gated on each step completing.

## Scope
- Primary mode: Auto-Scroll (app drives scrolling, default).
- Secondary/fallback mode: Manual (user scrolls, for apps where synthetic scroll events don't register — e.g. custom scroll containers, games). Not the focus of this pass; stub the entry point only.
- Out of scope for this pass: annotation, export formats, UI polish.

## Architecture

```
1. User selects target window/region → clicks "Scrolling Capture"
2. Capture baseline frame (frame 0) via ScreenCaptureKit
3. Loop:
   a. Post synthetic scroll event (CGEvent, fixed pixel delta)
   b. Settle delay (tunable, default 40ms) for repaint
   c. Capture frame N (SCScreenshotManager.captureImage, single frame — not SCStream)
   d. Cross-correlate frame N against frame N-1 (see Stitching below)
   e. If NCC confidence < threshold → retry this step once with delta reduced by half
   f. If retry also low confidence → log step as low-confidence, keep best-effort offset, continue
   g. If offset ≈ 0 (no new content) → end of scrollable area, stop loop
   h. Crop new strip using offset, append to stitched canvas at native resolution
4. Final assembly → hand off stitched image (no downscaling at any stage)
```

## Components to build

### 1. `ScrollSynthesizer`
- Posts `CGEvent(scrollWheelEvent2Source:units:.pixel,...)` targeted at the selected window.
- Delta size: configurable, default = 65% of the capture viewport height (guarantees overlap).
- Exposes `scroll(deltaY: Int32)` and adaptive `scroll(deltaY:) -> reduced delta on retry`.

### 2. `FrameCapturer`
- Wraps `SCScreenshotManager.captureImage(contentFilter:configuration:)`.
- Captures at full `backingScaleFactor` — never downsample.
- Returns raw frame + timestamp.

### 3. `StitchEngine`
- No OpenCV. Use Accelerate/vImage for grayscale downsample + vDSP for normalized cross-correlation (NCC).
- Two-pass matching:
  - Pass 1: downsampled grayscale (~25% width) coarse search for vertical offset.
  - Pass 2: refine offset on full-res band around the coarse result.
- Input: bottom band (~150px) of previous frame, search region: top ~40% of new frame.
- Output: `(offsetPixels: Int, confidence: Float)`.
- Confidence threshold: start at 0.85 NCC score, make tunable.
- Sticky-element handling: if the same offset (near-zero shift) is found across multiple non-adjacent bands, flag as a fixed header/footer candidate — exclude that row range from future correlation searches and from repeated appends to the stitched canvas.

### 4. `ScrollCaptureController` (orchestrator)
- Owns the loop described in Architecture above.
- State machine: `idle → capturingBaseline → scrolling → capturingFrame → stitching → (loop | done | failed)`.
- End condition: offset ≈ 0 for 2 consecutive steps (avoids stopping on a single false negative, e.g. mid-animation frame).
- Emits progress events for UI (frames captured, current stitched height) so the UI can show live progress.

### 5. `StitchedCanvasBuilder`
- Appends cropped strips into a growing native-resolution buffer (not a fixed-size bitmap — grow incrementally, e.g. `CGContext` sized to running total height, or write strips to disk-backed buffer if capture is very long, to avoid memory blowup on huge pages).
- No resolution scaling at any point before final export.

## Acceptance criteria
- [ ] Capturing a 5000px+ scrollable web page produces a stitched image with no visible seams or duplicated rows at 100% zoom.
- [ ] Text remains crisp/native-resolution regardless of total capture length (no progressive downscaling).
- [ ] Sticky headers/nav bars appear once in the output, not once per step.
- [ ] A capture that hits low-confidence matches (e.g. autoplaying video mid-page) completes with a best-effort stitch rather than aborting.
- [ ] Auto-scroll capture of a long page (e.g. 10 viewport-heights) completes in under [X] seconds — no dependency on human input speed.
- [ ] Works on Retina (2x) displays without offset/scale bugs.

## Explicitly not using
- OpenCV — unnecessary C++/bridging overhead for a 1D vertical-offset problem; Accelerate/vDSP covers it natively.
- `SCStream` continuous capture for this feature — discrete `SCScreenshotManager` calls per step are simpler to reason about and avoid dropped-frame edge cases.
