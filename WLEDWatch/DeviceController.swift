import Foundation
import SwiftUI

/// Talks to one WLED device over its HTTP JSON API (`/json/state`).
///
/// While the control screen is visible the state is polled every couple of seconds.
/// Local changes are applied optimistically and sent right away; polled values for the
/// same field are ignored for a short while so the UI doesn't jump back.
@MainActor
final class DeviceController: ObservableObject {
    enum Connection {
        case connecting, online, offline
    }

    /// 0 means the strip is off (WLED treats `bri: 0` as off).
    static let minBrightness: Double = 0
    static let maxBrightness: Double = 255

    let device: WatchDevice

    @Published private(set) var connection: Connection = .connecting
    @Published private(set) var isOn = false
    @Published private(set) var isNightlightOn = false
    /// When the active nightlight finishes. `nil` if inactive or unknown.
    @Published private(set) var nightlightEnd: Date?
    /// Shown brightness. While on: the device's current brightness. While off: the brightness
    /// it will have once turned on. The brightness control can drag it to 0, which turns the strip off.
    @Published var brightness: Double = 128 {
        didSet {
            guard brightness != oldValue, !isApplyingRemoteState else { return }
            brightnessDidChangeLocally()
        }
    }

    private var isApplyingRemoteState = false
    /// Last non-zero brightness known, restored when the strip is turned back on.
    private var lastBrightness: Double = 128
    /// Brightness to bring back when the nightlight ends. The nightlight fades the device's
    /// `bri` down, which must not overwrite the brightness the user picked.
    private var preNightlightBrightness: Double?
    private var pollTask: Task<Void, Never>?
    private var brightnessSendTask: Task<Void, Never>?
    private var ignoreRemoteUntil: [Field: Date] = [:]

    private enum Field { case power, brightness, nightlight }

    private let pollInterval: Duration = .seconds(2)
    private let localChangeGrace: TimeInterval = 2
    private let session: URLSession

    init(device: WatchDevice) {
        self.device = device
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Lifecycle

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        brightnessSendTask?.cancel()
        brightnessSendTask = nil
    }

    // MARK: - Commands

    func setPower(_ on: Bool) {
        isOn = on
        markLocalChange(.power)
        send(["on": on])
    }

    func setNightlight(_ on: Bool) {
        let wasOn = isNightlightOn
        isNightlightOn = on
        if !on { nightlightEnd = nil }
        markLocalChange(.nightlight)
        if on, !wasOn { preNightlightBrightness = lastBrightness }
        // Nightlight only makes sense with the strip on. Duration and mode are the ones
        // configured on the device (set up from the iPhone / WLED settings).
        var payload: [String: Any] = ["nl": ["on": on]]
        if on {
            isOn = true
            if brightness == 0 { showBrightnessWithoutSending(lastBrightness) }
            payload["on"] = true
        } else if wasOn, let saved = preNightlightBrightness {
            // Stopping the nightlight leaves the device at its faded brightness: put it back.
            preNightlightBrightness = nil
            lastBrightness = saved
            if isOn { showBrightnessWithoutSending(saved) }
            payload["bri"] = Int(saved.rounded())
            markLocalChange(.brightness)
        }
        send(payload)
    }

    private func brightnessDidChangeLocally() {
        markLocalChange(.brightness)
        markLocalChange(.power)
        let value = Int(brightness.rounded())
        isOn = value > 0
        if value > 0 {
            lastBrightness = brightness
            // Changed by hand during a nightlight: that's the value to restore afterwards.
            if preNightlightBrightness != nil { preNightlightBrightness = brightness }
        }
        brightnessSendTask?.cancel()
        brightnessSendTask = Task { [weak self] in
            // Debounce: the crown produces many values per second.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            // 0 = off. Don't send `bri: 0`, so the device keeps its brightness for next power on.
            self?.send(value == 0 ? ["on": false] : ["bri": value, "on": true])
        }
    }

    private func showBrightnessWithoutSending(_ value: Double) {
        isApplyingRemoteState = true
        brightness = value
        isApplyingRemoteState = false
    }

    // MARK: - Networking

    private func url() -> URL? {
        URL(string: "http://\(device.address)/json/state")
    }

    private func refresh() async {
        guard let url = url() else { return }
        do {
            let (data, _) = try await session.data(from: url)
            apply(try JSONDecoder().decode(WledState.self, from: data))
        } catch {
            if !Task.isCancelled { connection = .offline }
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let url = url() else { return }
        var body = payload
        body["v"] = true // ask the device to answer with its full new state
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let session = session
        Task { [weak self] in
            do {
                let (responseData, _) = try await session.data(for: request)
                if let state = try? JSONDecoder().decode(WledState.self, from: responseData) {
                    self?.apply(state)
                } else {
                    self?.connection = .online
                }
            } catch {
                if !Task.isCancelled { self?.connection = .offline }
            }
        }
    }

    // MARK: - State

    private func markLocalChange(_ field: Field) {
        ignoreRemoteUntil[field] = Date().addingTimeInterval(localChangeGrace)
    }

    private func shouldApplyRemote(_ field: Field) -> Bool {
        guard let until = ignoreRemoteUntil[field] else { return true }
        return Date() >= until
    }

    private func apply(_ state: WledState) {
        connection = .online
        isApplyingRemoteState = true
        defer { isApplyingRemoteState = false }

        let applyPower = shouldApplyRemote(.power)
        let nightlightNow = state.nightlight?.isOn ?? false
        let nightlightWasOn = isNightlightOn
        if applyPower, let on = state.isOn {
            isOn = on
        }
        // While a nightlight runs (or just ended), `bri` is the faded value: don't remember it.
        if !nightlightNow, !nightlightWasOn, let bri = state.brightness, bri > 0 {
            lastBrightness = min(Double(bri), Self.maxBrightness)
        }
        if shouldApplyRemote(.nightlight), let nl = state.nightlight {
            isNightlightOn = nightlightNow
            if isNightlightOn, let remaining = nl.remainingTime, remaining >= 0 {
                nightlightEnd = Date().addingTimeInterval(TimeInterval(remaining))
            } else {
                nightlightEnd = nil
            }
            if nightlightNow, !nightlightWasOn, preNightlightBrightness == nil {
                // Started elsewhere (iPhone, WLED UI, schedule).
                preNightlightBrightness = lastBrightness
            } else if !nightlightNow, nightlightWasOn {
                restoreBrightnessAfterNightlight()
            }
        }
        if applyPower, shouldApplyRemote(.brightness) {
            // On: the live brightness of the device. Off: the brightness it will have when turned on.
            if isOn, let bri = state.brightness, bri > 0 {
                brightness = min(Double(bri), Self.maxBrightness)
            } else {
                brightness = lastBrightness
            }
        }
    }

    /// The nightlight finished by itself (or was stopped elsewhere): put the user's brightness back.
    private func restoreBrightnessAfterNightlight() {
        guard let saved = preNightlightBrightness else { return }
        preNightlightBrightness = nil
        lastBrightness = saved
        markLocalChange(.brightness)
        // If the nightlight turned the strip off, keep it off. Setting `on: false` also stores
        // the brightness on the device for the next power on.
        send(isOn ? ["bri": Int(saved.rounded())] : ["bri": Int(saved.rounded()), "on": false])
    }
}
