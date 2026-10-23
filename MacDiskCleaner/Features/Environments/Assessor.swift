import Foundation

/// Decides how urgent an update is, from published release lines. Pure — no network, no clock.
nonisolated enum Assessor {
    static let soonWindow: TimeInterval = 90 * 24 * 3600

    static func assess(
        _ install: Installation, spec: ToolSpec, cycles: [ReleaseCycle], securityReleases: [Version] = [],
        today: Date
    ) -> Assessment {
        guard !cycles.isEmpty else {
            return Assessment(
                urgency: .unknown, reason: "No published release schedule to compare with.", latestInLine: nil,
                latest: nil, command: nil)
        }
        let mine = install.version
        let line =
            cycles.first { $0.cycle == mine.cycle(depth: spec.cycleDepth) }
            // JDK vendors and some products name lines by major only.
            ?? cycles.first { $0.cycle == String(mine.major) }
        let newest = cycles.compactMap { cycle in cycle.latest.flatMap(Version.init).map { (cycle, $0) } }
            .max { $0.1 < $1.1 }
        let latestOverall = newest?.1.description
        let latestInLine = line?.latest.flatMap(Version.init)
        let systemNote = install.source == .system ? "This is macOS's built-in copy; install your own instead. " : ""

        func result(_ urgency: Urgency, _ reason: String, remove: Bool = false) -> Assessment {
            let command =
                remove
                ? spec.removeCommand(for: install)
                : spec.updateCommand(for: install, latestInLine: latestInLine?.description)
            return Assessment(
                urgency: urgency, reason: systemNote + reason, latestInLine: latestInLine?.description,
                latest: latestOverall, command: command)
        }

        // Older than every published line: certainly out of support.
        guard let line else {
            let oldest = cycles.compactMap { Version($0.cycle) }.min()
            if let oldest, mine < oldest {
                return install.isActive
                    ? result(.updateNow, "\(spec.name) \(mine.cycle(depth: spec.cycleDepth)) is long out of support.")
                    : result(.updateNow, "Long out of support. Remove it if no project needs it.", remove: true)
            }
            return result(.unknown, "This version isn't in the published schedule.")
        }

        if line.eolReached || line.eol.map({ $0 <= today }) == true {
            let since = line.eol.map { " since \(Self.format($0))" } ?? ""
            return install.isActive
                ? result(.updateNow, "No longer supported\(since) — it gets no security fixes.")
                : result(
                    .updateNow, "Not supported\(since). Remove it if no project needs this version.", remove: true)
        }

        if let fix = securityReleases.filter({ $0.major == mine.major && $0 > mine }).max() {
            return result(.updateNow, "\(spec.name) \(fix) is a security release for your version line.")
        }

        if let end = line.eol, end.timeIntervalSince(today) < soonWindow {
            return result(.soon, "Support ends \(Self.format(end)). Plan a move to a newer version.")
        }

        if let latestInLine, mine < latestInLine {
            return result(.convenient, "\(latestInLine) is out with fixes for your version line.")
        }

        if let newest, let lineLatest = line.latest.flatMap(Version.init), lineLatest < newest.1 {
            return result(.optional, "\(spec.name) \(newest.0.cycle) is the newest line; yours is still supported.")
        }

        return Assessment(
            urgency: .upToDate, reason: "Latest in a supported line.", latestInLine: latestInLine?.description,
            latest: latestOverall, command: nil)
    }

    static func format(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
