import Foundation

/// Minimal one-shot client of a WLED device's JSON API, for the Control Center controls.
/// (The watch app itself uses `DeviceController`, which also polls and keeps local state.)
struct WledRemote: Sendable {
    struct State: Decodable, Sendable {
        struct Nightlight: Decodable, Sendable {
            let on: Bool
        }

        let on: Bool
        let bri: Int
        let nl: Nightlight?

        var isNightlightOn: Bool { nl?.on ?? false }
    }

    private struct Update: Encodable {
        struct Nightlight: Encodable {
            let on: Bool
        }

        var on: Bool?
        var bri: Int?
        var nl: Nightlight?
    }

    let device: WatchDevice

    func fetchState() async throws -> State {
        try JSONDecoder().decode(State.self, from: await send(request(method: "GET", body: nil)))
    }

    func setPower(_ on: Bool) async throws {
        try await post(Update(on: on))
    }

    /// Starts or stops the nightlight (duration and mode are the ones configured on the device).
    /// Starting remembers the brightness, stopping puts it back: the nightlight fades `bri` down.
    func setNightlight(_ on: Bool) async throws {
        if on {
            let state = try await fetchState()
            // Keep an already saved value: if the previous nightlight ended by itself, `bri` is the
            // faded one, not the one the user picked.
            if !state.isNightlightOn, state.bri > 0,
               WatchSharedStore.preNightlightBrightness(for: device.id) == nil {
                WatchSharedStore.setPreNightlightBrightness(state.bri, for: device.id)
            }
            try await post(Update(on: true, nl: .init(on: true)))
        } else {
            let saved = WatchSharedStore.preNightlightBrightness(for: device.id)
            try await post(Update(bri: saved, nl: .init(on: false)))
            // Cleared only once the device got the request, so a failure can be retried.
            WatchSharedStore.setPreNightlightBrightness(nil, for: device.id)
        }
    }

    /// A nightlight started from the controls that finished by itself leaves the device at the
    /// faded brightness: put the saved one back. Does nothing otherwise.
    func restoreBrightnessIfNightlightEnded(_ state: State) async throws {
        guard !state.isNightlightOn,
              let saved = WatchSharedStore.preNightlightBrightness(for: device.id) else { return }
        // Only `bri`: the strip stays on or off as the nightlight left it.
        try await post(Update(bri: saved))
        WatchSharedStore.setPreNightlightBrightness(nil, for: device.id)
    }

    // MARK: - Networking

    private func post(_ update: Update) async throws {
        try await send(request(method: "POST", body: JSONEncoder().encode(update)))
    }

    private func request(method: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: "http://\(device.address)/json/state") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
