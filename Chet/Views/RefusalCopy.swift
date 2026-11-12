import ChetCore

enum RefusalCopy {
    static func reason(_ reason: RefusalReason) -> String {
        switch reason {
        case .excludedFolder: "In an excluded folder"
        case .outsideHome: "Outside your home folder"
        case .containerFolder: "A folder Chet never removes"
        case .protectedFolder: "Protected by Chet"
        case .gitRepository: "A git repository"
        case .appBundle: "An app bundle"
        case .photosLibrary: "A Photos library"
        case .symlink: "A symbolic link"
        case .mountPoint: "A mounted volume"
        case .missing: "Already gone"
        case .changed: "Changed since the scan"
        case .appRunning: "The app is open"
        case .localState: "A project is using it"
        case .informational: "Listed for information only"
        case .batchEmpty: "Nothing was selected"
        case .batchTooLarge: "Too many items at once"
        case .batchMalformed: "A path was not valid"
        case .batchOutsideRoot: "A path was outside the scan"
        }
    }

    static func detail(_ reason: RefusalReason) -> String? {
        switch reason {
        case .excludedFolder: "This folder is on your excluded list."
        case .outsideHome: "Chet only removes files inside your home folder."
        case .containerFolder: "Chet never removes a whole container folder."
        case .protectedFolder: "macOS keeps this folder, so Chet leaves it alone."
        case .gitRepository: "A git repository holds work you cannot rebuild."
        case .appBundle: "Remove an app from the Apps page instead."
        case .photosLibrary: "A Photos library holds originals you cannot rebuild."
        case .symlink: "A link can point anywhere, so Chet does not follow it."
        case .mountPoint: "A mounted volume is not part of this disk."
        case .missing: "The item was gone before the clean pass reached it."
        case .changed: "The item changed after the scan, so Chet left it alone."
        case .appRunning: "Quit the app, then scan again."
        case .localState: "Terraform state cannot be downloaded again."
        case .informational: "This item is shown for size only."
        case .batchEmpty: "Select at least one item."
        case .batchTooLarge: "Clean in smaller groups."
        case .batchMalformed: "The selection held a path Chet cannot check."
        case .batchOutsideRoot: "The selection held a path outside the scan."
        }
    }

    static func restore(_ reason: RestoreRefusal) -> String {
        switch reason {
        case .trashedItemMissing: "The Trash copy is gone"
        case .originalPathOccupied: "Something else is at the original path"
        case .parentMissing: "The original folder is gone"
        case .outsideHome: "The original path is outside your home folder"
        case .nameMismatch: "The file name does not match"
        }
    }
}
