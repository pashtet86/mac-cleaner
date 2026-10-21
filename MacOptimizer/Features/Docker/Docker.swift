import Foundation

nonisolated struct DockerUsage: Identifiable, Sendable, Hashable {
    let type: String
    let totalCount: Int
    let active: Int
    let size: Int64
    let reclaimable: Int64
    var id: String { type }
}

/// Fixed allowlist of Docker operations. Volumes are never pruned.
nonisolated enum DockerAction: String, CaseIterable, Identifiable, Sendable {
    case buildCache, stoppedContainers, danglingImages, unusedImages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buildCache: "Build cache"
        case .stoppedContainers: "Stopped containers"
        case .danglingImages: "Dangling images"
        case .unusedImages: "Unused images"
        }
    }

    var detail: String {
        switch self {
        case .buildCache: "Layers cached by docker build. Next builds are slower once."
        case .stoppedContainers: "Containers that are not running. Their writable layers are removed."
        case .danglingImages: "Untagged image layers left behind by rebuilds."
        case .unusedImages: "Every image not used by a container. They are pulled again on demand."
        }
    }

    var symbol: String {
        switch self {
        case .buildCache: "hammer"
        case .stoppedContainers: "stop.circle"
        case .danglingImages: "square.dashed"
        case .unusedImages: "square.stack.3d.down.right"
        }
    }

    /// Which `docker system df` row estimates the space this action frees.
    var usageType: String? {
        switch self {
        case .buildCache: "Build Cache"
        case .stoppedContainers: "Containers"
        case .unusedImages: "Images"
        case .danglingImages: nil
        }
    }

    fileprivate var arguments: [String] {
        switch self {
        case .buildCache: ["builder", "prune", "--force"]
        case .stoppedContainers: ["container", "prune", "--force"]
        case .danglingImages: ["image", "prune", "--force"]
        case .unusedImages: ["image", "prune", "--all", "--force"]
        }
    }
}

nonisolated enum Docker {
    static let appURL = URL(fileURLWithPath: "/Applications/Docker.app")

    static var executable: String? {
        [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    enum Status: Sendable {
        case notInstalled
        case notRunning
        case running([DockerUsage])
    }

    static func status() async -> Status {
        guard let docker = executable else { return .notInstalled }
        guard let result = try? await ProcessRunner.run(docker, ["system", "df", "--format", "json"]),
            result.succeeded
        else { return .notRunning }
        // One JSON object per line.
        let rows = String(decoding: result.stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> DockerUsage? in
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                    let type = object["Type"] as? String
                else { return nil }
                return DockerUsage(
                    type: type,
                    totalCount: Int(object["TotalCount"] as? String ?? "") ?? 0,
                    active: Int(object["Active"] as? String ?? "") ?? 0,
                    size: parseSize(object["Size"] as? String ?? ""),
                    reclaimable: parseSize(object["Reclaimable"] as? String ?? "")
                )
            }
        return .running(rows)
    }

    static func perform(_ action: DockerAction) async throws {
        guard let docker = executable else { return }
        try await ProcessRunner.checked(docker, action.arguments)
    }

    /// Parses Docker's decimal sizes such as "1.234GB (50%)", "12.5kB", "0B".
    static func parseSize(_ text: String) -> Int64 {
        let token = text.split(separator: " ").first.map(String.init) ?? ""
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (suffix, multiplier) in units where token.hasSuffix(suffix) {
            let number = Double(token.dropLast(suffix.count)) ?? 0
            return Int64(number * multiplier)
        }
        return 0
    }
}
