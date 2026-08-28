import Foundation
import Testing
@testable import Hidden

struct SearchQueryTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("A year term matches capture year")
    func yearSearch() {
        let assets = [
            Fixture.asset("recent", daysAgo: 5),        // anchor is 2025
            Fixture.asset("old", daysAgo: 5 * 365),
        ]
        let result = SearchQuery.run("2025", in: assets, meta: [:], calendar: calendar)
        #expect(result.map(\.localIdentifier) == ["recent"])
    }

    @Test("Media keywords match kinds")
    func kindSearch() {
        let assets = [
            Fixture.asset("clip", video: true, duration: 30),
            Fixture.asset("still"),
        ]
        #expect(SearchQuery.run("video", in: assets, meta: [:], calendar: calendar)
            .map(\.localIdentifier) == ["clip"])
        #expect(SearchQuery.run("photos", in: assets, meta: [:], calendar: calendar)
            .map(\.localIdentifier) == ["still"])
    }

    @Test("Tag substrings match, and terms AND together")
    func tagSearch() {
        let assets = [
            Fixture.asset("tagged", video: true, duration: 30),
            Fixture.asset("plain", video: true, duration: 30),
        ]
        let meta = ["tagged": Fixture.meta(tags: ["Summer Trip"])]
        #expect(SearchQuery.run("summer", in: assets, meta: meta, calendar: calendar)
            .map(\.localIdentifier) == ["tagged"])
        #expect(SearchQuery.run("summer video", in: assets, meta: meta, calendar: calendar)
            .map(\.localIdentifier) == ["tagged"])
        #expect(SearchQuery.run("summer photo", in: assets, meta: meta, calendar: calendar).isEmpty)
    }

    @Test("An empty query returns everything")
    func emptyQuery() {
        let assets = [Fixture.asset("a"), Fixture.asset("b")]
        #expect(SearchQuery.run("  ", in: assets, meta: [:], calendar: calendar).count == 2)
    }
}

struct SessionGroupingTests {

    private func meta(observedSecondsAgo: TimeInterval) -> AssetMeta {
        var meta = AssetMeta()
        meta.firstObservedHiddenAt = Date(timeIntervalSince1970: 1_756_000_000 - observedSecondsAgo)
        return meta
    }

    @Test("A quiet gap splits sessions; proximity joins them")
    func grouping() {
        let assets = [
            Fixture.asset("a1"), Fixture.asset("a2"),
            Fixture.asset("b1", video: true, duration: 120),
        ]
        let metas: [String: AssetMeta] = [
            "a1": meta(observedSecondsAgo: 100),
            "a2": meta(observedSecondsAgo: 200),          // 100s apart — same session
            "b1": meta(observedSecondsAgo: 10_000),       // hours earlier — its own session
        ]
        let sessions = SessionGrouping.sessions(assets: assets, meta: metas)
        #expect(sessions.count == 2)
        // Newest first.
        #expect(Set(sessions[0].assetIDs) == ["a1", "a2"])
        #expect(sessions[0].photoCount == 2)
        #expect(sessions[1].assetIDs == ["b1"])
        #expect(sessions[1].videoCount == 1)
        #expect(sessions[1].videoSeconds == 120)
    }

    @Test("Assets without an observation date are left out, not guessed")
    func unobservedLeftOut() {
        let assets = [Fixture.asset("known"), Fixture.asset("unknown")]
        let sessions = SessionGrouping.sessions(
            assets: assets,
            meta: ["known": meta(observedSecondsAgo: 50)])
        #expect(sessions.count == 1)
        #expect(sessions[0].assetIDs == ["known"])
    }

    @Test("No observations at all means no sessions")
    func empty() {
        #expect(SessionGrouping.sessions(assets: [Fixture.asset("x")], meta: [:]).isEmpty)
    }
}
