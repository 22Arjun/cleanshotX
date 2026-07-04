//
//  CaptureSoundService.swift
//  clearshotX
//
//  Created by Codex on 04/07/26.
//

import AppKit
import Foundation
import OSLog

@MainActor
final class CaptureSoundService {
    private enum UserDefaultsKey {
        static let captureSoundEnabled = "CaptureSoundEnabled"
    }

    private static let systemScreenshotSoundURL = URL(
        fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
    )

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "clearshotX",
        category: "CaptureSound"
    )
    private let userDefaults: UserDefaults
    private var activeSound: NSSound?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        registerDefaults()
    }

    var isEnabled: Bool {
        get {
            userDefaults.bool(forKey: UserDefaultsKey.captureSoundEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKey.captureSoundEnabled)
            logger.info("Capture sound enabled changed to \(newValue, privacy: .public)")
        }
    }

    func playCaptureSoundIfEnabled() {
        guard isEnabled else {
            return
        }

        guard playSound(at: Self.systemScreenshotSoundURL) ?? playSound(named: "Glass") ?? playSound(named: "Pop") ?? false else {
            logger.warning("No capture sound could be played")
            return
        }

        logger.info("Capture sound played")
    }

    private func registerDefaults() {
        userDefaults.register(defaults: [
            UserDefaultsKey.captureSoundEnabled: true
        ])
    }

    private func playSound(at url: URL) -> Bool? {
        guard FileManager.default.fileExists(atPath: url.path),
              let sound = NSSound(contentsOf: url, byReference: true)
        else {
            return nil
        }

        activeSound = sound
        sound.stop()
        return sound.play()
    }

    private func playSound(named soundName: String) -> Bool? {
        guard let sound = NSSound(named: NSSound.Name(soundName)) else {
            return nil
        }

        activeSound = sound
        sound.stop()
        return sound.play()
    }
}
