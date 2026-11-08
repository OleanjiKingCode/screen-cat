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
recolours them in memory at launch. They are used with the artist's permission.
If you want the cat art for something else, get it from the artist's page. See
`Assets/CREDIT.txt`.

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
| **Trash rescue** | Not random: it runs when you throw something from the Desktop, Documents or Downloads in the Trash. See Trash rescue. |

Only the ball chase and the trash rescue run. Every other walk is a walk.

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

**Idle crawl.** After `idleCrawlSeconds` (1800, half an hour) with no mouse, trackpad or
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

## LLM mode

Choose **LLM mode > Turn LLM mode on** in the menu (**Turn LLM mode off** to
stop). From then on, whatever you copy, and every screenshot you take, goes to
Claude. The cat walks on, sits, and holds up a card: "THINKING..." with what you asked, then
the answer. It works out what you want: a question gets answered, an equation
or sum gets solved with the steps, a claim gets checked, a word gets explained,
code or an error gets explained or fixed. The answer is plain text you can
select. Each answer also goes on the clipboard as it arrives, ready to paste
(**Copy answers to clipboard** in the menu, `llmCopyAnswer`, on by default);
**COPY** on the card copies it again. Close the card with the ✕ or Esc,
and the cat walks off. Otherwise it closes `llmAnswerSeconds` (120) after the
answer arrives, but never while the pointer is on it. You can drag the card.
A new question while the cat is sitting reuses the same card.

**Show answer box** (`llmShowAnswer`, on by default) controls the cat and the
card. Untick it and neither appears: each answer goes straight to the
clipboard, whatever **Copy answers to clipboard** says, and the cat in the menu
bar shows 💭 while it thinks, then ✅ when the answer is ready to paste (⚠️ if
there is no answer; hover the icon for why). Unticking it while a card is up
closes the card.

**Ask about what I copied** asks about the clipboard once, with or without LLM
mode.

- **How it talks to Claude**: it runs the `claude` command line tool (Claude
  Code) with the login you already have, so there is no API key to set up. It
  runs with no tools, no MCP servers, no CLAUDE.md and no memory, from an empty
  folder. An answer takes about 7 to 10 seconds. If `claude` is not in
  `~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin`, set `llmClaudePath`.
- **Screenshots** are picked up from the folder the Screenshot app saves to and
  from the Desktop, by the tag macOS puts on every screenshot. macOS asks once
  for access to the Desktop folder. The file only appears after the floating
  thumbnail goes, about 5 seconds; turn the thumbnail off in the Screenshot
  app's Options for a faster answer. A screenshot copied to the clipboard
  (Control in the shortcut) is picked up at once.
- **What is never sent**: anything a password manager marks as private, files
  copied in Finder, what was already on the clipboard when you turned the mode
  on, the same text twice in a row, and text copied out of the cat's own card.
  Everything else you copy is sent to Anthropic while the mode is on.
- **Screenshots & recordings**: the card follows the cat. With **Show in
  screenshots & recordings** unticked (the default), neither shows up in
  captures or screen sharing; ticked, both do. LLM mode works either way.
- Pause stops it from answering; a menu pick of **Ask about what I copied**
  still works while paused.

Test it without the cat: `--ask "2x^2 - 8x + 6 = 0"` or
`--ask-image screenshot.png` prints the answer.

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
own dwell, and not during a trash rescue: it is busy.

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

## Trash rescue

Drag a file or folder from the Desktop, Documents or Downloads, or from any
folder inside them, to the Trash (or press ⌘⌫) and the pet comes in from the
side nearest the Trash, runs to it and digs. Out pops a little pixel folder or
page, which it carries on its back toward the middle of the screen, then
tosses home: up to the top right for something that was right on the Desktop,
where the icons are, or over to Finder at the other end of the Dock for
anything else. When it lands, the real item is moved back from the Trash to
the exact path it came from. Several things thrown at once ride as a small
stack and all come back, a folder before anything that was inside it.

- **Once in ten minutes.** Throw the same thing away again within ten minutes (the
  same item, even renamed, or anything at the same path) and the pet lets it
  go: you meant it.
- **Never in the way.** Nothing happens while the pet is paused, while the
  screen is off, while a blocked app (a film) is in front, or while the pet
  is busy with an answer card, a game you said yes to, or the idle crawl. A
  film that comes to the front mid-rescue sends the pet home. The item just
  stays in the Trash.
- **Only from Finder.** It rescues only while Finder is the app in front, so
  what you throw away by dragging or with ⌘⌫. Files an editor or a script
  moves to the Trash while it is in front (VS Code deleting a file in a
  project, say) stay there, and the activity log names the app that was in
  front. It goes by the app in front, not by who moved the file, so a
  background tool trashing something while Finder is in front still counts.
- **Name taken.** If something new has the old name by then, it comes back
  as "name 2", the way Finder numbers copies.
- **Only the watched folders.** The Desktop, Documents and Downloads by
  default; set `trashRescueFolders` for others. Things thrown away from
  anywhere else, from hidden folders such as `.git`, emptied straight from
  the Trash, or deleted with `rm` are left alone. So is a move from one
  watched folder to another: only the Trash counts.
- **Folders it cannot watch.** A folder in `trashRescueFolders` that is not
  there, is not a folder, is on another disk (that disk has its own Trash),
  is or holds the Trash (such as your home folder), or sits inside another
  watched folder is left out, and the activity log says which and why.

How it sees it: `~/.Trash` cannot be listed without Full Disk Access, but
FSEvents still reports both ends of the move, the path that went away and the
Trash path that appeared, with the same file ID. Watching never looks inside
the folders. Putting it back is a plain move of that one path.

macOS protects the Desktop, Documents and Downloads, so when the rescue starts
the pet looks in each watched folder once, and macOS asks once whether Screen
Cat may use each protected one. That is also what lets it hear about throws
from there. It asks off the main thread, so the pet never waits. Say no, or
turn it off later in **System Settings > Privacy & Security > Files and
Folders**, and things thrown from that folder stay in the Trash; the activity
log says there is no access to it. A folder outside those three that cannot be
written gets a plain "no permission" line instead.

Where the Trash and Finder are comes from the Dock's own settings (side, icon
size and how many icons it shows), so the pet digs near the Trash, not always
exactly under it.

Untick **Rescue things I trash** in the menu, or set `trashRescue` to
`false`, to turn it off. **Play now > Dig something out of the Trash** shows
the routine with nothing real on its back.

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

The icon is the pet itself: a little silhouette of the cat or dog. A ☕ next
to it means **Stepped out** is on; 💭, ✅ and ⚠️ show an answer on its way when
the answer box is hidden. The menu, top to bottom:

- The top line says what the pet is doing, or how long until the next visit.
- **Pause** / **Resume**.
- **Pet: Cat / Dog**: switch pets, saved, at once.
- **Mode: Normal / Crawler**: the saved mode (see Modes).
- **Play now**: walk, nap, ball, beg, ask to play, dig something out of the
  Trash, break some apps, crawl until I touch something, and Zero Day (3 min
  hack).
- **LLM mode: On / Off** (see LLM mode):
  - **Answer what I copy or screenshot**: the mode itself.
  - **Ask about what I copied now**: once, with or without the mode.
  - **Show answer box** and **Copy answers to clipboard**.
  - **Set API key…**: paste an Anthropic API key, kept in the keychain. With a
    key, answers come from the Claude API directly; without one, from your
    Claude Code login. The last line says which one is in use.
- **Stepped out (Mac never sleeps)**: ticked, the Mac does not sleep and the
  screen does not go off, like `caffeinate -di`. Saved, so it survives a
  restart. Quitting lets the Mac sleep again. Closing the lid on battery still
  sleeps it.
- **Rescue things I trash**: ticked (the default), the pet digs things
  thrown from the watched folders out of the Trash and puts them back, once
  in ten minutes for each thing (see Trash rescue).
- **Show in screenshots & recordings**: ticked, the pet and its answer card
  appear in captures. Unticked (the default) they stay out of them.
- **Open at login**: writes or removes the same LaunchAgent as
  `install-login-item.sh`. Takes effect at the next login.
- **Open playground**.
- **Activity log**: today's log, or the folder with all of them.
- **Settings**: edit the settings file, or reload it.
- **Quit Screen Cat** (⌘Q).

On the very first launch a short welcome says where the app lives, with a
button to also open it at login.

## Pets

`pet` is `cat` (the default) or `dog`. The cat follows the colour settings; the
dog keeps its own tan coat and only its eyes are recoloured. Both wear the same
shades and gold chain. The dog is original art drawn by `mac/Tools/make_dog.swift`.

## App icon and releases

`--app-icon <dir.iconset>` draws the app icon with the app's own renderer;
`iconutil -c icns <dir.iconset> -o Assets/AppIcon.icns` turns it into the file
the build bundles. `./release.sh` builds and zips the app into
`dist/ScreenCat-mac-<version>.zip` (set `VERSION=` to change it) and prints its
SHA-256 for the release notes.

## Settings

`~/.screencat.json`, created on first launch. Edit it and hit **Reload settings**
(it is also re-read at the start of every routine).

| Key | Default | Meaning |
| --- | --- | --- |
| `pet` | `cat` | `cat` or `dog`. Also on the menu as **Pet**. |
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
| `idleCrawlSeconds` | `1800` | How long with no input before it starts (30 minutes). At least `15`. Keep it below the display sleep time, or the screen goes off first (not a problem while **Stepped out** is on). |
| `growScale` | `2` | How big the cat grows when the idle crawl starts, `1` to `4`. |
| `glitchStyleSeconds` | `60` | How long each full-screen glitch style plays at speed 1. At least `5`. |
| `glitchSpeed` | `2` | How fast the idle crawl's glitches animate and change. |
| `zeroDaySpeed` | `8` | The same for Zero Day. |
| `zeroDaySound` | `true` | Play Zero Day's background sound. |
| `zeroDayVolume` | `0.25` | How loud it is, `0` to `1`. |
| `steppedOut` | `false` | Keep the Mac awake and the screen on. Also on the menu as **Stepped out**. |
| `trashRescue` | `true` | Dig things thrown from the watched folders out of the Trash and put them back. Also on the menu as **Rescue things I trash**. |
| `trashRescueFolders` | `["~/Desktop", "~/Documents", "~/Downloads"]` | The folders the trash rescue watches, with every folder inside them. `~` is your home folder. Changes apply on **Reload settings**. |
| `llmMode` | `false` | Answer what you copy and screenshot. Also on the menu as **LLM mode**. |
| `llmFromClipboard` / `llmFromScreenshots` | `true` / `true` | Which of the two LLM mode listens to. |
| `llmCopyAnswer` | `true` | Put each answer on the clipboard as it arrives. Also on the menu as **Copy answers to clipboard**. |
| `llmShowAnswer` | `true` | Show the cat and the answer card. `false` sends answers only to the clipboard, with a badge on the menu bar icon. Also on the menu as **Show answer box**. |
| `llmModel` | `claude-opus-5-5` | The Claude model that answers. |
| `llmEffort` | `medium` | How hard it thinks: `low`, `medium`, `high`, `xhigh` or `max`. |
| `llmAnswerSeconds` | `120` | Close the answer this long after it arrives, unless the pointer is on it. `0` keeps it until you close it. |
| `llmClaudePath` | `""` | Full path to `claude`, if it is not in one of the usual places. |
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
how the movement rules get checked without needing a screen recording. For
`rescue`, `--from Documents` makes the pretend folder come from Documents, so
it is tossed to Finder instead of the Desktop.

```bash
./ScreenCat.app/Contents/MacOS/ScreenCat --rescue-selftest [desktop] [folders]
```

Checks the trash rescue end to end without the pet: throws a scratch file, a
scratch folder, a name the Trash already holds, a file from a folder inside a
watched one, and a file it may not put back, checks each one is seen, puts
them back, and deletes them again. Also checks that folders it cannot watch
are left out, and that a move to another folder, watched or not, is not taken
for a throw. Uses scratch folders, or the real Desktop with `desktop`.
`folders` also throws scratch files from the real Documents and Downloads and
from a folder inside each, and moves one from Documents to the Desktop, so it
touches the real Desktop too. macOS
protects those folders, so run `folders` from a terminal that already has
access to them, or macOS asks. Everything it makes is deleted again, in every
folder and in the Trash. Prints PASS or the first thing that failed.

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
