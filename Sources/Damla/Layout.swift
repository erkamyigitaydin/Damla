import Foundation
import CoreGraphics

enum NotchState: Equatable { case closed, hud, drop, expanded }

enum DisplayMode: String, CaseIterable, Identifiable {
    case all = "Tümü", followMouse = "Fareyi izle", notch = "Çentikli"   // raw values are stored settings
    var id: String { rawValue }
    var title: String {
        switch self { case .all: return String(localized: "Tümü"); case .followMouse: return String(localized: "Fareyi izle"); case .notch: return String(localized: "Çentikli") }
    }
}

/// How the panel sits on a screen that has no physical notch.
enum ExternalStyle: String, CaseIterable, Identifiable {
    case menuBar = "Menü çubuğu"   // a fake notch drawn into the menu bar, same shape as the real one
    case island = "Ada"            // a floating pill just under the menu bar
    var id: String { rawValue }
    var title: String { self == .menuBar ? String(localized: "Menü çubuğu") : String(localized: "Ada") }
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
    static let compactSide: CGFloat = 54      // one live activity: glyph on the left, status on the right
    static let compactSideSplit: CGFloat = 80 // two live activities: each side holds one activity's glyph + status
    static let notchlessTopInset: CGFloat = 6 // gap under the menu bar on screens without a notch
    static let notchlessIdleWidth: CGFloat = 92
    static let dropBandHeight: CGFloat = 104   // tray under the notch while dragging; deep enough to hit without touching the screen edge
    static let fakeNotchWidth: CGFloat = 120   // middle section of the fake notch on notchless screens
    static let fakeNotchHeight: CGFloat = 30   // fallback when the menu bar height cannot be read

    static func ear(_ m: Metrics, open: Bool) -> CGFloat { m.hasNotch ? (open ? 10 : 6) : 0 }
    static func headerHeight(_ m: Metrics) -> CGFloat { m.hasNotch ? m.notchHeight : 12 }
    static func closedHeight(_ m: Metrics) -> CGFloat { m.notchHeight } // flush with the menu bar on every screen

    /// Width of one side of the closed notch for the given number of live activities (0, 1 or 2).
    static func compactSide(slots: Int) -> CGFloat { slots >= 2 ? compactSideSplit : compactSide }

    static func shapeSize(_ state: NotchState, _ m: Metrics, compactSlots: Int) -> CGSize {
        switch state {
        case .closed:
            let extra: CGFloat = compactSlots > 0 ? compactSide(slots: compactSlots) * 2 : (m.hasNotch ? 12 : notchlessIdleWidth)
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
    static func visibleRect(_ state: NotchState, _ m: Metrics, compactSlots: Int, midX: CGFloat, top: CGFloat) -> CGRect {
        var size = shapeSize(state, m, compactSlots: compactSlots)
        if state == .expanded { size.height += pillGap + pillHeight }
        return CGRect(x: midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }
}
