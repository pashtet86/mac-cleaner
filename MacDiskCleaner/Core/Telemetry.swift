import Foundation
import Observation

/// Optional, opt-in anonymous statistics sent to our own Cloudflare Worker (see `telemetry/`).
///
/// Off unless the build sets `TELEMETRY_ENDPOINT` *and* the user agrees. Sends only: a random
/// install ID, app and macOS version, CPU architecture, and for cleanups the section and byte
/// count. Never file names, paths, the Mac's or user's name. Failures are ignored silently.
@Observable
final class Telemetry {
    static let shared = Telemetry()

    enum Consent: String { case unknown, granted, denied }

    /// HTTPS only; nil when the build has no endpoint, which hides every telemetry UI.
    static let endpoint: URL? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "DSTelemetryEndpoint") as? String,
            let url = URL(string: value.trimmingCharacters(in: .whitespaces)), isAllowed(url)
        else { return nil }
        return url.appending(path: "v1/events")
    }()

    /// HTTPS everywhere; plain HTTP only to a local `wrangler dev` in Debug builds.
    private static func isAllowed(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && url.host == "127.0.0.1"
        #else
        return false
        #endif
    }

    private enum Key {
        static let consent = "telemetry.consent"
        static let installID = "telemetry.installID"
        static let firstLaunchSent = "telemetry.firstLaunchSent"
        static let lastOpenDay = "telemetry.lastOpenDay"
    }

    private let defaults = UserDefaults.standard
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    private(set) var consent: Consent

    private init() {
        consent = UserDefaults.standard.string(forKey: Key.consent).flatMap(Consent.init) ?? .unknown
    }

    var isAvailable: Bool { Self.endpoint != nil }
    var shouldAsk: Bool { isAvailable && consent == .unknown }

    func setSharing(_ enabled: Bool) {
        consent = enabled ? .granted : .denied
        defaults.set(consent.rawValue, forKey: Key.consent)
        if enabled {
            appOpened()
        } else {
            // Opting out also forgets the ID, so a later opt-in starts as a new, unlinked install.
            defaults.removeObject(forKey: Key.installID)
            defaults.removeObject(forKey: Key.firstLaunchSent)
        }
    }

    /// Once per day at most; also sends the one-time first launch after opting in.
    func appOpened() {
        guard consent == .granted else { return }
        if !defaults.bool(forKey: Key.firstLaunchSent) {
            send(["event": "first_launch"])
            defaults.set(true, forKey: Key.firstLaunchSent)
        }
        let today = ISO8601DateFormatter.string(from: .now, timeZone: .gmt, formatOptions: .withFullDate)
        guard defaults.string(forKey: Key.lastOpenDay) != today else { return }
        defaults.set(today, forKey: Key.lastOpenDay)
        send(["event": "app_open"])
    }

    func cleaned(_ bytes: Int64, in section: AppSection) {
        guard consent == .granted, bytes > 0 else { return }
        send(["event": "cleanup", "section": section.rawValue, "bytesCleaned": bytes])
    }

    private var installID: String {
        if let id = defaults.string(forKey: Key.installID) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: Key.installID)
        return id
    }

    private func send(_ fields: [String: Any]) {
        guard let endpoint = Self.endpoint else { return }
        var body = fields
        body["installId"] = installID
        body["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        body["osVersion"] = "\(os.majorVersion).\(os.minorVersion)"
        #if arch(arm64)
        body["arch"] = "arm64"
        #else
        body["arch"] = "x86_64"
        #endif

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        session.dataTask(with: request).resume()
    }
}
