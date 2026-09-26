import AppKit

/// Turns a horizontal two-finger swipe on the open panel into a page change, once per gesture: fingers to the
/// left open the next page, to the right the previous one. A gesture that starts out vertical belongs to the
/// page's own scrolling (lyrics, clipboard, mixer), and mouse wheels and momentum are always left to it.
struct PanelSwipeGesture {
    static let swipeTravel: CGFloat = 50    // horizontal travel that counts as a swipe
    static let decideAfter: CGFloat = 6     // travel before a gesture commits to swiping or scrolling

    enum Action: Equatable { case next, previous }
    /// `consume` swallows the event so the content under the pointer does not also scroll.
    struct Result: Equatable {
        var consume = false
        var action: Action?
        static let pass = Result()
    }

    private var horizontal: Bool?
    private var totalUp: CGFloat = 0
    private var totalRight: CGFloat = 0
    private var swiped = false

    /// `up` and `right` are the fingers' direction (see `finger(_:)`), in points.
    mutating func feed(up: CGFloat, right: CGFloat, precise: Bool, began: Bool, ended: Bool, momentum: Bool) -> Result {
        guard precise, !momentum else { return .pass }
        if began { reset() }
        defer { if ended { reset() } }
        totalUp += up; totalRight += right
        if horizontal == nil, max(abs(totalUp), abs(totalRight)) >= Self.decideAfter {
            horizontal = abs(totalRight) > abs(totalUp) * 1.5
        }
        guard horizontal == true else { return .pass }
        guard !swiped, abs(totalRight) >= Self.swipeTravel else { return Result(consume: true) }
        swiped = true
        return Result(consume: true, action: totalRight < 0 ? .next : .previous)
    }

    private mutating func reset() { horizontal = nil; totalUp = 0; totalRight = 0; swiped = false }

    /// The fingers' movement, independent of the "natural scrolling" setting. AppKit's positive deltaY moves
    /// content down and positive deltaX moves content right; natural scrolling flips both relative to the device.
    static func finger(_ event: NSEvent) -> (up: CGFloat, right: CGFloat) {
        let inverted = event.isDirectionInvertedFromDevice
        return (inverted ? -event.scrollingDeltaY : event.scrollingDeltaY,
                inverted ? event.scrollingDeltaX : -event.scrollingDeltaX)
    }
}
