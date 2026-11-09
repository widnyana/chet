import Foundation

/// The user's Trash. Emptying is permanent, so the caller confirms first.
public enum TrashBin {
    public static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    public struct EmptyResult: Sendable, Equatable {
        public var removed = 0
        public var freed: Int64 = 0
        public var failed: [String] = []
    }

    /// Allocated size of the Trash. ponytail: home Trash only, not each volume's .Trashes.
    public static func size(at directory: URL = url) -> Int64 {
        FS.usage(directory.path).size
    }

    /// Permanently removes each top-level item in the Trash and reports what went.
    public static func empty(at directory: URL = url) -> EmptyResult {
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
