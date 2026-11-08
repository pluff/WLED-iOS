import Foundation

/// Minimal description of a WLED device, sent from the iPhone to the Apple Watch.
///
/// Device configuration (names, discovery, firmware updates...) stays on the iPhone.
/// The watch only receives what it needs to reach a device and control it.
struct WatchDevice: Codable, Identifiable, Hashable, Sendable {
    /// MAC address, stable across IP changes.
    let id: String
    let name: String
    let address: String
}

enum WatchSync {
    /// Key of the `applicationContext` entry holding the JSON encoded `[WatchDevice]`.
    static let devicesKey = "devices"
    /// Key of the message the watch sends to ask the iPhone for the device list.
    static let requestKey = "requestDevices"

    static func encode(_ devices: [WatchDevice]) -> Data? {
        try? JSONEncoder().encode(devices)
    }

    static func decode(_ data: Data) -> [WatchDevice] {
        (try? JSONDecoder().decode([WatchDevice].self, from: data)) ?? []
    }
}
