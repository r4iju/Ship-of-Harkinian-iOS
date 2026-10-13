# Ship of Harkinian for Apple Platforms

This tree is a direct iOS adaptation of the Android fork. It is not a patch
launcher and does not require a second Ship of Harkinian checkout.

## What is shared with Android

- The Ship of Harkinian game, enhancement, randomizer, and resource code
- libultraship and the Metal renderer
- The SDL input stack and controller mappings
- The ROM-free `soh.o2r` support archive
- The user-data format used by other Ship of Harkinian builds

The Apple layer is intentionally small: CMake/Xcode configuration, application
lifecycle handling, platform-appropriate local storage, CloudKit save sync,
and a native translation of the Android touch overlay on iPhone and iPad.
Touch input appears to the engine as an SDL virtual game
controller, so controller rebinding and gameplay input follow the same path as
Android. The iOS layout preserves the Android controls, behavior, and styling:
left stick, right-side look area, C-direction cross, A/B/X/Y buttons, L/R/Z,
Back/Start, and the visibility toggle.

## Requirements

- macOS with Xcode and the iOS SDK
- The tvOS SDK for Apple TV builds
- CMake
- An arm64 Mac for the simulator configuration
- `soh/soh.o2r`
- A supported Ocarina of Time ROM for first-run extraction

The ROM is never bundled in the app.

The iOS target is universal and supports both iPhone and iPad.

## Simulator build

```sh
scripts/build-ios.sh --simulator
```

The app is written to:

```text
build-ios-sim/soh/Release-iphonesimulator/Ship of Harkinian.app
```

## Device build

For an unsigned compile check:

```sh
scripts/build-ios.sh --device
```

For a signed development build, supply the Apple development-team identifier:

```sh
DEVELOPMENT_TEAM=ABCDE12345 scripts/build-ios.sh --device
```

The default bundle identifier is `com.shipofharkinian.ios`. Override it when
needed:

```sh
BUNDLE_ID=org.example.soh DEVELOPMENT_TEAM=ABCDE12345 \
  scripts/build-ios.sh --device
```

Version and deployment settings can also be overridden:

```sh
SOH_IOS_VERSION=1.2.3 SOH_IOS_BUILD_NUMBER=42 DEPLOYMENT_TARGET=15.0 \
  scripts/build-ios.sh --device
```

The default deployment target is 15.0, the minimum accepted by Xcode 27's
Apple mobile SDKs. Override `DEPLOYMENT_TARGET` when using another SDK.

## Apple TV builds

For the Apple TV simulator:

```sh
scripts/build-ios.sh --tvos-simulator
```

The app is written to:

```text
build-tvos-sim/soh/Release-appletvsimulator/Ship of Harkinian.app
```

For a signed physical Apple TV build:

```sh
DEVELOPMENT_TEAM=ABCDE12345 scripts/build-ios.sh --tvos-device
```

The default tvOS bundle identifier is `com.shipofharkinian.tvos`. The iOS and
tvOS app identifiers must both be granted access to the same CloudKit container
for cross-device save synchronization.

## Importing a ROM

1. Install and open the app once.
2. In the iOS Files app, open **On My iPhone** or **On My iPad**, then
   **Ship of Harkinian**.
3. Copy a supported ROM into that folder.
4. Return to Ship of Harkinian.

The normal Ship extraction code creates the local game archive in the same
Documents directory. Saves and configuration remain visible through Files for
backup and transfer.

## Importing game data, mods, and saves on Apple TV

Apple TV has no Files-app document workflow. The tvOS build therefore starts a
small local transfer server and advertises it with Bonjour:

1. Open Ship of Harkinian on Apple TV.
2. Note the `http://<address>:8080` address shown in the missing-game-data
   prompt or under **Settings > General > Local File Transfer**.
3. On a phone, tablet, or computer connected to the same home network, open
   that address in a browser.
4. Choose **Game Data** for `.o2r`, `.otr`, `.z64`, `.n64`, or `.v64` files;
   **Mods** for mod archives; or **Save Files** for `global.sav`, `file1.sav`,
   `file2.sav`, or `file3.sav`.
5. Return to the game and choose **Rescan** for game data or mods. A save upload
   is placed directly in `Save` and queued for iCloud synchronization when that
   option is enabled.

Uploads are streamed to a temporary file and atomically moved into the correct
app directory when complete. Game data and mods are not uploaded to CloudKit;
the supported save files are queued for the existing private iCloud save sync.
The transfer server can be stopped and restarted from the SOH settings menu.

## iCloud save synchronization

The iOS settings menu includes an opt-in **Sync Saves with iCloud** setting and
a **Sync Saves Now** action. Save synchronization uses the user's private
CloudKit database in the shared `iCloud.com.shipofharkinian.shared` container.
It does not place files in an iCloud Drive folder.

Only portable game state is synchronized:

- `Save/global.sav`
- `Save/file1.sav`
- `Save/file2.sav`
- `Save/file3.sav`

The large `soh.o2r`, extracted archives, mods, caches, logs, controller
bindings, display settings, and other device-specific configuration remain
local. This avoids large downloads and prevents an iPhone's display or touch
settings from replacing settings appropriate for an iPad, Apple TV, or Mac.

At startup, CloudKit is checked before the save manager loads its metadata. The
newest copy wins based on the source file modification date. If a different
local file is replaced, it is preserved beside the save with an
`.icloud-conflict-<timestamp>` suffix. A newer cloud copy discovered while a
game is running is deferred until the next launch so in-memory game state
cannot immediately overwrite it.

The iCloud container must be enabled for the app identifier and included in
the provisioning profile. It can be overridden when configuring a build:

```sh
SOH_ICLOUD_CONTAINER_ID=iCloud.org.example.soh.shared \
  DEVELOPMENT_TEAM=ABCDE12345 scripts/build-ios.sh --device
```

## Apple-platform storage model

The universal Xcode target supports iPhone and iPad, and a separate tvOS target
uses the same CloudKit save service. CloudKit is deliberately independent of
iCloud Drive because tvOS does not have a general-purpose Files/iCloud Drive
workflow. A future macOS target should use the same CloudKit container and save
record identifiers.

Each platform still needs a local source for the required game data:

- iPhone/iPad: Files document import
- Apple TV: the built-in local-network browser transfer page
- Mac: normal file selection

All targets can then share the four CloudKit save records while keeping game
archives and platform-specific settings local.

## iOS-specific source

- `CMake/ios.cmake` supplies iOS-compatible audio and image dependencies.
- `soh/ios/Info.plist.in` defines the application bundle and Files integration.
- `soh/ios/SOHiCloudSync.mm` synchronizes portable saves through the shared
  private CloudKit container.
- `soh/ios/SOHiOSTouchControls.mm` translates the Android SOH touch layout to
  UIKit while retaining the same SDL controller inputs.
- `soh/ios/SOHTVOSFileServer.mm` provides streamed local-network uploads for
  Apple TV game data, mods, and supported SOH saves.
- `soh/ios/Info-tvOS.plist.in` defines the Apple TV application bundle.
- `scripts/configure-ios.sh` generates iOS or tvOS simulator/device projects.
- `scripts/build-ios.sh` configures and builds the selected target.

## Current validation boundary

Local verification on 2026-10-13 includes native macOS gameplay, tvOS simulator
gameplay and save/reload, and signed installation on Living Room TV. The physical
TV pass exercised file loading, analogue movement, targeting, sword attacks,
shield raising, enemy damage, death/continue, in-game saving, and reopening the
save after a full app restart. It used an isolated save fixture and a temporary
SDL virtual controller, not human Bluetooth button presses. Original TV saves
and configuration were restored byte-for-byte, and the normal signed app was
reinstalled without QA helpers. Its bundled data launched to the title screen.

A presented-frame probe in the physical TV QA build recorded 3,599 intervals
over 59.97 seconds in the Deku Tree scene: 60.00 presented FPS, 16.67 ms median
and 16.90 ms p95 interval. This is one scene with probes active, not a whole-game
performance guarantee. Physical game CoreAudio output contained nonzero PCM;
TV speaker listening was not performed. Enemy defeat, full playthrough,
controller pairing/button feel, suspend/resume, interruptions and long-session
thermal behavior remain unverified. Browser import and CloudKit were not part
of this bundled-data pass. Private evidence remains under ignored
`build-host/gameplay-qa/`.

## Local app branding

Apple builds optionally load `local-branding/branding.cmake`, which is ignored
by Git together with its artwork. Set `SOH_APPLE_DISPLAY_NAME` for the app's
visible name, `SOH_APPLE_ASSET_CATALOG` to a local `.xcassets` catalog with
`AppIcon` and `AppIconTV`, and `SOH_APPLE_MAC_ICON` to a 1024×1024 PNG.
Reconfigure the build after changing these values. The defaults use the
repository's existing name and icons. Bundle identifiers and save paths do
not change. Keep supplied artwork inside `local-branding/`.

### Local builds must include the game

For this fork's local installations, include the user-owned game archive in
the app bundle so first launch does not require an import or HTTP upload.
Set `SOH_LOCAL_GAME_ARCHIVE` in ignored `local-branding/branding.cmake` to
`${CMAKE_SOURCE_DIR}/local-branding/oot.o2r`. The Apple build packages this
archive as a runtime resource; the existing loader discovers it in the bundle.
This local requirement takes precedence over upstream import instructions.
Keep the archive and source ROM out of Git and public distribution.

### Apple TV rendering defaults

The tvOS app supplies missing settings with 60 FPS frame interpolation,
2× multisample anti-aliasing, and a fixed 1080p game render resolution.
This avoids rendering every game frame at the TV's 4K output resolution
and retains the original game logic rate. Explicit saved settings take
precedence; these defaults do not reset controller mappings or saves.
Original game textures retain their original detail.

For local device verification, capture the Apple TV output with
`device-run --lease <request-id> -- devicectl device capture screenshot --device <udid> --destination <file.png>`.
Agents must claim the shared `device-queue` resource `physical:<udid>` first.
Use an Instruments Metal System Trace to measure frame timing, and distinguish
gameplay from menus when reporting results. Simulator performance does not
establish the physical Apple TV's frame rate.

### Installed local launch and installation

On Emanuel's Mac, launch the bundled native app with:

```sh
open '/Users/emanuel/Applications/The Legend of Zelda - Ocarina of Time.app'
```

These commands are for a human terminal. Agents use the same device arguments
through `device-run --lease <request-id> -- devicectl ...` after claiming a turn:

```sh
xcrun devicectl device install app --device a5ef39a5001ef59dec9c2fa15838447215252137 'build-tvos-device/soh/Release-appletvos/Ship of Harkinian.app'
xcrun devicectl device process launch --device a5ef39a5001ef59dec9c2fa15838447215252137 xyz.raiju.shipofharkinian.tvos
```

For Apple rendering regression checks, use a 1080p game buffer on a simulator
with a 4K display at 2× scale and enable MSAA. The render buffer then matches
the logical viewport but remains offscreen. Verify the title demo, file menu,
and gameplay stay visible, and run with `MTL_DEBUG_LAYER=1` to check Metal API
validation. The renderer must use `ViewportMatchesRendererResolution()`
consistently for framebuffer setup and coordinate offsets.
