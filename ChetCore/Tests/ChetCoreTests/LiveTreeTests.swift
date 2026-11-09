import ChetCore
import XCTest

/// The disk map's live-tree merge: rollups arrive post-order (children before parents) and
/// may reference folders whose ancestors haven't been measured yet.
final class LiveTreeTests: XCTestCase {
    private func dir(_ path: String, _ size: Int64, _ children: [FolderNode] = []) -> FolderNode {
        FolderNode(
            url: URL(fileURLWithPath: path, isDirectory: true), size: size,
            children: children.sorted { $0.size > $1.size })
    }

    private let home = "/Users/test"

    func testMergingReplacesSubtreeAtSameURL() {
        let old = dir("\(home)/Documents", 100, [dir("\(home)/Documents/a", 100)])
        let new = dir("\(home)/Documents", 250, [dir("\(home)/Documents/a", 250)])
        let merged = old.merging(new)
        XCTAssertEqual(merged.size, 250)
        XCTAssertEqual(merged.children.first?.size, 250)
    }

    func testMergingAppendsUnknownChild() {
        let tree = dir(home, 100, [dir("\(home)/Desktop", 100)])
        let merged = tree.merging(dir("\(home)/Documents", 50))
        XCTAssertEqual(merged.children.count, 2)
        XCTAssertEqual(merged.children.first?.url.path, "\(home)/Desktop")  // largest first
    }

    func testInsertingDeepRollupUnderExistingChain() {
        let tree = dir(home, 0, [dir("\(home)/Documents", 0, [dir("\(home)/Documents/Projects", 0)])])
        let deep = dir(
            "\(home)/Documents/Projects/chet", 700, [dir("\(home)/Documents/Projects/chet/.build", 700)])
        let merged = tree.inserting(deep)
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.children.first?.children.first?.size, 700)
    }

    func testInsertingDropsRollupWithUnmeasuredParent() {
        // Only Desktop measured so far; a rollup for Movies/Sub must be dropped —
        // Movies' own rollup will carry it later.
        let tree = dir(home, 0, [dir("\(home)/Desktop", 10)])
        XCTAssertNil(tree.inserting(dir("\(home)/Movies/Sub", 5)))
    }

    func testInsertingRootReplacesItself() {
        let tree = dir(home, 0)
        XCTAssertEqual(tree.inserting(dir(home, 42))?.size, 42)
    }

    func testInsertingKeepsChildrenLargestFirst() {
        let tree = dir(home, 0, [dir("\(home)/A", 10), dir("\(home)/B", 20)])
        let merged = tree.inserting(dir("\(home)/C", 30))
        XCTAssertEqual(merged?.children.map(\.size), [30, 20, 10])
    }

    func testInsertingGrowsHomeSizeToCoverChildren() {
        let tree = dir(home, 0, [dir("\(home)/Desktop", 10)])
        let merged = tree.inserting(dir("\(home)/Documents", 500))
        XCTAssertEqual(merged?.size, 510)
    }
}
