# ChatterFix for Windows (source)

System-tray app that filters keyboard chatter. Windows 10 and 11. Written in C#
against .NET Framework 4.8, which ships with Windows, so there is no SDK or
runtime to install.

## Build

```bat
build.cmd
```

This finds the C# compiler (`csc.exe`) built into Windows, regenerates the icon
if needed, and produces a single self-contained `ChatterFix.exe`. Nothing to
download.

Optional: `create-shortcut.ps1` puts a ChatterFix shortcut on the Desktop.

## Files

- `ChatterFix.cs` is the whole app: a low-level keyboard hook
  (`SetWindowsHookEx` with `WH_KEYBOARD_LL`) plus the tray UI.
- `ChatterFix.ico` is the app and tray icon. It is checked in, and
  `make-icon.ps1` regenerates it.
- `build.cmd` builds the exe in one step.
- `create-shortcut.ps1` and `make-icon.ps1` are the shortcut and icon helpers.

## Notes

- No special permission is needed to install the keyboard hook, so setup is
  run and go. Turn on Start at Login from the tray menu to launch at boot.
- The exe is unsigned, so a downloaded copy triggers the SmartScreen notice
  ("Windows protected your PC"). Click More info, then Run anyway. Some
  antivirus tools flag any app that installs a keyboard hook. The source here
  shows it only inspects timing and records nothing.
- It will not filter inside apps that read input below user-mode hooks, such as
  games with kernel anti-cheat, or elevated windows unless ChatterFix also runs
  elevated.
