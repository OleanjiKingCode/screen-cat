# Screen Cat for Android

The purple pixel cat from the Mac app, walking along the bottom of your phone
over every other app. Kotlin, no libraries beyond the Android SDK. The Mac
source in `../mac/Sources` is the spec; this is a port of it, and the files
here are named after the Swift files they come from.

## Build and install

Needs JDK 17 and the Android SDK (platform 36).

```bash
cd android
./gradlew assembleDebug        # app/build/outputs/apk/debug/app-debug.apk
./gradlew installDebug         # onto a connected phone or emulator
./gradlew testDebugUnitTest    # movement rules and the glitch random source
```

CI (`.github/workflows/android.yml`) builds the debug APK on every push that
touches `android/` and uploads it as the `screen-cat-debug-apk` artifact.

## First run

1. Open **Screen Cat** and tap **Allow display over other apps**. Find Screen
   Cat in the list and switch it on. Without this the cat cannot come out.
2. Allow notifications when asked (Android 13 and later). The cat runs as a
   foreground service, and its notification holds the **Mr. Robot**,
   **Pause** and **Stop** buttons.
3. Tap **Start**. The first visit comes after `firstAppearanceDelay` (20 s).
4. Some phones (Xiaomi, Samsung, Huawei and others) kill background services.
   If the cat stops after a while, set Screen Cat's battery use to
   "Unrestricted" in the system settings.

## What matches the Mac version

- **Sprites.** The same `Cat_Sprite_Sheet.png`, `Cat_Shadow.png` and
  `Cat_Ball.png`, in `app/src/main/assets`. 32x32 frames on a 12x9 grid, the
  same clips (row, start, count, fps, loops, mirrors, stride-driven),
  nearest-neighbour scaling, the shadow, and side clips mirrored when the cat
  faces left.
- **Colours.** The same exact-colour recolour: the coat map on the sheet, the
  yarn colours on the loose ball only. Same keys (`furColor`,
  `furShadeColor`, `outlineColor`, `innerColor`, `eyeColor`, `ballColor`).
- **Movement.** In and out from the sides, never climbing, descent capped at
  `maxSlope`, one gentle arc per leg capped at 8% of its length,
  `depthShrink`, `groundY` with `groundBias`, speeds in body heights per
  second, cat height = screen height / `sizeDivisor`.
- **Routines.** Walk, nap (lie down, z's), ball chase and hungry (food bowl),
  picked by the same weights with a 3 to 15 s gap between visits.
- **Outfit.** The gold chain (`chainChance`, always) and the small shades
  (`glassesChance`, 35%), anchored per frame from the white eye pixels of the
  untouched sheet, with the same pixel designs.
- **Idle crawl and the glitch takeover.** After `idleCrawlSeconds` (120) with
  no touch, the cat walks in, grows to `growScale` (2x) inside pulsing rings,
  then the whole screen becomes a glitch that stays on. All **50** styles are
  ported with the same names, layers and palettes, rendered at half
  resolution about 20 times a second and scaled up with nearest neighbour. A
  new style every `glitchStyleSeconds` (60). The cat roams up, down and
  sideways on top (shrinking as it goes up, zig-zagging at `maxSlope` up
  anything steeper) and zaps, which flashes the screen. Any touch ends it:
  the glitch clears at once and the cat shrinks to nothing over 0.8 s. Normal
  visits carry on after that. It also stops when the screen goes off.
- **Mr. Robot.** From the app or the notification: a three-second
  "MR. ROBOT IN 3" countdown, then the takeover at four times the speed (a
  new style every 15 s, the cat twice as fast), ending after three minutes or
  at the first touch, with the same shrink-away exit. It does not change the
  saved mode.
- **Crawler mode.** Most visits (`crawlChance`) become a crawl: the cat puts
  its shades on, walks under a few areas of the screen, zaps each one, and it
  "breaks" in one of the five per-area styles (breach, matrix, blue screen,
  no signal, meltdown) before "REBOOTING...".
- **Settings.** `screencat.json` in the app's files folder, with the same keys
  as the Mac's `~/.screencat.json`. The settings screen edits start/stop, the
  mode, `idleCrawlSeconds`, `glitchStyleSeconds`, `growScale`, the outfit
  chances and the colours; the raw JSON is editable at the bottom for every
  other key. A Mac file pasted in works as is.

## What Android cannot do, and why

- **No petting, no "Let's play".** Both need the pointer over the cat. A
  pass-through overlay never sees a touch on itself, and making the cat
  touchable would steal taps from the app underneath. `petSeconds`,
  `weightPlay`, `dwellSeconds` and friends are kept in the file but ignored.
- **The cat is a little see-through.** Android 12 and later block taps that
  pass through another app's overlay unless the overlay is at most 80%
  opaque. The window uses `min(opacity, maximumObscuringOpacityForTouch)`,
  so the cat and the glitch show at 80% on those versions. Without it you
  could not use the phone while the cat is out.
- **Bottom edge only.** The Mac cat sometimes walks up the left or right edge
  (`wallChance`). On a phone the cat stays on the bottom edge, above the
  navigation bar.
- **No real windows to break.** Android does not let an app see other apps'
  window positions. Crawler mode and the takeover zap made-up, app-sized areas
  of the screen instead.
- **No switching apps.** The Mac takeover brings the next app forward at the
  screen edge. An app cannot do that on Android without an accessibility
  service, so at the edge the cat turns round and a new style takes over.
- **Idle means no touch.** A 1x1 overlay window with
  `FLAG_WATCH_OUTSIDE_TOUCH` gets every tap elsewhere as `ACTION_OUTSIDE`;
  that is the "last input" clock. Hardware keys and the volume rocker do not
  count. Most phones turn the screen off after 30 s to 2 min, and the
  takeover stops when the screen goes off, so set `idleCrawlSeconds` (at
  least 15) below your screen timeout to see it on its own. **Crawl until I
  touch something** starts it at once.
- **No blocked apps.** Knowing which app is in front needs the Usage Access
  permission. The cat does not ask for it, so `blockedApps` and
  `hideWhileWatching` are ignored. Pause it from the notification instead.
- **Not over everything.** Android hides app overlays on the lock screen, the
  notification shade and some system dialogs (permission prompts, for one).
  The cat stays in while the phone is locked.
- **Not hidden from screenshots.** The Mac window is kept out of captures. An
  Android overlay shows in screenshots and recordings.
- **No activity log, no login item.** Those are Mac features.

## Notes

- The sprites are "Cat Pack" by Glem / octopusINKUS. The pack states no
  licence, so this repo must stay private. See
  `app/src/main/assets/CREDIT.txt`.
- Between routines the overlay window is removed and the frame loop stopped,
  so an idle cat costs nothing. Only the 1x1 touch watcher stays.
- The glitch renders on its own thread into three rotating bitmaps, so the
  cat's 60 fps frames never wait for it.
