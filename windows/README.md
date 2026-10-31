# Screen Cat for Windows

The Windows version of the purple desktop cat. Same routines, same movement
rules, same outfit, same cat or dog, same crawler mode, same 50 full-screen
glitch styles, Zero Day with its sound, Stepped out and LLM mode. C# on .NET 8
with WinForms for the tray menu and plain Win32 for the window and the sound.
No packages beyond .NET itself. The Mac source in `../mac/Sources` is the spec; most files here are a
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
| API key (LLM mode) | Windows Credential Manager, generic credential `ScreenCat/anthropic-api-key` |
| Screenshots LLM mode watches | the Screenshots folder (`Pictures\Screenshots` unless you moved it) |
| Sprites and icon | embedded in the exe from `ScreenCat\Assets` |

## Art credit

The cat is the free tier of **Cat Pack by Glem / octopusINKUS**
(https://octopusinkus.itch.io/cat-pack), used with the artist's permission.
The PNGs are the artist's originals, unmodified on disk; the cat is recoloured
in memory at launch. The dog is original art made for Screen Cat
(`../mac/Tools/make_dog.swift`). See `ScreenCat\Assets\CREDIT.txt`.

## Tray menu

Left or right click the tray cat. The same groups as the Mac menu.

- The top line says what the pet is doing, why it is hiding, or how long until
  the next visit.
- **Pause** / **Resume**.
- **Pet: Cat / Dog**: switch pets at once, even mid-walk. Saved as `pet`.
- **Mode: Normal / Crawler**: saved as `mode`.
- **Play now**: take a walk, have a nap, chase a ball, beg for food, ask to
  play, break some apps, crawl until I touch something, and **Zero Day (3 min
  hack)**. A menu pick ignores the blocked-app rule: if you ask for the pet,
  you get the pet. Zero Day runs once and leaves the saved mode alone.
- **LLM mode**: turn it on or off, ask about what is on the clipboard now,
  show or hide the answer box, copy answers to the clipboard, set your API key.
  The last line says where answers come from.
- **Stepped out (PC never sleeps)**: an amber dot on the tray cat while it is on.
- **Show in screenshots && recordings**: ticked, the pet and its answer card
  show in captures.
- **Open at login**.
- **Activity log**: open today's log, or the folder with all of them.
- **Settings**: edit the settings file (opens Notepad), or reload it (settings
  are also re-read at the start of every routine).
- **Quit Screen Cat**.

The first launch shows a short "Screen Cat is running" note that says where
the tray cat is, with a button to also open it at login.

## LLM mode

Turn it on in **LLM mode > Turn LLM mode on**. From then on:

- **Copy** any text and the pet walks on with a card: THINKING, then the
  answer. The card does not take focus from your app. Click it to select
  text; Esc or the cross closes it; drag it by its edge or heading.
- **Take a screenshot** with Win+Shift+S, Win+Print Screen or the Snipping
  Tool and it answers what is in it. Those tools copy the picture and save it
  too, so one screenshot is asked about once, not twice.
- **Show answer box** off: no pet and no card. The answer goes on the
  clipboard, and a dot on the tray cat shows blue while it thinks, then green
  (copied) or red (no answer; the tooltip says why).

Answers come from your own Anthropic API key if one is saved (**Set API
key...**), or else from the `claude` command (Claude Code) with its login.
Screen Cat looks for `claude.exe` in `%USERPROFILE%\.local\bin`, the npm shim
`claude.cmd` in `%APPDATA%\npm`, the WinGet links folder and `PATH`; set
`llmClaudePath` if it is somewhere else. It runs with no tools, no MCP
servers, no CLAUDE.md and no memory, from an empty temp folder.

Never sent: anything a password manager marks as private on the clipboard
(`ExcludeClipboardContentFromMonitorProcessing`, `Clipboard Viewer Ignore`, or
`CanIncludeInClipboardHistory` set to 0), copied files, whatever was already on
the clipboard when the mode was turned on, the same text twice in a row, and
text copied out of the pet's own answer.

## Settings

Same keys and defaults as the Mac's `~/.screencat.json`; see the table in
`../mac/README.md`. Differences:

| Key | On Windows |
| --- | --- |
| `idleCrawlSeconds` | 1800 (30 minutes), the same as the Mac. |
| `steppedOut` | Uses `SetThreadExecutionState` for the system and the display. `powercfg /requests` lists it under ScreenCat.exe. |
| `zeroDaySound`, `zeroDayVolume` | Played through `waveOut`. With no sound device, Zero Day is silent. |
| `llmClaudePath` | A full path to `claude.exe` or `claude.cmd`. |
| `blockedApps` | Process names, not bundle ids, matched as case-insensitive substrings. Default: `vlc`, `mpc-hc`, `mpc-be`, `PotPlayer`, `mpv`, `wmplayer`, `Video.UI` (Movies & TV), `Microsoft.Media.Player` (Media Player), `Netflix`, `Plex`, `KMPlayer`, `GOM`. Store apps are matched by the app's own process, not `ApplicationFrameHost`. |
| `windowLevel` | `"top"` and `"status"` keep the cat always on top. `"floating"` drops the always-on-top flag, so other windows can cover it. |
| `hideFromCapture` | Uses `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`, which needs Windows 10 version 2004 or later. Older builds show the cat in captures. |
| `glitchSpeed`, `zeroDaySpeed` | Same as the Mac: 2 (0.25 to 16) for the idle crawl's glitch clock, 8 (1 to 16) for Zero Day. |
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
  and Zero Day never move steeper than `maxSlope`; all 50 glitch styles render,
  with milliseconds per frame; the overlay window can be made and updated, and
  whether capture exclusion was accepted.
- `preview.png` and `preview-dog.png`: every clip of the cat and of the dog,
  with and without the outfit, plus the bubble, hearts, bowl, ball and the
  pixel font.
- `glitches.png`: the five crawler-mode glitches and a zap.
- `takeover.png`: all 50 full-screen styles as thumbnails.
- `trail.png`: where one stroll went.
- `zeroday.wav`: four seconds of Zero Day's sound, with hops.

The report also checks the dog's art and stride, that Zero Day has no
countdown, that the LLM cat sits and leaves by the side, how Claude's replies
are read (API and command line, answers and errors), and that a big
screenshot is shrunk to 1568 px before it is sent.

`--demo` plays the walk, ball, beg and nap back to back with a two second gap.

`ScreenCat.exe --ask "some text"` or `--ask-image picture.png` sends one
question through LLM mode with your real settings and prints the answer in the
terminal. `--zeroday-sound out.wav [seconds]` writes Zero Day's sound to a
file.

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
  a glitch that stays, animated at `glitchSpeed` (2x) with a new style every
  `glitchStyleSeconds` of glitch time. The cat roams up, down and sideways
  with depth shrink and zig-zags, zaps at most two windows and visits one open
  spot per screen, then at the edge bringing the next app's window forward. Any input ends it: the glitch
  goes at once, the cat shrinks to nothing over 0.8 s, and the window you were
  in comes back. It does not start while a blocked app is in front or
  fullscreen.
- **The 50 glitch styles**: the same names, layers and palettes, rendered at
  half resolution (in logical pixels) about 20 times a second (30 for Zero
  Day) and scaled up
  nearest-neighbour under the cat.
- **Zero Day**: no cat at all and no countdown. The whole screen glitches at
  `zeroDaySpeed` (8x) straight away (0.3 s fade in) with random flash bursts,
  over a live drone with data beeps and static. Input in the first 1.5 s is
  ignored, so letting go of the mouse after the click does not stop it. Every 1.5 to 3 seconds it hops to a random app one to three places left
  or right of the one in front, in the name-sorted list of switchable windows;
  during the 0.8 s hop the glitch dims to 25% so you glimpse the app, a whoosh
  plays, then a new style starts. It ends after three minutes or at the first input: the glitch
  clears at once and the window you started in comes back. It does not change
  the saved mode.
- **Hacker text, no cat theme in the glitches**: the same renamed styles
  (Kernel Panic, Root Wall, Worm Outbreak, Access Denied, Ransomware, Fatal
  Exception, Binary Rain, Blood Rain, Grid Runner, Red Haze, Firewall Melt,
  Breach Tunnel, Signal Intercept, Lockdown) and the same code, crash screen,
  popup and loading text as the Mac.
- **Danger colours only**: every palette, accent, slice tint and colour bar is
  red, green, amber or white on black, and zap flashes are alarm red (white one
  time in four), as on the Mac.

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
- **The tray icon is in colour.** Windows tray icons are not tinted like a
  Mac menu bar template, so the pet shows as itself, and the Mac's ☕ and
  answer badges are small coloured dots on it instead of text.
- **API key in Credential Manager**, not a keychain. `ANTHROPIC_API_KEY` in
  the environment works too.
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
tray menu and its dots, the answer card, the clipboard and screenshot
watchers, the `claude` command on a real install, the Zero Day sound, Stepped
out, and the activity log events.

## Release

Publishing a GitHub release runs the CI and attaches
`ScreenCat-windows-<version>.zip` (the exe and CREDIT.txt) to it. The exe is
not code-signed, so Windows SmartScreen warns the first time: **More info >
Run anyway**.
