import AppKit

MainActor.assumeIsolated {
    // Carry command-line settings forward after renaming the executable.
    let defaults = UserDefaults.standard
    if !defaults.bool(forKey: "picPocketMigrated") {
        let legacy = defaults.persistentDomain(forName: "Tendedero")
            ?? defaults.persistentDomain(forName: "app.tendedero.Tendedero") ?? [:]
        for key in ["pegged", "soundOff", "inboxEnabled", "inboxOffered", "inboxSavedSettings", "welcomed"] {
            if defaults.object(forKey: key) == nil, let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "picPocketMigrated")
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
