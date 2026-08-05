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
  is blocked by Gatekeeper on first launch. Double-clicking it (or launching it
  from Launchpad) reports that "Apple cannot check it for malicious software"
  and that "this software needs to be updated", offering only Show in Finder and
  OK. That is a dead end, and misleading, since there is nothing to update. Right-click
  the app and choose Open instead: the same warning appears, but with an Open
  button that runs it and records the exception. Notarizing with a paid Apple
  Developer account would remove the warning entirely.
- A locally built copy is not quarantined, so it opens without any of that. Only
  copies downloaded through a browser carry the `com.apple.quarantine` attribute
  that triggers Gatekeeper, which is why testing a real download differs from
  testing your own build.
- macOS treats a rebuild as a new app, so re-grant Accessibility if needed.
- Start at Login registers itself on first run via `SMAppService`, guarded by a
  `didDefaultLoginItem` flag in `UserDefaults` so it is set once rather than
  enforced on every launch. It is skipped while the bundle is running from
  `/Volumes`, since registering from the mounted .dmg would record a path that
  no longer exists at boot; the flag stays unset so it applies after the app is
  moved to Applications. Running a dev build registers the same bundle ID as an
  installed copy, so `defaults delete com.alex.chatterfix.app didDefaultLoginItem`
  is how to re-test the first-run path.
