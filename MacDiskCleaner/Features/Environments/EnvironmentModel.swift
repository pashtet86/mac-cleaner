import Foundation

/// A dotted version ("v24.20.0", "3.9.6", "2.6.10p210", "17.0.15+6") reduced to numbers for comparison.
nonisolated struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        guard let range = text.range(of: #"\d+(\.\d+){0,3}"#, options: .regularExpression) else { return nil }
        parts = text[range].split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
    }

    var major: Int { parts[0] }
    var description: String { parts.map(String.init).joined(separator: ".") }

    /// "24" for depth 1, "3.9" for depth 2 — how endoflife.date names release lines.
    func cycle(depth: Int) -> String { parts.prefix(depth).map(String.init).joined(separator: ".") }

    /// "24.20" and "24.20.0" are the same version — equality and hashing ignore trailing zeros.
    private var normalized: ArraySlice<Int> {
        var end = parts.count
        while end > 1 && parts[end - 1] == 0 { end -= 1 }
        return parts[..<end]
    }

    static func == (lhs: Version, rhs: Version) -> Bool { lhs.normalized == rhs.normalized }

    func hash(into hasher: inout Hasher) { hasher.combine(Array(normalized)) }

    static func < (lhs: Version, rhs: Version) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}

/// Where an installation came from; decides the update or removal command.
nonisolated enum InstallSource: String, Sendable {
    case homebrew = "Homebrew"
    case system = "macOS"
    case nvm, fnm
    case volta = "Volta"
    case pyenv, rbenv, asdf, rustup
    case jdk = "JDK"
    case appBundle = "App"
    case other = "PATH"

    static func of(path: String, home: String) -> InstallSource {
        if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/Cellar/") || path.hasPrefix("/usr/local/opt/")
        {
            return .homebrew
        }
        if path.hasPrefix("/usr/bin/") || path.hasPrefix("/bin/") || path.hasPrefix("/System/") { return .system }
        if path.contains("/.nvm/") { return .nvm }
        if path.contains("/fnm/") { return .fnm }
        if path.contains("/.volta/") { return .volta }
        if path.contains("/.pyenv/") { return .pyenv }
        if path.contains("/.rbenv/") { return .rbenv }
        if path.contains("/.asdf/") { return .asdf }
        if path.contains("/.cargo/") || path.contains("/.rustup/") { return .rustup }
        if path.hasPrefix("/Library/Java/JavaVirtualMachines/") || path.contains("/Library/Java/JavaVirtualMachines/") {
            return .jdk
        }
        if path.contains(".app/Contents/") { return .appBundle }
        return .other
    }
}

nonisolated struct Installation: Identifiable, Hashable, Sendable {
    let toolID: String
    let version: Version
    /// Path of the executable or install folder.
    let path: String
    let source: InstallSource
    /// The copy your shell runs. Others are installed side by side (nvm, pyenv, extra JDKs).
    let isActive: Bool
    /// JDK vendor or similar detail, shown next to the version.
    var note: String? = nil

    var id: String { "\(toolID)|\(path)" }
}

/// One release line from endoflife.date (e.g. Node "24", Python "3.12").
nonisolated struct ReleaseCycle: Decodable, Sendable {
    let cycle: String
    let latest: String?
    /// nil when the line has no announced end; dates are "YYYY-MM-DD".
    let eol: Date?
    let eolReached: Bool

    enum CodingKeys: String, CodingKey { case cycle, latest, eol }

    init(cycle: String, latest: String?, eol: Date?, eolReached: Bool = false) {
        self.cycle = cycle
        self.latest = latest
        self.eol = eol
        self.eolReached = eolReached
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `cycle` and `latest` are usually strings but occasionally numbers.
        cycle =
            (try? container.decode(String.self, forKey: .cycle))
            ?? (try? container.decode(Double.self, forKey: .cycle)).map { String($0) } ?? ""
        latest = try? container.decode(String.self, forKey: .latest)
        if let text = try? container.decode(String.self, forKey: .eol) {
            eol = Self.day.date(from: text)
            eolReached = false
        } else {
            eol = nil
            eolReached = (try? container.decode(Bool.self, forKey: .eol)) ?? false
        }
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

nonisolated enum Urgency: Int, Comparable, CaseIterable, Sendable {
    case updateNow, soon, convenient, optional, upToDate, unknown

    static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .updateNow: "Urgent"
        case .soon: "Soon"
        case .convenient: "When convenient"
        case .optional: "Optional"
        case .upToDate: "Up to date"
        case .unknown: "Not checked"
        }
    }
}

nonisolated struct Assessment: Sendable {
    let urgency: Urgency
    let reason: String
    let latestInLine: String?
    let latest: String?
    let command: String?
}
