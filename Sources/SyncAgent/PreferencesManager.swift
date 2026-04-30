import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.sync.agent", category: "Preferences")

@MainActor
final class PreferencesManager {

    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled       = "isEnabled"
        static let idleThreshold   = "idleThreshold"
        static let launchAtLogin   = "launchAtLogin"
        static let scheduleEnabled = "scheduleEnabled"
        static let scheduleStart   = "scheduleStartHour"
        static let scheduleEnd     = "scheduleEndHour"
        static let scheduleDays    = "scheduleDays"
    }

    private init() {
        // Mon–Fri = weekdays 2–6 in Calendar convention (1=Sun … 7=Sat)
        defaults.register(defaults: [
            Keys.isEnabled:       false,
            Keys.idleThreshold:   60.0,
            Keys.launchAtLogin:   false,
            Keys.scheduleEnabled: false,
            Keys.scheduleStart:   8,
            Keys.scheduleEnd:     18,
            Keys.scheduleDays:    [2, 3, 4, 5, 6]
        ])
    }

    // MARK: - Existing

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
            logger.info("isEnabled -> \(newValue)")
        }
    }

    var idleThreshold: Double {
        get { defaults.double(forKey: Keys.idleThreshold) }
        set {
            defaults.set(newValue, forKey: Keys.idleThreshold)
            logger.info("idleThreshold -> \(newValue)s")
        }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin(newValue)
        }
    }

    var launchAtLoginRegistered: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    // MARK: - Schedule

    var scheduleEnabled: Bool {
        get { defaults.bool(forKey: Keys.scheduleEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.scheduleEnabled)
            logger.info("scheduleEnabled -> \(newValue)")
        }
    }

    var scheduleStartHour: Int {
        get { defaults.integer(forKey: Keys.scheduleStart) }
        set { defaults.set(newValue, forKey: Keys.scheduleStart) }
    }

    var scheduleEndHour: Int {
        get { defaults.integer(forKey: Keys.scheduleEnd) }
        set { defaults.set(newValue, forKey: Keys.scheduleEnd) }
    }

    // Stored as sorted [Int]; presented as Set<Int> for O(1) lookup
    var scheduleDays: Set<Int> {
        get {
            let arr = defaults.array(forKey: Keys.scheduleDays) as? [Int] ?? [2, 3, 4, 5, 6]
            return Set(arr)
        }
        set {
            defaults.set(Array(newValue).sorted(), forKey: Keys.scheduleDays)
        }
    }

    // MARK: - Schedule check

    func isWithinSchedule() -> Bool {
        let cal     = Calendar.current
        let now     = Date()
        let hour    = cal.component(.hour,    from: now)
        let weekday = cal.component(.weekday, from: now)   // 1=Sun … 7=Sat
        return hour >= scheduleStartHour
            && hour <  scheduleEndHour
            && scheduleDays.contains(weekday)
    }

    // MARK: - Private

    private func applyLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                    logger.info("SMAppService registered")
                } else {
                    try SMAppService.mainApp.unregister()
                    logger.info("SMAppService unregistered")
                }
            } catch {
                logger.error("SMAppService error: \(error.localizedDescription)")
            }
        }
    }
}
