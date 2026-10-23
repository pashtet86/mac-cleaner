import Foundation
import Testing

@testable import MacDiskCleaner

@Suite("Versions")
struct VersionTests {
    @Test(
        "Parses the version out of tool output",
        arguments: [
            ("v24.20.0", "24.20.0"), ("Python 3.9.6", "3.9.6"), ("ruby 2.6.10p210 (2022-04-12)", "2.6.10"),
            ("openjdk version \"17.0.15\" 2025-04-15 LTS", "17.0.15"),
            ("Docker version 29.1.3, build f52814d", "29.1.3"),
            ("27+35", "27"),
        ])
    func parses(text: String, expected: String) {
        #expect(Version(text)?.description == expected)
    }

    @Test("Compares numerically, not as text")
    func compares() throws {
        #expect(try #require(Version("1.10.0")) > #require(Version("1.9.9")))
        #expect(try #require(Version("24.20")) == #require(Version("24.20.0")))
        #expect(try #require(Version("3.9.6")).cycle(depth: 2) == "3.9")
    }

    @Test("Swift reports the language version, not the driver version")
    func swiftVersion() throws {
        let spec = try #require(ToolSpec.spec("swift"))
        let output = Data("swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1)".utf8)
        #expect(EnvironmentScanner.parseVersion(spec, output: output, stderr: "")?.description == "6.4")
    }
}

@Suite("Release schedules")
struct ReleaseCycleTests {
    @Test("Decodes endoflife.date: dates, booleans and numeric cycles")
    func decodes() throws {
        let json = """
            [{"cycle":"24","latest":"24.21.0","eol":"2028-04-30"},
             {"cycle":"16","latest":"16.20.2","eol":true},
             {"cycle":1.27,"latest":"1.27.3","eol":false}]
            """
        let cycles = try JSONDecoder().decode([ReleaseCycle].self, from: Data(json.utf8))
        #expect(cycles[0].eol != nil && !cycles[0].eolReached)
        #expect(cycles[1].eol == nil && cycles[1].eolReached)
        #expect(cycles[2].cycle == "1.27" && !cycles[2].eolReached)
    }
}

@Suite("Update urgency")
struct AssessorTests {
    private let node = ToolSpec.spec("node")!
    private let python = ToolSpec.spec("python3")!
    private let today = ISO8601DateFormatter().date(from: "2026-10-23T12:00:00Z")!

    private func day(_ text: String) -> Date { ISO8601DateFormatter().date(from: "\(text)T00:00:00Z")! }

    private var nodeCycles: [ReleaseCycle] {
        [
            ReleaseCycle(cycle: "26", latest: "26.12.1", eol: day("2029-04-30")),
            ReleaseCycle(cycle: "24", latest: "24.21.0", eol: day("2028-04-30")),
            ReleaseCycle(cycle: "22", latest: "22.22.1", eol: day("2027-04-30")),
            ReleaseCycle(cycle: "20", latest: "20.19.6", eol: day("2026-12-31")),
            ReleaseCycle(cycle: "16", latest: "16.20.2", eol: day("2023-09-11")),
        ]
    }

    private func install(
        _ version: String, _ source: InstallSource = .homebrew, active: Bool = true, tool: String = "node"
    )
        -> Installation
    {
        Installation(toolID: tool, version: Version(version)!, path: "/x/\(version)", source: source, isActive: active)
    }

    @Test("End of life is urgent; an unused old copy is offered for removal")
    func endOfLife() {
        let active = Assessor.assess(install("16.20.2"), spec: node, cycles: nodeCycles, today: today)
        #expect(active.urgency == .updateNow)
        #expect(active.command == "brew upgrade node")

        let unused = Assessor.assess(
            install("16.20.2", .nvm, active: false), spec: node, cycles: nodeCycles, today: today)
        #expect(unused.urgency == .updateNow)
        #expect(unused.command == "nvm uninstall 16.20.2")
    }

    @Test("A security release in your line beats a plain patch")
    func security() {
        let result = Assessor.assess(
            install("24.20.0"), spec: node, cycles: nodeCycles, securityReleases: [Version("24.21.0")!], today: today)
        #expect(result.urgency == .updateNow)
        #expect(result.reason.contains("security"))
    }

    @Test("Support ending within 90 days is 'soon'")
    func endingSoon() {
        #expect(Assessor.assess(install("20.19.6"), spec: node, cycles: nodeCycles, today: today).urgency == .soon)
    }

    @Test("A newer patch in a supported line is 'when convenient'")
    func patch() {
        let result = Assessor.assess(install("24.20.0"), spec: node, cycles: nodeCycles, today: today)
        #expect(result.urgency == .convenient)
        #expect(result.latestInLine == "24.21.0")
    }

    @Test("Latest of an older supported line: only a new major is optional")
    func newerMajor() {
        #expect(Assessor.assess(install("22.22.1"), spec: node, cycles: nodeCycles, today: today).urgency == .optional)
        #expect(Assessor.assess(install("26.12.1"), spec: node, cycles: nodeCycles, today: today).urgency == .upToDate)
    }

    @Test("macOS's own Python is flagged with a Homebrew install command")
    func systemPython() {
        let cycles = [
            ReleaseCycle(cycle: "3.14", latest: "3.14.2", eol: day("2030-10-31")),
            ReleaseCycle(cycle: "3.9", latest: "3.9.25", eol: day("2025-10-31")),
        ]
        let result = Assessor.assess(
            install("3.9.6", .system, tool: "python3"), spec: python, cycles: cycles, today: today)
        #expect(result.urgency == .updateNow)
        #expect(result.command == "brew install python")
        #expect(result.reason.contains("built-in"))
    }

    @Test("Versions older than every published line are out of support")
    func olderThanSchedule() {
        let result = Assessor.assess(install("8.17.0"), spec: node, cycles: nodeCycles, today: today)
        #expect(result.urgency == .updateNow)
    }

    @Test("Only fixed public hosts and allowlisted product names are requested")
    func productNames() async {
        await #expect(throws: URLError.self) { try await VersionSources.cycles(for: "../etc/passwd") }
    }
}

@Suite("Redundant copies")
struct RedundantCopyTests {
    @Test("An unused older copy of a line already installed newer is offered for removal")
    func redundant() {
        let active = Installation(
            toolID: "node", version: Version("24.20.0")!, path: "/a", source: .nvm, isActive: true)
        let old = Installation(toolID: "node", version: Version("24.2.0")!, path: "/b", source: .nvm, isActive: false)
        let other = Installation(
            toolID: "node", version: Version("22.22.1")!, path: "/c", source: .nvm, isActive: false)
        let alarm = Assessment(urgency: .updateNow, reason: "", latestInLine: "24.22.1", latest: nil, command: nil)
        let result = EnvironmentsStore.markingRedundantCopies(
            [active, old, other], [active.id: alarm, old.id: alarm, other.id: alarm])
        #expect(result[old.id]?.urgency == .optional)
        #expect(result[old.id]?.command == "nvm uninstall 24.2.0")
        #expect(result[active.id]?.urgency == .updateNow)
        #expect(result[other.id]?.urgency == .updateNow)
    }

    @Test("Updating a Node line stays on its major")
    func sameMajor() {
        let install = Installation(
            toolID: "node", version: Version("22.22.1")!, path: "/c", source: .nvm, isActive: false)
        #expect(ToolSpec.spec("node")?.updateCommand(for: install, latestInLine: "22.23.4") == "nvm install 22")
    }
}
