//
//  clearshotXApp.swift
//  clearshotX
//
//  Created by Arjun on 03/07/26.
//

import SwiftUI

@main
struct clearshotXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppShellViewModel()

    var body: some Scene {
        MenuBarExtra("ClearshotX", systemImage: "camera.viewfinder") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)
    }
}
