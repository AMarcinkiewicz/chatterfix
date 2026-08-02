# ChatterFix

**Stop your keyboard from typing double.** A small, free tool that fixes
keyboard chatter, which is when a worn or dirty key registers two presses from
a single tap. Think "hello" coming out as "helllo", or space bar double-spacing.

**Download for macOS or Windows at [chatterfix.app](https://chatterfix.app)**

Free forever, source available, no ads, no account, no tracking.

## What is keyboard chatter?

As a key switch ages or collects dust, one press can electrically bounce and
report twice. ChatterFix watches your keystrokes and ignores that bogus second
press. If a key fires again within a few milliseconds of releasing the same key,
it counts as a bounce and gets dropped. Real typing leaves a much bigger gap,
even fast double letters like "ll", so normal typing is not affected.

A few things worth knowing:

- It adds no delay. Every real keystroke passes through instantly. Nothing is
  buffered or held back.
- Holding a key still works normally, and it only ever compares a key against
  itself, so typing fast across different keys is fine.
- It never records what you type. ChatterFix looks only at timing, meaning which
  key and how long since that key was last released, and it keeps none of it.
  The full source is in this repo if you want to check.

## Download

Get the latest build from [chatterfix.app](https://chatterfix.app) or the
[Releases page](../../releases/latest):

- **macOS:** universal `.dmg` that runs on both Apple Silicon and Intel Macs,
  macOS 13 or newer.
- **Windows:** `.exe` for Windows 10 and 11. No installer, nothing else to set up.

On macOS the first launch asks for the Accessibility permission, which it needs
to watch for chatter. On both systems you can turn on Start at Login so it runs
quietly in the background. Because the downloads are not signed with a paid
certificate yet, you will see a one-time "unverified developer" (macOS) or
SmartScreen (Windows) notice. The per-platform notes below explain how to get
past it.

## How to use it

ChatterFix sits in your menu bar (macOS) or system tray (Windows) as a small
keyboard icon. Click it to:

- See how many double-presses it has blocked and which keys are chattering.
- Change the sensitivity, which is how close together two presses must be to
  count as chatter. Standard (50 ms) is a good starting point. If doubles still
  get through, move one step stronger. If a genuine fast double letter gets
  eaten, move one step gentler.
- Pause filtering, or turn Start at Login on and off.

## Building from source

- **macOS:** see [`mac/`](mac/). Run `./build_app.sh` (needs the Xcode
  command-line tools). More detail in [mac/README.md](mac/README.md).
- **Windows:** see [`windows/`](windows/). Run `build.cmd`, which uses the C#
  compiler already built into Windows. More detail in
  [windows/README.md](windows/README.md).

## Updates

ChatterFix checks `https://chatterfix.app/appcast.json` once a day. If a newer
version is listed it offers to install it, with Install / Later / Skip This
Version and an "install automatically" option. Nothing else is sent.

The manifest is signed with an RSA key held offline, and the public half is
compiled into both apps. An update is installed only if the manifest signature
verifies *and* the downloaded file matches the SHA-256 in the manifest. This
matters because ChatterFix holds Accessibility permission on macOS and a
low-level keyboard hook on Windows, so an unverified update would be a
keylogger delivery route.

To publish a release: build both artifacts, upload them to a GitHub release
tagged `vX.Y.Z`, then run `./tools/sign_release.sh X.Y.Z` and commit the
regenerated `docs/appcast.json`.

## Limitations

- Modifier keys (Shift, Cmd or Win, Ctrl, Alt or Option) travel a different
  event path and are not filtered. Chatter on those is rare.
- Games with kernel-level anti-cheat and secure password fields read input below
  where ChatterFix sits, so filtering does not apply there.

## License

[MIT with the Commons Clause](LICENSE). Free to use, change, fork, and share,
including at work and inside a company. The one thing you cannot do is sell it,
or sell a product or service whose value comes substantially from it.

Note that this is source available rather than open source in the OSI sense,
because the no-selling condition is a restriction on use.
