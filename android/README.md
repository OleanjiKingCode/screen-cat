# Screen Cat for Android (planned)

Android lets an app draw over other apps once you allow "Display over other
apps", so the cat can walk over everything, the same as on the Mac.

## Plan

- Kotlin app with a foreground service that owns a `TYPE_APPLICATION_OVERLAY`
  window: full screen, not touchable, so taps pass through to the app below.
- A `SurfaceView` or `Canvas` loop at 60 fps that draws the same sprite sheet
  from `../mac/Assets`, with nearest-neighbour scaling.
- Port the routines and movement rules from `../mac/Sources/Behavior.swift`
  and the glitches from `../mac/Sources/Glitch.swift`.
- Idle crawl: start after no touch for `idleCrawlSeconds`; a touch on the
  overlay is not possible while it passes taps through, so detect return with
  `ACTION_SCREEN_ON` / user-present broadcasts and the screen turning on.
- "Next app" cannot be forced on Android without Accessibility, so at the edge
  the cat turns round instead.
- Settings screen with the same keys as `~/.screencat.json`.

## Limits

- Android hides overlays over some system screens (lock screen, permission
  dialogs).
- Some phones kill background services; the app needs a battery exemption.
