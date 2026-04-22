import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t137a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func testOverflowAffordancesStayHiddenWhenContentFits() {
    let state = QuotesListViewTestProbe.filterOverflowPresentationState(
        viewportWidth: 320,
        contentWidth: 320,
        contentOffset: 0
    )

    assertEqual(state.showsLeadingAffordance, false, "Expected leading affordance to stay hidden when the filter row fits")
    assertEqual(state.showsTrailingAffordance, false, "Expected trailing affordance to stay hidden when the filter row fits")
}

private func testOverflowAffordancesTrackScrollPositionAcrossRange() {
    let leadingEdge = QuotesListViewTestProbe.filterOverflowPresentationState(
        viewportWidth: 240,
        contentWidth: 520,
        contentOffset: 0
    )
    assertEqual(leadingEdge.showsLeadingAffordance, false, "Expected leading affordance to stay hidden at the left edge")
    assertEqual(leadingEdge.showsTrailingAffordance, true, "Expected trailing affordance to show when more filters remain offscreen")

    let middle = QuotesListViewTestProbe.filterOverflowPresentationState(
        viewportWidth: 240,
        contentWidth: 520,
        contentOffset: 140
    )
    assertEqual(middle.showsLeadingAffordance, true, "Expected leading affordance to show after scrolling away from the left edge")
    assertEqual(middle.showsTrailingAffordance, true, "Expected trailing affordance to stay visible before the end of the row")

    let trailingEdge = QuotesListViewTestProbe.filterOverflowPresentationState(
        viewportWidth: 240,
        contentWidth: 520,
        contentOffset: 280
    )
    assertEqual(trailingEdge.showsLeadingAffordance, true, "Expected leading affordance to remain visible at the trailing edge")
    assertEqual(trailingEdge.showsTrailingAffordance, false, "Expected trailing affordance to hide once the row is fully scrolled into view")
}

private func testOverflowAffordancesClampOverscrollAndTolerance() {
    let negativeOffset = QuotesListViewTestProbe.filterOverflowPresentationState(
        viewportWidth: 240,
        contentWidth: 520,
        contentOffset: -20
    )
    assertEqual(negativeOffset.showsLeadingAffordance, false, "Expected negative offsets to clamp to the leading edge")
    assertEqual(negativeOffset.showsTrailingAffordance, true, "Expected negative offsets to preserve the trailing affordance")

    let overscrolled = QuotesListViewTestProbe.filterOverflowPresentationState(
        viewportWidth: 240,
        contentWidth: 520,
        contentOffset: 999
    )
    assertEqual(overscrolled.showsLeadingAffordance, true, "Expected overscrolled values to clamp to the trailing edge")
    assertEqual(overscrolled.showsTrailingAffordance, false, "Expected overscrolled values to hide the trailing affordance")

    let nearlyFitting = QuotesListViewTestProbe.filterOverflowPresentationState(
        viewportWidth: 320,
        contentWidth: 320.5,
        contentOffset: 0
    )
    assertEqual(nearlyFitting.showsLeadingAffordance, false, "Expected tolerance to suppress leading affordances for sub-point overflow")
    assertEqual(nearlyFitting.showsTrailingAffordance, false, "Expected tolerance to suppress trailing affordances for sub-point overflow")
}

@main
struct VerifyT137AMain {
    static func main() {
        testOverflowAffordancesStayHiddenWhenContentFits()
        testOverflowAffordancesTrackScrollPositionAcrossRange()
        testOverflowAffordancesClampOverscrollAndTolerance()
        print("verify_t137a_main passed")
    }
}
