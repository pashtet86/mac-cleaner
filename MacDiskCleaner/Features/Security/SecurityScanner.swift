import AppKit
import Foundation
import Security

/// Who signed a program, as far as macOS can verify.
nonisolated enum Signer: Sendable, Equatable {
    case apple
    case developer(String)
    case adHoc
    case unsigned
    case invalid
    case script
    case missing

    var label: String {
        switch self {
        case .apple: "Apple"
        case let .developer(name): name
        case .adHoc: "Ad-hoc signature (no developer identity)"
        case .unsigned: "Not signed"
        case .invalid: "Signature doesn't verify"
        case .script: "Script"
        case .missing: "Program is missing"
        }
    }
}

nonisolated struct LaunchItem: Identifiable, Sendable {
    enum Domain: String, Sendable {
        case userAgent = "Starts at your login"
        case globalAgent = "Starts at every login"
        case daemon = "Runs as root"
    }

    let label: String
    let plist: URL
    let domain: Domain
    /// The program that actually runs (the script for `sh script.sh`).
    let program: String?
    let signer: Signer
    let fromWorldWritableFolder: Bool

    var id: String { plist.path }
}

/// Read-only checks of macOS protections and of everything that starts automatically.
nonisolated enum SecurityScanner {
    struct Protections: Sendable {
        var sip: Bool?
        var gatekeeper: Bool?
        var fileVault: Bool?
        var managedByMDM: Bool?
    }

    static func protections() async -> Protections {
        async let sip = output("/usr/bin/csrutil", ["status"])
        async let gatekeeper = output("/usr/sbin/spctl", ["--status"])
        async let fileVault = output("/usr/bin/fdesetup", ["status"])
        async let mdm = output("/usr/bin/profiles", ["status", "-type", "enrollment"])
        let (s, g, f, m) = await (sip, gatekeeper, fileVault, mdm)
        return Protections(
            sip: s.map { $0.contains("enabled") },
            gatekeeper: g.map { $0.contains("enabled") },
            fileVault: f.map { $0.contains("is On") },
            managedByMDM: m.map { $0.contains("MDM enrollment: Yes") }
        )
    }

    private static func output(_ tool: String, _ arguments: [String]) async -> String? {
        guard let result = try? await ProcessRunner.run(tool, arguments, timeout: 10) else { return nil }
        let text = String(decoding: result.stdout, as: UTF8.self) + result.stderr
        return text.isEmpty ? nil : text
    }

    // MARK: - Launch agents and daemons

    static func launchItems() -> [LaunchItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders: [(URL, LaunchItem.Domain)] = [
            (home.appending(path: "Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        return folders.flatMap { folder, domain in
            let files =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "plist" }.compactMap { item(at: $0, domain: domain) }
        }
    }

    private static let interpreters: Set<String> = [
        "/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env", "/usr/bin/python3", "/usr/bin/perl", "/usr/bin/ruby",
        "/usr/bin/osascript",
    ]

    static func item(at plist: URL, domain: LaunchItem.Domain) -> LaunchItem? {
        guard let data = try? Data(contentsOf: plist),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let label = dict["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
        let arguments = dict["ProgramArguments"] as? [String] ?? []
        var program = dict["Program"] as? String ?? arguments.first

        // Helpers registered with SMAppService point into their app bundle.
        if program == nil, let relative = dict["BundleProgram"] as? String,
            let bundleID = (dict["AssociatedBundleIdentifiers"] as? [String])?.first
                ?? dict["AssociatedBundleIdentifiers"] as? String,
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            program = app.appending(path: relative).path
        }

        // `sh /path/script.sh`: the script is what actually runs.
        var commandText = arguments.joined(separator: " ")
        if let first = program, interpreters.contains(first) {
            if let script = arguments.dropFirst().first(where: { $0.hasPrefix("/") }) {
                program = script
            } else {
                commandText = arguments.dropFirst().joined(separator: " ")
                program = nil
            }
        }

        let signer: Signer
        if let program {
            signer = FileManager.default.fileExists(atPath: program) ? Self.signer(of: program) : .missing
        } else {
            signer = .script
        }
        let suspiciousPath = program.map(isInWorldWritableFolder) ?? false
        let inlineMentionsTemp =
            commandText.range(
                of: #"(^|\s)(/private)?(/tmp|/var/tmp|/Users/Shared)/"#, options: .regularExpression) != nil
        return LaunchItem(
            label: label, plist: plist, domain: domain, program: program, signer: signer,
            fromWorldWritableFolder: suspiciousPath || inlineMentionsTemp)
    }

    /// /tmp, /var/tmp, /Users/Shared and any folder anyone can write to: another user could swap the program.
    static func isInWorldWritableFolder(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        for prefix in ["/private/tmp/", "/private/var/tmp/", "/tmp/", "/var/tmp/", "/Users/Shared/"]
        where resolved.hasPrefix(prefix) || path.hasPrefix(prefix) {
            return true
        }
        var folder = URL(fileURLWithPath: resolved).deletingLastPathComponent().path
        while folder != "/" && !folder.isEmpty {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: folder),
                let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o002 != 0
            {
                return true
            }
            folder = (folder as NSString).deletingLastPathComponent
        }
        return false
    }

    static func signer(of path: String) -> Signer {
        guard isMachO(path) || path.hasSuffix(".app") else { return .script }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
            let code = staticCode
        else { return .unsigned }

        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any] ?? [:]
        guard dict[kSecCodeInfoIdentifier as String] != nil else { return .unsigned }
        guard SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return .invalid }

        var appleRequirement: SecRequirement?
        if SecRequirementCreateWithString("anchor apple" as CFString, [], &appleRequirement) == errSecSuccess,
            let appleRequirement, SecStaticCodeCheckValidity(code, [], appleRequirement) == errSecSuccess
        {
            return .apple
        }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if flags & 0x2 != 0 { return .adHoc }  // kSecCodeSignatureAdhoc
        if let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first,
            let summary = SecCertificateCopySubjectSummary(leaf) as String?
        {
            return .developer(summary)
        }
        return .adHoc
    }

    private static func isMachO(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path), let data = try? handle.read(upToCount: 4),
            data.count == 4
        else { return false }
        try? handle.close()
        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        return [0xfeed_face, 0xfeed_facf, 0xcafe_babe, 0xcefa_edfe, 0xcffa_edfe, 0xbeba_feca].contains(magic)
    }

    // MARK: - Findings

    static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!
    static let loginItemsSettings = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    static func findings(protections: Protections, items: [LaunchItem]) -> [HealthFinding] {
        var findings: [HealthFinding] = []

        func protection(
            _ id: String, _ value: Bool?, on: String, off: String, detail: String, severity: Severity, command: String?
        ) {
            guard let value else { return }
            findings.append(
                HealthFinding(
                    id: id, severity: value ? .ok : severity, title: value ? on : off,
                    detail: value ? "" : detail, symbol: value ? "checkmark.shield" : "exclamationmark.shield",
                    command: value ? nil : command, settingsURL: value ? nil : privacySettings))
        }
        protection(
            "sip", protections.sip, on: "System Integrity Protection is on", off: "System Integrity Protection is off",
            detail: "macOS can't stop software from changing protected system files. Turn it back on in Recovery.",
            severity: .critical, command: "csrutil enable")
        protection(
            "gatekeeper", protections.gatekeeper, on: "Gatekeeper is on", off: "Gatekeeper is off",
            detail: "Apps open without checking who made them or whether Apple scanned them for malware.",
            severity: .critical, command: "sudo spctl --global-enable")
        protection(
            "filevault", protections.fileVault, on: "FileVault encrypts this disk", off: "FileVault is off",
            detail:
                "Anyone with this Mac in hand can read the disk. Turn it on in System Settings → Privacy & Security.",
            severity: .warning, command: nil)
        if protections.managedByMDM == true {
            findings.append(
                HealthFinding(
                    id: "mdm", severity: .info, title: "Managed by an organization",
                    detail: "This Mac is enrolled in device management (MDM), which can install profiles and apps.",
                    symbol: "building.2"))
        }

        for item in items {
            let isUser = item.domain == .userAgent
            let removal =
                item.domain == .daemon
                ? "sudo launchctl bootout system \"\(item.plist.path)\" && sudo rm \"\(item.plist.path)\""
                : isUser ? nil : "sudo rm \"\(item.plist.path)\""
            if item.fromWorldWritableFolder {
                findings.append(
                    HealthFinding(
                        id: item.id, severity: .critical, title: "\(item.label) runs from a folder anyone can write to",
                        detail: "\(item.domain.rawValue). Any user or app could replace what it runs"
                            + (item.domain == .daemon ? " and gain root access." : ".")
                            + " Remove it unless you know exactly what it is.",
                        symbol: "exclamationmark.triangle", subtitle: item.program ?? item.plist.path,
                        command: removal, trashablePlist: isUser ? item.plist : nil))
            } else if item.signer == .missing {
                findings.append(
                    HealthFinding(
                        id: item.id, severity: .info, title: "\(item.label) points to a missing program",
                        detail: "A leftover from an app that was removed. It fails silently at every start.",
                        symbol: "questionmark.folder", subtitle: item.plist.path, command: removal,
                        trashablePlist: isUser ? item.plist : nil))
            } else if item.signer == .unsigned || item.signer == .invalid {
                findings.append(
                    HealthFinding(
                        id: item.id, severity: .warning, title: "\(item.label) runs unsigned code",
                        detail: "\(item.domain.rawValue). \(item.signer.label) — make sure you recognize it.",
                        symbol: "exclamationmark.triangle", subtitle: item.program ?? item.plist.path,
                        command: removal, trashablePlist: isUser ? item.plist : nil))
            }
        }
        return findings.sorted { ($0.severity, $0.title) < ($1.severity, $1.title) }
    }
}
