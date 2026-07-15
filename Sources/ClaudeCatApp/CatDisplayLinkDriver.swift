#if os(macOS)

import CoreVideo
import Foundation

protocol CatDisplayLinkDriving: AnyObject {
    var timestampHandler: (@Sendable (TimeInterval) -> Void)? { get set }

    @discardableResult
    func start() -> Bool
    func stop()
}

enum CatDisplayLinkClock {
    static func now() -> TimeInterval {
        let frequency = CVGetHostClockFrequency()
        guard frequency.isFinite, frequency > 0 else { return 0 }
        return TimeInterval(CVGetCurrentHostTime()) / frequency
    }
}

// Core Video invokes this context off-main; the lock protects all shared state.
private final class CatDisplayLinkCallbackContext: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (TimeInterval) -> Void)?
    private var isEnabled = false

    func update(
        handler: (@Sendable (TimeInterval) -> Void)?,
        isEnabled: Bool
    ) {
        lock.lock()
        self.handler = handler
        self.isEnabled = isEnabled
        lock.unlock()
    }

    func emit(timestamp: TimeInterval) {
        lock.lock()
        let currentHandler = isEnabled ? handler : nil
        lock.unlock()
        currentHandler?(timestamp)
    }
}

private let catDisplayLinkOutputCallback: CVDisplayLinkOutputCallback = {
    _, _, outputTime, _, _, rawContext in
    guard let rawContext else { return kCVReturnInvalidArgument }

    let context = Unmanaged<CatDisplayLinkCallbackContext>
        .fromOpaque(rawContext)
        .takeUnretainedValue()
    let frequency = CVGetHostClockFrequency()
    guard frequency.isFinite, frequency > 0 else { return kCVReturnInvalidArgument }

    let timestamp = TimeInterval(outputTime.pointee.hostTime) / frequency
    guard timestamp.isFinite else { return kCVReturnInvalidArgument }
    context.emit(timestamp: timestamp)
    return kCVReturnSuccess
}

final class CatDisplayLinkDriver: CatDisplayLinkDriving {
    var timestampHandler: (@Sendable (TimeInterval) -> Void)? {
        didSet {
            callbackContext.update(
                handler: timestampHandler,
                isEnabled: isRunning
            )
        }
    }

    private let callbackContext = CatDisplayLinkCallbackContext()
    private var displayLink: CVDisplayLink?
    private var isRunning = false

    init() {
        var createdDisplayLink: CVDisplayLink?
        let creationResult = CVDisplayLinkCreateWithActiveCGDisplays(
            &createdDisplayLink
        )
        guard creationResult == kCVReturnSuccess,
              let createdDisplayLink else {
            return
        }

        let callbackResult = CVDisplayLinkSetOutputCallback(
            createdDisplayLink,
            catDisplayLinkOutputCallback,
            Unmanaged.passUnretained(callbackContext).toOpaque()
        )
        guard callbackResult == kCVReturnSuccess else { return }
        displayLink = createdDisplayLink
    }

    deinit {
        stop()
        callbackContext.update(handler: nil, isEnabled: false)
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard let displayLink else { return false }
        callbackContext.update(handler: timestampHandler, isEnabled: true)

        guard CVDisplayLinkStart(displayLink) == kCVReturnSuccess else {
            callbackContext.update(handler: timestampHandler, isEnabled: false)
            return false
        }
        isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        callbackContext.update(handler: timestampHandler, isEnabled: false)
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}

#endif
