//
//  MenuBarContentView.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: AppShellViewModel

    var body: some View {
        Button {
            viewModel.captureFullScreen()
        } label: {
            Label(
                viewModel.isCapturing ? "Capturing..." : "Capture Full Screen",
                systemImage: "rectangle.inset.filled"
            )
        }
        .disabled(viewModel.isCapturing)

        Divider()

        Button {
            viewModel.captureRegion()
        } label: {
            Label("Capture Region", systemImage: "selection.pin.in.out")
        }
        .disabled(viewModel.isCapturing)

        Button {
            viewModel.captureWindow()
        } label: {
            Label("Capture Window", systemImage: "macwindow")
        }
        .disabled(viewModel.isCapturing)

        Divider()

        Button {
            viewModel.openScreenRecordingSettings()
        } label: {
            Label("Screen Recording Permission", systemImage: "lock.shield")
        }

        Button {
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .disabled(true)

        Divider()

        Button {
            viewModel.quit()
        } label: {
            Label("Quit ClearshotX", systemImage: "power")
        }
    }
}
