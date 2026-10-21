import AppKit
import Foundation
import Observation

/// Scans every cleanup rule once; pages read and act on their own section.
@Observable
final class CleanupStore {
    enum Phase: Equatable { case idle, scanning, ready, cleaning }

    let rules: [CleanupRule]
    private(set) var phase: Phase = .idle
    private(set) var results: [String: [CleanupItem]] = [:]
    private(set) var scannedAt: Date?
    private(set) var lastReport: (section: RuleSection, report: TrashReport)?
    var selection: Set<URL> = []

    init(rules: [CleanupRule] = CleanupRule.loadBundled()) {
        self.rules = rules
    }

    var isBusy: Bool { phase == .scanning || phase == .cleaning }

    func rules(in section: RuleSection) -> [CleanupRule] { rules.filter { $0.section == section } }

    func items(for rule: CleanupRule) -> [CleanupItem] { results[rule.id] ?? [] }

    func size(of rule: CleanupRule) -> Int64 { items(for: rule).reduce(0) { $0 + $1.size } }

    func total(in section: RuleSection) -> Int64 { rules(in: section).reduce(0) { $0 + size(of: $1) } }

    func total(for risk: Risk, in section: RuleSection) -> Int64 {
        rules(in: section).filter { $0.risk == risk }.reduce(0) { $0 + size(of: $1) }
    }

    func safeTotal(in section: RuleSection) -> Int64 { total(for: .safe, in: section) }

    func selectedItems(in section: RuleSection) -> [(rule: CleanupRule, item: CleanupItem)] {
        rules(in: section).flatMap { rule in
            items(for: rule).filter { selection.contains($0.url) }.map { (rule, $0) }
        }
    }

    func selectedBytes(in section: RuleSection) -> Int64 {
        selectedItems(in: section).reduce(0) { $0 + $1.item.size }
    }

    func selectionState(of rule: CleanupRule) -> SelectionMark.State {
        let urls = items(for: rule).map(\.url)
        guard !urls.isEmpty else { return .off }
        let count = urls.filter(selection.contains).count
        return count == 0 ? .off : (count == urls.count ? .on : .mixed)
    }

    func toggle(_ rule: CleanupRule) {
        let urls = items(for: rule).map(\.url)
        if selectionState(of: rule) == .on {
            selection.subtract(urls)
        } else {
            selection.formUnion(urls)
        }
    }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    /// Running apps among the selected rules that should be quit first.
    func appsToQuit(in section: RuleSection) -> [NSRunningApplication] {
        let ids = Set(selectedItems(in: section).flatMap { $0.rule.closeApps ?? [] })
        guard !ids.isEmpty else { return [] }
        return NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier.map(ids.contains) ?? false
        }
    }

    func scanIfNeeded() async {
        if phase == .idle { await scan() }
    }

    func scan() async {
        guard !isBusy else { return }
        phase = .scanning
        let rules = rules
        let found = await withTaskGroup(of: (String, [CleanupItem]).self) { group in
            for rule in rules {
                group.addTask(priority: .userInitiated) { (rule.id, CleanupScanner.scan(rule)) }
            }
            var found: [String: [CleanupItem]] = [:]
            for await (id, items) in group { found[id] = items }
            return found
        }
        results = found
        // Default selection: everything in rules marked safe.
        selection = Set(rules.filter { $0.risk == .safe }.flatMap { found[$0.id] ?? [] }.map(\.url))
        scannedAt = .now
        phase = .ready
    }

    func cleanSelected(in section: RuleSection) async {
        let targets = selectedItems(in: section).map { (url: $0.item.url, size: $0.item.size) }
        guard !targets.isEmpty else { return }
        phase = .cleaning
        let report = await SafeTrash.trash(targets)
        lastReport = (section, report)
        phase = .ready
        await scan()
    }

    func dismissReport() { lastReport = nil }
}
