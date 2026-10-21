import Foundation
import IOKit

/// Read-only access to the System Management Controller (AppleSMC user client).
/// No root needed for reads. Used for fan speeds; nothing is ever written.
nonisolated final class SMC: @unchecked Sendable {
    // C layout of SMCKeyData_t — 80 bytes. The explicit padding keeps Swift from packing
    // later fields into `KeyInfo`'s tail padding, which the kernel would misread.
    private struct Version {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0
    }
    private struct PowerLimit {
        var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0
    }
    private struct KeyInfo {
        var size: UInt32 = 0, type: UInt32 = 0, attributes: UInt8 = 0, padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }
    private struct Message {
        var key: UInt32 = 0
        var version = Version()
        var limit = PowerLimit()
        var info = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes:
            (
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8
            ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 {
        case readBytes = 5
        case readKeyInfo = 9
    }

    private let connection: io_connect_t
    private let lock = NSLock()

    init?() {
        guard MemoryLayout<Message>.stride == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    /// Decoded numeric value of a key, for the types the fan keys use.
    func number(_ key: String) -> Double? {
        guard let (type, bytes) = read(key) else { return nil }
        switch type {
        case "ui8 " where bytes.count >= 1:
            return Double(bytes[0])
        case "flt " where bytes.count == 4:
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "fpe2" where bytes.count == 2:
            // Intel Macs: unsigned fixed point, 14 integer bits and 2 fraction bits, big-endian.
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        default:
            return nil
        }
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        lock.withLock {
            var request = Message()
            request.key = Self.code(key)
            request.command = Command.readKeyInfo.rawValue
            guard let info = call(&request) else { return nil }

            request = Message()
            request.key = Self.code(key)
            request.info.size = info.info.size
            request.command = Command.readBytes.rawValue
            guard let reply = call(&request) else { return nil }
            let bytes = withUnsafeBytes(of: reply.bytes) { Array($0.prefix(Int(info.info.size))) }
            return (Self.string(info.info.type), bytes)
        }
    }

    private func call(_ input: inout Message) -> Message? {
        var output = Message()
        var size = MemoryLayout<Message>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Message>.stride, &output, &size)
        return result == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private static func code(_ key: String) -> UInt32 { key.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private static func string(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }, encoding: .ascii) ?? ""
    }
}

/// Fan speeds from the SMC. `nil` when the Mac has no fans (MacBook Air) or SMC is unreadable.
nonisolated struct FanReader: Sendable {
    let smc: SMC
    let count: Int

    init?() {
        guard let smc = SMC(), let count = smc.number("FNum"), count > 0 else { return nil }
        self.smc = smc
        self.count = Int(count)
    }

    /// Current speed of every fan, in RPM.
    func speeds() -> [Double] {
        (0..<count).compactMap { smc.number("F\($0)Ac") }
    }
}
