import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.sync.agent", category: "Preferences")

@MainActor
final class PreferencesManager {

    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled     = "isEnabled"
        static let idleThreshold = "idleThreshold"
        static let launchAtLogin = "launchAtLogin"
    }

    private init() {
        defaults.register(defaults: [
            Keys.isEnabled:     false,
            Keys.idleThreshold: 60.0,
            Keys.launchAtLogin: false
        ])
    }

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
