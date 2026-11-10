import Foundation
import Testing

@testable import ChetCore

@Suite struct ScanScopeTests {
    @Test func emptyScopeIsEverything() {
        let scope = ScanScope.everywhere
        #expect(!scope.isPartial)
        #expect(scope.needsIndex)
        #expect(ScanStep.allCases.allSatisfy(scope.runs))
    }

    @Test func categorySelectsOnlyItsSteps() {
        let scope = ScanScope(categories: ["browser"])
        #expect(scope.isPartial)
        #expect(scope.runs(.rules))
        #expect(!scope.runs(.index))
        #expect(!scope.needsIndex)
        #expect(!scope.runs(.duplicates))
        #expect(!scope.runs(.snapshots))
    }

    @Test func measurementCategoryPullsTheIndexIn() {
        let scope = ScanScope(categories: ["large-files"])
        #expect(scope.needsIndex)
        #expect(scope.runs(.index))
        #expect(scope.runs(.largeFiles))
        #expect(!scope.runs(.duplicates))
    }

    @Test func restrictedRootsNeedTheIndex() {
        let scope = ScanScope(roots: ["/Users/example/Documents"])
        #expect(scope.needsIndex)
        #expect(scope.runs(.index))
        #expect(scope.runs(.rules))
    }

    @Test func everyCatalogCategoryIsKnown() {
        for rule in Rule.catalog {
            #expect(ScanScope.knownCategories.contains(rule.category))
            #expect(ScanScope(categories: [rule.category]).runs(.rules))
        }
        #expect(ScanScope.knownCategories.contains(UserRule.category))
        #expect(ScanScope.knownCategories.contains("snapshots"))
    }

    @Test func normalizationDropsUnknownIdsAndRelativeRoots() {
        let scope = ScanScope(
            categories: ["browser", "not-a-category"], roots: ["relative/path", "/tmp/../tmp", "/tmp"]
        ).normalized()
        #expect(scope.categories == ["browser"])
        #expect(scope.roots == ["/tmp"])
    }

    @Test func scopeRoundTripsThroughJSON() throws {
        let scope = ScanScope(categories: ["duplicates"], roots: ["/Users/example"])
        let data = try JSONEncoder().encode(scope)
        #expect(try JSONDecoder().decode(ScanScope.self, from: data) == scope)
    }
}
