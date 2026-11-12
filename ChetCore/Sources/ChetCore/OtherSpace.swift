import Darwin
import Foundation

/// A folder the scan skipped, labeled by why, for the "other space" accounting.
public enum SpaceSkipReason: String, Sendable {
    case user, always, cloud, network

    public var word: String {
        switch self {
        case .user: "Folder left out of the scan"
        case .always: "Folder the scan never reads"
        case .cloud: "Cloud folder"
        case .network: "Network volume"
        }
    }
}

/// What the disk scan cannot see but still takes space on the startup disk: sibling APFS
/// volumes, local snapshots, swap, and folders the scan left out.
public struct OtherSpaceInfo: Sendable {
    public struct Volume: Sendable {
        public let name: String
        public let role: String
        public let size: Int64

        public init(name: String, role: String, size: Int64) {
            self.name = name
            self.role = role
            self.size = size
        }
    }
    public struct Folder: Sendable {
        public let path: String
        public let size: Int64
        public let reason: SpaceSkipReason

        public init(path: String, size: Int64, reason: SpaceSkipReason) {
            self.path = path
            self.size = size
            self.reason = reason
        }
    }

    public var volumes: [Volume] = []
    public var snapshots = 0
    public var swapUsed: Int64 = 0
    public var folders: [Folder] = []
    public var cloudFolders: [String] = []

    public init(
        volumes: [Volume] = [], snapshots: Int = 0, swapUsed: Int64 = 0,
        folders: [Folder] = [], cloudFolders: [String] = []
    ) {
        self.volumes = volumes
        self.snapshots = snapshots
        self.swapUsed = swapUsed
        self.folders = folders
        self.cloudFolders = cloudFolders
    }
}

public enum OtherSpace {
    /// Slow (runs diskutil and tmutil, walks skipped folders): call off the main thread.
    public static func measure(skipped: [(path: String, reason: SpaceSkipReason)]) -> OtherSpaceInfo {
        var info = OtherSpaceInfo()
        info.volumes = siblingVolumes()
        info.snapshots = localSnapshots()
        info.swapUsed = swapUsed()
        for entry in skipped {
            switch entry.reason {
            case .user, .always:
                let size = FS.usage(entry.path).size
                if size > 0 {
                    info.folders.append(.init(path: entry.path, size: size, reason: entry.reason))
                }
            case .cloud:
                info.cloudFolders.append(entry.path)
            case .network:
                break
            }
        }
        info.folders.sort { $0.size > $1.size }
        return info
    }

    /// Volumes in the APFS container of "/" other than System and Data, which the scan covers.
    private static func siblingVolumes() -> [OtherSpaceInfo.Volume] {
        guard
            let infoData = Subprocess.run("/usr/sbin/diskutil", ["info", "-plist", "/"]).okData,
            let info = plist(infoData),
            let container = info["APFSContainerReference"] as? String,
            let listData = Subprocess.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"]).okData,
            let list = plist(listData),
            let containers = list["Containers"] as? [[String: Any]],
            let matched = containers.first(where: { $0["ContainerReference"] as? String == container }),
            let volumes = matched["Volumes"] as? [[String: Any]]
        else { return [] }
        return
            volumes
            .compactMap { volume -> OtherSpaceInfo.Volume? in
                let roles = volume["Roles"] as? [String] ?? []
                if roles.contains("System") || roles.contains("Data") { return nil }
                let size = (volume["CapacityInUse"] as? NSNumber)?.int64Value ?? 0
                guard size > 0 else { return nil }
                return .init(name: volume["Name"] as? String ?? "?", role: roles.first ?? "", size: size)
            }
            .sorted { $0.size > $1.size }
    }

    /// macOS reports the count of local snapshots but not their sizes before deletion.
    private static func localSnapshots() -> Int {
        let result = Subprocess.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        return result.out.split(separator: "\n").filter { $0.hasPrefix("com.apple.") }.count
    }

    private static func swapUsed() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }

    private static func plist(_ data: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }
}

extension Subprocess.Result {
    /// stdout as Data when the command succeeded, else nil, to keep guard chains terse.
    fileprivate var okData: Data? { ok ? Data(out.utf8) : nil }
}
