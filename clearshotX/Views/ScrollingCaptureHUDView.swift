//
//  ScrollingCaptureHUDView.swift
//  clearshotX
//

import SwiftUI

/// Narrow live-result sidecar. It deliberately contains no primary controls so the
/// preview can stay beside the selected region while controls remain anchored below.
struct ScrollingCaptureHUDView: View {
    @ObservedObject var viewModel: ScrollingCaptureHUDViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                statusIcon

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.state.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(statusDetail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            preview

            HStack(spacing: 6) {
                if let dimensions = viewModel.state.dimensionsText {
                    Text(dimensions)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                Spacer(minLength: 4)
                Text(viewModel.state.acceptedFramesText)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 18, y: 8)
        .padding(8)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(.black.opacity(0.38))

            if let previewImage = viewModel.previewImage {
                Image(decorative: previewImage, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .padding(7)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 22, weight: .light))
                    Text("Live result")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var statusDetail: String {
        switch viewModel.state.phase {
        case .starting:
            "Preparing native pixels"
        case .capturing:
            "Scroll vertically"
        case .guidance:
            "Use smaller scroll steps"
        case .paused:
            "Frames are suspended"
        case .finishing:
            "Assembling full quality"
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.17))
                .frame(width: 28, height: 28)

            if viewModel.state.phase == .starting || viewModel.state.phase == .finishing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: statusSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(iconColor)
            }
        }
    }

    private var iconColor: Color {
        viewModel.state.phase == .guidance ? .orange : .accentColor
    }

    private var statusSymbol: String {
        switch viewModel.state.phase {
        case .guidance:
            "speedometer"
        case .paused:
            "pause.fill"
        default:
            "arrow.down"
        }
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
