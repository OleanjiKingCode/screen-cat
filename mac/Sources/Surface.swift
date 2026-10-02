import AppKit

/// Which edge of the screen the cat is treating as the floor.
///
/// Everything about a routine is written in surface-local coordinates, where x
/// runs along the floor and y is height above it. A single transform at draw
/// time maps that onto the screen, so walking up the left edge is the same code
/// as padding along the bottom, just rotated. The "never climb" rule then means
/// "never drift away from the wall", which is exactly right.
enum Surface: CaseIterable {
    case bottom, left, right

    /// The walking area in local coordinates, always at the origin.
    /// Width is the length of the floor, height is how far out from it we could
    /// possibly go. `Scene.roamBand` is what actually limits that.
    func localRect(for screen: CGRect) -> CGRect {
        switch self {
        case .bottom:
            return CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
        case .left, .right:
            return CGRect(x: 0, y: 0, width: screen.height, height: screen.width)
        }
    }

    /// Local coordinates onto screen coordinates. A proper rotation, never a
    /// reflection, so the cat is not mirrored when it walks a wall.
    func transform(for screen: CGRect) -> CGAffineTransform {
        switch self {
        case .bottom:
            // (x, y) -> (minX + x, minY + y)
            return CGAffineTransform(translationX: screen.minX, y: screen.minY)
        case .left:
            // (x, y) -> (minX + y, maxY - x): walks down the left edge.
            return CGAffineTransform(translationX: screen.minX, y: screen.maxY)
                .rotated(by: -.pi / 2)
        case .right:
            // (x, y) -> (maxX - y, minY + x): walks up the right edge.
            return CGAffineTransform(translationX: screen.maxX, y: screen.minY)
                .rotated(by: .pi / 2)
        }
    }

    var isWall: Bool { self != .bottom }
}
