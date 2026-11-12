import Foundation

/// Every reason a path or a batch can be refused. The raw values are the strings the
/// safety policy, the cleaner, and the storage trasher already report.
public enum RefusalReason: String, Codable, Sendable, CaseIterable {
    case excludedFolder = "excluded folder"
    case outsideHome = "outside home"
    case containerFolder = "container folder"
    case protectedFolder = "protected folder"
    case gitRepository = "git repository"
    case appBundle = "app bundle"
    case photosLibrary = "Photos library"
    case symlink = "symlink"
    case mountPoint = "mount point"

    case missing
    case changed
    case appRunning
    case localState
    case informational

    case batchEmpty
    case batchTooLarge
    case batchMalformed
    case batchOutsideRoot
}
