/// Single source of truth for the floating window geometry in logical pixels
/// (port of `electron/src/shared/layout.ts`).

public enum LAYOUT {
  /// Total transparent window size.
  public static let window = Size(width: 470, height: 404)
  /// Transparent margin around the panels so shadows are never clipped.
  public static let margin = Margin(top: 8, right: 14, bottom: 28, left: 14)
  /// Vertical rail with the three rings.
  public static let rail = Rail(width: 108, notchHeight: 12)
  /// Distance between the rail's left edge and the detail card's right edge (tail lives here).
  public static let cardGap = 14.0
  /// Detail card (speech bubble).
  public static let cardWidth = 320.0
  /// Vertical gap between the bottom of the menu bar / tray icon and the window top.
  public static let trayGap = 4.0
  /// How the window is anchored on screen (see the TS source for the two modes).
  public static let anchorMode = AnchorMode.rightEdge

  public struct Size: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
      self.width = width
      self.height = height
    }
  }

  public struct Margin: Sendable, Equatable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double
    public init(top: Double, right: Double, bottom: Double, left: Double) {
      self.top = top
      self.right = right
      self.bottom = bottom
      self.left = left
    }
  }

  public struct Rail: Sendable, Equatable {
    public var width: Double
    public var notchHeight: Double
    public init(width: Double, notchHeight: Double) {
      self.width = width
      self.notchHeight = notchHeight
    }
  }
}

public enum AnchorMode: String, Sendable, Codable {
  case rightEdge = "right-edge"
  case tray
}

/// X offset (from the window's left edge) of the rail's horizontal centre.
public func railAnchorX() -> Double {
  LAYOUT.window.width - LAYOUT.margin.right - LAYOUT.rail.width / 2
}

/// Which screen edge the shelf grows out of.
public enum ShelfEdge: String, Sendable, Codable { case left, right }

/// Shelf geometry (logical pixels) — see `electron/src/shared/layout.ts` for the shape description.
public enum SHELF {
  public static let body = LAYOUT.Size(width: 224, height: 288)
  public static let radius = 18.0
  public static let fillet = 20.0
  public static let shadow = 28.0
}

/// Total transparent window size for the shelf.
public enum SHELF_WINDOW {
  public static let width = SHELF.body.width + SHELF.shadow
  public static let height = SHELF.body.height + SHELF.fillet * 2
}

/// How long the shelf's exit slide takes; main hides the window only after it has played.
public let SHELF_EXIT_MS = 260
