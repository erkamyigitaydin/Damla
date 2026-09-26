import AppKit

/// A horizontal two-finger swipe on the open panel, followed as it happens: the page moves with the fingers, and
/// on release it turns (far enough, or flicked) or springs back. Fingers to the left mean the next page. A gesture
/// that starts out vertical belongs to the page's own scrolling (lyrics, clipboard, mixer); mouse wheels and
/// momentum are always left to it.
struct PanelSwipeGesture {
    static let decideAfter: CGFloat = 6      // travel before a gesture commits to swiping or scrolling
    static let commitTravel: CGFloat = 70    // a slow swipe this far turns the page
    static let flickSpeed: CGFloat = 450     // points a second that turn it after a short flick
    static let flickTravel: CGFloat = 18

    enum Action: Equatable { case next, previous }
    enum Event: Equatable { case drag(CGFloat), release(Action?) }
    /// `consume` swallows the event so the content under the pointer does not also scroll.
    struct Result: Equatable {
        var consume = false
        var event: Event?
        static let pass = Result()
    }

    private var horizontal: Bool?
    private var totalUp: CGFloat = 0
    private var totalRight: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastTime: TimeInterval?
    private var lastMove: TimeInterval = 0

    /// `up` and `right` are the fingers' direction (see `finger(_:)`), in points; `time` is the event's timestamp.
    mutating func feed(up: CGFloat, right: CGFloat, precise: Bool, began: Bool, ended: Bool, momentum: Bool, time: TimeInterval = 0) -> Result {
        guard precise, !momentum else { return .pass }
        if began { reset() }
        totalUp += up; totalRight += right
        if right != 0 {
            if let lastTime, time > lastTime { velocity = velocity * 0.4 + right / CGFloat(time - lastTime) * 0.6 }
            lastMove = time
        }
        lastTime = time
        if horizontal == nil, max(abs(totalUp), abs(totalRight)) >= Self.decideAfter {
            horizontal = abs(totalRight) > abs(totalUp) * 1.5
        }
        if ended {
            defer { reset() }
            guard horizontal == true else { return .pass }
            // Fingers that stopped before lifting have no flick left in them.
            let speed = time - lastMove > 0.08 ? 0 : velocity
            return Result(consume: true, event: .release(Self.decision(travel: totalRight, velocity: speed)))
        }
        guard horizontal == true else { return .pass }
        return Result(consume: true, event: .drag(totalRight))
    }

    static func decision(travel: CGFloat, velocity: CGFloat) -> Action? {
        let flicked = abs(velocity) >= flickSpeed && abs(travel) >= flickTravel && (velocity < 0) == (travel < 0)
        guard abs(travel) >= commitTravel || flicked else { return nil }
        return travel < 0 ? .next : .previous
    }

    /// How far a page follows the fingers when there is no page on that side: it gives, less and less, up to 44 pt.
    static func rubberBand(_ travel: CGFloat) -> CGFloat {
        let limit: CGFloat = 44
        let pulled = limit * (1 - 1 / (abs(travel) * 0.55 / limit + 1))
        return travel < 0 ? -pulled : pulled
    }

    private mutating func reset() { horizontal = nil; totalUp = 0; totalRight = 0; velocity = 0; lastTime = nil; lastMove = 0 }

    /// The fingers' movement, independent of the "natural scrolling" setting. AppKit's positive deltaY moves
    /// content down and positive deltaX moves content right; natural scrolling flips both relative to the device.
    static func finger(_ event: NSEvent) -> (up: CGFloat, right: CGFloat) {
        let inverted = event.isDirectionInvertedFromDevice
        return (inverted ? -event.scrollingDeltaY : event.scrollingDeltaY,
                inverted ? event.scrollingDeltaX : -event.scrollingDeltaX)
    }
}
