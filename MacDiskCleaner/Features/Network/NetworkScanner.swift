import Darwin
import Foundation

/// A process accepting TCP connections, merged across IPv4 and IPv6.
nonisolated struct Listener: Identifiable, Sendable, Equatable {
    let port: Int
    let process: String
    let pid: Int32
    /// Reachable from other devices, not just this Mac.
    let isExposed: Bool
    let addresses: [String]

    var id: String { "\(port)-\(pid)" }
    var service: KnownService? { KnownService.forPort(port) }
}

nonisolated struct KnownService: Sendable, Equatable {
    enum Kind: Sendable { case remoteAccess, sharing, development, system }

    let name: String
    let kind: Kind

    static func forPort(_ port: Int) -> KnownService? {
        switch port {
        case 22: KnownService(name: "Remote Login (SSH)", kind: .remoteAccess)
        case 3283: KnownService(name: "Remote Management", kind: .remoteAccess)
        case 5900: KnownService(name: "Screen Sharing", kind: .remoteAccess)
        case 445: KnownService(name: "File Sharing (SMB)", kind: .sharing)
        case 548: KnownService(name: "File Sharing (AFP)", kind: .sharing)
        case 631: KnownService(name: "Printer Sharing", kind: .sharing)
        case 3689: KnownService(name: "Media Sharing", kind: .sharing)
        case 5000, 7000: KnownService(name: "AirPlay Receiver", kind: .system)
        case 17500: KnownService(name: "Dropbox LAN sync", kind: .sharing)
        case 3000, 3001, 4200, 5173, 8000, 8080, 8081, 8888, 19000, 19001, 19006:
            KnownService(name: "Development server", kind: .development)
        case 3306: KnownService(name: "MySQL", kind: .development)
        case 5432: KnownService(name: "PostgreSQL", kind: .development)
        case 6379: KnownService(name: "Redis", kind: .development)
        case 27017: KnownService(name: "MongoDB", kind: .development)
        default: nil
        }
    }
}

/// Read-only look at what this Mac exposes to the network.
nonisolated enum NetworkScanner {
    struct Firewall: Sendable, Equatable {
        var enabled: Bool?
        var stealth: Bool?
        var blocksAll: Bool?
    }

    struct Proxy: Sendable, Equatable {
        var servers: [String] = []
        var autoConfigURL: String?
        var isEmpty: Bool { servers.isEmpty && autoConfigURL == nil }
    }

    private static let firewallTool = "/usr/libexec/ApplicationFirewall/socketfilterfw"

    static func firewall() async -> Firewall {
        async let global = output(firewallTool, ["--getglobalstate"])
        async let stealth = output(firewallTool, ["--getstealthmode"])
        async let blockAll = output(firewallTool, ["--getblockall"])
        let (g, s, b) = await (global, stealth, blockAll)
        return Firewall(
            enabled: g.map { $0.contains("enabled") },
            stealth: s.map { $0.contains("enabled") || $0.contains(" on") },
            blocksAll: b.map { $0.contains("enabled") && !$0.contains("disabled") })
    }

    static func listeners() async -> [Listener] {
        // netstat prints nothing when run from an app on recent macOS; lsof works but only
        // sees your own processes, so system sharing services are found by a local probe.
        var sockets: [Socket] = []
        if let text = await output("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]) {
            sockets = parseLsof(text)
        }
        if sockets.isEmpty, let text = await output("/usr/sbin/netstat", ["-anv", "-p", "tcp"]) {
            sockets = parseNetstat(text)
        }
        let seen = Set(sockets.map(\.port))
        let system = await Task.detached {
            remoteServicePorts.filter { !seen.contains($0) && acceptsLocalConnection(port: $0) }
        }.value
        let probed = system.map { port in
            Listener(
                port: port, process: KnownService.forPort(port)?.name ?? "System service", pid: 0, isExposed: true,
                addresses: ["*"])
        }
        return
            (merge(sockets).map { listener in
                // lsof and netstat shorten names; the executable path has the full one.
                guard let name = executableName(pid: listener.pid) else { return listener }
                return Listener(
                    port: listener.port, process: name, pid: listener.pid, isExposed: listener.isExposed,
                    addresses: listener.addresses)
            } + probed).sorted { ($0.port, $0.process) < ($1.port, $1.process) }
    }

    /// Sharing services run as root, out of lsof's sight.
    static let remoteServicePorts = [22, 445, 548, 3283, 5900]

    private static func acceptsLocalConnection(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func proxy() async -> Proxy {
        guard let text = await output("/usr/sbin/scutil", ["--proxy"]) else { return Proxy() }
        return parseProxy(text)
    }

    private static func output(_ tool: String, _ arguments: [String]) async -> String? {
        guard let result = try? await ProcessRunner.run(tool, arguments, timeout: 10) else { return nil }
        let text = String(decoding: result.stdout, as: UTF8.self) + result.stderr
        return text.isEmpty ? nil : text
    }

    // MARK: - Parsing

    struct Socket: Sendable, Equatable {
        let address: String
        let port: Int
        let process: String
        let pid: Int32
    }

    private static let listenLine = try? NSRegularExpression(
        pattern: #"^tcp\S*\s+\d+\s+\d+\s+(\S+)\s+\S+\s+LISTEN\s+\d+\s+\d+\s+\d+\s+\d+\s+(.+?):(\d+)\s"#)

    /// LISTEN rows of `netstat -anv -p tcp`. Process names may contain spaces.
    static func parseNetstat(_ text: String) -> [Socket] {
        text.split(separator: "\n").compactMap { line in
            let line = String(line)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = listenLine?.firstMatch(in: line, range: range),
                let local = Range(match.range(at: 1), in: line),
                let name = Range(match.range(at: 2), in: line),
                let pid = Range(match.range(at: 3), in: line)
            else { return nil }
            let endpoint = String(line[local])
            guard let dot = endpoint.lastIndex(of: "."), let port = Int(endpoint[endpoint.index(after: dot)...])
            else { return nil }
            return Socket(
                address: String(endpoint[..<dot]), port: port,
                process: line[name].trimmingCharacters(in: .whitespaces), pid: Int32(line[pid]) ?? 0)
        }
    }

    /// `lsof -F pcn` output: "p<pid>", "c<command>", then one "n<address:port>" per socket.
    static func parseLsof(_ text: String) -> [Socket] {
        var sockets: [Socket] = []
        var pid: Int32 = 0
        var command = ""
        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...])
                else { continue }
                let address = value[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                sockets.append(Socket(address: address, port: port, process: command, pid: pid))
            default: break
            }
        }
        return sockets
    }

    static func isLoopback(_ address: String) -> Bool {
        address.hasPrefix("127.") || address == "::1" || address == "localhost" || address.hasPrefix("fe80::1%lo")
    }

    /// One row per process and port; exposed when any of its sockets is.
    static func merge(_ sockets: [Socket]) -> [Listener] {
        let groups = Dictionary(grouping: sockets) { "\($0.port)-\($0.pid)" }
        return groups.values.compactMap { group -> Listener? in
            guard let first = group.first else { return nil }
            let addresses = Array(Set(group.map(\.address))).sorted()
            return Listener(
                port: first.port, process: first.process, pid: first.pid,
                isExposed: addresses.contains { !isLoopback($0) }, addresses: addresses)
        }
        .sorted { ($0.port, $0.process) < ($1.port, $1.process) }
    }

    static func parseProxy(_ text: String) -> Proxy {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        var proxy = Proxy()
        for kind in ["HTTP", "HTTPS", "SOCKS"] where values["\(kind)Enable"] == "1" {
            if let host = values["\(kind)Proxy"] {
                proxy.servers.append("\(kind) \(host)" + (values["\(kind)Port"].map { ":\($0)" } ?? ""))
            }
        }
        if values["ProxyAutoConfigEnable"] == "1" { proxy.autoConfigURL = values["ProxyAutoConfigURLString"] }
        return proxy
    }

    private static func executableName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        // "/Applications/Visual Studio Code.app/Contents/…/Code Helper" → "Code Helper (Visual Studio Code)"
        let name = (path as NSString).lastPathComponent
        if let app = path.components(separatedBy: "/").first(where: { $0.hasSuffix(".app") }) {
            let appName = String(app.dropLast(4))
            return appName == name ? name : "\(name) (\(appName))"
        }
        return name
    }

    // MARK: - Findings

    static let sharingSettings = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")!
    static let firewallSettings = URL(
        string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")!

    static func findings(firewall: Firewall, listeners: [Listener], proxy: Proxy) -> [HealthFinding] {
        var findings: [HealthFinding] = []
        let firewallOn = firewall.enabled ?? true

        if let enabled = firewall.enabled {
            findings.append(
                enabled
                    ? HealthFinding(
                        id: "firewall", severity: .ok, title: "Firewall is on", detail: "", symbol: "flame")
                    : HealthFinding(
                        id: "firewall", severity: .warning, title: "Firewall is off",
                        detail: "Any app can accept connections from other devices on your network without asking.",
                        symbol: "flame",
                        command: "sudo \(firewallTool) --setglobalstate on", settingsURL: firewallSettings))
        }
        if firewall.enabled == true, firewall.stealth == false {
            findings.append(
                HealthFinding(
                    id: "stealth", severity: .info, title: "Stealth mode is off",
                    detail: "This Mac answers pings and probes from the network. Stealth mode makes it harder to find.",
                    symbol: "eye.slash", command: "sudo \(firewallTool) --setstealthmode on",
                    settingsURL: firewallSettings))
        }

        for listener in listeners where listener.isExposed {
            guard let service = listener.service else { continue }
            switch service.kind {
            case .remoteAccess:
                findings.append(
                    HealthFinding(
                        id: "listen-\(listener.id)", severity: firewallOn ? .info : .warning,
                        title: "\(service.name) is open to your network",
                        detail: "Other devices can try to sign in to this Mac on port \(listener.port)."
                            + " Turn it off in Sharing settings if you don't use it.",
                        symbol: "rectangle.on.rectangle",
                        subtitle: listener.process == service.name ? nil : listener.process,
                        settingsURL: sharingSettings))
            case .development where !firewallOn:
                findings.append(
                    HealthFinding(
                        id: "listen-\(listener.id)", severity: .info,
                        title: "\(service.name) on port \(listener.port) is open to your network",
                        detail: "\(listener.process) listens on every network interface. Bind it to 127.0.0.1"
                            + " unless you test from another device.",
                        symbol: "chevron.left.forwardslash.chevron.right",
                        subtitle: listener.addresses.joined(separator: ", ")))
            default:
                break
            }
        }

        if !proxy.isEmpty {
            findings.append(
                HealthFinding(
                    id: "proxy", severity: .warning, title: "Web traffic goes through a proxy",
                    detail: "Make sure you or your organization set this up — a proxy can read unencrypted traffic.",
                    symbol: "arrow.triangle.swap",
                    subtitle: (proxy.servers + [proxy.autoConfigURL].compactMap { $0 }).joined(separator: ", "),
                    settingsURL: URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")))
        }
        return findings.sorted { ($0.severity, $0.title) < ($1.severity, $1.title) }
    }
}
