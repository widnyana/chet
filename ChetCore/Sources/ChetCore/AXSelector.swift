public enum AXTermKey: String, Sendable {
    case id
    case role
    case desc
    case description
    case title
    case value
    case enabled
    case contains
}

public struct AXTerm: Equatable, Sendable {
    public let key: AXTermKey?
    public let value: String

    public init(key: AXTermKey?, value: String) {
        self.key = key
        self.value = value
    }
}

public struct AXSelector: Equatable, Sendable {
    public let terms: [AXTerm]

    public init(_ operands: [String]) {
        terms = operands.map { operand in
            guard let separator = operand.firstIndex(of: "=") else {
                return AXTerm(key: .contains, value: operand)
            }
            let key = operand[..<separator].lowercased()
            let value = operand[operand.index(after: separator)...]
            return AXTerm(key: AXTermKey(rawValue: key), value: String(value))
        }
    }

    public var isEmpty: Bool { terms.isEmpty }

    public func matches(
        id: String = "",
        role: String = "",
        desc: String = "",
        title: String = "",
        value: String = "",
        enabled: Bool? = nil
    ) -> Bool {
        terms.allSatisfy { term in
            switch term.key {
            case .id?: id == term.value
            case .role?: role == term.value
            case .desc?, .description?: desc == term.value
            case .title?: title == term.value
            case .value?: value == term.value
            case .enabled?: enabledMatches(term.value, enabled)
            case .contains?:
                "\(id) \(role) \(desc) \(title) \(value)".lowercased()
                    .contains(term.value.lowercased())
            case nil: false
            }
        }
    }

    private func enabledMatches(_ raw: String, _ enabled: Bool?) -> Bool {
        guard let enabled else { return false }
        switch raw.lowercased() {
        case "true", "1": return enabled
        case "false", "0": return !enabled
        default: return false
        }
    }
}
