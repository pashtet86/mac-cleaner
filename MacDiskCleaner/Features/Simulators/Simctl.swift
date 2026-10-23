import Foundation

nonisolated struct SimRuntime: Identifiable, Decodable, Sendable, Hashable {
    let identifier: String
    let version: String
    let build: String
    let platformIdentifier: String
    let runtimeIdentifier: String
    let state: String
    let sizeBytes: Int64?
    let deletable: Bool?
    let lastUsedAt: Date?

    var id: String { identifier }

    var platformName: String {
        switch platformIdentifier {
        case "com.apple.platform.iphonesimulator": "iOS"
        case "com.apple.platform.appletvsimulator": "tvOS"
        case "com.apple.platform.watchsimulator": "watchOS"
        case "com.apple.platform.xrsimulator": "visionOS"
        default: "Runtime"
        }
    }

    var title: String { "\(platformName) \(version)" }

    var symbol: String {
        switch platformName {
        case "tvOS": "appletv"
        case "watchOS": "applewatch"
        case "visionOS": "visionpro"
        default: "iphone"
        }
    }
}

nonisolated struct SimDevice: Identifiable, Sendable, Hashable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool
    let dataPathSize: Int64?
    let lastUsedAt: Date?
    let runtimeIdentifier: String

    var id: String { udid }
    var isBooted: Bool { state == "Booted" }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-1" → "iOS 27.1"
    var runtimeName: String {
        guard let last = runtimeIdentifier.split(separator: ".").last else { return runtimeIdentifier }
        let parts = last.split(separator: "-")
        guard let platform = parts.first else { return String(last) }
        return "\(platform) " + parts.dropFirst().joined(separator: ".")
    }
}

/// Fixed set of simctl operations. Identifiers are validated as UUIDs before use.
nonisolated enum Simctl {
    private static let xcrun = "/usr/bin/xcrun"

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// simctl ships with full Xcode only; Command Line Tools alone don't have it.
    static func isAvailable() async -> Bool {
        (try? await ProcessRunner.run(xcrun, ["--find", "simctl"]))?.succeeded ?? false
    }

    static func runtimes() async throws -> [SimRuntime] {
        let result = try await ProcessRunner.checked(xcrun, ["simctl", "runtime", "list", "--json"])
        let map = try decoder.decode([String: SimRuntime].self, from: result.stdout)
        return map.values.sorted { a, b in
            guard a.platformName == b.platformName else { return a.platformName < b.platformName }
            return a.version.compare(b.version, options: .numeric) == .orderedDescending
        }
    }

    static func devices() async throws -> [SimDevice] {
        struct Listing: Decodable { let devices: [String: [Entry]] }
        struct Entry: Decodable {
            let udid: String
            let name: String
            let state: String
            let isAvailable: Bool
            let dataPathSize: Int64?
            let lastUsedAt: Date?
        }
        let result = try await ProcessRunner.checked(xcrun, ["simctl", "list", "devices", "--json"])
        let listing = try decoder.decode(Listing.self, from: result.stdout)
        return listing.devices.flatMap { runtime, entries in
            entries.map {
                SimDevice(
                    udid: $0.udid, name: $0.name, state: $0.state, isAvailable: $0.isAvailable,
                    dataPathSize: $0.dataPathSize, lastUsedAt: $0.lastUsedAt, runtimeIdentifier: runtime)
            }
        }
    }

    static func deleteRuntime(_ identifier: String) async throws {
        try await ProcessRunner.checked(xcrun, ["simctl", "runtime", "delete", validated(identifier)])
    }

    static func deleteDevice(_ udid: String) async throws {
        try await ProcessRunner.checked(xcrun, ["simctl", "delete", validated(udid)])
    }

    static func deleteUnavailableDevices() async throws {
        try await ProcessRunner.checked(xcrun, ["simctl", "delete", "unavailable"])
    }

    private static func validated(_ identifier: String) throws -> String {
        guard let uuid = UUID(uuidString: identifier) else {
            throw CocoaError(.keyValueValidation)
        }
        return uuid.uuidString
    }
}
