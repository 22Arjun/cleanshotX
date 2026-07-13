//
//  CaptureExportService.swift
//  clearshotX
//
//  Created by Codex on 13/07/26.
//

import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

enum CaptureSaveMode: String, CaseIterable, Identifiable {
    case askEveryTime
    case fixedFolder

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .askEveryTime:
            "Ask Every Time"
        case .fixedFolder:
            "Custom Folder"
        }
    }
}

enum CaptureSaveOutcome {
    case saved(URL)
    case cancelled
}

enum CaptureExportError: LocalizedError {
    case sourceUnavailable
    case defaultFolderUnavailable
    case fixedFolderUnavailable
    case bookmarkCreationFailed(Error)
    case bookmarkResolutionFailed(Error)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "The screenshot file is no longer available."
        case .defaultFolderUnavailable:
            "ClearShotX could not access its default screenshot folder."
        case .fixedFolderUnavailable:
            "The selected save folder is no longer available."
        case .bookmarkCreationFailed:
            "ClearshotX could not remember the selected save folder."
        case .bookmarkResolutionFailed:
            "ClearshotX could not access the saved destination."
        case .writeFailed:
            "The screenshot could not be saved."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .defaultFolderUnavailable:
            "Open ClearShotX Settings and grant access to the screenshot folder."
        case .fixedFolderUnavailable, .bookmarkCreationFailed, .bookmarkResolutionFailed:
            "Choose the save folder again in ClearshotX Settings."
        case .sourceUnavailable:
            "Take the screenshot again and retry the save."
        case .writeFailed:
            "Check the destination folder and available disk space, then try again."
        }
    }
}

final class CaptureSavePreferences {
    private enum Key {
        static let mode = "captureSaveMode"
        static let defaultFolderBookmark = "captureDefaultFolderBookmark"
        static let defaultFolderDisplayPath = "captureDefaultFolderDisplayPath"
        static let fixedFolderBookmark = "captureSaveFolderBookmark"
        static let fixedFolderDisplayPath = "captureSaveFolderDisplayPath"
        static let lastSaveDirectoryPath = "captureLastSaveDirectoryPath"
        static let temporaryCaptureCleanupEnabled = "temporaryCaptureCleanupEnabled"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var mode: CaptureSaveMode {
        get {
            guard let rawValue = userDefaults.string(forKey: Key.mode),
                  let mode = CaptureSaveMode(rawValue: rawValue)
            else {
                return .askEveryTime
            }

            if mode == .fixedFolder && !hasFixedFolder {
                return .askEveryTime
            }

            return mode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.mode)
        }
    }

    var hasFixedFolder: Bool {
        userDefaults.data(forKey: Key.fixedFolderBookmark) != nil
    }

    var hasDefaultFolderAuthorization: Bool {
        userDefaults.data(forKey: Key.defaultFolderBookmark) != nil
    }

    var fixedFolderDisplayPath: String? {
        userDefaults.string(forKey: Key.fixedFolderDisplayPath)
    }

    var defaultCaptureFolderURL: URL {
        defaultCaptureParentFolderURL
            .appendingPathComponent("ClearShotX", isDirectory: true)
    }

    var defaultCaptureParentFolderURL: URL {
        Self.realUserHomeDirectoryURL
            .appendingPathComponent("Documents", isDirectory: true)
    }

    var captureFolderDisplayPath: String {
        switch mode {
        case .askEveryTime:
            userDefaults.string(forKey: Key.defaultFolderDisplayPath)
                ?? "~/Documents/ClearShotX"
        case .fixedFolder:
            fixedFolderDisplayPath ?? "Choose a folder"
        }
    }

    var lastSaveDirectoryURL: URL? {
        guard let path = userDefaults.string(forKey: Key.lastSaveDirectoryPath) else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    var isTemporaryCaptureCleanupEnabled: Bool {
        get {
            guard userDefaults.object(forKey: Key.temporaryCaptureCleanupEnabled) != nil else {
                return false
            }

            return userDefaults.bool(forKey: Key.temporaryCaptureCleanupEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Key.temporaryCaptureCleanupEnabled)
        }
    }

    func setFixedFolder(_ folderURL: URL) throws {
        do {
            let bookmark = try folderURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            userDefaults.set(bookmark, forKey: Key.fixedFolderBookmark)
            userDefaults.set(abbreviatedPath(for: folderURL), forKey: Key.fixedFolderDisplayPath)
            rememberLastSaveDirectory(folderURL)
            mode = .fixedFolder
        } catch {
            throw CaptureExportError.bookmarkCreationFailed(error)
        }
    }

    func authorizeDefaultCaptureParentFolder(_ folderURL: URL) throws {
        do {
            let bookmark = try folderURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let captureFolderURL = folderURL
                .appendingPathComponent("ClearShotX", isDirectory: true)
            userDefaults.set(bookmark, forKey: Key.defaultFolderBookmark)
            userDefaults.set(
                abbreviatedPath(for: captureFolderURL),
                forKey: Key.defaultFolderDisplayPath
            )
        } catch {
            throw CaptureExportError.bookmarkCreationFailed(error)
        }
    }

    func rememberLastSaveDirectory(_ directoryURL: URL) {
        userDefaults.set(directoryURL.path, forKey: Key.lastSaveDirectoryPath)
    }

    func withFixedFolderAccess<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let bookmark = userDefaults.data(forKey: Key.fixedFolderBookmark) else {
            throw CaptureExportError.fixedFolderUnavailable
        }

        var isStale = false
        let folderURL: URL

        do {
            folderURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw CaptureExportError.bookmarkResolutionFailed(error)
        }

        let didStartAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        if isStale {
            try setFixedFolder(folderURL)
        }

        return try operation(folderURL)
    }

    func withDefaultCaptureFolderAccess<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let bookmark = userDefaults.data(forKey: Key.defaultFolderBookmark) else {
            throw CaptureExportError.defaultFolderUnavailable
        }

        var isStale = false
        let parentFolderURL: URL

        do {
            parentFolderURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw CaptureExportError.bookmarkResolutionFailed(error)
        }

        let didStartAccessing = parentFolderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                parentFolderURL.stopAccessingSecurityScopedResource()
            }
        }

        if isStale {
            try authorizeDefaultCaptureParentFolder(parentFolderURL)
        }

        let captureFolderURL = parentFolderURL
            .appendingPathComponent("ClearShotX", isDirectory: true)
        return try operation(captureFolderURL)
    }

    func withCaptureStorageDestinationAccess<T>(_ operation: (URL) throws -> T) throws -> T {
        switch mode {
        case .askEveryTime:
            if hasDefaultFolderAuthorization {
                return try withDefaultCaptureFolderAccess(operation)
            }
            return try operation(defaultCaptureFolderURL)
        case .fixedFolder:
            return try withFixedFolderAccess(operation)
        }
    }

    private static let realUserHomeDirectoryURL: URL = {
        guard let passwordEntry = getpwuid(getuid()) else {
            return FileManager.default.homeDirectory(forUser: NSUserName())
                ?? FileManager.default.homeDirectoryForCurrentUser
        }

        return URL(
            fileURLWithPath: String(cString: passwordEntry.pointee.pw_dir),
            isDirectory: true
        )
    }()

    private func abbreviatedPath(for folderURL: URL) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard folderURL.path.hasPrefix(homePath) else {
            return folderURL.path
        }

        return "~" + folderURL.path.dropFirst(homePath.count)
    }
}

protocol CaptureExportServicing: AnyObject {
    func saveCapture(
        at sourceURL: URL,
        suggestedFileName: String,
        completion: @escaping (Result<CaptureSaveOutcome, CaptureExportError>) -> Void
    )

    func savePNGData(
        _ pngData: Data,
        suggestedFileName: String,
        completion: @escaping (Result<CaptureSaveOutcome, CaptureExportError>) -> Void
    )
}

final class CaptureExportService: CaptureExportServicing {
    private let preferences: CaptureSavePreferences
    private let fileManager: FileManager

    init(
        preferences: CaptureSavePreferences = CaptureSavePreferences(),
        fileManager: FileManager = .default
    ) {
        self.preferences = preferences
        self.fileManager = fileManager
    }

    func saveCapture(
        at sourceURL: URL,
        suggestedFileName: String,
        completion: @escaping (Result<CaptureSaveOutcome, CaptureExportError>) -> Void
    ) {
        if isAlreadyStoredInFixedFolder(sourceURL) {
            completion(.success(.saved(sourceURL)))
            return
        }

        guard let pngData = try? Data(contentsOf: sourceURL) else {
            completion(.failure(.sourceUnavailable))
            return
        }

        savePNGData(
            pngData,
            suggestedFileName: suggestedFileName,
            completion: completion
        )
    }

    func savePNGData(
        _ pngData: Data,
        suggestedFileName: String,
        completion: @escaping (Result<CaptureSaveOutcome, CaptureExportError>) -> Void
    ) {
        let fileName = normalizedPNGFileName(suggestedFileName)

        switch preferences.mode {
        case .askEveryTime:
            presentSavePanel(
                pngData: pngData,
                suggestedFileName: fileName,
                completion: completion
            )
        case .fixedFolder:
            do {
                let destinationURL = try preferences.withFixedFolderAccess { folderURL in
                    try fileManager.createDirectory(
                        at: folderURL,
                        withIntermediateDirectories: true
                    )
                    let destinationURL = uniqueDestinationURL(
                        in: folderURL,
                        fileName: fileName
                    )
                    try write(pngData, to: destinationURL)
                    return destinationURL
                }
                NSDocumentController.shared.noteNewRecentDocumentURL(destinationURL)
                completion(.success(.saved(destinationURL)))
            } catch let error as CaptureExportError {
                completion(.failure(error))
            } catch {
                completion(.failure(.writeFailed(error)))
            }
        }
    }

    private func presentSavePanel(
        pngData: Data,
        suggestedFileName: String,
        completion: @escaping (Result<CaptureSaveOutcome, CaptureExportError>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName
        panel.directoryURL = preferences.lastSaveDirectoryURL
        panel.prompt = "Save"
        panel.message = "Choose where to save this screenshot."

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else {
                return
            }

            guard response == .OK,
                  let destinationURL = panel.url
            else {
                completion(.success(.cancelled))
                return
            }

            do {
                try self.write(pngData, to: destinationURL)
                self.preferences.rememberLastSaveDirectory(
                    destinationURL.deletingLastPathComponent()
                )
                NSDocumentController.shared.noteNewRecentDocumentURL(destinationURL)
                completion(.success(.saved(destinationURL)))
            } catch {
                completion(.failure(.writeFailed(error)))
            }
        }
    }

    private func isAlreadyStoredInFixedFolder(_ sourceURL: URL) -> Bool {
        guard preferences.mode == .fixedFolder else {
            return false
        }

        return (try? preferences.withFixedFolderAccess { folderURL in
            sourceURL.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL
        }) == true
    }

    private func write(_ data: Data, to destinationURL: URL) throws {
        try data.write(to: destinationURL, options: .atomic)
    }

    private func uniqueDestinationURL(in folderURL: URL, fileName: String) -> URL {
        let sourceURL = URL(fileURLWithPath: fileName)
        let fileExtension = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidateURL = folderURL.appendingPathComponent(fileName)
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            let suffixedName = "\(baseName)-\(suffix)"
            candidateURL = folderURL
                .appendingPathComponent(suffixedName)
                .appendingPathExtension(fileExtension)
            suffix += 1
        }

        return candidateURL
    }

    private func normalizedPNGFileName(_ suggestedFileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        let sanitizedName = suggestedFileName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = URL(fileURLWithPath: sanitizedName)
            .deletingPathExtension()
            .lastPathComponent

        return "\(baseName.isEmpty ? "ClearshotX Screenshot" : baseName).png"
    }
}
