# Screen Cat for Windows

The Windows version of the purple desktop cat. Same routines, same movement
rules, same outfit, same crawler mode, same 50 full-screen glitch styles and
Mr. Robot. C# on .NET 8 with WinForms for the tray menu and plain Win32 for the
window. The Mac source in `../mac/Sources` is the spec; most files here are a
line-by-line port of the Swift file with the same name.

One transparent, click-through, always-on-top window covers every monitor. It
never takes focus and never blocks a click. A cat icon sits in the system tray;
that is the only visible chrome.

## Build and run

You need the .NET 8 SDK on Windows 10 (version 2004 or later) or Windows 11.

```powershell
cd windows\ScreenCat
dotnet build -c Release
dotnet run -c Release
```

One self-contained exe, no .NET install needed to run it:

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
publish\ScreenCat.exe
```

CI (`.github/workflows/windows.yml`) builds and publishes on `windows-latest`,
runs the self-test below, and uploads two artifacts: `ScreenCat-win-x64` (the
exe) and `ScreenCat-selftest` (pictures and a report).

The project also builds on a Mac or Linux for a compile check, with
`dotnet build -c Release -p:EnableWindowsTargeting=true`. It only runs on
Windows.

**Only one cat, ever.** A second launch shows "Screen Cat is already running"
and quits. The guard is a named mutex, which Windows drops when the process
exits, even after a crash.

## Where things live

| What | Where |
| --- | --- |
| Settings | `%APPDATA%\ScreenCat\screencat.json`, written with every default on first launch |
| Activity log | `%LOCALAPPDATA%\ScreenCat\Logs\activity-YYYY-MM-DD.txt`, one file per day |
| Open at login | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value `ScreenCat` |
| Sprites | embedded in the exe from `ScreenCat\Assets` |

## Art credit

Sprites are the free tier of **Cat Pack by Glem / octopusINKUS**
(https://octopusinkus.itch.io/cat-pack). The pack states no licence. It is used
here in a personal toy that is not redistributed, so this repository and every
built exe must stay private. See `ScreenCat\Assets\CREDIT.txt`. The PNGs are
the author's originals, unmodified on disk; the cat is recoloured in memory at
launch.

## Tray menu

Left or right click the tray cat.

- The top line says what the cat is doing, why it is hiding, or how long until
  the next visit.
- **Take a walk / Have a nap / Chase a ball / Beg for food / Ask to play /
  Break some apps (crawler)**: play a routine now. A menu pick ignores the
  blocked-app rule: if you ask for the cat, you get the cat.
- **Crawl until I touch something**: start the idle crawl now.
- **Mode**: **Normal**, **Crawler**, or **Mr. Robot (3 min hack, starts now)**.
  Normal and Crawler are saved as `mode`; Mr. Robot runs once and leaves the
  saved mode alone.
- **Pause** / **Resume**.
- **Show in screenshots && recordings**: ticked, the cat shows in captures.
- **Open at login**.
- **Open today's activity log** / **Show all activity logs**.
- **Edit settings...** (opens Notepad) / **Reload settings** (settings are
  also re-read at the start of every routine).
- **Quit Screen Cat**.

## Settings

Same keys and defaults as the Mac's `~/.screencat.json`; see the table in
`../mac/README.md`. Differences:

| Key | On Windows |
| --- | --- |
| `blockedApps` | Process names, not bundle ids, matched as case-insensitive substrings. Default: `vlc`, `mpc-hc`, `mpc-be`, `PotPlayer`, `mpv`, `wmplayer`, `Video.UI` (Movies & TV), `Microsoft.Media.Player` (Media Player), `Netflix`, `Plex`, `KMPlayer`, `GOM`. Store apps are matched by the app's own process, not `ApplicationFrameHost`. |
| `windowLevel` | `"top"` and `"status"` keep the cat always on top. `"floating"` drops the always-on-top flag, so other windows can cover it. |
| `hideFromCapture` | Uses `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`, which needs Windows 10 version 2004 or later. Older builds show the cat in captures. |
| `sizeDivisor`, speeds | Measured in physical pixels of the working area (screen minus taskbar), so the cat is the same share of the screen at any display scale. |

Comments and trailing commas in the JSON are tolerated. A broken file falls
back to the defaults.

## Activity log

The same diary as the Mac, in the same line format:

```
14:02:11  APP       in front: Visual Studio Code  (after Google Chrome for 12m 4s)
14:05:40  CAT       came out: stroll on the bottom of DISPLAY1, wearing chain
```

It records the app in front and for how long (`APP`, with `[fullscreen]`),
apps and background programs starting and quitting (`OPENED`, `QUIT`,
`BG-START`, `BG-STOP`, polled every 5 seconds), sleep and wake, screen off and
on, lock and unlock, user switches, shutdown, five minutes with no input
(`IDLE`), Bluetooth on or off (`BLUETOOTH`, from Windows.Devices.Radios), every
open app, background program and console process at start, after wake and
every hour (`RUNNING`), and what the cat did (`CAT`), including whether its
window is visible and topmost on every app switch.

Local only: no window titles, keystrokes or screen contents. `activityLog:
false` turns it off; `activityLogDays` (30) is how long day files are kept.

## Self-test

```powershell
ScreenCat.exe --selftest out
```

Runs with nobody at the screen and writes to `out`:

- `report.txt`: settings round-trip and clamping; the sprites load and the
  recolour matches the pack's exact colours; every frame crops out and the
  face is found for the accessories; every routine runs to the end on every
  edge it may use, legs never end higher than they start, and the idle crawl
  and Mr. Robot never move steeper than `maxSlope`; all 50 glitch styles render,
  with milliseconds per frame; the overlay window can be made and updated, and
  whether capture exclusion was accepted.
- `preview.png`: every clip, with and without the outfit, plus the bubble,
  hearts, bowl, ball and the pixel font.
- `glitches.png`: the five crawler-mode glitches and a zap.
- `takeover.png`: all 50 full-screen styles as thumbnails.
- `trail.png`: where one stroll went.

`--demo` plays the walk, ball, beg and nap back to back with a two second gap.

## What matches the Mac

- **Sprites**: 32x32 frames on the 12 x 9 sheet, every clip with the same row,
  start, count, fps, looping, mirroring and stride-driven frames; nearest
  neighbour scaling snapped to whole pixels; the shadow; mirroring; the exact
  colour recolour (coat on the sheet, yarn colours only on the loose ball).
- **Movement**: surface-local maths with one transform per edge (bottom, left,
  right) and `wallChance`; entry and exit from the sides only; legs never
  climb; descent capped at `maxSlope`; one arc per leg capped at 8%;
  `depthShrink`, `groundY` with `groundBias`, `roamHeight`; speeds in body
  heights per second; `sizeDivisor` 24.
- **Routines**: stroll, nap with z's, ball chase, hungry with the bowl, the
  play invite with the pixel speech bubble (dwell to accept, or click OK; only
  the OK button ever takes a click) and follow-the-pointer with switchbacks;
  weighted picks with a 3 to 15 second gap; petting by hovering, with hearts.
- **Outfit**: gold chain always, shades 35% of visits, both anchored per frame
  from the white eye pixels of the raw sheet; shades for every crawl.
- **Crawler mode**: up to four visible windows on the cat's screen, the zap,
  and the five breach styles in the six accent colours.
- **Idle crawl**: after `idleCrawlSeconds` (120) with no input, the walk in,
  the 2x grow with pulsing rings, then the whole screen (taskbar too) turns into
  a glitch that stays, a new style every `glitchStyleSeconds`, the cat roaming
  up, down and sideways with depth shrink and zig-zags, zapping windows, and at
  the edge bringing the next app's window forward. Any input ends it: the glitch
  goes at once, the cat shrinks to nothing over 0.8 s, and the window you were
  in comes back. It does not start while a blocked app is in front or
  fullscreen.
- **The 50 glitch styles**: the same names, layers and palettes, rendered at
  half resolution (in logical pixels) about 20 times a second and scaled up
  nearest-neighbour under the cat.
- **Mr. Robot**: the 3 second "MR. ROBOT IN 3" countdown, 4x speed, a new style
  every 15 seconds, a 2x faster cat that hops apps after one window, three
  minutes or the first touch, the same shrink exit.

## What differs, and why

- **"Next app" is a window, not a Space.** Windows has no Spaces to slide
  between, so at the edge the cat brings the next app's top window forward
  (apps on the cat's screen first, in name order, skipping blocked apps and
  minimised windows). Windows only lets the app you are using change the
  foreground, so it borrows the foreground thread's input state
  (`AttachThreadInput`) and, if that is refused, taps Alt with a masking key so
  no menu opens. The taps are marked as injected and never count as you coming
  back.
- **Only real input ends the crawl.** Low-level keyboard and mouse hooks run
  only while the crawl is out and ignore injected events. If hooks are blocked
  (some managed PCs), it falls back to `GetLastInputInfo`.
- **No playground window.** The Mac's "Open playground" and its offscreen
  tools (`--preview`, `--simulate`, `--takeover`, `--glitches`,
  `--watching`, `--checkpid`) are folded into `--selftest`.
- **Fonts.** The code walls use Consolas (or Cascadia Mono), and the katakana
  rain uses Yu Gothic or Meiryo when installed. Without a Japanese font the
  rain shows only its digits and Latin letters.
- **Colour bars** use fixed RGB values for what macOS calls its system yellow,
  teal, green, pink, red and blue.
- **Fullscreen games** that take the display exclusively draw over every
  window, the cat included. Borderless fullscreen is fine.
- **Activity log**: app start and quit are found by polling every 5 seconds
  rather than from notifications, and "background apps" means programs in your
  session outside the Windows folder with no window. Bluetooth needs a
  Bluetooth radio Windows will report on.

## Status

Compiled and self-tested in CI on `windows-latest` (no real desktop there).
Not yet run by hand on a Windows PC, so treat the live parts as untested:
the layered window and its dirty-rect updates, click-through with the OK
button, capture exclusion, bringing other apps forward, the input hooks, the
tray menu and the activity log events.
