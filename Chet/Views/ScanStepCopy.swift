import ChetCore

/// Short names for scan steps. `ScanStep.title` stays in the core for logs and tests;
/// the interface uses these.
enum ScanStepCopy {
    static func title(_ step: ScanStep) -> String {
        switch step {
        case .rules: "Caches and logs"
        case .index: "Measuring folders"
        case .largeFiles: "Big files"
        case .duplicates: "Duplicate files"
        case .leftovers: "Leftover app files"
        case .photos: "Similar photos"
        case .videos: "Similar videos"
        case .snapshots: "Time Machine snapshots"
        }
    }
}
