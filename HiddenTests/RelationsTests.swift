import Foundation
import Testing
@testable import Hidden

struct RelatedFinderTests {

    @Test("Same shooting moment outranks same day, and unrelated is absent")
    func ranking() {
        let anchor = Fixture.asset("anchor", daysAgo: 10)
        let sameMoment = HiddenAsset(localIdentifier: "moment", kind: .photo,
                                     creationDate: anchor.creationDate.addingTimeInterval(60),
                                     modificationDate: nil, pixelWidth: 100, pixelHeight: 100,
                                     duration: 0, isFavorite: false, subtypes: [],
                                     latitude: nil, longitude: nil)
        let sameDay = HiddenAsset(localIdentifier: "day", kind: .photo,
                                  creationDate: anchor.creationDate.addingTimeInterval(6 * 3600),
                                  modificationDate: nil, pixelWidth: 100, pixelHeight: 100,
                                  duration: 0, isFavorite: false, subtypes: [],
                                  latitude: nil, longitude: nil)
        let unrelated = Fixture.asset("far", daysAgo: 500)

        let related = RelatedFinder.related(to: anchor,
                                            in: [anchor, sameDay, sameMoment, unrelated],
                                            meta: [:])
        #expect(related.map(\.localIdentifier) == ["moment", "day"])
    }

    @Test("A shared tag relates assets from different eras")
    func sharedTag() {
        let anchor = Fixture.asset("anchor", daysAgo: 10)
        let tagged = Fixture.asset("tagged", daysAgo: 900)
        let meta = [
            "anchor": Fixture.meta(tags: ["trip"]),
            "tagged": Fixture.meta(tags: ["trip", "beach"]),
        ]
        let related = RelatedFinder.related(to: anchor, in: [anchor, tagged], meta: meta)
        #expect(related.map(\.localIdentifier) == ["tagged"])
    }
}

struct StackGroupingTests {

    private func photo(_ id: String, secondsFromAnchor: TimeInterval) -> HiddenAsset {
        HiddenAsset(localIdentifier: id, kind: .photo,
                    creationDate: Date(timeIntervalSince1970: 1_756_000_000 + secondsFromAnchor),
                    modificationDate: nil, pixelWidth: 100, pixelHeight: 100,
                    duration: 0, isFavorite: false, subtypes: [], latitude: nil, longitude: nil)
    }

    @Test("A burst chains; a gap breaks it; pairs are dropped as noise")
    func grouping() {
        let assets = [
            photo("a1", secondsFromAnchor: 0),
            photo("a2", secondsFromAnchor: 5),
            photo("a3", secondsFromAnchor: 11),
            photo("b1", secondsFromAnchor: 500),
            photo("b2", secondsFromAnchor: 506),   // only two — noise
            photo("c1", secondsFromAnchor: 5000),
        ]
        let stacks = StackGrouping.stacks(in: assets)
        #expect(stacks.count == 1)
        #expect(Set(stacks[0].assets.map(\.localIdentifier)) == ["a1", "a2", "a3"])
    }

    @Test("Videos never stack")
    func videosExcluded() {
        let assets = (0..<5).map { index in
            Fixture.asset("v\(index)", video: true, duration: 30, daysAgo: 0)
        }
        #expect(StackGrouping.stacks(in: assets).isEmpty)
    }
}

struct DuplicateFinderTests {

    @Test("Same second and dimensions group; anything else does not")
    func grouping() {
        let date = Date(timeIntervalSince1970: 1_756_000_000)
        func make(_ id: String, offset: TimeInterval = 0, width: Int = 3024) -> HiddenAsset {
            HiddenAsset(localIdentifier: id, kind: .photo,
                        creationDate: date.addingTimeInterval(offset),
                        modificationDate: nil, pixelWidth: width, pixelHeight: 4032,
                        duration: 0, isFavorite: false, subtypes: [],
                        latitude: nil, longitude: nil)
        }
        let groups = DuplicateFinder.possibleDuplicateGroups(in: [
            make("dupA"), make("dupB"),
            make("otherSize", width: 2000),
            make("otherTime", offset: 5),
        ])
        #expect(groups.count == 1)
        #expect(Set(groups[0].map(\.localIdentifier)) == ["dupA", "dupB"])
    }
}
