//
//  ScrollingCaptureHUDView.swift
//  clearshotX
//

import SwiftUI

struct ScrollingCaptureHUDView: View {
    @ObservedObject var viewModel: ScrollingCaptureHUDViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 11) {
                statusIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.state.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Text(viewModel.state.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            preview

            HStack {
                if let dimensions = viewModel.state.dimensionsText {
                    Text(dimensions)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for the first stable frame")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(viewModel.state.acceptedFramesText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(viewModel.state.pauseButtonTitle) {
                    viewModel.togglePause()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.state.canPause)

                Spacer(minLength: 4)

                Button("Cancel") { viewModel.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Finish") { viewModel.finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!viewModel.state.canFinish)
            }
        }
        .padding(16)
        .frame(width: 320, height: 390)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .padding(20)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.24))

            if let previewImage = viewModel.previewImage {
                Image(decorative: previewImage, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .padding(10)
                    .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 24, weight: .light))
                    Text("Live preview")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.16))
                .frame(width: 36, height: 36)

            if viewModel.state.phase == .starting || viewModel.state.phase == .finishing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusSymbol)
                    .font(.system(size: 15, weight: .semibold))
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
            "arrow.down.to.line.compact"
        }
    }
}
