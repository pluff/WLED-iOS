import AppIntents
import SwiftUI
import WidgetKit

/// Controls shown in the watch's Control Center (side button), acting on the device
/// last opened in the watch app.
@main
struct WLEDControlsBundle: WidgetBundle {
    var body: some Widget {
        PowerControl()
        NightlightControl()
    }
}

// MARK: - Value

enum ControlKind {
    static let power = "ca.cgagnier.wled-native.control.power"
    static let nightlight = "ca.cgagnier.wled-native.control.nightlight"

    /// Both controls read the same device: a change from one (nightlight turns the strip on)
    /// must refresh the other.
    static func reloadAll() {
        ControlCenter.shared.reloadControls(ofKind: power)
        ControlCenter.shared.reloadControls(ofKind: nightlight)
    }
}

struct ControlState: Sendable {
    var deviceName: String?
    var isOn: Bool
}

enum ControlError: LocalizedError {
    case noDevice

    var errorDescription: String? {
        "Open the WLED app on your watch and pick a device first."
    }
}

/// Throws when the device can't be reached, so the system shows the control as unavailable
/// instead of a misleading "Off".
private func currentState(_ keyPath: KeyPath<WledRemote.State, Bool>) async throws -> ControlState {
    guard let device = WatchSharedStore.lastDevice else { return ControlState(deviceName: nil, isOn: false) }
    let remote = WledRemote(device: device)
    let state = try await remote.fetchState()
    // Best effort: showing the state must not fail because the restore did.
    try? await remote.restoreBrightnessIfNightlightEnded(state)
    return ControlState(deviceName: device.name, isOn: state[keyPath: keyPath])
}

// MARK: - Power

struct PowerControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: ControlState { ControlState(deviceName: "WLED", isOn: true) }

        func currentValue() async throws -> ControlState {
            try await currentState(\.on)
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.power, provider: Provider()) { value in
            ControlWidgetToggle(isOn: value.isOn, action: SetPowerIntent()) {
                Label(value.deviceName ?? "WLED", image: "wled-power")
                    .imageScale(.large)
                    .font(.title)
            } valueLabel: { isOn in
                Text(isOn ? "On" : "Off")
            }
        }
        .displayName("Power")
        .description("Turns the last used WLED device on or off.")
    }
}

struct SetPowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set WLED Power"

    @Parameter(title: "On")
    var value: Bool

    func perform() async throws -> some IntentResult {
        guard let device = WatchSharedStore.lastDevice else { throw ControlError.noDevice }
        try await WledRemote(device: device).setPower(value)
        ControlKind.reloadAll()
        return .result()
    }
}

// MARK: - Nightlight

struct NightlightControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: ControlState { ControlState(deviceName: "WLED", isOn: false) }

        func currentValue() async throws -> ControlState {
            try await currentState(\.isNightlightOn)
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.nightlight, provider: Provider()) { value in
            ControlWidgetToggle(isOn: value.isOn, action: SetNightlightIntent()) {
                Label(value.deviceName ?? "WLED", image: "wled-nightlight")
                    .imageScale(.large)
                    .font(.title)
            } valueLabel: { isOn in
                Text(isOn ? "Nightlight on" : "Nightlight off")
            }
        }
        .displayName("Nightlight")
        .description("Starts or stops the nightlight of the last used WLED device.")
    }
}

struct SetNightlightIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set WLED Nightlight"

    @Parameter(title: "On")
    var value: Bool

    func perform() async throws -> some IntentResult {
        guard let device = WatchSharedStore.lastDevice else { throw ControlError.noDevice }
        try await WledRemote(device: device).setNightlight(value)
        ControlKind.reloadAll()
        return .result()
    }
}
