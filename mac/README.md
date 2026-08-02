# ChatterFix for macOS (source)

Menu-bar app that filters keyboard chatter. Universal binary (Apple Silicon and
Intel), macOS 13 or newer.

## Build

Requires the Xcode command-line tools (`xcode-select --install`).

```sh
./build_app.sh     # compiles the universal ChatterFix.app
./package_dmg.sh   # wraps it in ChatterFix.dmg, drag-to-Applications (optional)
```

`build_app.sh` compiles for arm64 and x86_64, merges them with `lipo`, assembles
`ChatterFix.app`, generates the icon on first run, and ad-hoc signs the bundle,
which Apple Silicon requires in order to run it.

## Files

- `ChatterFixApp.swift` is the menu-bar app, both the filtering engine and the UI.
- `chatterfix.swift` is an optional command-line version with a `--dry-run`
  diagnostic mode. Build it with
  `swiftc -O chatterfix.swift -o chatterfix -framework Cocoa`, then run
  `./chatterfix --help`.
- `make_icon.swift` renders the app icon. `AppIcon.icns` is checked in, so this
  only runs if the icon is missing.
- `Info.plist` holds the app metadata. `LSUIElement` makes it menu-bar-only with
  no Dock icon.

## Notes

- First launch asks for Accessibility (System Settings, then Privacy & Security,
  then Accessibility). Filtering starts on its own once you grant it.
- The app is ad-hoc signed, not signed with a Developer ID, so a downloaded copy
  shows Gatekeeper's "unverified developer" notice. Right-click the app and
  choose Open the first time to get past it. Notarizing it with a paid Apple
  Developer account would remove that notice.
- macOS treats a rebuild as a new app, so re-grant Accessibility if needed.
