import Foundation

/// Reads temperature sensors through IOKit's HID event system.
///
/// This is private API (the same one Stats and iStat Menus use) — fine outside the App Store,
/// but Apple may change it. Every symbol is looked up at runtime: if anything is missing,
/// `reading()` returns nil and the UI falls back to the public `ProcessInfo.thermalState`.
nonisolated final class ThermalSensors: @unchecked Sendable {
    struct Reading: Sendable {
        /// Hottest CPU die sensor.
        let cpu: Double?
        /// SSD (NAND) temperature.
        let ssd: Double?
    }

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    /// Readings outside this range are other quantities exposed on the same page (e.g. "tdev").
    private static let plausible = 1.0...130.0

    private let lock = NSLock()
    /// The services are only valid while their client lives — keep it for the object's lifetime.
    private let client: AnyObject
    private let copyProperty: CopyPropertyFn
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private let services: [AnyObject]

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", as: CreateFn.self),
            let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
            let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self),
            let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self),
            let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEventFn.self),
            let getFloat = symbol("IOHIDEventGetFloatValue", as: GetFloatFn.self),
            let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return nil }

        // Apple vendor page 0xff00, usage 5: temperature sensors.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject], !services.isEmpty else {
            return nil
        }
        self.client = client
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.getFloat = getFloat
        self.services = services
    }

    func reading() -> Reading? {
        lock.withLock {
            var cpu: [Double] = []
            var ssd: [Double] = []
            for service in services {
                guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                    let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue()
                else { continue }
                let value = getFloat(event, Int32(Self.temperatureEvent << 16))
                guard Self.plausible.contains(value) else { continue }
                if name.hasPrefix("PMU tdie") {
                    cpu.append(value)
                } else if name.hasPrefix("NAND") {
                    ssd.append(value)
                }
            }
            guard !cpu.isEmpty || !ssd.isEmpty else { return nil }
            return Reading(cpu: cpu.max(), ssd: ssd.max())
        }
    }
}
