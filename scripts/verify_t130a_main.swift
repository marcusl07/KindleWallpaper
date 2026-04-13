import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t130a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func testCommittedSearchRefreshCommitsLatestRawSearchText() {
    let commit = QuotesListViewTestProbe.committedSearchRefresh(
        rawSearchText: "draft",
        effectiveSearchText: ""
    )

    assertEqual(commit.effectiveSearchText, "draft", "Expected the debounced search commit to adopt the latest raw search text")
    assertTrue(commit.shouldRefresh, "Expected a changed effective search text to trigger a refresh")
}

private func testCommittedSearchRefreshSkipsRedundantRefreshes() {
    let commit = QuotesListViewTestProbe.committedSearchRefresh(
        rawSearchText: "stable",
        effectiveSearchText: "stable"
    )

    assertEqual(commit.effectiveSearchText, "stable", "Expected the committed search text to remain stable when the raw input has not changed")
    assertTrue(!commit.shouldRefresh, "Expected identical raw and effective search text to skip refresh work")
}

private func testHasActiveQueryReadsCommittedEffectiveSearchState() {
    assertTrue(
        !QuotesListViewTestProbe.hasActiveQuery(
            effectiveSearchText: "   ",
            filters: QuotesListFilters()
        ),
        "Expected whitespace-only effective search text to remain inactive"
    )
    assertTrue(
        QuotesListViewTestProbe.hasActiveQuery(
            effectiveSearchText: "committed",
            filters: QuotesListFilters()
        ),
        "Expected committed effective search text to mark the quotes list as actively filtered"
    )
    assertTrue(
        QuotesListViewTestProbe.hasActiveQuery(
            effectiveSearchText: "",
            filters: QuotesListFilters(selectedAuthor: "Ursula K. Le Guin")
        ),
        "Expected active filters to keep the list in an active-query presentation state"
    )
}

@main
struct VerifyT130AMain {
    static func main() {
        testCommittedSearchRefreshCommitsLatestRawSearchText()
        testCommittedSearchRefreshSkipsRedundantRefreshes()
        testHasActiveQueryReadsCommittedEffectiveSearchState()
        print("verify_t130a_main passed")
    }
}
