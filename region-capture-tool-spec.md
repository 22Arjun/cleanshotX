# Task: Build a macOS `screencapture -i` Equivalent — Interactive Region Selection Tool

## Goal
Replicate the exact UX of macOS's built-in Cmd+Shift+4 region capture: full-screen dimming overlay, crosshair cursor, drag-to-select rectangle with live dimension readout, pixel-precision magnifier near cursor, Esc to cancel, and a clean final screenshot with no overlay artifacts.

## Stack Constraints
- Swift 6
- SwiftUI + AppKit (NSWindow/NSView for the overlay — SwiftUI alone can't do borderless full-screen click-through overlays reliably)
- ScreenCaptureKit for the actual pixel capture
- MVVM architecture, matching the rest of the app

## Requirements

### 1. Overlay window(s)
- One borderless, transparent `NSWindow` per connected `NSScreen`
- Window level `.screenSaver` or higher
- Covers full display bounds
- Must support multi-monitor: all displays dim simultaneously; selection itself stays within a single display's bounds (dragging a selection across displays is not required, matching Apple's own behavior)

### 2. Crosshair cursor
- Set `NSCursor.crosshair` on overlay appear
- Reset to default cursor on dismiss/cancel

### 3. Dimming + selection punch-through
- Entire screen dimmed (~30% black overlay) except the live-dragged selection rectangle
- Selection rectangle stays fully undimmed with a 1px white border
- Redraw on every `mouseDragged` event

### 4. Live dimension label
- Small text readout near the selection rectangle showing width × height in pixels
- Updates live during drag
- Match Apple's own label style/position

### 5. Magnifier/loupe
- Small zoomed preview near the cursor showing pixel-level detail of the area directly under the crosshair
- Active before the drag starts (for precise starting-point placement) — same as Apple's tool
- Source the zoomed content from ScreenCaptureKit frame data or `CGWindowListCreateImage`, cropped to a small region around the cursor and scaled up

### 6. Mouse handling
- `mouseDown`: record start point
- `mouseDragged`: update selection rect, redraw
- `mouseUp`: finalize rect, proceed to capture step
- Edge case: `mouseUp` with near-zero-size rect (user just clicked without dragging) — either cancel, or fall back to whole-window/whole-screen capture if the click landed on a window (matching Apple's click-to-select-window fallback in interactive mode). **Flag as optional — decide if in scope for v1.**

### 7. Esc to cancel
- Local key event monitor
- Dismiss overlay, no capture taken, reset cursor

### 8. Capture execution
Critical sequencing — this is the most common bug, test explicitly for it:
1. Hide/dismiss ALL overlay windows first
2. Wait one frame/short delay to ensure the window server has removed them
3. THEN call `SCScreenshotManager.captureImage` with `SCContentFilter` + `SCStreamConfiguration.sourceRect` scoped to the finalized selection rect on the correct display

The overlay must never appear in the final captured image.

### 9. Post-capture handoff
- Resulting `CGImage`/`NSImage` should be passed into the existing capture-completion flow (auto-save to disk, floating thumbnail/Quick Access Overlay, Recents update) already built elsewhere in the app
- Do not duplicate that logic here — just feed the image into the existing pipeline

## Explicitly Out of Scope (v1)
Do not build unless asked:
- Window-specific capture mode
- Scrolling capture
- Timer/delay capture
- "Last selection" memory

## Definition of Done
- Triggering the tool shows the dimming overlay with crosshair immediately
- Drag produces a live-updating selection with dimension label and magnifier
- Releasing the mouse captures exactly the selected pixels with zero overlay artifacts
- Esc cancels cleanly
- Result flows into the existing post-capture pipeline
