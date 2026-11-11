import Testing

@testable import ChetCore

struct CategoryBodyStateTests {
    @Test func nothingCountedShowsEmptyState() {
        #expect(CategoryBodyState.resolve(itemCount: 0, groupRows: nil) == .empty)
        #expect(CategoryBodyState.resolve(itemCount: 0, groupRows: []) == .empty)
        #expect(CategoryBodyState.resolve(itemCount: 0, groupRows: [3]) == .empty)
    }

    @Test func countedItemsWithoutGroupEntryRenderTable() {
        #expect(CategoryBodyState.resolve(itemCount: 100, groupRows: nil) == .table)
    }

    @Test func countedItemsWithEmptyGroupArrayRenderTable() {
        #expect(CategoryBodyState.resolve(itemCount: 100, groupRows: []) == .table)
    }

    @Test func countedItemsWithGroupRowsRenderGroups() {
        #expect(CategoryBodyState.resolve(itemCount: 100, groupRows: [8, 5]) == .grouped)
        #expect(CategoryBodyState.resolve(itemCount: 100, groupRows: [0, 5]) == .grouped)
    }

    @Test func countedItemsWithNoGroupRowsShowReasonedEmptyState() {
        #expect(CategoryBodyState.resolve(itemCount: 100, groupRows: [0, 0]) == .emptyMismatch)
    }
}
