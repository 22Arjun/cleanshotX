//
//  AppShellViewModel.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit
import Combine

extension Notification.Name {
    static let clearshotXCaptureSucceeded = Notification.Name("ClearshotXCaptureSucceeded")
}

@MainActor
final class AppShellViewModel: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var activeHotkeyMode: GlobalHotkeyMode = .preferred
    @Published private(set) var isCaptureSoundEnabled: Bool
    @Published private(set) var regionMagnifierMode: RegionMagnifierMode
    @Published private(set) var captureSaveMode: CaptureSaveMode
    @Published private(set) var captureSaveFolderPath: String?
    @Published private(set) var hasDefaultCaptureFolderAuthorization: Bool
    @Published private(set) var isTemporaryCaptureCleanupEnabled: Bool

    private let screenCaptureService: ScreenCaptureService
    private let captureStore: CaptureStoring
    private let captureSavePreferences: CaptureSavePreferences
    private let regionCapturePreferences: RegionCapturePreferences
    private let captureSoundService: CaptureSoundService
    private let clipboardService: ClipboardService
    private let editorWindowManager: EditorWindowManager
    private let quickAccessOverlayManager: QuickAccessOverlayManager
    private let regionSelectionManager: RegionSelectionManager
    private let windowSelectionManager: WindowSelectionManager
    private let hotkeyConflictResolutionManager: HotkeyConflictResolutionManager
    private let hotkeySetupWindowManager: HotkeySetupWindowManager
    private let settingsWindowManager: SettingsWindowManager
    private let menuBarStatusItemManager: MenuBarStatusItemManager
    private let menuBarReadyHintManager: MenuBarReadyHintManager
    private let alertPresenter: AlertPresenter

    private var appDidFinishLaunchingObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?

    init(
        screenCaptureService: ScreenCaptureService? = nil,
        captureStore: CaptureStoring? = nil,
        captureSavePreferences: CaptureSavePreferences? = nil,
        regionCapturePreferences: RegionCapturePreferences? = nil,
        captureExportService: CaptureExportServicing? = nil,
        captureSoundService: CaptureSoundService? = nil,
        clipboardService: ClipboardService? = nil,
        editorWindowManager: EditorWindowManager? = nil,
        quickAccessOverlayManager: QuickAccessOverlayManager? = nil,
        regionSelectionManager: RegionSelectionManager? = nil,
        windowSelectionManager: WindowSelectionManager? = nil,
        hotkeyConflictResolutionManager: HotkeyConflictResolutionManager? = nil,
        hotkeySetupWindowManager: HotkeySetupWindowManager? = nil,
        settingsWindowManager: SettingsWindowManager? = nil,
        menuBarStatusItemManager: MenuBarStatusItemManager? = nil,
        menuBarReadyHintManager: MenuBarReadyHintManager? = nil,
        alertPresenter: AlertPresenter? = nil
    ) {
        let resolvedSavePreferences = captureSavePreferences ?? CaptureSavePreferences()
        let resolvedRegionCapturePreferences = regionCapturePreferences ?? RegionCapturePreferences()
        let resolvedCaptureStore = captureStore ?? CaptureStore(
            preferences: resolvedSavePreferences,
            isCleanupEnabled: { resolvedSavePreferences.isTemporaryCaptureCleanupEnabled }
        )
        let resolvedExportService = captureExportService ?? CaptureExportService(
            preferences: resolvedSavePreferences
        )

        self.screenCaptureService = screenCaptureService ?? ScreenCaptureService(
            captureStore: resolvedCaptureStore
        )
        self.captureStore = resolvedCaptureStore
        self.captureSavePreferences = resolvedSavePreferences
        self.regionCapturePreferences = resolvedRegionCapturePreferences
        self.captureSoundService = captureSoundService ?? CaptureSoundService()
        self.clipboardService = clipboardService ?? ClipboardService()
        self.editorWindowManager = editorWindowManager ?? EditorWindowManager(
            outputService: EditorOutputService(
                captureExportService: resolvedExportService
            )
        )
        self.quickAccessOverlayManager = quickAccessOverlayManager ?? QuickAccessOverlayManager(
            captureExportService: resolvedExportService,
            captureStore: resolvedCaptureStore
        )
        self.regionSelectionManager = regionSelectionManager ?? RegionSelectionManager()
        self.windowSelectionManager = windowSelectionManager ?? WindowSelectionManager()
        self.hotkeyConflictResolutionManager = hotkeyConflictResolutionManager ?? HotkeyConflictResolutionManager()
        self.hotkeySetupWindowManager = hotkeySetupWindowManager ?? HotkeySetupWindowManager()
        self.settingsWindowManager = settingsWindowManager ?? SettingsWindowManager()
        self.menuBarStatusItemManager = menuBarStatusItemManager ?? MenuBarStatusItemManager()
        self.menuBarReadyHintManager = menuBarReadyHintManager ?? MenuBarReadyHintManager()
        self.alertPresenter = alertPresenter ?? AlertPresenter()
        self.isCaptureSoundEnabled = self.captureSoundService.isEnabled
        self.regionMagnifierMode = resolvedRegionCapturePreferences.magnifierMode
        self.captureSaveMode = resolvedSavePreferences.mode
        self.captureSaveFolderPath = resolvedSavePreferences.captureFolderDisplayPath
        self.hasDefaultCaptureFolderAuthorization = resolvedSavePreferences.hasDefaultFolderAuthorization
        self.isTemporaryCaptureCleanupEnabled = resolvedSavePreferences.isTemporaryCaptureCleanupEnabled

        self.menuBarStatusItemManager.configure(viewModel: self)
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

        if !screenCaptureService.hasScreenRecordingPermission() {
            _ = screenCaptureService.requestScreenRecordingPermission()

            guard screenCaptureService.hasScreenRecordingPermission() else {
                handleCaptureError(ScreenCaptureServiceError.permissionDenied)
                return
            }
        }

        isCapturing = true

        Task {
            defer {
                isCapturing = false
            }

            guard let region = await regionSelectionManager.selectRegion(
                magnifierMode: regionMagnifierMode
            ) else {
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

    func setCaptureSoundEnabled(_ isEnabled: Bool) {
        captureSoundService.isEnabled = isEnabled
        isCaptureSoundEnabled = isEnabled
    }

    func setRegionMagnifierMode(_ mode: RegionMagnifierMode) {
        regionCapturePreferences.magnifierMode = mode
        regionMagnifierMode = mode
    }

    func setCaptureSaveMode(_ mode: CaptureSaveMode) {
        switch mode {
        case .askEveryTime:
            captureSavePreferences.mode = .askEveryTime
            refreshCaptureSavePreferences()
        case .fixedFolder:
            if captureSavePreferences.hasFixedFolder {
                captureSavePreferences.mode = .fixedFolder
                refreshCaptureSavePreferences()
            } else {
                chooseCaptureSaveFolder()
            }
        }
    }

    func revealCaptureSaveFolder() {
        if captureSaveMode == .askEveryTime,
           !captureSavePreferences.hasDefaultFolderAuthorization {
            authorizeDefaultCaptureFolder()
            return
        }

        do {
            let folderURL = try captureSavePreferences.withCaptureStorageDestinationAccess { folderURL in
                try FileManager.default.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: true
                )
                return folderURL
            }
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        } catch {
            let localizedError = error as? LocalizedError
            alertPresenter.showError(
                title: localizedError?.errorDescription ?? "Save Folder Unavailable",
                message: localizedError?.recoverySuggestion ?? error.localizedDescription
            )
        }
    }

    func authorizeDefaultCaptureFolder() {
        let panel = NSOpenPanel()
        panel.title = "Grant Screenshot Folder Access"
        panel.message = "Choose Documents, or another parent folder. ClearShotX will create and use a ClearShotX folder inside it."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = captureSavePreferences.defaultCaptureParentFolderURL

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self,
                  response == .OK,
                  let parentFolderURL = panel.url
            else {
                return
            }

            do {
                try self.captureSavePreferences.authorizeDefaultCaptureParentFolder(parentFolderURL)
                let captureFolderURL = try self.captureSavePreferences.withDefaultCaptureFolderAccess { folderURL in
                    try FileManager.default.createDirectory(
                        at: folderURL,
                        withIntermediateDirectories: true
                    )
                    return folderURL
                }
                self.refreshCaptureSavePreferences()
                NSWorkspace.shared.activateFileViewerSelecting([captureFolderURL])
            } catch {
                let localizedError = error as? LocalizedError
                self.alertPresenter.showError(
                    title: localizedError?.errorDescription ?? "Folder Access Failed",
                    message: localizedError?.recoverySuggestion ?? error.localizedDescription
                )
            }
        }
    }

    func setTemporaryCaptureCleanupEnabled(_ isEnabled: Bool) {
        captureSavePreferences.isTemporaryCaptureCleanupEnabled = isEnabled
        isTemporaryCaptureCleanupEnabled = isEnabled

        guard isEnabled else {
            return
        }

        try? captureStore.removeExpiredCaptures()
    }

    func chooseCaptureSaveFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenshot Folder"
        panel.message = "ClearshotX will save screenshots directly to this folder."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = captureSavePreferences.lastSaveDirectoryURL

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self,
                  response == .OK,
                  let folderURL = panel.url
            else {
                return
            }

            do {
                try self.captureSavePreferences.setFixedFolder(folderURL)
                self.refreshCaptureSavePreferences()
            } catch {
                let localizedError = error as? LocalizedError
                self.alertPresenter.showError(
                    title: localizedError?.errorDescription ?? "Save Folder Unavailable",
                    message: localizedError?.recoverySuggestion ?? error.localizedDescription
                )
            }
        }
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
            menuBarStatusItemManager.hide()
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

    private func refreshCaptureSavePreferences() {
        captureSaveMode = captureSavePreferences.mode
        captureSaveFolderPath = captureSavePreferences.captureFolderDisplayPath
        hasDefaultCaptureFolderAuthorization = captureSavePreferences.hasDefaultFolderAuthorization
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
            menuBarStatusItemManager.show()
            break
        case .presentOnboarding:
            menuBarStatusItemManager.hide()
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

                if context == .firstRun {
                    self.menuBarStatusItemManager.show { [weak self] statusItemButton, statusItemFrame in
                        self?.menuBarReadyHintManager.showReadyHint(
                            attachedTo: statusItemButton,
                            pointingTo: statusItemFrame
                        )
                    }
                }
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
        captureSoundService.playCaptureSoundIfEnabled()
        quickAccessOverlayManager.show(
            capture: capture,
            clipboardService: clipboardService,
            editorWindowManager: editorWindowManager
        )
        NotificationCenter.default.post(name: .clearshotXCaptureSucceeded, object: nil)
    }
}
