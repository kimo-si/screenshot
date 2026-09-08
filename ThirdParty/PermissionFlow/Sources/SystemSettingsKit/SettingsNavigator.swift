#if os(macOS)
import AppKit

@available(macOS 13.0, *)
@MainActor
final class SettingsNavigator {
    private let bundleIdentifier = "com.apple.systempreferences"

    /// Opens System Settings with a generic deeplink URL.
    ///
    /// Menu-bar (`LSUIElement`) hosts are not the frontmost app, so launching
    /// System Settings.app first and then sending the deeplink often drops the
    /// URL. Activate ourselves, open the deeplink directly, and fall back to
    /// `/usr/bin/open` if AppKit refuses the URL.
    @discardableResult
    func openSettings(at url: URL) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        var didOpen = NSWorkspace.shared.open(url)
        if !didOpen {
            didOpen = openWithLaunchServices(url)
        }
        activateSettings()
        return didOpen
    }

    private func openWithLaunchServices(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Re-activates the running System Settings process if it already exists.
    func activateSettings() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .activate(options: [])
    }
}
#elseif os(iOS)
import UIKit

@available(iOS 16.0, *)
@MainActor
final class SettingsNavigator {
    /// Opens the destination URL through UIKit. iOS support is intentionally
    /// limited to URLs that the platform publicly allows.
    @discardableResult
    func openSettings(at url: URL) -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
#endif
