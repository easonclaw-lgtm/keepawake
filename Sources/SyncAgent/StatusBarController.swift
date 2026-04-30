import AppKit
import os

private let logger = Logger(subsystem: "com.sync.agent", category: "StatusBar")

@MainActor
final class StatusBarController {

    private let statusItem: NSStatusItem
    private let simulator: ActivitySimulator

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        simulator = ActivitySimulator()
        simulator.start()
        configureButton()
        buildMenu()
    }

    deinit {
        let sim = simulator
        Task { @MainActor in sim.stop() }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        updateIcon()
        button.toolTip = "SyncAgent"
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let isOn = PreferencesManager.shared.isEnabled
        let symbolName = isOn ? "sun.max.fill" : "moon.zzz.fill"
        let img = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isOn ? "SyncAgent On" : "SyncAgent Off"
        )
        img?.isTemplate = true
        button.image = img
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let prefs = PreferencesManager.shared

        let toggleTitle = prefs.isEnabled ? "SyncAgent: ON" : "SyncAgent: OFF"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.state = prefs.isEnabled ? .on : .off
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let header = NSMenuItem(title: "Idle Trigger:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let thresholds: [(title: String, seconds: Double)] = [
            ("1 minute",  60.0),
            ("2 minutes", 120.0),
            ("5 minutes", 300.0)
        ]
        for entry in thresholds {
            let item = NSMenuItem(title: entry.title, action: #selector(setThreshold(_:)), keyEquivalent: "")
            item.tag = Int(entry.seconds)
            item.state = (prefs.idleThreshold == entry.seconds) ? .on : .off
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = prefs.launchAtLoginRegistered ? .on : .off
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        PreferencesManager.shared.isEnabled.toggle()
        updateIcon()
        buildMenu()
        logger.info("Toggled enabled: \(PreferencesManager.shared.isEnabled)")
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        let seconds = Double(sender.tag)
        PreferencesManager.shared.idleThreshold = seconds
        buildMenu()
        logger.info("Threshold set to \(seconds)s")
    }

    @objc private func toggleLaunchAtLogin() {
        PreferencesManager.shared.launchAtLogin.toggle()
        buildMenu()
    }
}
