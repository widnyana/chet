import Foundation

public struct CoverageReport: Codable, Sendable, Equatable {
    public struct Bucket: Codable, Sendable, Equatable {
        public let label: String
        public let bytes: Int64
        public let reason: String

        public init(label: String, bytes: Int64, reason: String) {
            self.label = label
            self.bytes = bytes
            self.reason = reason
        }
    }

    public let used: Int64
    public let scanned: Int64
    public let hidden: [Bucket]
    public let excluded: [Bucket]
    public let unaccounted: Int64

    public init(used: Int64, scanned: Int64, hidden: [Bucket], excluded: [Bucket], unaccounted: Int64) {
        self.used = used
        self.scanned = scanned
        self.hidden = hidden
        self.excluded = excluded
        self.unaccounted = unaccounted
    }
}

public enum CoverageAccounting {
    public static func measure(
        scannedBytes: Int64, capacity: VolumeCapacity, otherSpace: OtherSpaceInfo
    ) -> CoverageReport {
        let used = max(0, capacity.total - capacity.free)

        var hidden: [CoverageReport.Bucket] = []
        for volume in otherSpace.volumes {
            hidden.append(
                .init(
                    label: volume.name, bytes: volume.size,
                    reason: "Separate volume in the same APFS container"))
        }
        if otherSpace.swapUsed > 0 {
            hidden.append(.init(label: "Swap", bytes: otherSpace.swapUsed, reason: "Swap in use"))
        }
        if otherSpace.snapshots > 0 {
            hidden.append(
                .init(
                    label: "Snapshots", bytes: 0,
                    reason: "macOS reports the size only when deleted"))
        }

        var excluded: [CoverageReport.Bucket] = []
        for folder in otherSpace.folders {
            excluded.append(
                .init(label: folder.path, bytes: folder.size, reason: folder.reason.word))
        }
        for path in otherSpace.cloudFolders {
            excluded.append(
                .init(label: path, bytes: 0, reason: "Cloud folder, contents not downloaded"))
        }

        let hiddenBytes = hidden.reduce(Int64(0)) { $0 + $1.bytes }
        let excludedBytes = excluded.reduce(Int64(0)) { $0 + $1.bytes }
        let unaccounted = max(0, used - scannedBytes - hiddenBytes - excludedBytes)
        return CoverageReport(
            used: used, scanned: scannedBytes, hidden: hidden, excluded: excluded,
            unaccounted: unaccounted)
    }
}
