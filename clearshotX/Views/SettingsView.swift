//
//  SettingsView.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import SwiftUI

#if DEBUG
private let settingsWindowHeight: CGFloat = 720
#else
private let settingsWindowHeight: CGFloat = 630
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
                Label("Saving", systemImage: "folder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Picker(
                    "Save destination",
                    selection: Binding(
                        get: { viewModel.captureSaveMode },
                        set: { viewModel.setCaptureSaveMode($0) }
                    )
                ) {
                    ForEach(CaptureSaveMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)

                if viewModel.captureSaveMode == .fixedFolder {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)

                        Text(viewModel.captureSaveFolderPath ?? "Choose a folder")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Choose Folder") {
                            viewModel.chooseCaptureSaveFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(width: 420)
                } else {
                    Text("Show the macOS Save dialog and remember its most recent location.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                Toggle(
                    isOn: Binding(
                        get: { viewModel.isTemporaryCaptureCleanupEnabled },
                        set: { viewModel.setTemporaryCaptureCleanupEnabled($0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Automatically remove temporary captures")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(nsColor: .labelColor))

                        Text(
                            viewModel.isTemporaryCaptureCleanupEnabled
                                ? "Remove unsaved working captures after 24 hours."
                                : "Keep unsaved working captures until you delete them."
                        )
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
