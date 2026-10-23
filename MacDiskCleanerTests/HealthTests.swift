import Foundation
import Testing

@testable import MacDiskCleaner

@Suite("Network parsing")
struct NetworkParsingTests {
    private let netstat = """
        Active Internet connections (including servers)
        Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options
        tcp4       0      0  192.168.0.74.53883     54.145.182.64.443      ESTABLISHED        15624         4911  131072  132352 Brave Browser He:1782   00102 00000008
        tcp46      0      0  *.5900                 *.*                    LISTEN                 0            0  131072  131072      screensharingd:669    00100 00000006
        tcp6       0      0  *.5900                 *.*                    LISTEN                 0            0  131072  131072      screensharingd:669    00100 00000006
        tcp4       0      0  127.0.0.1.16907        *.*                    LISTEN                 0            0  131072  131072 Code Helper (Plu:53746  00100 00000106
        tcp6       0      0  ::1.8000               *.*                    LISTEN                 0            0  131072  131072           Python:49110  00000 00000006
        tcp4       0      0  127.0.0.1.8000         *.*                    LISTEN                 0            0  131072  131072           Python:49110  00000 00000006
        """

    @Test("Reads only listening sockets, with process names that contain spaces")
    func listeningSockets() {
        let sockets = NetworkScanner.parseNetstat(netstat)
        #expect(sockets.count == 5)
        #expect(sockets.first == .init(address: "*", port: 5900, process: "screensharingd", pid: 669))
        #expect(sockets.contains(.init(address: "127.0.0.1", port: 16907, process: "Code Helper (Plu", pid: 53746)))
        #expect(sockets.contains(.init(address: "::1", port: 8000, process: "Python", pid: 49110)))
    }

    @Test("Merges IPv4 and IPv6 and separates exposed from loopback")
    func merging() {
        let listeners = NetworkScanner.merge(NetworkScanner.parseNetstat(netstat))
        #expect(listeners.map(\.port) == [5900, 8000, 16907])
        #expect(listeners.filter(\.isExposed).map(\.port) == [5900])
        #expect(listeners.first { $0.port == 8000 }?.addresses == ["127.0.0.1", "::1"])
    }

    @Test("Reads lsof field output, including IPv6 brackets")
    func lsofFields() {
        let sockets = NetworkScanner.parseLsof(
            "p658\ncControlCenter\nn*:7000\nn*:7000\np49110\ncPython\nn127.0.0.1:8000\nn[::1]:8000\n")
        #expect(sockets.count == 4)
        #expect(sockets.first == .init(address: "*", port: 7000, process: "ControlCenter", pid: 658))
        #expect(sockets.last == .init(address: "::1", port: 8000, process: "Python", pid: 49110))
        let listeners = NetworkScanner.merge(sockets)
        #expect(listeners.map(\.isExposed) == [true, false])
    }

    @Test("Reports only proxies that are switched on")
    func proxies() {
        let proxy = NetworkScanner.parseProxy(
            """
            <dictionary> {
              HTTPEnable : 1
              HTTPPort : 8080
              HTTPProxy : proxy.example.test
              HTTPSEnable : 0
              HTTPSProxy : ignored.example.test
            }
            """)
        #expect(proxy.servers == ["HTTP proxy.example.test:8080"])
        #expect(proxy.autoConfigURL == nil)
        #expect(NetworkScanner.parseProxy("<dictionary> {\n  FTPPassive : 1\n}").isEmpty)
    }

    @Test("Remote access needs a look only while the firewall is off")
    func firewallAndRemoteAccess() {
        let screen = Listener(port: 5900, process: "screensharingd", pid: 1, isExposed: true, addresses: ["*"])
        let off = NetworkScanner.findings(
            firewall: .init(enabled: false, stealth: false), listeners: [screen], proxy: .init())
        #expect(off.filter(\.severity.needsAttention).count == 2)
        #expect(off.first?.severity == .warning)

        let on = NetworkScanner.findings(
            firewall: .init(enabled: true, stealth: true), listeners: [screen], proxy: .init())
        #expect(on.filter(\.severity.needsAttention).isEmpty)
    }
}

@Suite("Security scanner")
struct SecurityScannerTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func plist(_ contents: [String: Any]) throws -> URL {
        let url = folder.appending(path: "\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    @Test("Temp and shared folders, and any folder anyone can write to")
    func worldWritable() throws {
        #expect(SecurityScanner.isInWorldWritableFolder("/var/tmp/readPowerLog.sh"))
        #expect(SecurityScanner.isInWorldWritableFolder("/private/tmp/x"))
        #expect(SecurityScanner.isInWorldWritableFolder("/Users/Shared/tool"))
        #expect(!SecurityScanner.isInWorldWritableFolder("/usr/bin/true"))

        let open = folder.appending(path: "open")
        try FileManager.default.createDirectory(at: open, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: open.path)
        #expect(SecurityScanner.isInWorldWritableFolder(open.appending(path: "tool").path))
    }

    @Test("A root daemon running a script from /var/tmp is critical and never removed by the app")
    func scriptInTemp() throws {
        let url = try plist(["Label": "vendor.power", "ProgramArguments": ["/bin/sh", "/var/tmp/readPowerLog.sh"]])
        let item = try #require(SecurityScanner.item(at: url, domain: .daemon))
        #expect(item.program == "/var/tmp/readPowerLog.sh")
        #expect(item.fromWorldWritableFolder)

        let finding = try #require(SecurityScanner.findings(protections: .init(), items: [item]).first)
        #expect(finding.severity == .critical)
        #expect(finding.command?.hasPrefix("sudo launchctl bootout system") == true)
        #expect(finding.trashablePlist == nil)
    }

    @Test("A missing program is a tidy-up, and your own agent can go to the Trash")
    func missingProgram() throws {
        let url = try plist(["Label": "com.vendor.updater", "Program": folder.appending(path: "gone").path])
        let item = try #require(SecurityScanner.item(at: url, domain: .userAgent))
        #expect(item.signer == .missing)
        let finding = try #require(SecurityScanner.findings(protections: .init(), items: [item]).first)
        #expect(finding.severity == .info)
        #expect(finding.trashablePlist == url)
        #expect(!finding.severity.needsAttention)
    }

    @Test("Apple's own binaries are recognized and raise nothing")
    func appleBinary() throws {
        let url = try plist(["Label": "com.example.true", "ProgramArguments": ["/usr/bin/true"]])
        let item = try #require(SecurityScanner.item(at: url, domain: .userAgent))
        #expect(item.signer == .apple)
        #expect(SecurityScanner.findings(protections: .init(), items: [item]).isEmpty)
    }

    @Test("Protections that are off rank first")
    func protectionsOrder() {
        let findings = SecurityScanner.findings(
            protections: .init(sip: true, gatekeeper: false, fileVault: false, managedByMDM: false), items: [])
        #expect(findings.map(\.severity) == [.critical, .warning, .ok])
        #expect(findings.first?.id == "gatekeeper")
    }
}
