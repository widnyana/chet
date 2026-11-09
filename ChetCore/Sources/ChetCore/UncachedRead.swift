import Darwin
import Foundation

extension FileHandle {
    /// Opens a file for reading without filling the system file cache (`F_NOCACHE`), so hashing
    /// many gigabytes does not push other apps' memory out.
    static func uncached(_ url: URL) throws -> FileHandle {
        let handle = try FileHandle(forReadingFrom: url)
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        return handle
    }
}
