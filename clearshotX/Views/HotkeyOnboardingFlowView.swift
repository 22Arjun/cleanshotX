//
//  HotkeyOnboardingFlowView.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AVFoundation
import SwiftUI

struct HotkeyOnboardingFlowView: View {
    @ObservedObject var viewModel: HotkeyOnboardingFlowViewModel

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader

            ZStack {
                switch viewModel.screen {
                case .welcome:
                    welcomeScreen
                case .capturePreview:
                    capturePreviewScreen
                case .defaultScreenshotToolDecision:
                    defaultScreenshotToolDecision
                case .systemSettingsInstructions:
                    systemSettingsInstructions
                case .screenRecordingPermission:
                    screenRecordingPermissionScreen
                case .firstCaptureMoment:
                    firstCaptureMomentScreen
                case .nextOnboardingScreen:
                    readyScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .frame(width: 720, height: 620)
        .background(onboardingBackground)
        .animation(.smooth(duration: 0.24), value: viewModel.screen)
    }

    private var onboardingHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                appGlyph

                Text("ClearshotX")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<viewModel.stepCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index <= viewModel.currentStepIndex ? Color(nsColor: .systemBlue) : Color(nsColor: .separatorColor))
                        .frame(width: index == viewModel.currentStepIndex ? 24 : 7, height: 7)
                        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewModel.currentStepIndex)
                }
            }
            .accessibilityLabel("Step \(viewModel.currentStepIndex + 1) of \(viewModel.stepCount)")
        }
        .padding(.leading, 86)
        .padding(.trailing, 28)
        .padding(.top, 34)
        .padding(.bottom, 10)
    }

    private var welcomeScreen: some View {
        OnboardingScreenLayout(
            visual: welcomeVisual,
            title: "Screenshots, without the cleanup",
            subtitle: "ClearshotX lives in your menu bar, captures fast, and keeps the next action close the moment you take a shot.",
            inlineMessage: nil,
            shortcutStatuses: [],
            footer: {
                OnboardingFooter {
                    Button {
                        viewModel.continueFromWelcome()
                    } label: {
                        Label("Get Started", systemImage: "arrow.right")
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 146))
                    .keyboardShortcut(.defaultAction)
                }
            }
        )
    }

    private var capturePreviewScreen: some View {
        OnboardingScreenLayout(
            visual: capturePreviewVisual,
            title: "Capture what matters",
            subtitle: "Grab the full screen or drag a region. ClearshotX brings up a lightweight control surface right after capture.",
            inlineMessage: nil,
            shortcutStatuses: [],
            footer: {
                OnboardingFooter {
                    Button {
                        viewModel.continueFromCapturePreview()
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 132))
                    .keyboardShortcut(.defaultAction)
                }
            }
        )
    }

    private var defaultScreenshotToolDecision: some View {
        OnboardingScreenLayout(
            visual: shortcutChoiceVisual,
            title: "Use familiar Mac shortcuts?",
            subtitle: "ClearshotX can take over ⇧⌘3 and ⇧⌘4, or keep separate shortcuts so macOS stays unchanged.",
            inlineMessage: nil,
            shortcutStatuses: [],
            footer: {
                OnboardingFooter {
                    Button {
                        viewModel.declineDefaultShortcuts()
                    } label: {
                        Label("Use Separate", systemImage: "keyboard.badge.ellipsis")
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 150))
                    .disabled(viewModel.isWorking)

                    Button {
                        viewModel.acceptDefaultShortcuts()
                    } label: {
                        Label("Use Mac Shortcuts", systemImage: "command")
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 174))
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isWorking)
                }
            }
        )
    }

    private var systemSettingsInstructions: some View {
        OnboardingScreenLayout(
            visual: systemSettingsGraphic,
            title: "One quick step in System Settings",
            subtitle: "Turn off all five rows under Keyboard Shortcuts > Screenshots, then return here.",
            inlineMessage: viewModel.inlineMessage,
            shortcutStatuses: viewModel.screenshotShortcutStatuses,
            footer: {
                OnboardingFooter {
                    Button {
                        viewModel.returnToDefaultShortcutDecision()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 116))
                    .disabled(viewModel.isWorking)

                    Button {
                        viewModel.openSystemSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 148))
                    .disabled(viewModel.isWorking)

                    Button {
                        viewModel.confirmSystemShortcutsDisabled()
                    } label: {
                        if viewModel.isWorking {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 18, height: 18)
                        } else {
                            Label("I Turned It Off", systemImage: "checkmark")
                        }
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 156))
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isWorking)
                }
            }
        )
    }

    private var screenRecordingPermissionScreen: some View {
        OnboardingScreenLayout(
            visual: screenRecordingPermissionVisual,
            title: "Screen Recording Access",
            subtitle: "macOS requires this permission before ClearshotX can capture screenshots. ClearshotX only captures when you ask it to.",
            inlineMessage: viewModel.inlineMessage,
            shortcutStatuses: [],
            footer: {
                OnboardingFooter {
                    if viewModel.screenRecordingPermissionState == .granted {
                        Button {
                            viewModel.confirmScreenRecordingPermission()
                        } label: {
                            Label("Continue", systemImage: "arrow.right")
                        }
                        .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 132))
                        .keyboardShortcut(.defaultAction)
                        .disabled(viewModel.isWorking)
                    } else {
                        Button {
                            viewModel.requestScreenRecordingPermission()
                        } label: {
                            Label("Allow Access", systemImage: "lock.open")
                        }
                        .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 138))
                        .disabled(viewModel.isWorking)

                        Button {
                            viewModel.openScreenRecordingSettings()
                        } label: {
                            Label("Open Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 148))
                        .disabled(viewModel.isWorking)

                        Button {
                            viewModel.confirmScreenRecordingPermission()
                        } label: {
                            if viewModel.isWorking {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 18, height: 18)
                            } else {
                                Label("I Enabled It", systemImage: "checkmark")
                            }
                        }
                        .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 142))
                        .keyboardShortcut(.defaultAction)
                        .disabled(viewModel.isWorking)
                    }
                }
            }
        )
    }

    private var firstCaptureMomentScreen: some View {
        OnboardingScreenLayout(
            visual: firstCaptureMomentVisual,
            title: viewModel.firstCaptureDidSucceed ? "There it is" : "Try your first capture",
            subtitle: firstCaptureSubtitle,
            inlineMessage: viewModel.inlineMessage,
            shortcutStatuses: [],
            footer: {
                OnboardingFooter {
                    if viewModel.firstCaptureDidSucceed {
                        Button {
                            viewModel.tryFirstCapture()
                        } label: {
                            Label("Try Again", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 126))

                        Button {
                            viewModel.continueFromFirstCaptureMoment()
                        } label: {
                            Label("Continue", systemImage: "arrow.right")
                        }
                        .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 132))
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button {
                            viewModel.continueFromFirstCaptureMoment()
                        } label: {
                            Label("Continue", systemImage: "arrow.right")
                        }
                        .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, width: 126))

                        Button {
                            viewModel.tryFirstCapture()
                        } label: {
                            Label("Try a Capture", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 152))
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        )
    }

    private var readyScreen: some View {
        OnboardingScreenLayout(
            visual: readyVisual,
            title: viewModel.nextScreenTitle,
            subtitle: viewModel.nextScreenSubtitle,
            inlineMessage: nil,
            shortcutStatuses: [],
            footer: {
                OnboardingFooter {
                    Button {
                        viewModel.finish()
                    } label: {
                        Label(viewModel.nextScreenButtonTitle, systemImage: "checkmark")
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .primary, width: 132))
                    .keyboardShortcut(.defaultAction)
                }
            }
        )
    }

    private var onboardingBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color(nsColor: .systemBlue).opacity(0.08),
                    Color(nsColor: .systemGreen).opacity(0.04),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var appGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .systemBlue))
                .frame(width: 26, height: 26)

            Image(systemName: "viewfinder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var welcomeVisual: some View {
        ZStack {
            VisualPanel(width: 352, height: 206)

            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    menuBarDot(color: .systemRed)
                    menuBarDot(color: .systemYellow)
                    menuBarDot(color: .systemGreen)

                    Spacer()

                    HStack(spacing: 7) {
                        Image(systemName: "viewfinder")
                        Text("ClearshotX")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule(style: .continuous))
                }

                HStack(spacing: 14) {
                    FeaturePill(icon: "rectangle.dashed", title: "Region")
                    FeaturePill(icon: "macwindow", title: "Window")
                    FeaturePill(icon: "display", title: "Screen")
                }

                HStack(spacing: 10) {
                    quickAction(icon: "square.and.arrow.down", color: .systemBlue)
                    quickAction(icon: "doc.on.clipboard", color: .systemGreen)
                    quickAction(icon: "arrowshape.turn.up.right", color: .systemPurple)
                }
            }
            .padding(22)
            .frame(width: 352, height: 206)
        }
        .frame(width: 380, height: 230)
    }

    private var capturePreviewVisual: some View {
        ZStack {
            VisualPanel(width: 376, height: 224)

            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    MiniWindow(title: "Notes")
                    MiniWindow(title: "Browser")
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemBlue), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .frame(width: 236, height: 86)

                    HStack(spacing: 10) {
                        Image(systemName: "cursorarrow.click")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .systemBlue))

                        Text("Drag to capture")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))
                    }
                }
            }
        }
        .frame(width: 396, height: 244)
    }

    private var shortcutChoiceVisual: some View {
        HStack(spacing: 18) {
            ShortcutOptionVisual(shortcut: "⇧⌘3", title: "Full Screen", tint: Color(nsColor: .systemBlue))
            ShortcutOptionVisual(shortcut: "⇧⌘4", title: "Region", tint: Color(nsColor: .systemGreen))
        }
        .frame(width: 390, height: 188)
    }

    private var systemSettingsGraphic: some View {
        SystemSettingsInstructionVisual()
    }

    private var screenRecordingPermissionVisual: some View {
        ScreenRecordingPermissionVisual(state: viewModel.screenRecordingPermissionState)
    }

    private var firstCaptureMomentVisual: some View {
        FirstCaptureMomentVisual(success: viewModel.firstCaptureDidSucceed)
    }

    private var firstCaptureSubtitle: String {
        let shortcut = viewModel.fullScreenShortcutLabel

        if shortcut.isEmpty {
            return "Click Try a Capture, or press your full-screen shortcut. ClearshotX will show the quick overlay right after the screenshot."
        }

        return "Click Try a Capture, or press \(shortcut). ClearshotX will show the quick overlay right after the screenshot."
    }

    private var readyVisual: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .systemGreen).opacity(0.14))
                .frame(width: 150, height: 150)

            Circle()
                .stroke(Color(nsColor: .systemGreen).opacity(0.28), lineWidth: 1)
                .frame(width: 180, height: 180)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 220, height: 220)
    }

    private func menuBarDot(color: NSColor) -> some View {
        Circle()
            .fill(Color(nsColor: color))
            .frame(width: 10, height: 10)
    }

    private func quickAction(icon: String, color: NSColor) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(Color(nsColor: color), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct OnboardingScreenLayout<Visual: View, Footer: View>: View {
    let visual: Visual
    let title: String
    let subtitle: String
    let inlineMessage: String?
    let shortcutStatuses: [MacScreenshotShortcutStatus]
    let footer: Footer

    init(
        visual: Visual,
        title: String,
        subtitle: String,
        inlineMessage: String?,
        shortcutStatuses: [MacScreenshotShortcutStatus],
        @ViewBuilder footer: () -> Footer
    ) {
        self.visual = visual
        self.title = title
        self.subtitle = subtitle
        self.inlineMessage = inlineMessage
        self.shortcutStatuses = shortcutStatuses
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    visual
                        .padding(.top, 14)

                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                        .padding(.horizontal, 58)

                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .padding(.horizontal, 92)

                    if !shortcutStatuses.isEmpty {
                        ScreenshotShortcutStatusPanel(
                            message: inlineMessage,
                            statuses: shortcutStatuses
                        )
                        .padding(.top, 14)
                        .padding(.horizontal, 88)
                    } else if let inlineMessage {
                        InlineOnboardingMessage(message: inlineMessage)
                            .padding(.top, 14)
                            .padding(.horizontal, 92)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)

            footer
        }
    }
}

private struct InlineOnboardingMessage: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(nsColor: .systemOrange))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .systemOrange).opacity(0.10))
            )
    }
}

private struct ScreenshotShortcutStatusPanel: View {
    let message: String?
    let statuses: [MacScreenshotShortcutStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(statuses.enumerated()), id: \.element.id) { index, status in
                    ScreenshotShortcutStatusRow(status: status)

                    if index < statuses.count - 1 {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.62), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .systemOrange).opacity(0.08))
        )
    }
}

private struct ScreenshotShortcutStatusRow: View {
    let status: MacScreenshotShortcutStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.isEnabled ? "checkmark.square.fill" : "square")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status.isEnabled ? Color(nsColor: .systemBlue) : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 22, height: 24)

            Text(status.systemShortcutName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            Text(status.shortcutDisplayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
    }
}

private struct OnboardingFooter<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.thinMaterial)
        }
    }
}

private struct VisualPanel: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.62), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 18)
            .frame(width: width, height: height)
    }
}

private struct FeaturePill: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemBlue))
                .frame(width: 42, height: 42)
                .background(Color(nsColor: .systemBlue).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .frame(width: 82)
    }
}

private struct MiniWindow: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(Color(nsColor: .systemRed)).frame(width: 6, height: 6)
                Circle().fill(Color(nsColor: .systemYellow)).frame(width: 6, height: 6)
                Circle().fill(Color(nsColor: .systemGreen)).frame(width: 6, height: 6)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(height: 8)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(0.36))
                .frame(width: 82, height: 8)
        }
        .padding(12)
        .frame(width: 142, height: 104)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ShortcutOptionVisual: View {
    let shortcut: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 13) {
            Text(shortcut)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: 132, height: 74)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 8)
                )

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(18)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ScreenRecordingPermissionVisual: View {
    let state: ScreenRecordingPermissionState

    private var isGranted: Bool {
        state == .granted
    }

    private var statusText: String {
        isGranted ? "Permission enabled" : "Permission needed"
    }

    private var statusIcon: String {
        isGranted ? "checkmark.shield.fill" : "lock.shield.fill"
    }

    private var statusColor: NSColor {
        isGranted ? .systemGreen : .systemBlue
    }

    var body: some View {
        ZStack {
            VisualPanel(width: 392, height: 278)

            VStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Color(nsColor: statusColor).opacity(0.13))
                        .frame(width: 72, height: 72)

                    Circle()
                        .stroke(Color(nsColor: statusColor).opacity(0.28), lineWidth: 1)
                        .frame(width: 90, height: 90)

                    Image(systemName: statusIcon)
                        .font(.system(size: 38, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color(nsColor: statusColor))
                }

                Text(statusText)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                VStack(spacing: 0) {
                    PermissionTrustRow(icon: "cursorarrow.click.2", title: "You stay in control", detail: "Capture starts from your shortcut or menu action.")
                    Divider().padding(.leading, 40)
                    PermissionTrustRow(icon: "eye.slash", title: "No background watching", detail: "ClearshotX is idle until you trigger a screenshot.")
                    Divider().padding(.leading, 40)
                    PermissionTrustRow(icon: "macwindow", title: "Mac protected", detail: "macOS keeps this permission visible in System Settings.")
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(18)
            .frame(width: 392, height: 278)
        }
        .frame(width: 420, height: 300)
    }
}

private struct PermissionTrustRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemBlue))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}

private struct FirstCaptureMomentVisual: View {
    let success: Bool

    var body: some View {
        ZStack {
            VisualPanel(width: 408, height: 258)

            ZStack(alignment: .bottomLeading) {
                VStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Circle().fill(Color(nsColor: .systemRed)).frame(width: 8, height: 8)
                        Circle().fill(Color(nsColor: .systemYellow)).frame(width: 8, height: 8)
                        Circle().fill(Color(nsColor: .systemGreen)).frame(width: 8, height: 8)

                        Spacer()

                        Text("Capture")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))

                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemBlue).opacity(0.16),
                                Color(nsColor: .systemGreen).opacity(0.12),
                                Color(nsColor: .textBackgroundColor).opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                CaptureMomentWindow(width: 106, height: 64, title: "Browser")
                                CaptureMomentWindow(width: 124, height: 78, title: "Notes")
                            }

                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(nsColor: .separatorColor).opacity(0.38))
                                .frame(width: 222, height: 9)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.58), lineWidth: 1)
                )
                .frame(width: 338, height: 190)

                QuickOverlayPreview(success: success)
                    .offset(x: 20, y: 24)
            }
            .frame(width: 408, height: 258)
        }
        .frame(width: 430, height: 280)
    }
}

private struct CaptureMomentWindow: View {
    let width: CGFloat
    let height: CGFloat
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: .separatorColor).opacity(0.7)).frame(width: 5, height: 5)
                Circle().fill(Color(nsColor: .separatorColor).opacity(0.52)).frame(width: 5, height: 5)
            }

            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 7)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(0.28))
                .frame(width: width * 0.58, height: 7)
        }
        .padding(10)
        .frame(width: width, height: height)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.86), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct QuickOverlayPreview: View {
    let success: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .frame(width: 138, height: 92)
                .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 1)
                )

            VStack(spacing: 7) {
                Image(systemName: success ? "checkmark.circle.fill" : "viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: success ? .systemGreen : .systemBlue))

                HStack(spacing: 6) {
                    CaptureMomentAction(icon: "doc.on.clipboard", title: "Copy")
                    CaptureMomentAction(icon: "square.and.arrow.down", title: "Save")
                    CaptureMomentAction(icon: "pencil", title: "Edit")
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: success ? "sparkles" : "cursorarrow.click")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(nsColor: success ? .systemGreen : .systemBlue))
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                .offset(x: 8, y: -8)
        }
    }
}

private struct CaptureMomentAction: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: 24, height: 20)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
    }
}

private struct SystemSettingsInstructionVisual: View {
    private var videoURL: URL? {
        Bundle.main.url(forResource: "DisableScreenshotShortcutsGuide", withExtension: "mp4")
            ?? Bundle.main.url(forResource: "DisableScreenshotShortcutsGuide", withExtension: "mov")
            ?? Bundle.main.url(forResource: "DisableScreenshotShortcutsGuide", withExtension: "mp4", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "DisableScreenshotShortcutsGuide", withExtension: "mov", subdirectory: "Resources")
    }

    var body: some View {
        ZStack {
            if let videoURL {
                MutedLoopingVideoView(url: videoURL)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.62), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 18)
                    .frame(width: 442, height: 311)
                    .accessibilityLabel("Looping guide showing how to disable macOS screenshot shortcuts")
            } else {
                SystemSettingsChecklistFallback()
            }
        }
        .frame(width: 462, height: 329)
    }
}

private struct SystemSettingsChecklistFallback: View {
    var body: some View {
        ZStack {
            VisualPanel(width: 390, height: 220)

            VStack(spacing: 10) {
                Text("Screenshots")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)

                SettingsShortcutRow(title: "Save picture of screen", shortcut: "⇧⌘3")
                SettingsShortcutRow(title: "Copy picture of screen", shortcut: "⌃⇧⌘3")
                SettingsShortcutRow(title: "Save selected area", shortcut: "⇧⌘4")
                SettingsShortcutRow(title: "Copy selected area", shortcut: "⌃⇧⌘4")
                SettingsShortcutRow(title: "Screenshot options", shortcut: "⇧⌘5")
            }
            .padding(22)
            .frame(width: 390, height: 220)
        }
        .frame(width: 410, height: 238)
    }
}

private struct MutedLoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingVideoPlayerView {
        let view = LoopingVideoPlayerView()
        view.configure(with: url)
        return view
    }

    func updateNSView(_ nsView: LoopingVideoPlayerView, context: Context) {
        nsView.configure(with: url)
        nsView.play()
    }

    static func dismantleNSView(_ nsView: LoopingVideoPlayerView, coordinator: ()) {
        nsView.stop()
    }
}

private final class LoopingVideoPlayerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var currentURL: URL?
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func configure(with url: URL) {
        guard currentURL != url else {
            play()
            return
        }

        stop()

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none

        currentURL = url
        player = queuePlayer
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        playerLayer.player = queuePlayer

        play()
    }

    func play() {
        player?.isMuted = true
        player?.play()
    }

    func stop() {
        player?.pause()
        playerLayer.player = nil
        playerLooper = nil
        player = nil
        currentURL = nil
    }
}

private struct SettingsShortcutRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.square")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemBlue))
                .frame(width: 20, height: 20)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(shortcut)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .frame(height: 24)
    }
}

private struct OnboardingActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(foregroundColor)
            .frame(width: width, height: 38)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor, lineWidth: kind == .primary ? 0 : 1)
            )
            .shadow(color: .black.opacity(kind == .primary ? 0.12 : 0.05), radius: 4, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            .white
        case .secondary:
            Color(nsColor: .labelColor)
        }
    }

    private var borderColor: Color {
        Color(nsColor: .separatorColor).opacity(0.7)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            Color(nsColor: isPressed ? .systemBlue.withSystemEffect(.pressed) : .systemBlue)
        case .secondary:
            Color(nsColor: isPressed ? .controlBackgroundColor.withSystemEffect(.pressed) : .controlBackgroundColor)
        }
    }
}
