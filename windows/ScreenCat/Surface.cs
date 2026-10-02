namespace ScreenCat;

/// Which edge of the screen the cat is treating as the floor.
///
/// Everything about a routine is written in surface-local coordinates, where x
/// runs along the floor and y is height above it. A single transform at draw
/// time maps that onto the screen, so walking up the left edge is the same code
/// as padding along the bottom, just rotated. The "never climb" rule then means
/// "never drift away from the wall", which is exactly right.
///
/// Screen rectangles here are Windows ones: physical pixels, y pointing down.
public enum Surface
{
    Bottom,
    Left,
    Right,
}

public static class SurfaceMath
{
    /// The walking area in local coordinates, always at the origin.
    /// Width is the length of the floor, height is how far out from it we could
    /// possibly go. `Scene.RoamBand` is what actually limits that.
    public static RectD LocalRect(this Surface s, RectD screen) => s switch
    {
        Surface.Bottom => new RectD(0, 0, screen.Width, screen.Height),
        _ => new RectD(0, 0, screen.Height, screen.Width),
    };

    /// Local coordinates (y up) onto screen coordinates (y down). Every one of
    /// these flips once, so relative to each other they are proper rotations,
    /// never a reflection, and the cat is not mirrored when it walks a wall.
    public static Affine Transform(this Surface s, RectD screen) => s switch
    {
        // (x, y) -> (left + x, bottom - y)
        Surface.Bottom => new Affine(1, 0, 0, -1, screen.MinX, screen.MaxY),
        // (x, y) -> (left + y, top + x): walks down the left edge.
        Surface.Left => new Affine(0, 1, 1, 0, screen.MinX, screen.MinY),
        // (x, y) -> (right - y, bottom - x): walks up the right edge.
        _ => new Affine(0, -1, -1, 0, screen.MaxX, screen.MaxY),
    };

    public static bool IsWall(this Surface s) => s != Surface.Bottom;

    public static string Name(this Surface s) => s switch
    {
        Surface.Bottom => "bottom",
        Surface.Left => "left",
        _ => "right",
    };
}
