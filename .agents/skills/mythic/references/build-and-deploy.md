# Build and deploy

## CI (Codemagic)

`codemagic.yaml` — workflow `ios-iwin-workflow`, `mac_mini_m2`, Xcode latest.

Order of steps:
1. `brew install ninja llvm@15 llvm gnutls freetype mingw-w64`
2. Build FEX for iOS (cmake/ninja, `FEX/build-ios`, target
   `FEXCore FEXCore_Base fmt cephes_128bit xxhash softfloat_3e JemallocLibs`).
3. Build Wine + DXMT static libs: copy `build/config_ios_base.h` →
   `wine/include/config.h`; WIDL-generate headers; then
   `build/freetype-ios`, `build/wineserver/build.sh all`,
   `build/ntdll-unix`, `build/win32u-unix`, `build/dxmt-ios`.
4. `xcodebuild archive` (scheme `Mythic`, `CODE_SIGNING_ALLOWED=NO`).
5. Package `Payload/` → `iWin.ipa` and `iWin.tipa`.

Artifacts: `build/*.ipa`, `build/*.tipa`.

## Local iteration

- `scripts/build-prefix-snapshot.sh` — regenerates `app/Mythic/prefix-template.tar.gz`
  from a macOS `wineboot --init`, normalizing the build host user to `mythic`
  and stripping files shipped in the bundle.
- `scripts/deploy-thumper.sh` — `xcrun devicectl device copy to …` pushes the
  Thumper game dir into the app container (`Documents/wine/drive_c/Program Files/Thumper`).
- `server_logger.py` — the remote log server (HTTP + UDP on port 8080); the app
  posts to `http://3.1.51.240:8080/log`.

## Building low-level libs

Each `build/<component>/build.sh` compiles a static `.a` that links into the
main `Mythic` Mach-O. After changing one, nuke DerivedData. Verify a change
actually shipped by grepping the **bundle binary**, not the intermediate `.a`
(see gotchas).

## Prefix lifecycle

- On first launch `PrefixExtractor.c` extracts the bundled
  `prefix-template.tar.gz` and (re)creates `dosdevices/c:`.
- Seeding must happen **before the wineserver loads the registry**
  (`WineServerBridge.m` calls `mythic_seed_prefix_if_needed`), or an empty
  registry is built and overwrites the template's 17k+ keys (#ml588).
- Profile repair (`ml666`/`ml667`) un-mangles `usersmythic` → `users\mythic`
  in the `.reg` files and merges the tree, marker-gated and idempotent.
