//
//  SettingsView.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import SwiftUI

#if DEBUG
private let settingsWindowHeight: CGFloat = 500
#else
private let settingsWindowHeight: CGFloat = 430
#endif

struct SettingsView: View {
    @ObservedObject var viewModel: AppShellViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(nsColor: .labelColor))

            VStack(alignment: .leading, spacing: 14) {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                VStack(alignment: .leading, spacing: 8) {
                    settingsRow("Full screen", shortcut: viewModel.shortcutLabel(for: .captureFullScreen))
                    settingsRow("Region", shortcut: viewModel.shortcutLabel(for: .captureRegion))
                }

                Button {
                    viewModel.openDefaultShortcutSetupFromSettings()
                } label: {
                    Label("Set Default Screenshot Shortcuts", systemImage: "command")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Label("Capture Feedback", systemImage: "speaker.wave.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Toggle(
                    isOn: Binding(
                        get: {
                            viewModel.isCaptureSoundEnabled
                        },
                        set: { isEnabled in
                            viewModel.setCaptureSoundEnabled(isEnabled)
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Screenshot capture sound")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(nsColor: .labelColor))

                        Text(viewModel.isCaptureSoundEnabled ? "Play a subtle sound after every successful capture." : "Keep successful captures silent.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.regular)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Label("Permissions", systemImage: "lock.shield")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Button {
                    viewModel.openScreenRecordingSettings()
                } label: {
                    Label("Screen Recording Permission", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            #if DEBUG
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Label("Development", systemImage: "hammer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Button {
                    viewModel.resetOnboardingForDevelopment()
                } label: {
                    Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Text("Clears onboarding flags and opens the first-run flow.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            #endif

            Spacer()
        }
        .padding(28)
        .frame(width: 520, height: settingsWindowHeight, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsRow(_ title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Spacer()

            Text(shortcut.isEmpty ? "Not registered" : shortcut)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: .labelColor))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .frame(width: 340)
    }
}
