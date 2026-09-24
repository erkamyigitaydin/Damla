import AppKit

/// Turns scrolling on the notch strip into volume steps and track skips. Vertical travel changes the volume
/// (a mouse wheel click is one step); a horizontal trackpad swipe skips once per gesture: fingers to the left
/// is the next track, to the right the previous one. Momentum after the fingers lift is ignored, so the
/// volume never runs on by itself.
struct NotchScrollGesture {
    static let volumeTravel: CGFloat = 14   // points of finger travel per volume step
    static let swipeTravel: CGFloat = 60    // horizontal travel that counts as a swipe
    static let decideAfter: CGFloat = 6     // travel before a gesture commits to volume or swipe

    enum Action: Equatable { case volume(Int), next, previous }
    private enum Mode { case volume, swipe }

    private var mode: Mode?
    private var pending: CGFloat = 0
    private var totalUp: CGFloat = 0
    private var totalRight: CGFloat = 0
    private var swiped = false

    /// `up` and `right` are the fingers' direction (see `finger(_:)`), in points.
    mutating func feed(up: CGFloat, right: CGFloat, precise: Bool, began: Bool, ended: Bool, momentum: Bool) -> [Action] {
        if momentum { return [] }
        guard precise else {
            // A mouse wheel has no phases: every click with a vertical delta is one step.
            return up == 0 ? [] : [.volume(up > 0 ? 1 : -1)]
        }
        if began { reset() }
        defer { if ended { reset() } }
        totalUp += up; totalRight += right
        if mode == nil, max(abs(totalUp), abs(totalRight)) >= Self.decideAfter {
            mode = abs(totalRight) > abs(totalUp) * 1.5 ? .swipe : .volume
            if mode == .volume { pending = totalUp }
        } else if mode == .volume {
            pending += up
        }
        switch mode {
        case .volume:
            let steps = Int(pending / Self.volumeTravel)
            guard steps != 0 else { return [] }
            pending -= CGFloat(steps) * Self.volumeTravel
            return [.volume(steps)]
        case .swipe:
            guard !swiped, abs(totalRight) >= Self.swipeTravel else { return [] }
            swiped = true
            return [totalRight < 0 ? .next : .previous]
        case nil:
            return []
        }
    }

    private mutating func reset() { mode = nil; pending = 0; totalUp = 0; totalRight = 0; swiped = false }

    /// The fingers' movement, independent of the "natural scrolling" setting. AppKit's positive deltaY moves
    /// content down and positive deltaX moves content right; natural scrolling flips both relative to the device.
    static func finger(_ event: NSEvent) -> (up: CGFloat, right: CGFloat) {
        let inverted = event.isDirectionInvertedFromDevice
        return (inverted ? -event.scrollingDeltaY : event.scrollingDeltaY,
                inverted ? event.scrollingDeltaX : -event.scrollingDeltaX)
    }
}
