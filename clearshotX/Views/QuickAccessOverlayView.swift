//
//  QuickAccessOverlayView.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import SwiftUI

struct QuickAccessOverlayView: View {
    let capture: CaptureResult
    let onHoverChanged: (Bool) -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear

            thumbnailCard
                .padding(.leading, 84)
                .padding(.bottom, 132)
        }
        .frame(width: 348, height: 324)
    }

    private var thumbnailCard: some View {
        ZStack {
            thumbnail

            if isHovering {
                controls
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(width: 180, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(isHovering ? 0.24 : 0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 48, x: 0, y: 29)
        .shadow(color: .black.opacity(0.17), radius: 25, x: 0, y: 17)
        .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }

            onHoverChanged(hovering)
        }
    }

    private var thumbnail: some View {
        Image(nsImage: capture.image)
            .resizable()
            .scaledToFill()
            .frame(width: 180, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controls: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.10))
                .background(.regularMaterial.opacity(0.50))

            VStack(spacing: 6) {
                pillButton("Copy", action: onCopy)
                pillButton("Save", action: onSave)
            }

            cornerButton(systemImage: "xmark", title: "Close", action: onClose)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(7)

            cornerButton(systemImage: "pin.fill", title: "Pin", action: onPin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(7)

            cornerButton(systemImage: "pencil", title: "Edit", action: onEdit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(7)

            cornerButton(systemImage: "trash", title: "Delete", role: .destructive, action: onDelete)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(7)
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.86))
                .frame(minWidth: 56, minHeight: 23)
                .padding(.horizontal, 5)
                .background(.white.opacity(0.82), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func cornerButton(
        systemImage: String,
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(role == .destructive ? .red : .black.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.84), in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
