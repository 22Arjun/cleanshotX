//
//  AppShellViewModel.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import Combine

@MainActor
final class AppShellViewModel: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var activeHotkeyMode: GlobalHotkeyMode = .preferred

    private let screenCaptureService: ScreenCaptureService
    private let clipboardService: ClipboardService
    private let previewWindowManager: PreviewWindowManager
    private let quickAccessOverlayManager: QuickAccessOverlayManager
    private let regionSelectionManager: RegionSelectionManager
    private let windowSelectionManager: WindowSelectionManager
    private let hotkeyConflictResolutionManager: HotkeyConflictResolutionManager
    private let hotkeySetupWindowManager: HotkeySetupWindowManager
    private let settingsWindowManager: SettingsWindowManager
    private let alertPresenter: AlertPresenter

    private var appDidFinishLaunchingObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?

    init(
        screenCaptureService: ScreenCaptureService? = nil,
        clipboardService: ClipboardService? = nil,
        previewWindowManager: PreviewWindowManager? = nil,
        quickAccessOverlayManager: QuickAccessOverlayManager? = nil,
        regionSelectionManager: RegionSelectionManager? = nil,
        windowSelectionManager: WindowSelectionManager? = nil,
        hotkeyConflictResolutionManager: HotkeyConflictResolutionManager? = nil,
        hotkeySetupWindowManager: HotkeySetupWindowManager? = nil,
        settingsWindowManager: SettingsWindowManager? = nil,
        alertPresenter: AlertPresenter? = nil
    ) {
        self.screenCaptureService = screenCaptureService ?? ScreenCaptureService()
        self.clipboardService = clipboardService ?? ClipboardService()
        self.previewWindowManager = previewWindowManager ?? PreviewWindowManager()
        self.quickAccessOverlayManager = quickAccessOverlayManager ?? QuickAccessOverlayManager()
        self.regionSelectionManager = regionSelectionManager ?? RegionSelectionManager()
        self.windowSelectionManager = windowSelectionManager ?? WindowSelectionManager()
        self.hotkeyConflictResolutionManager = hotkeyConflictResolutionManager ?? HotkeyConflictResolutionManager()
        self.hotkeySetupWindowManager = hotkeySetupWindowManager ?? HotkeySetupWindowManager()
        self.settingsWindowManager = settingsWindowManager ?? SettingsWindowManager()
        self.alertPresenter = alertPresenter ?? AlertPresenter()

        observeAppActivation()
        configureGlobalHotkeysAfterLaunch()
    }

    deinit {
        if let appDidFinishLaunchingObserver {
            NotificationCenter.default.removeObserver(appDidFinishLaunchingObserver)
        }

        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
        }
    }

    func captureFullScreen() {
        guard !isCapturing else {
            return
        }

        isCapturing = true

        Task {
            defer {
                isCapturing = false
            }

            do {
                let capture = try await screenCaptureService.captureFullScreen()
                showQuickAccessOverlay(for: capture)
            } catch {
                handleCaptureError(error)
            }
        }
    }

    func captureRegion() {
        guard !isCapturing else {
            return
        }

        isCapturing = true

        Task {
            defer {
                isCapturing = false
            }

            guard let region = await regionSelectionManager.selectRegion() else {
                return
            }

            do {
                let capture = try await screenCaptureService.captureRegion(region)
                showQuickAccessOverlay(for: capture)
            } catch {
                handleCaptureError(error)
            }
        }
    }

    func captureWindow() {
        guard !isCapturing else {
            return
        }

        isCapturing = true

        Task {
            defer {
                isCapturing = false
            }

            do {
                let windows = try await screenCaptureService.availableWindows()

                guard let window = await windowSelectionManager.selectWindow(from: windows) else {
                    return
                }

                let capture = try await screenCaptureService.captureWindow(window)
                showQuickAccessOverlay(for: capture)
            } catch {
                handleCaptureError(error)
            }
        }
    }

    func openScreenRecordingSettings() {
        screenCaptureService.openScreenRecordingSettings()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func shortcutLabel(for action: GlobalHotkeyAction) -> String {
        hotkeyConflictResolutionManager.shortcutLabel(for: action)
    }

    func openSettings() {
        settingsWindowManager.show(viewModel: self)
    }

    func openDefaultShortcutSetupFromSettings() {
        showHotkeyResolutionFlow(context: .settings)
    }

    func resetKeyboardShortcutSetup() {
        Task {
            await hotkeyConflictResolutionManager.resetSetup(
                captureFullScreen: { [weak self] in
                    self?.captureFullScreen()
                },
                captureRegion: { [weak self] in
                    self?.captureRegion()
                }
            )
            activeHotkeyMode = hotkeyConflictResolutionManager.activeMode
        }
    }

    #if DEBUG
    func resetOnboardingForDevelopment() {
        Task {
            await hotkeyConflictResolutionManager.resetOnboardingForDevelopment(
                captureFullScreen: { [weak self] in
                    self?.captureFullScreen()
                },
                captureRegion: { [weak self] in
                    self?.captureRegion()
                }
            )
            activeHotkeyMode = hotkeyConflictResolutionManager.activeMode
            showHotkeyResolutionFlow(context: .firstRun)
        }
    }
    #endif

    private func configureGlobalHotkeysAfterLaunch() {
        if NSApp.isRunning {
            Task { @MainActor in
                await configureGlobalHotkeysOnLaunch()
            }
            return
        }

        appDidFinishLaunchingObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.configureGlobalHotkeysOnLaunch()
            }
        }
    }

    private func configureGlobalHotkeysOnLaunch() async {
        let presentation = await hotkeyConflictResolutionManager.configureOnLaunch(
            captureFullScreen: { [weak self] in
                self?.captureFullScreen()
            },
            captureRegion: { [weak self] in
                self?.captureRegion()
            }
        )
        activeHotkeyMode = hotkeyConflictResolutionManager.activeMode

        switch presentation {
        case .none:
            break
        case .presentOnboarding:
            showHotkeyResolutionFlow(context: .firstRun)
        }
    }

    private func observeAppActivation() {
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.hotkeyConflictResolutionManager.defaultShortcutSetupIsPending else {
                    return
                }

                await self.hotkeyConflictResolutionManager.refreshPendingDefaultShortcutSetup(
                    captureFullScreen: { [weak self] in
                        self?.captureFullScreen()
                    },
                    captureRegion: { [weak self] in
                        self?.captureRegion()
                    }
                )
                self.activeHotkeyMode = self.hotkeyConflictResolutionManager.activeMode
            }
        }
    }

    private func showHotkeyResolutionFlow(context: HotkeyOnboardingFlowContext) {
        let flowViewModel = HotkeyOnboardingFlowViewModel(
            context: context,
            hotkeyConflictResolutionManager: hotkeyConflictResolutionManager,
            captureFullScreen: { [weak self] in
                self?.captureFullScreen()
            },
            captureRegion: { [weak self] in
                self?.captureRegion()
            },
            onHotkeyModeChanged: { [weak self] in
                guard let self else { return }
                self.activeHotkeyMode = self.hotkeyConflictResolutionManager.activeMode
            },
            onFinished: { [weak self] in
                guard let self else { return }
                self.activeHotkeyMode = self.hotkeyConflictResolutionManager.activeMode
                self.hotkeySetupWindowManager.close()
            }
        )

        hotkeySetupWindowManager.show(viewModel: flowViewModel)
    }

    private func handleCaptureError(_ error: Error) {
        if case ScreenCaptureServiceError.permissionDenied = error {
            alertPresenter.showScreenRecordingPermissionAlert(
                openSettings: { [screenCaptureService] in
                    screenCaptureService.openScreenRecordingSettings()
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
            return
        }

        let localizedError = error as? LocalizedError
        let message = [
            localizedError?.errorDescription ?? error.localizedDescription,
            localizedError?.recoverySuggestion
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        alertPresenter.showError(
            title: "Screen Capture Failed",
            message: message
        )
    }

    private func showQuickAccessOverlay(for capture: CaptureResult) {
        quickAccessOverlayManager.show(
            capture: capture,
            clipboardService: clipboardService,
            previewWindowManager: previewWindowManager
        )
    }
}
