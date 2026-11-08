import Foundation
import WatchConnectivity

/// Holds the list of devices received from the iPhone.
///
/// The list is cached in `UserDefaults` so devices are available right at launch,
/// even when the iPhone is out of reach.
@MainActor
final class WatchDeviceStore: NSObject, ObservableObject {
    @Published private(set) var devices: [WatchDevice] = []

    private static let cacheKey = "cachedDevices"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            devices = WatchSync.decode(data)
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context[WatchSync.devicesKey] as? Data else { return }
        devices = WatchSync.decode(data)
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

extension WatchDeviceStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Pick up whatever the iPhone sent while the app was not running.
        let context = session.receivedApplicationContext
        if let data = context[WatchSync.devicesKey] as? Data {
            Task { @MainActor in
                self.apply([WatchSync.devicesKey: data])
            }
        }
        // Also ask the iPhone directly, in case no context was ever delivered.
        requestDevices(session)
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { requestDevices(session) }
    }

    private nonisolated func requestDevices(_ session: WCSession) {
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchSync.requestKey: true]) { reply in
            guard let data = reply[WatchSync.devicesKey] as? Data, !data.isEmpty else { return }
            Task { @MainActor in
                self.apply([WatchSync.devicesKey: data])
            }
        } errorHandler: { error in
            print("WatchDeviceStore: request failed: \(error)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchSync.devicesKey] as? Data else { return }
        Task { @MainActor in
            self.apply([WatchSync.devicesKey: data])
        }
    }
}
