//
//  CapturePreviewView.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import SwiftUI

struct CapturePreviewView: View {
    let capture: CaptureResult
    let onCopy: () -> Void
    let onRevealInFinder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            header
            imagePreview
            footer
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 380)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot Captured")
                    .font(.headline)

                Text("\(capture.pixelWidth) x \(capture.pixelHeight) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var imagePreview: some View {
        Image(nsImage: capture.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.fileURL.lastPathComponent)
                    .font(.caption.weight(.medium))

                Text(capture.fileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                onRevealInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }

            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
