//
//  RegionCapturePreferences.swift
//  clearshotX
//
//  Created by Codex on 17/07/26.
//

import Foundation

enum RegionMagnifierMode: String, CaseIterable, Identifiable {
    case automatic = "auto"
    case always
    case off

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .automatic:
            "Auto"
        case .always:
            "Always"
        case .off:
            "Off"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            "Show while positioning the starting point, then hide while dragging."
        case .always:
            "Keep the pixel magnifier visible throughout region selection."
        case .off:
            "Hide the pixel magnifier for a cleaner selection view."
        }
    }
}

final class RegionCapturePreferences {
    private enum UserDefaultsKey {
        static let magnifierMode = "RegionCaptureMagnifierMode"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            UserDefaultsKey.magnifierMode: RegionMagnifierMode.automatic.rawValue
        ])
    }

    var magnifierMode: RegionMagnifierMode {
        get {
            guard let rawValue = userDefaults.string(forKey: UserDefaultsKey.magnifierMode),
                  let mode = RegionMagnifierMode(rawValue: rawValue)
            else {
                return .automatic
            }

            return mode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: UserDefaultsKey.magnifierMode)
        }
    }
}
