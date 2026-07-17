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

enum RegionMagnifierZoom: Int, CaseIterable, Identifiable {
    case four = 4
    case eight = 8
    case twelve = 12

    var id: Int {
        rawValue
    }

    var title: String {
        "\(rawValue)×"
    }
}

enum RegionMagnifierSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .small:
            "Small"
        case .medium:
            "Medium"
        case .large:
            "Large"
        }
    }

    var dimensions: CGSize {
        switch self {
        case .small:
            CGSize(width: 104, height: 78)
        case .medium:
            CGSize(width: 128, height: 96)
        case .large:
            CGSize(width: 156, height: 117)
        }
    }
}

final class RegionCapturePreferences {
    private enum UserDefaultsKey {
        static let magnifierMode = "RegionCaptureMagnifierMode"
        static let magnifierZoom = "RegionCaptureMagnifierZoom"
        static let magnifierSize = "RegionCaptureMagnifierSize"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            UserDefaultsKey.magnifierMode: RegionMagnifierMode.automatic.rawValue,
            UserDefaultsKey.magnifierZoom: RegionMagnifierZoom.eight.rawValue,
            UserDefaultsKey.magnifierSize: RegionMagnifierSize.medium.rawValue
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

    var magnifierZoom: RegionMagnifierZoom {
        get {
            RegionMagnifierZoom(
                rawValue: userDefaults.integer(forKey: UserDefaultsKey.magnifierZoom)
            ) ?? .eight
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: UserDefaultsKey.magnifierZoom)
        }
    }

    var magnifierSize: RegionMagnifierSize {
        get {
            guard let rawValue = userDefaults.string(forKey: UserDefaultsKey.magnifierSize),
                  let size = RegionMagnifierSize(rawValue: rawValue)
            else {
                return .medium
            }

            return size
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: UserDefaultsKey.magnifierSize)
        }
    }
}
