import XCTest
import ClaudeCatCore
import ClaudeCatPet
@testable import ClaudeCatApp

@MainActor
final class PetPresentationRouterTests: XCTestCase {
    nonisolated func testCatAndPixelCreatureForwardOnlyToTheirSelectedSurface() async {
        await Self.assertCatAndPixelCreatureForwardOnlyToTheirSelectedSurface()
    }

    nonisolated func testSwitchesStopAndHideInactiveSurfaceBeforeShowingNewestBoundaryStage() async {
        await Self.assertSwitchesStopAndHideInactiveSurfaceBeforeShowingNewestBoundaryStage()
    }

    nonisolated func testUnknownAndMissingArtHideBothAndExposeFailureWithoutStaleReplay() async {
        await Self.assertUnknownAndMissingArtHideBothAndExposeFailureWithoutStaleReplay()
    }

    nonisolated func testRunningStateTargetsOnlyActiveSurfaceAndGlobalStopHidesBoth() async {
        await Self.assertRunningStateTargetsOnlyActiveSurfaceAndGlobalStopHidesBoth()
    }

    nonisolated func testRepeatedIdenticalUpdateIsIdempotentAndUsesInjectedSurfacesOnce() async {
        await Self.assertRepeatedIdenticalUpdateIsIdempotentAndUsesInjectedSurfacesOnce()
    }

    private static func assertCatAndPixelCreatureForwardOnlyToTheirSelectedSurface() {
        let recorder = EventRecorder()
        let illustrated = FakeSurface(name: "illustrated", recorder: recorder)
        let pixel = FakeSurface(name: "pixel", recorder: recorder)
        let router = makeRouter(illustrated: illustrated, pixel: pixel)

        router.setRunning(true)
        XCTAssertEqual(
            router.update(
                creatureID: "cat",
                family: .sonnet,
                state: .jumping(frameInterval: 1.2),
                overlay: .hovering,
                stage: 0
            ),
            .presented(.illustratedCat)
        )

        XCTAssertEqual(
            illustrated.updates,
            [
                PetPresentationInput(
                    creatureID: "cat",
                    family: .sonnet,
                    state: .jumping(frameInterval: 1.2),
                    overlay: .hovering,
                    stage: 0
                )
            ]
        )
        XCTAssertTrue(illustrated.isVisible)
        XCTAssertTrue(illustrated.isRunning)
        XCTAssertTrue(pixel.updates.isEmpty)
        XCTAssertFalse(pixel.isVisible)
        XCTAssertFalse(pixel.isRunning)

        XCTAssertEqual(
            router.update(
                creatureID: "bunny",
                family: .opus,
                state: .sleeping,
                overlay: .none,
                stage: 5
            ),
            .presented(.pixelArt)
        )

        XCTAssertEqual(pixel.updates.last?.creatureID, "bunny")
        XCTAssertEqual(pixel.updates.last?.family, .opus)
        XCTAssertEqual(pixel.updates.last?.state, .sleeping)
        XCTAssertEqual(pixel.updates.last?.overlay, PetOverlay.none)
        XCTAssertEqual(pixel.updates.last?.stage, 5)
        XCTAssertFalse(illustrated.isVisible)
        XCTAssertFalse(illustrated.isRunning)
        XCTAssertTrue(pixel.isVisible)
        XCTAssertTrue(pixel.isRunning)
    }

    private static func assertSwitchesStopAndHideInactiveSurfaceBeforeShowingNewestBoundaryStage() {
        let recorder = EventRecorder()
        let illustrated = FakeSurface(name: "illustrated", recorder: recorder)
        let pixel = FakeSurface(name: "pixel", recorder: recorder)
        let router = makeRouter(illustrated: illustrated, pixel: pixel)

        router.setRunning(true)
        router.update(
            creatureID: "cat",
            family: .haiku,
            state: .jumping(frameInterval: 2.5),
            overlay: .none,
            stage: -4
        )
        recorder.events.removeAll()

        router.update(
            creatureID: "bunny",
            family: .fable,
            state: .jumping(frameInterval: 0.7),
            overlay: .dragging,
            stage: 99
        )

        XCTAssertEqual(
            recorder.events,
            [
                "illustrated.running.false",
                "illustrated.visible.false",
                "pixel.update.bunny.5",
                "pixel.visible.true",
                "pixel.running.true"
            ]
        )
        recorder.events.removeAll()

        router.update(
            creatureID: "cat",
            family: .sonnet,
            state: .sleeping,
            overlay: .startled,
            stage: 0
        )

        XCTAssertEqual(
            recorder.events,
            [
                "pixel.running.false",
                "pixel.visible.false",
                "illustrated.update.cat.0",
                "illustrated.visible.true",
                "illustrated.running.true"
            ]
        )
        XCTAssertEqual(illustrated.updates.last?.family, .sonnet)
        XCTAssertEqual(illustrated.updates.last?.state, .sleeping)
        XCTAssertEqual(illustrated.updates.last?.overlay, .startled)
        XCTAssertTrue(illustrated.isVisible)
        XCTAssertTrue(illustrated.isRunning)
        XCTAssertFalse(pixel.isVisible)
        XCTAssertFalse(pixel.isRunning)
    }

    private static func assertUnknownAndMissingArtHideBothAndExposeFailureWithoutStaleReplay() {
        let recorder = EventRecorder()
        let illustrated = FakeSurface(name: "illustrated", recorder: recorder)
        let pixel = FakeSurface(name: "pixel", recorder: recorder)
        let router = makeRouter(
            illustrated: illustrated,
            pixel: pixel,
            pixelArtIDs: ["bird", "flower", "pig"]
        )
        var failures: [PetPresentationFailure?] = []
        router.onFailureChange = { failures.append($0) }

        router.setRunning(true)
        router.update(
            creatureID: "cat",
            family: nil,
            state: .sleeping,
            overlay: .none,
            stage: 2
        )
        let catUpdateCount = illustrated.updates.count

        XCTAssertEqual(
            router.update(
                creatureID: "dragon",
                family: .other,
                state: .broken,
                overlay: .none,
                stage: 3
            ),
            .failure(.unknownCreature(id: "dragon"))
        )
        XCTAssertEqual(router.failure, .unknownCreature(id: "dragon"))
        XCTAssertFalse(illustrated.isVisible)
        XCTAssertFalse(illustrated.isRunning)
        XCTAssertFalse(pixel.isVisible)
        XCTAssertFalse(pixel.isRunning)
        XCTAssertEqual(illustrated.updates.count, catUpdateCount)

        let eventsAfterUnknown = recorder.events
        router.update(
            creatureID: "dragon",
            family: .other,
            state: .broken,
            overlay: .none,
            stage: 3
        )
        XCTAssertEqual(recorder.events, eventsAfterUnknown)

        XCTAssertEqual(
            router.update(
                creatureID: "bunny",
                family: .opus,
                state: .jumping(frameInterval: 1),
                overlay: .none,
                stage: 4
            ),
            .failure(.missingPixelArt(id: "bunny"))
        )
        XCTAssertEqual(router.failure, .missingPixelArt(id: "bunny"))
        XCTAssertTrue(pixel.updates.isEmpty)
        XCTAssertFalse(illustrated.isVisible)
        XCTAssertFalse(illustrated.isRunning)
        XCTAssertFalse(pixel.isVisible)
        XCTAssertFalse(pixel.isRunning)
        XCTAssertEqual(
            failures,
            [
                .unknownCreature(id: "dragon"),
                .missingPixelArt(id: "bunny")
            ]
        )
    }

    private static func assertRunningStateTargetsOnlyActiveSurfaceAndGlobalStopHidesBoth() {
        let recorder = EventRecorder()
        let illustrated = FakeSurface(name: "illustrated", recorder: recorder)
        let pixel = FakeSurface(name: "pixel", recorder: recorder)
        let router = makeRouter(illustrated: illustrated, pixel: pixel)

        router.update(
            creatureID: "pig",
            family: .other,
            state: .sleeping,
            overlay: .none,
            stage: 3
        )
        recorder.events.removeAll()

        router.setRunning(true)
        router.setRunning(true)
        router.setRunning(false)

        XCTAssertEqual(
            recorder.events,
            ["pixel.running.true", "pixel.running.false"]
        )
        XCTAssertTrue(illustrated.runningChanges.isEmpty)
        XCTAssertTrue(pixel.isVisible)

        recorder.events.removeAll()
        router.stop()

        XCTAssertEqual(
            recorder.events,
            [
                "illustrated.running.false",
                "illustrated.visible.false",
                "pixel.running.false",
                "pixel.visible.false"
            ]
        )
        XCTAssertFalse(illustrated.isVisible)
        XCTAssertFalse(illustrated.isRunning)
        XCTAssertFalse(pixel.isVisible)
        XCTAssertFalse(pixel.isRunning)
    }

    private static func assertRepeatedIdenticalUpdateIsIdempotentAndUsesInjectedSurfacesOnce() {
        let recorder = EventRecorder()
        let illustrated = FakeSurface(name: "illustrated", recorder: recorder)
        let pixel = FakeSurface(name: "pixel", recorder: recorder)
        var visualLookupCount = 0
        let router = PetPresentationRouter(
            illustratedSurface: illustrated,
            pixelSurface: pixel,
            visualLookup: { id in
                visualLookupCount += 1
                return PetVisualCatalog.visual(id: id)
            }
        )

        router.setRunning(true)
        for _ in 0..<3 {
            router.update(
                creatureID: "cat",
                family: .sonnet,
                state: .jumping(frameInterval: 1.4),
                overlay: .hovering,
                stage: 2
            )
        }

        XCTAssertEqual(visualLookupCount, 3)
        XCTAssertEqual(illustrated.updates.count, 1)
        XCTAssertEqual(illustrated.visibilityChanges, [true])
        XCTAssertEqual(illustrated.runningChanges, [true])
        XCTAssertTrue(pixel.updates.isEmpty)
        XCTAssertTrue(pixel.visibilityChanges.isEmpty)
        XCTAssertTrue(pixel.runningChanges.isEmpty)
    }

    private static func makeRouter(
        illustrated: FakeSurface,
        pixel: FakeSurface,
        pixelArtIDs: Set<String> = ["bunny", "bird", "flower", "pig"]
    ) -> PetPresentationRouter {
        PetPresentationRouter(
            illustratedSurface: illustrated,
            pixelSurface: pixel,
            pixelArtLookup: { pixelArtIDs.contains($0) }
        )
    }
}

@MainActor
private final class EventRecorder {
    var events: [String] = []
}

@MainActor
private final class FakeSurface: PetPresentationSurface {
    let name: String
    let recorder: EventRecorder

    private(set) var updates: [PetPresentationInput] = []
    private(set) var visibilityChanges: [Bool] = []
    private(set) var runningChanges: [Bool] = []
    private(set) var isVisible = false
    private(set) var isRunning = false

    init(name: String, recorder: EventRecorder) {
        self.name = name
        self.recorder = recorder
    }

    func update(_ input: PetPresentationInput) {
        updates.append(input)
        recorder.events.append("\(name).update.\(input.creatureID).\(input.stage)")
    }

    func setVisible(_ visible: Bool) {
        visibilityChanges.append(visible)
        isVisible = visible
        recorder.events.append("\(name).visible.\(visible)")
    }

    func setRunning(_ running: Bool) {
        runningChanges.append(running)
        isRunning = running
        recorder.events.append("\(name).running.\(running)")
    }
}
