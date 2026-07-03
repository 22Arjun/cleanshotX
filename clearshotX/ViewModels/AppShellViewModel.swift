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

    private let screenCaptureService: ScreenCaptureService
    private let clipboardService: ClipboardService
    private let previewWindowManager: PreviewWindowManager
    private let regionSelectionManager: RegionSelectionManager
    private let windowSelectionManager: WindowSelectionManager
    private let alertPresenter: AlertPresenter

    init(
        screenCaptureService: ScreenCaptureService? = nil,
        clipboardService: ClipboardService? = nil,
        previewWindowManager: PreviewWindowManager? = nil,
        regionSelectionManager: RegionSelectionManager? = nil,
        windowSelectionManager: WindowSelectionManager? = nil,
        alertPresenter: AlertPresenter? = nil
    ) {
        self.screenCaptureService = screenCaptureService ?? ScreenCaptureService()
        self.clipboardService = clipboardService ?? ClipboardService()
        self.previewWindowManager = previewWindowManager ?? PreviewWindowManager()
        self.regionSelectionManager = regionSelectionManager ?? RegionSelectionManager()
        self.windowSelectionManager = windowSelectionManager ?? WindowSelectionManager()
        self.alertPresenter = alertPresenter ?? AlertPresenter()
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
                previewWindowManager.showPreview(for: capture, clipboardService: clipboardService)
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
                previewWindowManager.showPreview(for: capture, clipboardService: clipboardService)
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
                previewWindowManager.showPreview(for: capture, clipboardService: clipboardService)
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
}
