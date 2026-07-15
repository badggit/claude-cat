import ClaudeCatCore
import ClaudeCatPet

struct PetPresentationInput: Equatable {
    let creatureID: String
    let family: ModelFamily?
    let state: PetBehaviorState
    let overlay: PetOverlay
    let stage: Int
}

@MainActor
protocol PetPresentationSurface: AnyObject {
    func update(_ input: PetPresentationInput)
    func setVisible(_ visible: Bool)
    func setRunning(_ running: Bool)
}

enum PetPresentationFailure: Equatable {
    case unknownCreature(id: String)
    case missingPixelArt(id: String)
}

enum PetPresentationResult: Equatable {
    case presented(PetVisualKind)
    case failure(PetPresentationFailure)
}

@MainActor
final class PetPresentationRouter {
    typealias VisualLookup = (String) -> PetVisualDescriptor?
    typealias PixelArtLookup = (String) -> Bool

    var onFailureChange: ((PetPresentationFailure?) -> Void)?

    private(set) var failure: PetPresentationFailure?

    private enum ActiveSurface {
        case illustratedCat
        case pixelArt
    }

    private let illustratedSurface: PetPresentationSurface
    private let pixelSurface: PetPresentationSurface
    private let visualLookup: VisualLookup
    private let pixelArtLookup: PixelArtLookup

    private var activeSurface: ActiveSurface?
    private var latestInput: PetPresentationInput?
    private var running = false

    init(
        illustratedSurface: PetPresentationSurface,
        pixelSurface: PetPresentationSurface,
        visualLookup: @escaping VisualLookup = PetVisualCatalog.visual,
        pixelArtLookup: @escaping PixelArtLookup = {
            PetArtCatalog.creature(id: $0) != nil
        }
    ) {
        self.illustratedSurface = illustratedSurface
        self.pixelSurface = pixelSurface
        self.visualLookup = visualLookup
        self.pixelArtLookup = pixelArtLookup
    }

    @discardableResult
    func update(
        creatureID: String,
        family: ModelFamily?,
        state: PetBehaviorState,
        overlay: PetOverlay,
        stage: Int
    ) -> PetPresentationResult {
        guard let descriptor = visualLookup(creatureID) else {
            let failure = PetPresentationFailure.unknownCreature(id: creatureID)
            fail(with: failure)
            return .failure(failure)
        }

        let target: ActiveSurface
        switch descriptor.kind {
        case .illustratedCat:
            target = .illustratedCat
        case .pixelArt:
            guard pixelArtLookup(creatureID) else {
                let failure = PetPresentationFailure.missingPixelArt(id: creatureID)
                fail(with: failure)
                return .failure(failure)
            }
            target = .pixelArt
        }

        let input = PetPresentationInput(
            creatureID: creatureID,
            family: family,
            state: state,
            overlay: overlay,
            stage: PetStateEngine.clampedStage(stage, stageCount: descriptor.stageCount)
        )
        clearFailure()

        if activeSurface != target {
            deactivateActiveSurface()
            let surface = surface(for: target)
            surface.update(input)
            surface.setVisible(true)
            if running {
                surface.setRunning(true)
            }
            activeSurface = target
            latestInput = input
        } else if latestInput != input {
            surface(for: target).update(input)
            latestInput = input
        }

        return .presented(descriptor.kind)
    }

    func setRunning(_ running: Bool) {
        guard running != self.running else { return }
        self.running = running
        guard let activeSurface else { return }
        surface(for: activeSurface).setRunning(running)
    }

    func stop() {
        running = false
        deactivateBothSurfaces()
        activeSurface = nil
        latestInput = nil
        clearFailure()
    }

    private func surface(for activeSurface: ActiveSurface) -> PetPresentationSurface {
        switch activeSurface {
        case .illustratedCat:
            return illustratedSurface
        case .pixelArt:
            return pixelSurface
        }
    }

    private func deactivateActiveSurface() {
        guard let activeSurface else { return }
        let active = surface(for: activeSurface)
        active.setRunning(false)
        active.setVisible(false)
        self.activeSurface = nil
        latestInput = nil
    }

    private func deactivateBothSurfaces() {
        illustratedSurface.setRunning(false)
        illustratedSurface.setVisible(false)
        pixelSurface.setRunning(false)
        pixelSurface.setVisible(false)
    }

    private func fail(with failure: PetPresentationFailure) {
        guard activeSurface != nil || latestInput != nil || self.failure != failure else {
            return
        }
        deactivateBothSurfaces()
        activeSurface = nil
        latestInput = nil
        setFailure(failure)
    }

    private func clearFailure() {
        setFailure(nil)
    }

    private func setFailure(_ failure: PetPresentationFailure?) {
        guard failure != self.failure else { return }
        self.failure = failure
        onFailureChange?(failure)
    }
}

#if os(macOS)

import AppKit

@MainActor
final class IllustratedCatPresentationSurface: PetPresentationSurface {
    private let view: CatIllustrationView

    init(view: CatIllustrationView) {
        self.view = view
    }

    func update(_ input: PetPresentationInput) {
        view.update(
            stage: input.stage,
            family: input.family,
            state: input.state,
            overlay: input.overlay
        )
    }

    func setVisible(_ visible: Bool) {
        view.isHidden = !visible
    }

    func setRunning(_ running: Bool) {
        view.setRunning(running)
    }
}

@MainActor
final class PixelPetPresentationSurface: PetPresentationSurface {
    private let animator: PetAnimator
    private let view: NSView

    init(animator: PetAnimator, view: NSView) {
        self.animator = animator
        self.view = view
    }

    func update(_ input: PetPresentationInput) {
        animator.update(
            creatureID: input.creatureID,
            family: input.family,
            state: input.state,
            overlay: input.overlay,
            stage: input.stage
        )
    }

    func setVisible(_ visible: Bool) {
        view.isHidden = !visible
    }

    func setRunning(_ running: Bool) {
        animator.setRunning(running)
    }
}

#endif
