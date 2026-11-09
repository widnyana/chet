import Foundation

/// A folder the user added to clean. Its direct children become scan items, except the names
/// in `keepNames`, which the scan never lists and never deletes.
public struct UserRule: Identifiable, Codable, Sendable, Equatable {
    public static let category = "user-rules"

    public let id: String
    /// Absolute folder path, as the folder picker returns it.
    public let path: String
    /// Direct-child names the scan never lists and never deletes: the user's keep-forever list.
    public var keepNames: [String]

    public init(id: String = UUID().uuidString, path: String, keepNames: [String] = []) {
        self.id = id
        self.path = path
        self.keepNames = keepNames
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, keepNames
    }

    // Rules stored before keepNames existed carry only id and path, so default the list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        keepNames = try container.decodeIfPresent([String].self, forKey: .keepNames) ?? []
    }

    /// Review and trash: a folder the user chose is user data until they say otherwise.
    public var rule: Rule {
        Rule(
            id: "user-\(id)", category: Self.category, title: name, roots: [path],
            risk: .review, mode: .trash, excluded: Set(keepNames))
    }

    public var name: String {
        (path as NSString).lastPathComponent
    }
}
