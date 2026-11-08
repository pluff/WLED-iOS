import Foundation
import CoreData
import Combine
import WatchConnectivity

/// Pushes the list of known WLED devices to the paired Apple Watch.
///
/// The watch is a remote control only: it never edits the device list. Whenever the
/// Core Data devices change (added, renamed, new IP...), the list is re-sent through
/// `WCSession.updateApplicationContext`, which always delivers the latest value.
@MainActor
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    private var context: NSManagedObjectContext?
    private var cancellable: AnyCancellable?
    private var lastSentData: Data?

    func start(context: NSManagedObjectContext) {
        guard WCSession.isSupported(), self.context == nil else { return }
        self.context = context

        cancellable = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.pushDevices()
            }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func currentDevices() -> [WatchDevice] {
        guard let context else { return [] }
        let request = Device.fetchRequest()
        guard let devices = try? context.fetch(request) else { return [] }
        return devices
            .compactMap { device -> WatchDevice? in
                guard !device.isHidden,
                      let mac = device.macAddress, mac != AP_MODE_MAC_ADDRESS,
                      let address = device.address, !address.isEmpty
                else { return nil }
                return WatchDevice(id: mac, name: device.displayName, address: address)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func pushDevices() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let data = WatchSync.encode(currentDevices()), data != lastSentData else { return }
        do {
            try session.updateApplicationContext([WatchSync.devicesKey: data])
            lastSentData = data
        } catch {
            print("WatchSyncService: failed to update application context: \(error)")
        }
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.pushDevices()
        }
    }

    /// The watch asks for the list when it launches and missed the application context.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchSync.requestKey] != nil else {
            replyHandler([:])
            return
        }
        // WCSession's reply handler is safe to call from any thread.
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            let data = WatchSync.encode(self.currentDevices()) ?? Data()
            reply([WatchSync.devicesKey: data])
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Happens when switching to another paired watch.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // The watch app may have just been installed: send the list right away.
        Task { @MainActor in
            self.lastSentData = nil
            self.pushDevices()
        }
    }
}
