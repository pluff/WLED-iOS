import Foundation
import Testing
@testable import WLED

struct WatchSyncTests {
    @Test func devicesRoundTrip() throws {
        let devices = [
            WatchDevice(id: "AA:BB:CC:DD:EE:FF", name: "Desk", address: "192.168.1.10"),
            WatchDevice(id: "11:22:33:44:55:66", name: "TV", address: "wled-tv.local")
        ]
        let data = try #require(WatchSync.encode(devices))
        #expect(WatchSync.decode(data) == devices)
    }

    @Test func invalidDataDecodesToEmpty() {
        #expect(WatchSync.decode(Data("nope".utf8)).isEmpty)
    }

    @Test func nightlightStateDecodes() throws {
        let json = #"{"on":true,"bri":100,"nl":{"on":true,"dur":30,"mode":1,"tbri":0,"rem":1500}}"#
        let state = try JSONDecoder().decode(WledState.self, from: Data(json.utf8))
        #expect(state.nightlight?.isOn == true)
        #expect(state.nightlight?.remainingTime == 1500)
    }
}
