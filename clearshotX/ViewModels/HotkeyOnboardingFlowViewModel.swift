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
    case screenRecordingPermission
    case firstCaptureMoment
    case nextOnboardingScreen
}

@MainActor
final class HotkeyOnboardingFlowViewModel: ObservableObject {
    typealias Handler = GlobalHotkeyService.Handler

    @Published private(set) var screen: HotkeyOnboardingScreen
    @Published private(set) var inlineMessage: String?
    @Published private(set) var screenshotShortcutStatuses: [MacScreenshotShortcutStatus] = []
    @Published private(set) var screenRecordingPermissionState: ScreenRecordingPermissionState = .notGranted
    @Published private(set) var firstCaptureDidSucceed = false
    @Published private(set) var isWorking = false

    private let context: HotkeyOnboardingFlowContext
    private let hotkeyConflictResolutionManager: HotkeyConflictResolutionManager
    private let screenRecordingPermissionService: ScreenRecordingPermissionService
    private let captureFullScreen: Handler
    private let captureRegion: Handler
    private let onHotkeyModeChanged: () -> Void
    private let onFinished: () -> Void
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "HotkeyOnboarding"
    )
    private var captureSucceededObserver: NSObjectProtocol?

    init(
        context: HotkeyOnboardingFlowContext,
        hotkeyConflictResolutionManager: HotkeyConflictResolutionManager,
        screenRecordingPermissionService: ScreenRecordingPermissionService? = nil,
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler,
        onHotkeyModeChanged: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.context = context
        self.screen = context == .firstRun ? .welcome : .defaultScreenshotToolDecision
        self.hotkeyConflictResolutionManager = hotkeyConflictResolutionManager
        self.screenRecordingPermissionService = screenRecordingPermissionService ?? ScreenRecordingPermissionService()
        self.captureFullScreen = captureFullScreen
        self.captureRegion = captureRegion
        self.onHotkeyModeChanged = onHotkeyModeChanged
        self.onFinished = onFinished

        observeCaptureSucceeded()
    }

    deinit {
        if let captureSucceededObserver {
            NotificationCenter.default.removeObserver(captureSucceededObserver)
        }
    }

    var visibleScreens: [HotkeyOnboardingScreen] {
        switch context {
        case .firstRun:
            [.welcome, .capturePreview, .defaultScreenshotToolDecision, .screenRecordingPermission, .firstCaptureMoment, .nextOnboardingScreen]
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

    var fullScreenShortcutLabel: String {
        hotkeyConflictResolutionManager.shortcutLabel(for: .captureFullScreen)
    }

    var regionShortcutLabel: String {
        hotkeyConflictResolutionManager.shortcutLabel(for: .captureRegion)
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
                captureRegion: captureRegion,
                completeOnboarding: context == .settings
            )
            onHotkeyModeChanged()
            transitionAfterHotkeySetup()
        }
    }

    func acceptDefaultShortcuts() {
        guard !isWorking else {
            return
        }

        logger.info("User selected macOS default screenshot shortcuts")
        inlineMessage = nil
        screenshotShortcutStatuses = []
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
        screenshotShortcutStatuses = []

        guard hotkeyConflictResolutionManager.openKeyboardShortcutSettings() else {
            inlineMessage = "ClearshotX could not open System Settings automatically. Open Keyboard Shortcuts, then Screenshots, and turn off all five rows."
            return
        }

        logger.info("System Settings open request was accepted")
    }

    func returnToDefaultShortcutDecision() {
        inlineMessage = nil
        screenshotShortcutStatuses = []
        hotkeyConflictResolutionManager.cancelPendingDefaultShortcutSetup()
        transition(to: .defaultScreenshotToolDecision)
    }

    func confirmSystemShortcutsDisabled() {
        guard !isWorking else {
            return
        }

        inlineMessage = nil
        screenshotShortcutStatuses = []
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            let result = await hotkeyConflictResolutionManager.confirmDefaultShortcutSetup(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                completeOnboarding: context == .settings
            )
            onHotkeyModeChanged()

            switch result {
            case .ready:
                screenshotShortcutStatuses = []
                transitionAfterHotkeySetup()
            case .stillEnabled(let message, let shortcutStatuses):
                logger.info("User confirmation did not resolve the shortcut conflict")
                inlineMessage = message
                screenshotShortcutStatuses = shortcutStatuses
            }
        }
    }

    func refreshScreenRecordingPermission() {
        guard !isWorking else {
            return
        }

        logger.info("Refreshing Screen Recording permission state")
        inlineMessage = nil
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            screenRecordingPermissionState = await screenRecordingPermissionService.currentState()
        }
    }

    func requestScreenRecordingPermission() {
        guard !isWorking else {
            return
        }

        logger.info("User requested Screen Recording permission from onboarding")
        inlineMessage = nil
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            screenRecordingPermissionState = await screenRecordingPermissionService.requestPermission()

            if screenRecordingPermissionState != .granted {
                inlineMessage = "macOS has not granted Screen Recording yet. Open System Settings, enable ClearshotX, then come back here."
            }
        }
    }

    func openScreenRecordingSettings() {
        inlineMessage = nil

        guard screenRecordingPermissionService.openSystemSettings() else {
            inlineMessage = "ClearshotX could not open System Settings automatically. Open Privacy & Security > Screen & System Audio Recording, then enable ClearshotX."
            return
        }

        logger.info("Screen Recording settings open request was accepted")
    }

    func confirmScreenRecordingPermission() {
        guard !isWorking else {
            return
        }

        logger.info("User confirmed Screen Recording permission should be enabled")
        inlineMessage = nil
        isWorking = true

        Task { @MainActor in
            defer {
                isWorking = false
            }

            screenRecordingPermissionState = await screenRecordingPermissionService.currentState()

            guard screenRecordingPermissionState == .granted else {
                logger.info("Screen Recording permission is still not active")
                inlineMessage = "ClearshotX still cannot see Screen Recording permission. If you already enabled it, quit and reopen ClearshotX so macOS applies the change."
                return
            }

            transitionAfterScreenRecordingPermission()
        }
    }

    func tryFirstCapture() {
        logger.info("User started first capture moment from onboarding")
        inlineMessage = "Watch for the floating thumbnail. Hover it to reveal Copy, Save, Edit, Pin, and Delete."
        captureFullScreen()
    }

    func continueFromFirstCaptureMoment() {
        logger.info("User continued from first capture moment; success observed: \(self.firstCaptureDidSucceed, privacy: .public)")
        transition(to: .nextOnboardingScreen)
    }

    func finish() {
        logger.info("Hotkey onboarding flow finished")
        if context == .firstRun {
            hotkeyConflictResolutionManager.completeOnboardingFlow()
        }
        onFinished()
    }

    private func transition(to nextScreen: HotkeyOnboardingScreen) {
        let previousScreen = screen
        screen = nextScreen
        logger.info("Hotkey onboarding transition \(previousScreen.rawValue, privacy: .public) -> \(nextScreen.rawValue, privacy: .public)")

        if nextScreen == .screenRecordingPermission {
            Task { @MainActor in
                screenRecordingPermissionState = await screenRecordingPermissionService.currentState()
            }
        }

        if nextScreen == .firstCaptureMoment {
            inlineMessage = nil
            firstCaptureDidSucceed = false
        }
    }

    private func transitionAfterHotkeySetup() {
        switch context {
        case .firstRun:
            transition(to: .screenRecordingPermission)
        case .settings:
            transition(to: .nextOnboardingScreen)
        }
    }

    private func transitionAfterScreenRecordingPermission() {
        switch context {
        case .firstRun:
            transition(to: .firstCaptureMoment)
        case .settings:
            transition(to: .nextOnboardingScreen)
        }
    }

    private func observeCaptureSucceeded() {
        captureSucceededObserver = NotificationCenter.default.addObserver(
            forName: .clearshotXCaptureSucceeded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.screen == .firstCaptureMoment else {
                    return
                }

                self.logger.info("First capture success observed during onboarding")
                self.firstCaptureDidSucceed = true
                self.inlineMessage = "Nice. That floating thumbnail is the quick overlay: copy, save, edit, pin, or delete without breaking your flow."
            }
        }
    }
}
