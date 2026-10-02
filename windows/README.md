# Screen Cat for Windows (planned)

## Plan

- C# / .NET 8 with WPF or WinForms: a borderless, topmost, transparent window
  over the whole desktop with `WS_EX_TRANSPARENT | WS_EX_LAYERED`, so clicks
  pass through to the apps below.
- A 60 fps render loop drawing the sprite sheet from `../mac/Assets` with
  nearest-neighbour scaling.
- Port the routines and movement rules from `../mac/Sources/Behavior.swift`
  and the glitches from `../mac/Sources/Glitch.swift`.
- Crawler mode: window rectangles from `EnumWindows` + `GetWindowRect`
  (visible, not minimised, not cloaked).
- Idle crawl: idle time from `GetLastInputInfo`; "next app" via
  `SetForegroundWindow` on the next window in Alt+Tab order.
- Tray icon with the same menu as the Mac menu bar item; settings in
  `%APPDATA%\ScreenCat\screencat.json` with the same keys.
- Activity log in `%LOCALAPPDATA%\ScreenCat\Logs`.
