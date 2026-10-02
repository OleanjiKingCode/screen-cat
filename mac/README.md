# Screen Cat

A small purple cat that wanders across your Mac's screen from time to time.
Native AppKit, no runtime dependencies, one transparent click-through window that
never steals focus or blocks a click.

## Build and run

```bash
./build.sh && open ScreenCat.app
```

A `🐈` appears in the menu bar. That is the only visible chrome: no dock icon, no
window of its own.

**Only one cat, ever.** A second launch refuses to start and says so, so a login
item plus a manual launch cannot put two cats on the screen. The guard is an
advisory lock on `~/.screencat.lock`, held for the life of the process and
released by the kernel when it exits, so a crash cannot leave a stale one. Within
the running app a new routine always clears the current one first. The one-shot
tools below (`--preview`, `--simulate`, `--watching`, `--checkpid`) never take
the lock, so they work while the cat is out.

## Art credit

Sprites are the free tier of **[Cat Pack by Glem / octopusINKUS](https://octopusinkus.itch.io/cat-pack)**.
The files in `Assets/` are the author's originals, unmodified on disk; Screen Cat
recolours them in memory at launch. The pack states no licence and is a
name-your-own-price download, so it is used here in a personal, non-redistributed
toy. If you keep it, pay the author. See `Assets/CREDIT.txt`.

`Cat_Ball.png` is the yarn ball cropped out of the pack's play animation so it can
roll around on its own.

## What the cat does

One routine at random every few minutes, then it hides until the next one.

| Routine | What happens |
| --- | --- |
| **Walk** | Pads in from one side, wanders through two to four waypoints along the bottom of the screen at a changing pace, sometimes stops to sit and look around, then leaves by a side. |
| **Nap** | Walks in from one side, lies down, sleeps with floating `z`s for 20 to 60 seconds, wakes, sits, and strolls back out. |
| **Ball** | A ball rolls in from one edge. The cat runs in from the same spot chasing it, pounces, rolls around batting it for a few seconds, then boots it off screen and runs off after it. |
| **Hungry** | Walks in, turns to face you, sits up with an empty food bowl beside it, blinks and stares, then wanders off. |
| **Let's play** | Rare. Walks in, sits, and puts up a pixel speech bubble asking for a game. Say yes and it follows your pointer for a minute. Ignore it and it gives up after three. |

Only the ball chase runs. Every walk is a walk.

## How the cat moves

The cat treats a screen edge as the floor and walks along it. Usually the bottom
edge; `wallChance` of the time it uses the left or right edge instead, rotated a
quarter turn with its paws against the glass.

All the walking maths is written in surface-local coordinates, where x runs along
the floor and y is height above it. One transform at draw time maps that onto the
screen, so walking up a wall is the same code as padding along the bottom. The
rules below are stated in that local frame, and hold on every edge:

- **It stays near the floor.** Positions are pulled toward the edge by
  `groundBias` within a band set by `roamHeight`. Raise `roamHeight` to let it
  stray further out; lower `groundBias` to spread it evenly through the band.
- **Paths never climb.** Every leg is level with or below the last. On a wall
  that means it never drifts away from the wall, which is the same idea: a
  side-on cat leaving its floor reads as levitating.
- **Paths are never steep either.** Descent is capped at `maxSlope` (rise over
  run, default `0.45`), so travel is sideways or a shallow diagonal, never a
  vertical drop.
- **It comes and goes along the floor**, entering and leaving past either end.
- **Curves, not bobbing.** A non-straight path is one gentle arc per leg, capped
  at 8% of the leg's length. A repeating perpendicular wave is vertical movement
  by another name.
- **Perspective.** The cat draws slightly smaller the further it is from its
  floor, so drifting off it reads as distance rather than lift. `depthShrink`
  controls it; `0` for a flat look.

Begging always uses the bottom edge, since it faces you and only makes sense the
right way up. In practice the cat only ever plays the profile walk; the front-on
walk is kept for the begging pose.

## Outfit

Each visit the cat rolls what it wears: a gold chain (`chainChance`, 1.0 so
always) and small black shades with a glint (`glassesChance`, 0.35 so about one visit
in three). Both are baked per sprite frame from where the eyes are, so they stay
on the face through walks, blinks, runs and the ball play. See them all with
`--preview out.png --outfit`.

## Modes and the playground

Pick the mode from **Mode** in the menu, or the switch in the playground. One
mode drives both, and it is saved as `mode` in the settings.

- **Normal**: the routines above.
- **Crawler**: most visits (`crawlChance`, 0.7) become a crawl. The cat puts
  its shades on, walks under up to four windows on the screen, zaps each one
  with a green bolt from its head, and the window "breaks": it darkens, slices
  jump sideways in red and cyan, cracks spread from the hit, fictional hacker
  code types itself out, and a "SYSTEM BREACHED" banner flashes before
  "REBOOTING..." and it clears. It is all paint on the cat's overlay; no app is
  touched. Windows of apps on `blockedApps`, and windows mostly hidden behind
  others, are skipped. **Break some apps (crawler)** runs one now in any mode.

**Idle crawl.** After `idleCrawlSeconds` (120) with no mouse, trackpad or
keyboard input, in **any** mode (normal included), the cat walks onto the
screen, stops, and grows to `growScale` (2x) in pulses inside a ring of light.
Then the **whole screen** (menu bar and Dock too) turns into a glitch, and
stays that way. There are 50 full-screen styles (Digital Rain, Kernel Panic, No
Signal, Meltdown, Grid Runner, Radar Lock, Error Storm, Worm Outbreak, Hex
Dump, Ransomware and more), all in danger colours: blood red, terminal green,
warning amber and white on black. One plays for
`glitchStyleSeconds` (60), then the next takes over. The cat roams the screen
on top, up, down and sideways (shrinking as it goes up, zig-zagging up steep
climbs), stops at windows and zaps them, which flashes the screen. At the edge
of the screen it brings the next app forward, so macOS slides to it like a
three-finger swipe. The glitch drops for that moment, so you see the new screen
normally while the cat walks in, then a new style takes over. The first touch
or key press ends it: the glitch goes at once, the cat shrinks away to nothing,
and you are back in the app you left. Normal visits carry on after that. It does not start
while a blocked app (video) is in front or fullscreen, and stops when the
display sleeps. Only real hardware input counts. **Crawl until I touch
something** starts one now. `idleCrawl: false` turns it off.

**Zero Day.** **Mode > Zero Day (3 min hack, starts now)** is a three-minute
hacked-computer show with no cat at all. It starts the moment you pick it (input
in the first 1.5 seconds, letting go of the trackpad, does not count). The whole
screen glitches at `zeroDaySpeed` (8x) with bursts of red flashes, rendering at
30 fps, over a quiet background sound made live by the app: a low throbbing
drone, quick data beeps, bursts of static crackle and a rising whoosh on every
hop (`zeroDaySound`, `zeroDayVolume` 0.25). Every 1.5 to 3 seconds it jumps to
a random app one to three places left or right (the third app to the left,
then the second to the right, and so on); macOS slides to it, the glitch dims
for 0.8 s so you glimpse the app, then a new style takes over. It ends after
three minutes or at the first touch, with the glitch and sound gone at once and
you back in the app you started in. It does not change the saved mode.
`--idle-selftest zeroday` runs it invisibly and silently;
`--zeroday-sound out.wav [seconds]` writes the sound to a file.

The glitch renders at half resolution, 20 frames a second, on its own layer
under the cat; the slowest style takes about 12 ms a frame. See every style:
`--takeover out.png`; time them: `--takeover-bench`; run the crawl invisibly
and log it: `--idle-selftest`. The short per-window glitches of crawler mode:
`--glitches out.png`.

**Open playground** opens a window with its own cat and five pretend apps
(Terminal, Browser, Notes, Music, Files). Buttons run a walk, nap, ball, feed or
a crawl on demand; between them it picks its own routines for the current mode.
Render it headless with `--playground out.png [seconds]`.

## Activity log

A plain-text diary of the Mac, one file per day in `~/Library/Logs/ScreenCat`
(menu: **Open today's activity log** / **Show all activity logs**). It records:

- which app is in front, when, and how long the last one was (`APP`), with
  `[fullscreen]` when it fills a display;
- apps and background helpers opening and quitting (`OPENED`, `QUIT`,
  `BG-START`, `BG-STOP`);
- sleep, wake, screen off and on, lock, unlock, user switches, shutdown;
- idle: no input for five minutes, and how long you were away (`IDLE`);
- Bluetooth on or off, as it changes (`BLUETOOTH`);
- at start, after wake and every hour, every open app, every background app and
  your own command-line processes such as node, python or postgres (`RUNNING`);
- what the cat did (`CAT`), and on every app switch while it is out, whether
  its window is really on the Space you are looking at. A `NO` there names an
  app the cat failed to show over.

Local only: no window titles, keystrokes or screen contents. Bluetooth needs a
one-time permission (Privacy & Security > Bluetooth); an ad-hoc signed rebuild
may ask again. `activityLog: false` turns it off; `activityLogDays` (30) is how
long day files are kept, `0` keeps them forever.

## Petting

Rest the pointer on the cat for `petSeconds` (1s) and it stops, sits and shows
two hearts, then carries on. A sleeping cat stays asleep and just gets the
hearts. It is hover only, so no click is taken from the app underneath. Move off
the cat before it can be petted again. Not during the play invite, which has its
own dwell.

## Saying yes to a game

When the cat asks to play, there are two ways to accept, and it takes whichever
comes first:

- **Rest the pointer on the cat or its bubble.** After `dwellSeconds` it takes
  that as a yes. The OK button fills up as the time accrues, so you can see it
  happening rather than guessing. Moving the pointer away resets it, otherwise a
  pointer parked at the bottom of the screen would accept by accident.
- **Click the OK button.** Instant.

Ignore both and it gives up after `inviteSeconds` and wanders off.

Clicking needed care, because the overlay is click-through everywhere so it can
never intercept anything. The window only stops ignoring mouse events while the
pointer is actually within the OK button, and the view's `hitTest` returns itself
for that rect alone. Everywhere else, and at every other moment, clicks pass
straight through to whatever is underneath. The dwell needs none of that: it just
reads the pointer position each frame and intercepts nothing at all.

Once you accept, the cat trots after your pointer across the **whole screen**,
both axes. That means giving up the "never leave the floor" rule, so two other
mechanisms have to stop it looking like levitation:

- **The screen becomes a floor receding away from you.** The cat shrinks as it
  moves up it, by `followDepthShrink`, so height reads as distance rather than
  lift. Do not set this to zero: it is the thing doing the work.
- **It still never travels steeply.** Vertical speed stays within `maxSlope` of
  horizontal, so it can neither rise nor drop vertically. Measured over a full
  follow: the steepest move was exactly 0.45 rise over run, never above.

When your pointer is somewhere it cannot reach on one shallow diagonal (straight
overhead, say), the cat **switchbacks**, zig-zagging up the way you would walk a
slope too steep to take head on, rather than floating straight there.

## Where it shows up

The window sits at `windowLevel: "top"` and joins every Space, so the cat appears
over full-screen apps, not just the desktop. Drop it to `"status"` or `"floating"`
if you would rather it stayed under things, but note `"floating"` is why an
earlier version only ever showed on the desktop: a full-screen app sits above it.

**It never appears in screenshots, screen recordings, or anything you screen
share.** The window is marked `sharingType = .none`, so macOS keeps it out of
every capture path while still drawing it on the glass for you. That covers
Cmd-Shift-3/4, QuickTime and OBS recordings, and screen sharing on a video call.
Tick **Show in screenshots & recordings** in the menu, or set
`hideFromCapture: false`, if you want the cat in your captures.

If you also want the cat off your own screen during calls, add the meeting app to
`blockedApps`: that hides it while the app is frontmost.

## Keeping out of the way

The cat shows up over everything, with one exception: apps you name in
`blockedApps`, and only while one of them is **frontmost or fullscreen**. That is
the whole rule. `hideWhileWatching: false` turns even that off.

The default list is video players only: VLC, IINA, mpv, QuickTime, TV, Netflix,
Plex, Infuse. Entries are bundle-identifier fragments matched as case-insensitive
substrings, so `org.videolan.vlc` or just `vlc` both work. Add any app you never
want the cat walking over.

**Why it is not cleverer than that.** An earlier version inferred "video is
playing" from the display-sleep power assertion, which every video player takes so
the screen does not dim mid-film. It caught Netflix in a browser tab, which no app
list can. It was also useless in practice: WhatsApp holds that same assertion
permanently as an idle timer, and Electron apps do the same, so focusing WhatsApp
banished the cat for no reason. Guessing intent from a power assertion is not
worth an app that hides when you are chatting. The cost of the simpler rule is
that video in a browser tab no longer counts as watching. Add the browser to
`blockedApps` if you would rather have that back.

If a blocked app comes to the front while the cat is out, it leaves within half a
second. Choosing a routine from the menu overrides all of this: if you ask for the
cat, you get the cat. The top line of the menu says what it is doing, including
why it is hiding.

Window positions come from `CGWindowListCopyWindowInfo`. Bounds and owning
process are readable without Screen Recording access; only window *titles* need
it, and those are never requested.

## Menu bar

- **Take a walk / Have a nap / Chase a ball / Beg for food**: play a routine now.
- **Ask to play**: put the invite up now.
- **Pause**: stop until you resume.
- The top line says what the cat is doing, or how long until the next visit.
- **Show in screenshots & recordings**: ticked, the cat appears in captures.
  Unticked (the default) it stays out of them. Takes effect immediately and is
  written back to your settings, so it survives a restart.
- **Open at login**: writes or removes the same LaunchAgent as
  `install-login-item.sh`. Takes effect at the next login.
- **Edit settings…** / **Reload settings**.
- **Quit Screen Cat**.

## Settings

`~/.screencat.json`, created on first launch. Edit it and hit **Reload settings**
(it is also re-read at the start of every routine).

| Key | Default | Meaning |
| --- | --- | --- |
| `sizeDivisor` | `24` | Cat height = screen height / this. **Raise it to shrink the cat, lower it to grow.** The sprites are 32px art, so a small cat is a crisp one. |
| `firstAppearanceDelay` | `20` | Seconds after launch before the first appearance. |
| `opacity` | `1.0` | Overall transparency. Below `1` makes a small cat noticeably harder to spot. |
| `minGapSeconds` / `maxGapSeconds` | `3` / `15` | Random quiet gap between routines. With routines lasting 20-60s, these defaults keep the cat on screen roughly 80% of the time. Raise them for a rarer cat. |
| `walkSpeed` / `runSpeed` | `1.35` / `4.2` | Pace in body-heights per second, so it scales with `sizeDivisor`. If you make the cat much bigger, drop these or it will tear across the screen. |
| `napSecondsMin` / `napSecondsMax` | `20` / `60` | How long a nap lasts. |
| `begSecondsMin` / `begSecondsMax` | `9` / `20` | How long the hungry act lasts. |
| `playSecondsMin` / `playSecondsMax` | `4` / `8` | How long it rolls around with the ball. |
| `depthShrink` | `0.18` | How much smaller the cat gets at the top of the screen. `0` disables perspective. |
| `roamHeight` | `0.55` | The cat only uses the bottom this fraction of the screen. |
| `groundBias` | `3.0` | Pull toward the very bottom. `1` spreads it evenly through the band, higher hugs the edge. |
| `maxSlope` | `0.45` | Steepest walk allowed, rise over run. Lower is flatter. |
| `wallChance` | `0.4` | How often a routine walks the left or right edge instead of the bottom. `0` keeps it on the bottom only. |
| `windowLevel` | `"top"` | `"top"` shows over full-screen apps. `"status"` and `"floating"` sit lower; `"floating"` only shows on the desktop. |
| `hideFromCapture` | `true` | Keep the cat out of screenshots, recordings and screen sharing. Also on the menu as **Show in screenshots & recordings**, inverted. |
| `hideWhileWatching` | `true` | Honour `blockedApps` at all. `false` means the cat shows over absolutely everything. |
| `blockedApps` | VLC, IINA, mpv, QuickTime, TV, Netflix, Plex, Infuse | Apps that hide the cat while frontmost or fullscreen. Bundle-identifier fragments, matched as case-insensitive substrings. |
| `weightStroll`, `weightNap`, `weightBall`, `weightHungry`, `weightPlay` | `4`, `2`, `2`, `2`, `0.25` | Relative chance of each routine. Set one to `0` to turn it off. `weightPlay` is low on purpose: the invite ties the cat up for minutes. |
| `inviteSeconds` | `180` | How long the cat waits with its bubble up before giving up. |
| `dwellSeconds` | `30` | Pointer rest needed to accept. **30 is a long time to hold still, try `8`.** |
| `followSeconds` | `60` | How long it follows your pointer once you accept. |
| `petSeconds` | `1.0` | Pointer rest on the cat needed for a pet. `0` turns petting off. |
| `followDepthShrink` | `0.35` | How much smaller the cat gets at the top of the screen while following. This is what makes climbing read as walking away, so keep it well above `0`. |
| `furColor`, `furShadeColor`, `outlineColor` | purple | Coat colours, `#RRGGBB`. |
| `innerColor` | `#F5A8CE` | Inner ear. |
| `eyeColor` | `#FFC94A` | Eyes. |
| `ballColor` | `#BC4A9B` | The rolling yarn ball only. The ball in the play animation is baked into the sprite and keeps the pack's pink, because the cat's nose and mouth are drawn in the same two colours. |
| `shadow` | `true` | Shadow under the cat. |
| `chainChance` | `1.0` | Chance per visit of the gold chain, `0` to `1`. |
| `glassesChance` | `0.35` | Chance per visit of the shades, `0` to `1`. |
| `mode` | `normal` | `normal` or `crawler`. Also set from the menu and the playground. |
| `crawlChance` | `0.7` | In crawler mode, the chance a visit is a crawl. |
| `idleCrawl` | `true` | Start the nonstop crawl when you leave the Mac alone. |
| `idleCrawlSeconds` | `120` | How long with no input before it starts. At least `15`. |
| `growScale` | `2` | How big the cat grows when the idle crawl starts, `1` to `4`. |
| `glitchStyleSeconds` | `60` | How long each full-screen glitch style plays at speed 1. At least `5`. |
| `glitchSpeed` | `2` | How fast the idle crawl's glitches animate and change. |
| `zeroDaySpeed` | `8` | The same for Zero Day. |
| `zeroDaySound` | `true` | Play Zero Day's background sound. |
| `zeroDayVolume` | `0.25` | How loud it is, `0` to `1`. |
| `activityLog` | `true` | Keep the daily activity log in `~/Library/Logs/ScreenCat`. |
| `activityLogDays` | `30` | Delete day files older than this. `0` keeps them forever. |
| `opacity` | `1.0` | Overall transparency, `0.1` to `1.0`. |

## Start at login

```bash
./install-login-item.sh
```

Removes with `./install-login-item.sh --uninstall`.

## Handy flags

```bash
./ScreenCat.app/Contents/MacOS/ScreenCat --demo
```

Plays every routine back to back with a two second gap, so you can see the lot
without waiting. **Quit the menu bar copy first**: `--demo` is the real app, so
the single-instance lock will refuse to start it alongside another.

```bash
./ScreenCat.app/Contents/MacOS/ScreenCat --preview sheet.png
```

Renders a contact sheet of every animation to a PNG. Useful after changing colours.

```bash
./ScreenCat.app/Contents/MacOS/ScreenCat --simulate stroll out.png --surface left
```

Plays one routine offscreen through the real window and view, prints the clip
sequence and the area covered, and writes a trail of where the cat went. This is
how the movement rules get checked without needing a screen recording.

```bash
./ScreenCat.app/Contents/MacOS/ScreenCat --watching
```

Reports whether the cat would currently stay out of the way, and why: what is
playing, what is frontmost, whether anything playing is fullscreen here, and a
self-check that window detection works at all. Cross-check against
`pmset -g assertions`.

```bash
./ScreenCat.app/Contents/MacOS/ScreenCat --checkpid 1234
```

Lists one process's on-screen windows with their sizes, and says whether any of
them is fullscreen here. Useful for working out why a player is or is not
counting as "being watched".

## Notes

- The cat appears on whichever display your pointer is on.
- It uses the screen's `visibleFrame`, so it stays clear of the Dock and menu bar.
- The window sits at floating level: above normal windows, below menus, and not
  over full-screen apps.
- Click-through everywhere. The cat can never intercept a click.
- Between routines the window is removed and the frame timer stopped, so an idle
  cat costs nothing.
