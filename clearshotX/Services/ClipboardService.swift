//
//  ClipboardService.swift
//  clearshotX
//
//  Created by Codex on 03/07/26.
//

import AppKit

final class ClipboardService {
    func copy(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
