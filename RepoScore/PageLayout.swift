import Foundation

enum ReadingMode: String, CaseIterable {
    case single
    case double
}

/// The user's layout choice; automatic follows the current orientation.
enum ReadingPreference: Hashable {
    case automatic
    case single
    case double

    func mode(isLandscape: Bool) -> ReadingMode {
        switch self {
        case .automatic: isLandscape ? .double : .single
        case .single: .single
        case .double: .double
        }
    }
}

/// Zero-based physical page ranges. The reading anchor remains stable across modes.
struct PageLayout {
    let pageCount: Int
    let mode: ReadingMode
    let separateCover: Bool

    func spread(containing page: Int) -> Range<Int> {
        guard pageCount > 0 else { return 0..<0 }
        let page = min(max(page, 0), pageCount - 1)
        if mode == .single || (separateCover && page == 0) { return page..<(page + 1) }
        let offset = separateCover ? 1 : 0
        let start = offset + ((page - offset) / 2) * 2
        return start..<min(start + 2, pageCount)
    }

    func nextPage(from page: Int) -> Int {
        let current = spread(containing: page)
        return current.upperBound < pageCount ? current.upperBound : page
    }

    func previousPage(from page: Int) -> Int {
        let current = spread(containing: page)
        return current.lowerBound > 0 ? spread(containing: current.lowerBound - 1).lowerBound : page
    }
}
