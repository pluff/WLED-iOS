import Foundation

/// Data shared between the watch app and the Control Center controls (separate process),
/// through an App Group.
enum WatchSharedStore {
    static let appGroup = "group.ca.cgagnier.wled-native"

    private static let lastDeviceKey = "lastDevice"
    private static let preNightlightPrefix = "preNightlightBrightness."

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// The device last opened on the watch: the one the controls act on.
    static var lastDevice: WatchDevice? {
        get {
            guard let data = defaults.data(forKey: lastDeviceKey) else { return nil }
            return try? JSONDecoder().decode(WatchDevice.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: lastDeviceKey)
        }
    }

    /// Brightness to bring back when a nightlight started from the controls is stopped.
    static func preNightlightBrightness(for deviceID: String) -> Int? {
        let value = defaults.integer(forKey: preNightlightPrefix + deviceID)
        return value > 0 ? value : nil
    }

    static func setPreNightlightBrightness(_ value: Int?, for deviceID: String) {
        if let value {
            defaults.set(value, forKey: preNightlightPrefix + deviceID)
        } else {
            defaults.removeObject(forKey: preNightlightPrefix + deviceID)
        }
    }
}
