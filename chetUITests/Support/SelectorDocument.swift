import Foundation

struct SelectorDocument: Equatable {
    let generatedAt: String?
    let screens: [String: [String]]
    let allIdentifiers: [String]

    init(contentsOf url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SelectorDocumentError.unreadable(path: url.path, detail: error.localizedDescription)
        }
        try self.init(data: data)
    }

    init(data: Data) throws {
        let raw: RawDocument
        do {
            raw = try JSONDecoder().decode(RawDocument.self, from: data)
        } catch let error as DecodingError {
            throw SelectorDocumentError.malformed(
                field: Self.fieldPath(error), detail: Self.detail(error))
        } catch {
            throw SelectorDocumentError.malformed(field: "$", detail: error.localizedDescription)
        }

        var screens: [String: [String]] = [:]
        for (name, screen) in raw.screens {
            let identifiers = screen.selectors.compactMap(\.id).filter { !$0.isEmpty }
            screens[name] = Array(Set(identifiers)).sorted()
        }
        self.generatedAt = raw.generatedAt
        self.screens = screens
        self.allIdentifiers = Array(Set(screens.values.joined())).sorted()
    }

    var screenNames: [String] {
        screens.keys.sorted()
    }

    func identifiers(for screen: String) throws -> [String] {
        guard let identifiers = screens[screen] else {
            throw SelectorDocumentError.unknownScreen(screen, available: screenNames)
        }
        return identifiers
    }

    private struct RawDocument: Decodable {
        let generatedAt: String?
        let screens: [String: RawScreen]
    }

    private struct RawScreen: Decodable {
        let selectors: [RawSelector]
    }

    private struct RawSelector: Decodable {
        let id: String?
    }

    private static func fieldPath(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return path(context.codingPath + [key])
        case .typeMismatch(_, let context), .valueNotFound(_, let context),
            .dataCorrupted(let context):
            return path(context.codingPath)
        default:
            return "$"
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        guard !keys.isEmpty else { return "$" }
        var result = ""
        for key in keys {
            if let index = key.intValue {
                result += "[\(index)]"
            } else if result.isEmpty {
                result = key.stringValue
            } else {
                result += ".\(key.stringValue)"
            }
        }
        return result
    }

    private static func detail(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "missing required field \(key.stringValue)"
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(path(context.codingPath))"
        case .valueNotFound(let type, let context):
            return "expected \(type) at \(path(context.codingPath))"
        case .dataCorrupted(let context):
            return context.debugDescription
        default:
            return error.localizedDescription
        }
    }
}

enum SelectorDocumentError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case unreadable(path: String, detail: String)
    case malformed(field: String, detail: String)
    case unknownScreen(String, available: [String])

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .unreadable(let path, let detail):
            "could not read selector document at \(path): \(detail)"
        case .malformed(let field, let detail):
            "selector document field \(field): \(detail)"
        case .unknownScreen(let screen, let available):
            "selector document has no screen \(screen); screens: \(available.joined(separator: ", "))"
        }
    }
}
