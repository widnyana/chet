public enum HomeState: Sendable, Equatable, CaseIterable {
    case neverScanned, scanning, unreadable, measuredEmpty, hasFindings

    public static func resolve(
        isScanning: Bool,
        hasScanned: Bool,
        didFinishScan: Bool,
        totalBytes: Int64,
        blockingReadErrorCount: Int,
        needsFullDiskAccess: Bool
    ) -> HomeState {
        if isScanning { return .scanning }
        if !hasScanned { return .neverScanned }
        if !didFinishScan || blockingReadErrorCount > 0 || needsFullDiskAccess {
            return .unreadable
        }
        return totalBytes > 0 ? .hasFindings : .measuredEmpty
    }

    public var subtitle: String? {
        switch self {
        case .neverScanned: "A clear account of this disk."
        case .scanning: "Scanning. Results appear as they finish."
        case .unreadable: "Chet could not read every folder."
        case .measuredEmpty: "This Mac is tidy."
        case .hasFindings: nil
        }
    }

    public var emptyTitle: String? {
        switch self {
        case .unreadable: "Not everything was read"
        case .measuredEmpty: "Nothing to reclaim"
        case .neverScanned, .scanning, .hasFindings: nil
        }
    }

    public var emptyMessage: String? {
        switch self {
        case .unreadable: "Grant Full Disk Access to include caches, app data, and Mail downloads."
        case .measuredEmpty: "This Mac is tidy."
        case .neverScanned, .scanning, .hasFindings: nil
        }
    }
}
