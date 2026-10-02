# Screen Cat

A purple pixel cat that lives on your screen. It walks, naps, chases a ball,
begs for food, asks you to play, and in crawler mode it "hacks" your windows
with fake glitches, cracks and scrolling code. Nothing it does touches your
apps; it is all drawn on a see-through overlay.

| Platform | Folder | State |
| --- | --- | --- |
| macOS | [`mac/`](mac/) | Working. Native Swift/AppKit. See [mac/README.md](mac/README.md). |
| Android | [`android/`](android/) | Planned. See [android/README.md](android/README.md). |
| Windows | [`windows/`](windows/) | Planned. See [windows/README.md](windows/README.md). |

## Quick start (Mac)

```bash
cd mac
./build.sh
open ScreenCat.app
```

A 🐈 appears in the menu bar. Settings live in `~/.screencat.json`.

## Shared across platforms

Every port reuses the same pieces, so the cat looks and acts the same:

- **Sprites**: `mac/Assets` (32x32 frames, 12x9 grid, rows listed in
  `mac/Sources/Sprites.swift`).
- **Movement rules**: enters and leaves from the sides, never climbs straight
  up, shrinks as it goes up the screen, zig-zags up steep climbs
  (`maxSlope` 0.45).
- **Routines**: stroll, nap, ball, hungry, play, crawl, idle crawl.
- **Glitch styles**: breach, falling code, crash screen, no signal, meltdown,
  in six colours.
- **Settings keys**: the same JSON keys as `~/.screencat.json` on the Mac.

## Art credit

"Cat Pack" (free tier) by Glem / octopusINKUS,
https://octopusinkus.itch.io/cat-pack. The pack states no licence, so this repo
must stay private. Do not make it public with the sprites inside.
