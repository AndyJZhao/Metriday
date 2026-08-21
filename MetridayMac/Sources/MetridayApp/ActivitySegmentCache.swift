import Combine
import Foundation

@MainActor
final class ActivitySegmentCache: ObservableObject {
    private var segmentsByDate: [Date: [ActivitySegment]] = [:]

    func segments(for date: Date) -> [ActivitySegment]? {
        segmentsByDate[date]
    }

    func store(_ segments: [ActivitySegment], for date: Date) {
        segmentsByDate[date] = segments
    }

    func invalidate() {
        segmentsByDate.removeAll(keepingCapacity: true)
    }
}
