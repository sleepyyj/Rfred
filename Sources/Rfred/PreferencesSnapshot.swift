import AppKit
import RfredCore
import SwiftUI

/// Offscreen Preferences captures used to verify layout. Never starts the
/// launcher, never installs hotkeys, and never reads the user's saved state.
enum PreferencesSnapshot {
    enum Failure: Error, CustomStringConvertible {
        case missingView
        case captureFailed(String)

        var description: String {
            switch self {
            case .missingView: "The snapshot window has no content view."
            case .captureFailed(let name): "Could not capture \(name)."
            }
        }
    }

    @MainActor
    static func render(model: AppModel, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let window = NSWindow(
            contentRect: NSRect(x: -12_000, y: -12_000, width: 1180, height: 766),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = ""
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = NSColor(RfredColor.canvas)
        window.isOpaque = true
        window.isRestorable = false

        let host = NSHostingView(
            rootView: PreferencesShell(model: model)
                .frame(minWidth: 1180, minHeight: 766)
                .frame(width: 1180, height: 766)
        )
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(RfredColor.canvas).cgColor
        window.contentView = host
        window.setContentSize(NSSize(width: 1180, height: 766))
        window.orderBack(nil)
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        model.section = PrefSection(rawValue: PreferencesSidebar.defaultSelection) ?? .general
        try capture(window, to: directory.appendingPathComponent("prefs-general.png"))

        model.section = .update
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        try capture(window, to: directory.appendingPathComponent("prefs-update.png"))

        window.orderOut(nil)
        window.close()
    }

    @MainActor
    private static func capture(_ window: NSWindow, to url: URL) throws {
        // Prefer the theme frame so the titlebar and toolbar are included.
        guard let view = window.contentView?.superview ?? window.contentView else {
            throw Failure.missingView
        }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw Failure.captureFailed(url.lastPathComponent)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(RfredColor.canvas).setFill()
        bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw Failure.captureFailed(url.lastPathComponent)
        }
        try png.write(to: url, options: .atomic)
    }
}
