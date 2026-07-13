//
//  AppDelegate.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let existingApplication = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
        else {
            return
        }

        existingApplication.activate()
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
