public enum CategoryBodyState: Sendable, Equatable {
    case empty
    case emptyMismatch
    case grouped
    case table

    public static func resolve(itemCount: Int, groupRows: [Int]?) -> CategoryBodyState {
        guard itemCount > 0 else { return .empty }
        guard let groupRows, !groupRows.isEmpty else { return .table }
        return groupRows.contains { $0 > 0 } ? .grouped : .emptyMismatch
    }
}
