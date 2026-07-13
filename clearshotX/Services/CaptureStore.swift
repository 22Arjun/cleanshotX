//
//  CaptureStore.swift
//  clearshotX
//
//  Created by Codex on 13/07/26.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

protocol CaptureStoring: AnyObject {
    func store(_ image: CGImage) throws -> StoredCapture
    func removeCapture(at url: URL, dragFileURL: URL?) throws
    func removeExpiredCaptures() throws
}

struct StoredCapture {
    let fileURL: URL
    let dragFileURL: URL
}

enum CaptureStoreError: LocalizedError {
    case cachesDirectoryUnavailable
    case destinationCreationFailed
    case imageEncodingFailed
    case destinationAccessDenied

    var errorDescription: String? {
        switch self {
        case .cachesDirectoryUnavailable:
            "ClearshotX could not locate its temporary capture directory."
        case .destinationCreationFailed:
            "ClearshotX could not create a temporary screenshot file."
        case .imageEncodingFailed:
            "ClearshotX could not encode the screenshot as a PNG."
        case .destinationAccessDenied:
            "ClearShotX does not have permission to save screenshots in this folder."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .destinationAccessDenied:
            "Open ClearShotX Settings, choose Grant Screenshot Folder Access, and select Documents."
        default:
            "Check that there is available disk space, then try capturing again."
        }
    }
}

final class CaptureStore: CaptureStoring {
    private let fileManager: FileManager
    private let preferences: CaptureSavePreferences
    private let retentionInterval: TimeInterval
    private let isCleanupEnabled: () -> Bool
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        preferences: CaptureSavePreferences = CaptureSavePreferences(),
        retentionInterval: TimeInterval = 24 * 60 * 60,
        isCleanupEnabled: @escaping () -> Bool = { false },
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.preferences = preferences
        self.retentionInterval = retentionInterval
        self.isCleanupEnabled = isCleanupEnabled
        self.now = now
        try? removeExpiredCaptures()
    }

    func store(_ image: CGImage) throws -> StoredCapture {
        try? removeExpiredCaptures()

        do {
            return try preferences.withCaptureStorageDestinationAccess { directoryURL in
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )

                let fileURL = uniqueCaptureURL(in: directoryURL)
                let stagingURL = directoryURL
                    .appendingPathComponent(".\(UUID().uuidString)")
                    .appendingPathExtension("tmp")

                defer {
                    try? fileManager.removeItem(at: stagingURL)
                }

                guard let destination = CGImageDestinationCreateWithURL(
                    stagingURL as CFURL,
                    UTType.png.identifier as CFString,
                    1,
                    nil
                ) else {
                    throw CaptureStoreError.destinationCreationFailed
                }

                CGImageDestinationAddImage(destination, image, nil)

                guard CGImageDestinationFinalize(destination) else {
                    throw CaptureStoreError.imageEncodingFailed
                }

                try fileManager.moveItem(at: stagingURL, to: fileURL)
                let dragFileURL = try makeDragFile(for: fileURL, image: image)
                NSDocumentController.shared.noteNewRecentDocumentURL(fileURL)
                return StoredCapture(fileURL: fileURL, dragFileURL: dragFileURL)
            }
        } catch let error as CaptureStoreError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
                throw CaptureStoreError.destinationAccessDenied
            }

            if nsError.domain == NSPOSIXErrorDomain,
               nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
                throw CaptureStoreError.destinationAccessDenied
            }

            throw error
        }
    }

    func removeCapture(at url: URL, dragFileURL: URL? = nil) throws {
        try removeStoredCapture(at: url)

        guard let dragFileURL,
              dragFileURL.standardizedFileURL != url.standardizedFileURL
        else {
            return
        }

        try removeFile(at: dragFileURL)
        try? fileManager.removeItem(at: dragFileURL.deletingLastPathComponent())
    }

    private func removeStoredCapture(at url: URL) throws {
        let removedFromCurrentCaptureFolder = (try? preferences.withCaptureStorageDestinationAccess { directoryURL in
            guard url.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL else {
                return false
            }

            try removeFile(at: url)
            return true
        }) ?? false

        guard !removedFromCurrentCaptureFolder else {
            return
        }

        try removeFile(at: url)
    }

    private func removeFile(at url: URL) throws {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    func removeExpiredCaptures() throws {
        guard isCleanupEnabled() else {
            return
        }

        let directoryURL = try captureDirectoryURL()
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let expirationDate = now().addingTimeInterval(-retentionInterval)
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsSubdirectoryDescendants]
        )

        for fileURL in contents {
            let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true,
                  let modificationDate = values?.contentModificationDate,
                  modificationDate < expirationDate
            else {
                continue
            }

            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func captureDirectoryURL() throws -> URL {
        guard let cachesURL = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw CaptureStoreError.cachesDirectoryUnavailable
        }

        return cachesURL
            .appendingPathComponent("ClearShotX", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    private func makeDragFile(for sourceURL: URL, image: CGImage) throws -> URL {
        let exportsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ClearShotX-DragExports", isDirectory: true)
        removeExpiredDragDirectories(in: exportsDirectory)

        let directoryURL = exportsDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dragFileURL = directoryURL
            .appendingPathComponent(sourceURL.lastPathComponent)

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            do {
                try fileManager.linkItem(at: sourceURL, to: dragFileURL)
            } catch {
                do {
                    try fileManager.copyItem(at: sourceURL, to: dragFileURL)
                } catch {
                    guard let destination = CGImageDestinationCreateWithURL(
                        dragFileURL as CFURL,
                        UTType.png.identifier as CFString,
                        1,
                        nil
                    ) else {
                        throw CaptureStoreError.destinationCreationFailed
                    }

                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else {
                        throw CaptureStoreError.imageEncodingFailed
                    }
                }
            }

            return dragFileURL
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }

    private func removeExpiredDragDirectories(in exportsDirectory: URL) {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let expirationDate = now().addingTimeInterval(-24 * 60 * 60)
        for directory in directories {
            guard let values = try? directory.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey]
            ),
            values.isDirectory == true,
            let modificationDate = values.contentModificationDate,
            modificationDate < expirationDate
            else {
                continue
            }

            try? fileManager.removeItem(at: directory)
        }
    }

    private func uniqueCaptureURL(in directoryURL: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let baseName = "ClearshotX \(formatter.string(from: now()))"

        var candidateURL = directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension("png")
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = directoryURL
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension("png")
            suffix += 1
        }

        return candidateURL
    }
}
