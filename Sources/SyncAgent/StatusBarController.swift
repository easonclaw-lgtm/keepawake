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

    // MARK: - Menu

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let prefs = PreferencesManager.shared

        // ── Main toggle ──────────────────────────────────────────
        let toggleItem = NSMenuItem(
            title: prefs.isEnabled ? "SyncAgent: ON" : "SyncAgent: OFF",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.state = prefs.isEnabled ? .on : .off
        toggleItem.target = self
        menu.addItem(toggleItem)

        // ── Simulation options ───────────────────────────────────
        menu.addItem(.separator())

        let mouseItem = NSMenuItem(title: "Mouse Movement", action: #selector(toggleMouseMovement), keyEquivalent: "")
        mouseItem.state  = prefs.mouseMovementEnabled ? .on : .off
        mouseItem.target = self
        menu.addItem(mouseItem)

        let switchItem = NSMenuItem(title: "Window Switch", action: #selector(toggleWindowSwitch), keyEquivalent: "")
        switchItem.state  = prefs.windowSwitchEnabled ? .on : .off
        switchItem.target = self
        menu.addItem(switchItem)

        // ── Idle Trigger ─────────────────────────────────────────
        menu.addItem(.separator())
        let thresholdHeader = NSMenuItem(title: "Idle Trigger:", action: nil, keyEquivalent: "")
        thresholdHeader.isEnabled = false
        menu.addItem(thresholdHeader)

        for (title, secs) in [("1 minute", 60.0), ("2 minutes", 120.0), ("5 minutes", 300.0)] {
            let item = NSMenuItem(title: title, action: #selector(setThreshold(_:)), keyEquivalent: "")
            item.tag    = Int(secs)
            item.state  = prefs.idleThreshold == secs ? .on : .off
            item.target = self
            menu.addItem(item)
        }

        // ── Schedule ─────────────────────────────────────────────
        menu.addItem(.separator())

        let schedToggle = NSMenuItem(
            title: "Schedule",
            action: #selector(toggleSchedule),
            keyEquivalent: ""
        )
        schedToggle.state  = prefs.scheduleEnabled ? .on : .off
        schedToggle.target = self
        menu.addItem(schedToggle)

        // Hours submenu
        let hoursItem = NSMenuItem(
            title: "Hours: \(hourRangeLabel(prefs.scheduleStartHour, prefs.scheduleEndHour))",
            action: nil,
            keyEquivalent: ""
        )
        hoursItem.isEnabled = prefs.scheduleEnabled
        hoursItem.submenu   = buildHoursSubmenu(prefs: prefs)
        menu.addItem(hoursItem)

        // Days submenu
        let daysItem = NSMenuItem(
            title: "Days: \(daysLabel(prefs.scheduleDays))",
            action: nil,
            keyEquivalent: ""
        )
        daysItem.isEnabled = prefs.scheduleEnabled
        daysItem.submenu   = buildDaysSubmenu(prefs: prefs)
        menu.addItem(daysItem)

        // ── System ───────────────────────────────────────────────
        menu.addItem(.separator())
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.state  = prefs.launchAtLoginRegistered ? .on : .off
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Hours submenu

    private func buildHoursSubmenu(prefs: PreferencesManager) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        // Tag encodes start * 100 + end
        let ranges: [(String, Int, Int)] = [
            ("8am – 6pm",  8, 18),
            ("9am – 5pm",  9, 17),
            ("7am – 7pm",  7, 19),
            ("6am – 8pm",  6, 20),
        ]
        for (title, start, end) in ranges {
            let item = NSMenuItem(title: title, action: #selector(setHourRange(_:)), keyEquivalent: "")
            item.tag    = start * 100 + end
            item.state  = (prefs.scheduleStartHour == start && prefs.scheduleEndHour == end) ? .on : .off
            item.target = self
            sub.addItem(item)
        }
        return sub
    }

    // MARK: - Days submenu

    private func buildDaysSubmenu(prefs: PreferencesManager) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        let workdays: Set<Int> = [2, 3, 4, 5, 6]
        let everyday: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

        let workdaysItem = NSMenuItem(title: "Workdays  (Mon – Fri)", action: #selector(setDayPreset(_:)), keyEquivalent: "")
        workdaysItem.tag    = 10
        workdaysItem.state  = prefs.scheduleDays == workdays ? .on : .off
        workdaysItem.target = self
        sub.addItem(workdaysItem)

        let everydayItem = NSMenuItem(title: "Every Day", action: #selector(setDayPreset(_:)), keyEquivalent: "")
        everydayItem.tag    = 11
        everydayItem.state  = prefs.scheduleDays == everyday ? .on : .off
        everydayItem.target = self
        sub.addItem(everydayItem)

        sub.addItem(.separator())

        // Individual days — Calendar weekday: 1=Sun, 2=Mon … 7=Sat
        let days: [(Int, String)] = [
            (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"),
            (5, "Thursday"), (6, "Friday"), (7, "Saturday"), (1, "Sunday")
        ]
        for (weekday, name) in days {
            let item = NSMenuItem(title: name, action: #selector(toggleDay(_:)), keyEquivalent: "")
            item.tag    = weekday
            item.state  = prefs.scheduleDays.contains(weekday) ? .on : .off
            item.target = self
            sub.addItem(item)
        }
        return sub
    }

    // MARK: - Label helpers

    private func hourLabel(_ h: Int) -> String {
        switch h {
        case 0:  return "12am"
        case 12: return "12pm"
        default: return h < 12 ? "\(h)am" : "\(h - 12)pm"
        }
    }

    private func hourRangeLabel(_ start: Int, _ end: Int) -> String {
        "\(hourLabel(start)) – \(hourLabel(end))"
    }

    private func daysLabel(_ days: Set<Int>) -> String {
        switch days {
        case [2, 3, 4, 5, 6]:          return "Workdays"
        case [1, 2, 3, 4, 5, 6, 7]:    return "Every Day"
        default:
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return [2,3,4,5,6,7,1]
                .filter { days.contains($0) }
                .map    { names[$0 - 1] }
                .joined(separator: ", ")
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        PreferencesManager.shared.isEnabled.toggle()
        updateIcon()
        buildMenu()
        logger.info("Toggled enabled: \(PreferencesManager.shared.isEnabled)")
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        PreferencesManager.shared.idleThreshold = Double(sender.tag)
        buildMenu()
    }

    @objc private func toggleMouseMovement() {
        PreferencesManager.shared.mouseMovementEnabled.toggle()
        buildMenu()
    }

    @objc private func toggleWindowSwitch() {
        PreferencesManager.shared.windowSwitchEnabled.toggle()
        buildMenu()
    }

    @objc private func toggleSchedule() {
        PreferencesManager.shared.scheduleEnabled.toggle()
        buildMenu()
        logger.info("scheduleEnabled -> \(PreferencesManager.shared.scheduleEnabled)")
    }

    @objc private func setHourRange(_ sender: NSMenuItem) {
        let prefs = PreferencesManager.shared
        prefs.scheduleStartHour = sender.tag / 100
        prefs.scheduleEndHour   = sender.tag % 100
        buildMenu()
    }

    @objc private func setDayPreset(_ sender: NSMenuItem) {
        PreferencesManager.shared.scheduleDays = sender.tag == 10
            ? [2, 3, 4, 5, 6]
            : [1, 2, 3, 4, 5, 6, 7]
        buildMenu()
    }

    @objc private func toggleDay(_ sender: NSMenuItem) {
        let prefs = PreferencesManager.shared
        var days = prefs.scheduleDays
        if days.contains(sender.tag) {
            days.remove(sender.tag)
        } else {
            days.insert(sender.tag)
        }
        prefs.scheduleDays = days
        buildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        PreferencesManager.shared.launchAtLogin.toggle()
        buildMenu()
    }
}
