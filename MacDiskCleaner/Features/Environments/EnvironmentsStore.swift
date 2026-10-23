import Foundation
import Observation

@Observable
final class EnvironmentsStore {
    enum Phase: Equatable { case idle, scanning, ready, checking }

    private(set) var phase: Phase = .idle
    private(set) var installs: [Installation] = []
    private(set) var assessments: [String: Assessment] = [:]
    private(set) var brewOutdated: [VersionSources.BrewOutdated] = []
    private(set) var checkedAt: Date?
    private(set) var failedProducts: [String] = []
    private var environment: [String: String] = [:]

    /// Names of tools that need updating now, from the latest check — kept across launches so
    /// Overview can warn without a new check. Stores tool names and versions only.
    struct UrgentSummary: Codable, Equatable {
        let names: [String]
        let checkedAt: Date
    }

    private static let summaryKey = "environments.urgentSummary"
    private(set) var savedSummary: UrgentSummary? = {
        guard let data = UserDefaults.standard.data(forKey: summaryKey) else { return nil }
        return try? JSONDecoder().decode(UrgentSummary.self, from: data)
    }()

    /// What Overview shows: live results if this session checked, else the last saved check.
    var urgentSummary: UrgentSummary? {
        guard let summary = savedSummary, !summary.names.isEmpty else { return nil }
        return summary
    }

    var isBusy: Bool { phase == .scanning || phase == .checking }

    /// Installations ordered by how urgent they are, then by tool and version.
    var sorted: [Installation] {
        installs.sorted { a, b in
            let ua = urgency(a)
            let ub = urgency(b)
            if ua != ub { return ua < ub }
            if a.toolID != b.toolID { return name(a) < name(b) }
            if a.isActive != b.isActive { return a.isActive }
            return a.version > b.version
        }
    }

    func urgency(_ install: Installation) -> Urgency { assessments[install.id]?.urgency ?? .unknown }

    func count(_ urgency: Urgency) -> Int { installs.filter { self.urgency($0) == urgency }.count }

    /// Red-dot count for the sidebar.
    var needsAttention: Int { count(.updateNow) }

    func name(_ install: Installation) -> String { ToolSpec.spec(install.toolID)?.name ?? install.toolID }

    func scanIfNeeded() async {
        if phase == .idle { await scan() }
    }

    /// Opening the page: find the tools and, if you've checked online before, grade them again right
    /// away — Overview already showed the result, so the page shouldn't ask for another click.
    func prepare() async {
        await scanIfNeeded()
        if checkedAt == nil, savedSummary != nil { await checkOnline() }
    }

    func scan() async {
        guard !isBusy else { return }
        phase = .scanning
        environment = await EnvironmentScanner.loginEnvironment()
        let environment = environment
        installs = await EnvironmentScanner.scan(environment: environment)
        assessments = assessments.filter { key, _ in installs.contains { $0.id == key } }
        phase = .ready
    }

    /// Downloads public release schedules and grades every installation. Nothing about this Mac is sent.
    func checkOnline() async {
        guard !isBusy else { return }
        if installs.isEmpty { await scan() }
        phase = .checking
        let installs = installs
        let environment = environment

        // One request per product, even with several installs of it.
        let products = Set(
            installs.compactMap { install in
                ToolSpec.spec(install.toolID).flatMap { VersionSources.lifecycleProduct(for: install, spec: $0) }
            })
        var schedules: [String: [ReleaseCycle]] = [:]
        var failed: [String] = []
        await withTaskGroup(of: (String, [ReleaseCycle]?).self) { group in
            for product in products {
                group.addTask { (product, try? await VersionSources.cycles(for: product)) }
            }
            for await (product, cycles) in group {
                if let cycles { schedules[product] = cycles } else { failed.append(product) }
            }
        }
        let security =
            installs.contains { $0.toolID == "node" } ? ((try? await VersionSources.nodeSecurityReleases()) ?? []) : []
        let outdated = await VersionSources.brewOutdated(environment: environment)

        let today = Date()
        var graded: [String: Assessment] = [:]
        for install in installs {
            guard let spec = ToolSpec.spec(install.toolID) else { continue }
            let cycles = VersionSources.lifecycleProduct(for: install, spec: spec).flatMap { schedules[$0] } ?? []
            if !cycles.isEmpty {
                graded[install.id] = Assessor.assess(
                    install, spec: spec, cycles: cycles, securityReleases: install.toolID == "node" ? security : [],
                    today: today)
            } else if install.source == .homebrew,
                let item = outdated.first(where: { $0.name == homebrewFormula(for: install.toolID) })
            {
                // No published schedule, but Homebrew knows a newer build.
                graded[install.id] = Assessment(
                    urgency: .convenient, reason: "Homebrew has \(item.current).", latestInLine: nil,
                    latest: item.current, command: item.command)
            } else {
                graded[install.id] = Assessment(
                    urgency: install.source == .homebrew ? .upToDate : .unknown,
                    reason: install.source == .homebrew
                        ? "Homebrew has no newer version." : "No public release schedule to compare with.",
                    latestInLine: nil, latest: nil, command: nil)
            }
        }
        assessments = Self.markingRedundantCopies(installs, graded)
        brewOutdated = outdated
        failedProducts = failed.sorted()
        checkedAt = .now
        saveSummary()
        phase = .ready
    }

    private func saveSummary() {
        let names = sorted.filter { urgency($0) == .updateNow }.map { "\(name($0)) \($0.version)" }
        let summary = UrgentSummary(names: names, checkedAt: checkedAt ?? .now)
        savedSummary = summary
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: Self.summaryKey)
        }
    }

    /// An unused copy of a version line that already has a newer copy installed is just leftovers:
    /// offer to remove it instead of raising an alarm about it.
    nonisolated static func markingRedundantCopies(
        _ installs: [Installation], _ assessments: [String: Assessment]
    ) -> [String: Assessment] {
        var result = assessments
        let byLine = Dictionary(grouping: installs) { install in
            "\(install.toolID)|\(install.version.cycle(depth: ToolSpec.spec(install.toolID)?.cycleDepth ?? 1))"
        }
        for copies in byLine.values where copies.count > 1 {
            guard let newest = copies.max(by: { $0.version < $1.version }) else { continue }
            for copy in copies where !copy.isActive && copy.version < newest.version {
                guard let spec = ToolSpec.spec(copy.toolID) else { continue }
                result[copy.id] = Assessment(
                    urgency: .optional,
                    reason: "An older copy — \(spec.name) \(newest.version) of the same line is installed too.",
                    latestInLine: assessments[copy.id]?.latestInLine, latest: assessments[copy.id]?.latest,
                    command: spec.removeCommand(for: copy))
            }
        }
        return result
    }

    private func homebrewFormula(for toolID: String) -> String {
        switch toolID {
        case "python3": "python"
        case "pod": "cocoapods"
        case "rustc": "rust"
        default: toolID
        }
    }
}
