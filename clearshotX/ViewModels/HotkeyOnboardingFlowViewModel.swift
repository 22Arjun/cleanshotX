//
//  HotkeyOnboardingFlowViewModel.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import Combine
import Foundation
import OSLog

enum HotkeyOnboardingFlowContext {
    case firstRun
    case settings
}

enum HotkeyOnboardingScreen: String {
    case welcome
    case capturePreview
    case defaultScreenshotToolDecision
    case systemSettingsInstructions
    case nextOnboardingScreen
}

@MainActor
final class HotkeyOnboardingFlowViewModel: ObservableObject {
    typealias Handler = GlobalHotkeyService.Handler

    @Published private(set) var screen: HotkeyOnboardingScreen
    @Published private(set) var inlineMessage: String?
    @Published private(set) var isWorking = false

    private let context: HotkeyOnboardingFlowContext
    private let hotkeyConflictResolutionManager: HotkeyConflictResolutionManager
    private let captureFullScreen: Handler
    private let captureRegion: Handler
    private let onHotkeyModeChanged: () -> Void
    private let onFinished: () -> Void
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "HotkeyOnboarding"
    )

    init(
        context: HotkeyOnboardingFlowContext,
        hotkeyConflictResolutionManager: HotkeyConflictResolutionManager,
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler,
        onHotkeyModeChanged: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.context = context
        self.screen = context == .firstRun ? .welcome : .defaultScreenshotToolDecision
        self.hotkeyConflictResolutionManager = hotkeyConflictResolutionManager
        self.captureFullScreen = captureFullScreen
        self.captureRegion = captureRegion
        self.onHotkeyModeChanged = onHotkeyModeChanged
        self.onFinished = onFinished
    }

    var visibleScreens: [HotkeyOnboardingScreen] {
        switch context {
        case .firstRun:
            [.welcome, .capturePreview, .defaultScreenshotToolDecision, .nextOnboardingScreen]
        case .settings:
            [.defaultScreenshotToolDecision, .nextOnboardingScreen]
        }
    }

    var currentStepIndex: Int {
        if screen == .systemSettingsInstructions,
           let shortcutStepIndex = visibleScreens.firstIndex(of: .defaultScreenshotToolDecision) {
            return shortcutStepIndex
        }

        return visibleScreens.firstIndex(of: screen) ?? max(visibleScreens.count - 1, 0)
    }

    var stepCount: Int {
        visibleScreens.count
    }

    var nextScreenTitle: String {
        switch context {
        case .firstRun:
            "ClearshotX is ready"
        case .settings:
            "Keyboard shortcuts updated"
        }
    }

    var nextScreenSubtitle: String {
        switch context {
        case .firstRun:
            "Your screenshot shortcuts are set. ClearshotX is running quietly in the menu bar whenever you need it."
        case .settings:
            "ClearshotX will keep using the shortcut choice you just selected."
        }
    }

    var nextScreenButtonTitle: String {
        switch context {
        case .firstRun:
            "Continue"
        case .settings:
            "Done"
        }
    }

    func continueFromWelcome() {
        logger.info("User continued from welcome onboarding")
        transition(to: .capturePreview)
    }

    func continueFromCapturePreview() {
        logger.info("User continued from capture preview onboarding")
        transition(to: .defaultScreenshotToolDecision)
    }

    func declineDefaultShortcuts() {
        guard !isWorking else {
            return
        }

        logger.info("User selected independent screenshot shortcuts")
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            await hotkeyConflictResolutionManager.registerIndependentDefaultHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion
            )
            onHotkeyModeChanged()
            transition(to: .nextOnboardingScreen)
        }
    }

    func acceptDefaultShortcuts() {
        guard !isWorking else {
            return
        }

        logger.info("User selected macOS default screenshot shortcuts")
        inlineMessage = nil
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            await hotkeyConflictResolutionManager.prepareDefaultShortcutSetup(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion
            )
            onHotkeyModeChanged()
            transition(to: .systemSettingsInstructions)
        }
    }

    func openSystemSettings() {
        inlineMessage = nil

        guard hotkeyConflictResolutionManager.openKeyboardShortcutSettings() else {
            inlineMessage = "ClearshotX could not open System Settings automatically. Open Keyboard Shortcuts, then Screenshots, and turn off all five rows."
            return
        }

        logger.info("System Settings open request was accepted")
    }

    func returnToDefaultShortcutDecision() {
        inlineMessage = nil
        hotkeyConflictResolutionManager.cancelPendingDefaultShortcutSetup()
        transition(to: .defaultScreenshotToolDecision)
    }

    func confirmSystemShortcutsDisabled() {
        guard !isWorking else {
            return
        }

        inlineMessage = nil
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            let result = await hotkeyConflictResolutionManager.confirmDefaultShortcutSetup(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion
            )
            onHotkeyModeChanged()

            switch result {
            case .ready:
                transition(to: .nextOnboardingScreen)
            case .stillEnabled(let message):
                logger.info("User confirmation did not resolve the shortcut conflict")
                inlineMessage = message
            }
        }
    }

    func finish() {
        logger.info("Hotkey onboarding flow finished")
        onFinished()
    }

    private func transition(to nextScreen: HotkeyOnboardingScreen) {
        let previousScreen = screen
        screen = nextScreen
        logger.info("Hotkey onboarding transition \(previousScreen.rawValue, privacy: .public) -> \(nextScreen.rawValue, privacy: .public)")
    }
}
