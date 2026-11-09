import ChetCore

/// How a category is grouped on Home and in the sidebar. The list is split by what
/// the user has to decide, not by which scanner produced the item.
enum CategorySection {
    case safe, review, informational
}

/// The user-facing name, group, and one-line reason for every category id. The core
/// keeps its own titles for logs and tests; this table is what the interface shows.
enum CategoryCopy {
    static func title(_ id: String, fallback: String) -> String {
        copy[id]?.title ?? fallback
    }

    static func section(_ id: String, risk: Risk?) -> CategorySection {
        if let known = copy[id]?.section { return known }
        switch risk {
        case .safe: return .safe
        case .informational: return .informational
        default: return .review
        }
    }

    static func explanation(_ id: String) -> String {
        copy[id]?.explanation ?? ""
    }

    private struct Entry {
        let title: String
        let section: CategorySection
        let explanation: String
    }

    private static let copy: [String: Entry] = [
        "trash": Entry(
            title: "Trash", section: .safe,
            explanation: "Files already in the Trash."),
        "caches": Entry(
            title: "App caches", section: .safe,
            explanation: "Apps rebuild these files when they need them."),
        "logs": Entry(
            title: "Logs", section: .safe,
            explanation: "Old logs and crash reports. Apps recreate them."),
        "xcode": Entry(
            title: "Xcode files", section: .safe,
            explanation: "Build files Xcode can rebuild."),
        "xcode-archives": Entry(
            title: "Xcode archives", section: .review,
            explanation: "Old build archives. Check them before removing."),
        "package-caches": Entry(
            title: "Developer caches", section: .safe,
            explanation: "Downloaded packages. The tools fetch them again."),
        "browser": Entry(
            title: "Browser data", section: .safe,
            explanation: "Web caches. History and profiles stay."),
        "mail-downloads": Entry(
            title: "Mail downloads", section: .safe,
            explanation: "Attachments Mail saved to open them."),
        "installers": Entry(
            title: "Old installers", section: .review,
            explanation: "Installers you already used, older than 30 days."),
        "ios-backups": Entry(
            title: "iPhone and iPad backups", section: .review,
            explanation: "Finder backups of your devices."),
        "tagged-caches": Entry(
            title: "Tagged cache folders", section: .safe,
            explanation: "Folders tagged as cache. Check them before removing."),
        "duplicates": Entry(
            title: "Duplicate files", section: .review,
            explanation: "Extra copies of files. One copy stays."),
        "large-files": Entry(
            title: "Large files", section: .review,
            explanation: "Large files, and large files left untouched for a long time."),
        "leftovers": Entry(
            title: "Leftover app files", section: .review,
            explanation: "Data left by apps you removed."),
        "dev-garbage": Entry(
            title: "Project build files", section: .review,
            explanation: "Build folders projects can recreate."),
        "user-rules": Entry(
            title: "Your folders", section: .review,
            explanation: "Folders you added. Check before removing."),
        "similar-photos": Entry(
            title: "Similar photos", section: .review,
            explanation: "Copies and near-copies. One photo stays."),
        "blurry-photos": Entry(
            title: "Blurry photos", section: .review,
            explanation: "Photos with very little detail."),
        "similar-videos": Entry(
            title: "Similar videos", section: .review,
            explanation: "Copies and re-encoded videos. One video stays."),
        "snapshots": Entry(
            title: "Time Machine snapshots", section: .review,
            explanation: "Temporary Time Machine copies on this disk."),
        "nix": Entry(
            title: "Nix files", section: .informational,
            explanation: "Nix manages these files. Chet leaves them alone."),
    ]
}
