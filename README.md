# Screen Cat

A pixel pet that lives on your Mac screen. Pick a purple cat or a dog. It walks
along the bottom and the sides of your screen, naps, chases a ball, begs for
food, and asks you to play. Rest the pointer on it and it gets petted.

It can also answer things for you. Turn on **LLM mode**, copy a question or
take a screenshot, and the pet walks out holding the answer: maths solved with
the steps, facts checked, code explained, words defined.

Nothing it does touches your apps. It is all drawn on a see-through layer that
your clicks pass straight through.

## What it does

- **Cat or dog**: switch from the menu bar at any time, even mid-walk.
- **Routines**: walks, naps, ball chasing, begging, a "let's play" invite after
  which it follows your pointer, and petting with hearts.
- **LLM mode**: answers what you copy or screenshot, in a small card above the
  pet, and puts the answer on your clipboard. Works with your own Anthropic API
  key, or with Claude Code if you have it. You can hide the card and get
  answers on the clipboard only.
- **Crawler mode**: the pet "hacks" your windows with fake cracks, glitches and
  scrolling code. Only paint.
- **Zero Day**: a three-minute fake hack of your whole screen, with sound.
- **Idle takeover**: leave the Mac alone for half an hour and the pet grows
  and turns the screen into a glitch show until you touch something.
- **Stepped out**: keeps the Mac awake and the screen on.
- **Private by default**: the pet and its answer card stay out of screenshots,
  recordings and screen sharing unless you say otherwise.
- **Stays out of the way**: hides while a video player is in front.

## Install (Mac)

1. Download `ScreenCat-mac-<version>.zip` from
   [Releases](../../releases) and unzip it.
2. Move **Screen Cat** to your Applications folder.
3. The first time, **right-click it and choose Open**, then **Open** again. The
   app is not notarized by Apple yet, so a normal double-click is blocked the
   first time. (Or open it once, then go to System Settings > Privacy &
   Security and click **Open Anyway**.)
4. Look for the little cat in the menu bar at the top right. Everything is in
   that menu.

Needs macOS 12 or later.

### LLM mode setup

Open the menu, then **LLM mode > Set API key…** and paste an Anthropic API key
from [console.anthropic.com](https://console.anthropic.com). It is stored in
your Mac's keychain. You pay Anthropic for what you use; a typical answer costs
a few US cents at most.

No key? If you have [Claude Code](https://claude.com/claude-code) installed and
logged in, Screen Cat uses that instead.

While LLM mode is on, what you copy is sent to Anthropic to be answered.
Passwords from password managers, files copied in Finder, and what was already
on the clipboard when you turned the mode on are never sent.

## Build from source

```bash
cd mac
./build.sh
open ScreenCat.app
```

`./release.sh` builds and zips the app into `mac/dist/` for a GitHub release.
Every setting lives in `~/.screencat.json`; see [mac/README.md](mac/README.md)
for all of them, every menu item, and the test flags.

| Platform | Folder | State |
| --- | --- | --- |
| macOS | [`mac/`](mac/) | Working. Native Swift/AppKit. |
| Android | [`android/`](android/) | Early port on the `feat/android-port` branch. |
| Windows | [`windows/`](windows/) | Early port on the `feat/windows-port` branch. |

## Credits

- Cat art: "Cat Pack" by Glem / octopusINKUS,
  [octopusinkus.itch.io/cat-pack](https://octopusinkus.itch.io/cat-pack), used
  with the artist's permission.
- Dog art: original, made for Screen Cat.
- Made by [Oleanji](https://oleanji.life).
