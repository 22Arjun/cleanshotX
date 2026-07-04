//
//  HotkeyConflictResolutionManager.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import Foundation
import OSLog

enum HotkeyOnboardingLaunchPresentation {
    case none
    case presentOnboarding
}

enum HotkeyDefaultShortcutConfirmationResult {
    case ready
    case stillEnabled(message: String)
}

@MainActor
final class HotkeyConflictResolutionManager {
    typealias Handler = GlobalHotkeyService.Handler

    private enum UserDefaultsKey {
        static let hotkeyMode = "GlobalHotkeyMode"
        static let keyboardShortcutSetupCompleted = "KeyboardShortcutSetupCompleted"
        static let keyboardShortcutSetupVersion = "KeyboardShortcutSetupVersion"
        static let onboardingCompletedVersion = "OnboardingCompletedVersion"
        static let defaultShortcutSetupPending = "DefaultShortcutSetupPending"

        // Increase this when an updated onboarding flow should be shown to existing installs.
        static let currentOnboardingVersion = 1
        static let currentKeyboardShortcutSetupVersion = 8
    }

    private let globalHotkeyService: GlobalHotkeyService
    private let macScreenshotShortcutService: MacScreenshotShortcutService
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "HotkeyConflictResolution"
    )

    private(set) var activeMode: GlobalHotkeyMode = .temporary
    private(set) var registeredHotkeys: [GlobalHotkey] = []

    init(
        globalHotkeyService: GlobalHotkeyService? = nil,
        macScreenshotShortcutService: MacScreenshotShortcutService? = nil
    ) {
        self.globalHotkeyService = globalHotkeyService ?? GlobalHotkeyService()
        self.macScreenshotShortcutService = macScreenshotShortcutService ?? MacScreenshotShortcutService()
    }

    var defaultShortcutSetupIsPending: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKey.defaultShortcutSetupPending)
    }

    func configureOnLaunch(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) async -> HotkeyOnboardingLaunchPresentation {
        logger.info("Configuring global hotkeys on launch")

        guard currentOnboardingIsComplete else {
            logger.info("Current onboarding version has not completed; registering independent hotkeys and presenting onboarding")
            _ = registerIndependentHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                rememberChoice: false
            )
            return .presentOnboarding
        }

        if defaultShortcutSetupIsPending {
            logger.info("Default shortcut setup is pending; registering independent hotkeys silently")
            _ = registerIndependentHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                rememberChoice: false
            )
            return .none
        }

        guard keyboardShortcutSetupIsComplete else {
            logger.info("Shortcut setup metadata is stale; using independent hotkeys")
            _ = registerIndependentHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                rememberChoice: true,
                completeOnboarding: false
            )
            return .none
        }

        switch storedHotkeyMode ?? .temporary {
        case .preferred:
            if case .allDisabled = screenshotShortcutState() {
                _ = registerPreferredHotkeys(
                    captureFullScreen: captureFullScreen,
                    captureRegion: captureRegion,
                    completeOnboarding: false
                )
                return .none
            }

            logger.info("Preferred hotkeys conflict with macOS shortcuts; using independent hotkeys")
            _ = registerIndependentHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                rememberChoice: false
            )
            return .none
        case .temporary, .menuBarOnly:
            _ = registerIndependentHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                rememberChoice: true,
                completeOnboarding: false
            )
            return .none
        }
    }

    func registerIndependentDefaultHotkeys(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) async {
        logger.info("User declined default screenshot shortcuts; registering independent hotkeys")
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.defaultShortcutSetupPending)

        _ = registerIndependentHotkeys(
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion,
            rememberChoice: true
        )
    }

    func prepareDefaultShortcutSetup(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) async {
        logger.info("User chose ClearshotX as the default screenshot tool; preparing System Settings step")
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.defaultShortcutSetupPending)

        _ = registerIndependentHotkeys(
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion,
            rememberChoice: false
        )
    }

    func confirmDefaultShortcutSetup(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) async -> HotkeyDefaultShortcutConfirmationResult {
        logger.info("Re-checking macOS screenshot shortcut state after user confirmation")

        let state = screenshotShortcutState()

        guard case .allDisabled = state else {
            logger.info("macOS screenshot shortcuts are not confirmed disabled; keeping independent hotkeys registered")
            _ = registerIndependentHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                rememberChoice: false
            )
            return .stillEnabled(message: confirmationFailureMessage(for: state))
        }

        let preferredHotkeysRegistered = registerPreferredHotkeys(
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion
        )

        if !preferredHotkeysRegistered {
            logger.warning("macOS screenshot shortcuts are disabled, but preferred hotkey registration still failed; allowing onboarding to continue and retrying preferred registration on next launch")
            rememberSetup(mode: .preferred)
        }

        logger.info("Default screenshot shortcut setup completed")
        return .ready
    }

    func cancelPendingDefaultShortcutSetup() {
        logger.info("User returned from System Settings instructions to shortcut decision")
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.defaultShortcutSetupPending)
    }

    func refreshPendingDefaultShortcutSetup(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) async {
        guard defaultShortcutSetupIsPending else {
            return
        }

        guard case .allDisabled = screenshotShortcutState() else {
            logger.info("Pending default shortcut setup is not confirmed disabled; keeping independent hotkeys silently")
            _ = registerIndependentHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                rememberChoice: false
            )
            return
        }

        logger.info("Pending default shortcut setup is resolved; registering preferred hotkeys silently")
        _ = registerPreferredHotkeys(
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion,
            completeOnboarding: false
        )
    }

    func resetSetup(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) async {
        logger.info("Resetting keyboard shortcut setup")
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.hotkeyMode)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.keyboardShortcutSetupCompleted)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.keyboardShortcutSetupVersion)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.defaultShortcutSetupPending)

        _ = registerIndependentHotkeys(
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion,
            rememberChoice: true,
            completeOnboarding: false
        )
    }

    #if DEBUG
    func resetOnboardingForDevelopment(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) async {
        logger.info("Resetting onboarding for development")
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.hotkeyMode)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.keyboardShortcutSetupCompleted)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.keyboardShortcutSetupVersion)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.onboardingCompletedVersion)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.defaultShortcutSetupPending)

        _ = registerIndependentHotkeys(
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion,
            rememberChoice: false
        )
    }
    #endif

    @discardableResult
    func openKeyboardShortcutSettings() -> Bool {
        logger.info("Opening System Settings Keyboard Shortcuts pane")
        return macScreenshotShortcutService.openKeyboardShortcutSettings()
    }

    func shortcutLabel(for action: GlobalHotkeyAction) -> String {
        registeredHotkeys.first { $0.action == action }?.displayName
            ?? fallbackHotkeys(for: activeMode).first { $0.action == action }?.displayName
            ?? ""
    }

    private var storedHotkeyMode: GlobalHotkeyMode? {
        guard let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKey.hotkeyMode),
              let mode = GlobalHotkeyMode(rawValue: rawValue)
        else {
            return nil
        }

        return mode
    }

    private var keyboardShortcutSetupIsComplete: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKey.keyboardShortcutSetupCompleted)
            && UserDefaults.standard.integer(forKey: UserDefaultsKey.keyboardShortcutSetupVersion) == UserDefaultsKey.currentKeyboardShortcutSetupVersion
    }

    private var currentOnboardingIsComplete: Bool {
        UserDefaults.standard.integer(forKey: UserDefaultsKey.onboardingCompletedVersion) >= UserDefaultsKey.currentOnboardingVersion
    }

    private func activeScreenshotShortcutConflicts() -> [MacScreenshotShortcutConflict] {
        macScreenshotShortcutService.activeScreenshotShortcutConflicts()
    }

    private func screenshotShortcutState() -> MacScreenshotShortcutState {
        macScreenshotShortcutService.screenshotShortcutState()
    }

    private func confirmationFailureMessage(for state: MacScreenshotShortcutState) -> String {
        switch state {
        case .allDisabled:
            return ""
        case .active(let conflicts):
            let shortcutNames = conflicts.map(\.systemShortcutName).joined(separator: ", ")
            return "ClearshotX still reads these Screenshots rows as enabled: \(shortcutNames). Turn off all five rows, then try again."
        case .unknown:
            return "ClearshotX could not read a complete enabled/disabled state for all five macOS Screenshots shortcut rows yet. Close System Settings after changing them, then try again."
        }
    }

    @discardableResult
    private func registerPreferredHotkeys(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler,
        completeOnboarding: Bool = true
    ) -> Bool {
        logger.info("Attempting to register preferred screenshot hotkeys")
        let result = registerGlobalHotkeys(
            mode: .preferred,
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion
        )

        guard result.isSuccessful else {
            logger.warning("Preferred hotkey registration failed; falling back to independent hotkeys")
            _ = registerIndependentHotkeys(
                captureFullScreen: captureFullScreen,
                captureRegion: captureRegion,
                rememberChoice: false
            )
            return false
        }

        rememberSetup(mode: .preferred, completeOnboarding: completeOnboarding)
        logger.info("Preferred screenshot hotkeys registered successfully")
        return true
    }

    @discardableResult
    private func registerIndependentHotkeys(
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler,
        rememberChoice: Bool,
        completeOnboarding: Bool = true
    ) -> GlobalHotkeyRegistrationResult {
        logger.info("Registering independent hotkeys")
        let result = registerGlobalHotkeys(
            mode: .temporary,
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion
        )

        if result.isSuccessful {
            if rememberChoice {
                rememberSetup(mode: .temporary, completeOnboarding: completeOnboarding)
            }
            logger.info("Independent hotkeys registered successfully")
        } else {
            logger.error("Independent hotkey registration failed")
        }

        return result
    }

    private func registerGlobalHotkeys(
        mode: GlobalHotkeyMode,
        captureFullScreen: @escaping Handler,
        captureRegion: @escaping Handler
    ) -> GlobalHotkeyRegistrationResult {
        activeMode = mode

        let result = globalHotkeyService.register(
            mode: mode,
            captureFullScreen: captureFullScreen,
            captureRegion: captureRegion
        )

        registeredHotkeys = result.registeredHotkeys

        if !result.isSuccessful {
            logger.warning("Failed to register \(mode.rawValue, privacy: .public) hotkeys")
        }

        return result
    }

    private func rememberSetup(
        mode: GlobalHotkeyMode,
        completeOnboarding: Bool = true
    ) {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.defaultShortcutSetupPending)
        UserDefaults.standard.set(mode.rawValue, forKey: UserDefaultsKey.hotkeyMode)
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.keyboardShortcutSetupCompleted)
        UserDefaults.standard.set(
            UserDefaultsKey.currentKeyboardShortcutSetupVersion,
            forKey: UserDefaultsKey.keyboardShortcutSetupVersion
        )

        if completeOnboarding {
            UserDefaults.standard.set(
                UserDefaultsKey.currentOnboardingVersion,
                forKey: UserDefaultsKey.onboardingCompletedVersion
            )
        }
    }

    private func fallbackHotkeys(for mode: GlobalHotkeyMode) -> [GlobalHotkey] {
        switch mode {
        case .preferred:
            GlobalHotkeyService.preferredHotkeys
        case .temporary, .menuBarOnly:
            GlobalHotkeyService.temporaryHotkeys
        }
    }
}
