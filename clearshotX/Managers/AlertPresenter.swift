//
//  AlertPresenter.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit

final class AlertPresenter {
    func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func showScreenRecordingPermissionAlert(openSettings: () -> Void, quit: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording Permission Needed"
        alert.informativeText = "ClearshotX does not have active Screen Recording permission yet. If you already enabled it in System Settings, quit and reopen ClearshotX so macOS applies the change."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit ClearshotX")
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSettings()
        case .alertSecondButtonReturn:
            quit()
        default:
            break
        }
    }
}
