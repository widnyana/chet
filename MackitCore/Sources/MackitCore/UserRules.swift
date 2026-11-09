import Foundation

/// A folder the user added as a rule of their own. Its direct children become scan items.
public struct UserRule: Identifiable, Codable, Sendable, Equatable {
    public static let category = "user-rules"

    public let id: String
    /// Absolute folder path, as the folder picker returns it.
    public let path: String

    public init(id: String = UUID().uuidString, path: String) {
        self.id = id
        self.path = path
    }

    /// Review and trash: a folder the user chose is user data until they say otherwise.
    public var rule: Rule {
        Rule(
            id: "user-\(id)", category: Self.category, title: name, roots: [path],
            risk: .review, mode: .trash)
    }

    public var name: String {
        (path as NSString).lastPathComponent
    }
}
