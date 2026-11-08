import SwiftUI

@main
struct WLEDWatchApp: App {
    @StateObject private var store = WatchDeviceStore()

    var body: some Scene {
        WindowGroup {
            DeviceListWatchView()
                .environmentObject(store)
        }
    }
}
