import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.sync.agent", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        // Prompt for Accessibility permission on first launch
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: kCFBooleanTrue!] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            logger.warning("Accessibility permission not granted — activity simulation will be inactive until granted")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController = nil
    }
}
