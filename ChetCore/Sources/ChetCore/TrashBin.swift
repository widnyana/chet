import Foundation

/// The user's Trash. Emptying is permanent, so the caller confirms first.
enum TrashBin {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    struct EmptyResult: Equatable {
        var removed = 0
        var freed: Int64 = 0
        var failed: [String] = []
    }

    /// Allocated size of the Trash. ponytail: home Trash only, not each volume's .Trashes.
    static func size(at directory: URL = url) -> Int64 {
        FS.usage(directory.path).size
    }

    /// Permanently removes each top-level item in the Trash and reports what went.
    static func empty(at directory: URL = url) -> EmptyResult {
        var result = EmptyResult()
        let fileManager = FileManager.default
        for name in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] {
            let item = directory.appendingPathComponent(name)
            let bytes = FS.usage(item.path).size
            do {
                try fileManager.removeItem(at: item)
                result.removed += 1
                result.freed += bytes
            } catch {
                result.failed.append(name)
            }
        }
        return result
    }
}
