import XCTest
@testable import RepoScore

final class PageLayoutTests: XCTestCase {
    func testPairingWithAndWithoutCover() {
        let included = PageLayout(pageCount: 5, mode: .double, separateCover: false)
        XCTAssertEqual(included.spread(containing: 0), 0..<2)
        XCTAssertEqual(included.spread(containing: 1), 0..<2)
        XCTAssertEqual(included.spread(containing: 2), 2..<4)
        XCTAssertEqual(included.spread(containing: 4), 4..<5)
        let cover = PageLayout(pageCount: 6, mode: .double, separateCover: true)
        XCTAssertEqual(cover.spread(containing: 0), 0..<1)
        XCTAssertEqual(cover.spread(containing: 1), 1..<3)
        XCTAssertEqual(cover.spread(containing: 2), 1..<3)
        XCTAssertEqual(cover.spread(containing: 5), 5..<6)
    }

    func testAllPagesAreVisitedExactlyOnceForEveryLayoutAndParity() {
        for count in 1...10 {
            for mode in ReadingMode.allCases {
                for cover in [false, true] {
                    let layout = PageLayout(pageCount: count, mode: mode, separateCover: cover)
                    var anchor = 0
                    var visited: [Int] = []
                    while true {
                        let pages = layout.spread(containing: anchor)
                        visited.append(contentsOf: pages)
                        if pages.upperBound == count { break }
                        let next = layout.nextPage(from: anchor)
                        XCTAssertGreaterThan(next, anchor)
                        anchor = next
                    }
                    XCTAssertEqual(visited, Array(0..<count))
                    XCTAssertEqual(layout.nextPage(from: anchor), anchor)
                    while layout.spread(containing: anchor).lowerBound > 0 {
                        let previous = layout.previousPage(from: anchor)
                        XCTAssertLessThan(previous, anchor)
                        anchor = previous
                    }
                    XCTAssertEqual(anchor, 0)
                    XCTAssertEqual(layout.previousPage(from: anchor), 0)
                }
            }
        }
    }

    func testModeAndCoverChangesKeepPhysicalReadingAnchorVisible() {
        for page in 0..<7 {
            for mode in ReadingMode.allCases {
                for cover in [false, true] {
                    XCTAssertTrue(PageLayout(pageCount: 7, mode: mode, separateCover: cover)
                        .spread(containing: page).contains(page))
                }
            }
        }
    }

    func testEmptySinglePageAndOutOfRangeAnchors() {
        let empty = PageLayout(pageCount: 0, mode: .double, separateCover: false)
        XCTAssertEqual(empty.spread(containing: 0), 0..<0)
        let one = PageLayout(pageCount: 1, mode: .double, separateCover: true)
        XCTAssertEqual(one.spread(containing: -5), 0..<1)
        XCTAssertEqual(one.spread(containing: 15), 0..<1)
        XCTAssertEqual(one.nextPage(from: 0), 0)
        XCTAssertEqual(one.previousPage(from: 0), 0)
    }

    func testAutomaticPreferenceFollowsOrientation() {
        XCTAssertEqual(ReadingPreference.automatic.mode(isLandscape: true), .double)
        XCTAssertEqual(ReadingPreference.automatic.mode(isLandscape: false), .single)
        XCTAssertEqual(ReadingPreference.single.mode(isLandscape: true), .single)
        XCTAssertEqual(ReadingPreference.double.mode(isLandscape: false), .double)
    }
}
