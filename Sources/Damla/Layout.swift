import Foundation
import CoreGraphics

enum NotchState: Equatable { case closed, hud, drop, expanded }

enum DisplayMode: String, CaseIterable, Identifiable {
    case followMouse = "Fareyi izle", notch = "Çentikli ekran"
    var id: String { rawValue }
}

/// How the panel sits on a screen that has no physical notch.
enum ExternalStyle: String, CaseIterable, Identifiable {
    case menuBar = "Menü çubuğu"   // a fake notch drawn into the menu bar, same shape as the real one
    case island = "Ada"            // a floating pill just under the menu bar
    var id: String { rawValue }
}

/// Single source of truth for sizes. Both the AppKit window and the SwiftUI shape read from here,
/// so hover tracking and drawing never disagree.
enum Layout {
    struct Metrics: Equatable {
        var notchWidth: CGFloat
        var notchHeight: CGFloat
        var hasNotch: Bool
    }

    static let panelWidth: CGFloat = 404
    static let contentHeight: CGFloat = 188
    static let pillHeight: CGFloat = 36
    static let pillGap: CGFloat = 8
    static let margin: CGFloat = 36           // transparent window margin that holds the shadow
    static let hudSide: CGFloat = 124         // HUD width on each side of the notch
    static let compactSide: CGFloat = 54      // compact content width on each side of the notch
    static let notchlessTopInset: CGFloat = 6 // gap under the menu bar on screens without a notch
    static let notchlessIdleWidth: CGFloat = 92
    static let dropBandHeight: CGFloat = 30    // extra band under the notch that holds the "drop here" label
    static let fakeNotchWidth: CGFloat = 120   // middle section of the fake notch on notchless screens
    static let fakeNotchHeight: CGFloat = 30   // fallback when the menu bar height cannot be read

    static func ear(_ m: Metrics, open: Bool) -> CGFloat { m.hasNotch ? (open ? 10 : 6) : 0 }
    static func headerHeight(_ m: Metrics) -> CGFloat { m.hasNotch ? m.notchHeight : 12 }
    static func closedHeight(_ m: Metrics) -> CGFloat { m.notchHeight } // flush with the menu bar on every screen

    static func shapeSize(_ state: NotchState, _ m: Metrics, compactContent: Bool) -> CGSize {
        switch state {
        case .closed:
            let extra: CGFloat = compactContent ? compactSide * 2 : (m.hasNotch ? 12 : notchlessIdleWidth)
            return CGSize(width: m.notchWidth + extra, height: closedHeight(m))
        case .hud:
            return CGSize(width: m.notchWidth + (m.hasNotch ? hudSide * 2 : 256), height: closedHeight(m))
        case .drop:
            // Basket: a wider, slightly taller target that appears while a file is being dragged anywhere.
            return CGSize(width: m.notchWidth + (m.hasNotch ? hudSide * 2 : 256), height: closedHeight(m) + dropBandHeight)
        case .expanded:
            return CGSize(width: panelWidth, height: headerHeight(m) + contentHeight)
        }
    }

    static func windowSize(_ m: Metrics) -> CGSize {
        let width = max(panelWidth, m.notchWidth + hudSide * 2) + margin * 2
        let height = headerHeight(m) + contentHeight + pillGap + pillHeight + margin
        return CGSize(width: width, height: height)
    }

    /// Screen-space rect of everything currently drawn (shape plus the tab pill when open).
    static func visibleRect(_ state: NotchState, _ m: Metrics, compactContent: Bool, midX: CGFloat, top: CGFloat) -> CGRect {
        var size = shapeSize(state, m, compactContent: compactContent)
        if state == .expanded { size.height += pillGap + pillHeight }
        return CGRect(x: midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }
}
