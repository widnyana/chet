import Foundation

/// Capacity of a volume, including the purgeable space macOS reclaims on demand. The gap
/// between raw free and purgeable-inclusive free explains why "free space" can look wrong.
struct VolumeCapacity: Sendable, Equatable {
    let name: String
    let total: Int64
    let free: Int64
    let purgeable: Int64

    static func make(name: String, total: Int64, rawFree: Int64, importantFree: Int64) -> VolumeCapacity {
        VolumeCapacity(
            name: name, total: total, free: rawFree, purgeable: max(0, importantFree - rawFree))
    }

    static func current(path: String = "/") -> VolumeCapacity {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey,
        ])
        return make(
            name: values?.volumeLocalizedName ?? "Startup disk",
            total: Int64(values?.volumeTotalCapacity ?? 0),
            rawFree: Int64(values?.volumeAvailableCapacity ?? 0),
            importantFree: values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
