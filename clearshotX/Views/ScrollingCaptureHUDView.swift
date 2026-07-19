//
//  ScrollingCaptureHUDView.swift
//  clearshotX
//

import SwiftUI

/// A chrome-free miniature of the captured document. The hosting panel is also
/// transparent, so every visible pixel in this HUD belongs to the page itself.
/// Capture controls live in their own panel and are intentionally kept separate.
struct ScrollingCaptureHUDView: View {
    @ObservedObject var viewModel: ScrollingCaptureHUDViewModel

    var body: some View {
        Group {
            if let previewImage = viewModel.previewImage {
                Image(decorative: previewImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.18), value: previewAspectRatio)
    }

    private var previewAspectRatio: CGFloat {
        guard let image = viewModel.previewImage, image.height > 0 else { return 1 }
        return CGFloat(image.width) / CGFloat(image.height)
    }
}

struct ScrollingCaptureControlsView: View {
    @ObservedObject var viewModel: ScrollingCaptureHUDViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(ScrollingCapturePillButtonStyle(emphasized: false))

            Button {
                viewModel.togglePause()
            } label: {
                Image(systemName: viewModel.state.phase == .paused ? "play.fill" : "pause.fill")
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(ScrollingCapturePillButtonStyle(emphasized: false))
            .disabled(!viewModel.state.canPause)
            .help(viewModel.state.pauseButtonTitle)

            Button {
                viewModel.finish()
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(ScrollingCapturePillButtonStyle(emphasized: true))
            .disabled(!viewModel.state.canFinish)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScrollingCapturePillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let emphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(emphasized ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                emphasized ? Color.white : Color.black.opacity(0.76),
                in: Capsule()
            )
            .opacity(!isEnabled ? 0.46 : (configuration.isPressed ? 0.72 : 1))
    }
}
