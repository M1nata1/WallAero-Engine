import CEFHost
import Foundation
@testable import WallAeroApp

// Scripts run as they are in a page, by the helpers and tests alone: the app tells pages only
// what PlayerBridge.swift has for them.
extension WebWallpaperView {
    /// Runs a script in the page, once it is there.
    func evaluate(_ script: String) {
        guard hasLoaded else { return }
        webView?.executeScript(script)
    }

    /// What a script evaluates to in the page; nil if it fails or the page is not there.
    func value(of script: String) async -> Any? {
        guard hasLoaded, let webView else { return nil }
        let json: String? = await withCheckedContinuation { continuation in
            webView.evaluateScript(script) { continuation.resume(returning: $0) }
        }
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
