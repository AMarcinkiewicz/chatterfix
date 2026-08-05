# Working on ChatterFix

## Writing style

**Never use em dashes.** Not in code comments, UI strings, README files, site
copy, commit messages, release notes, or anything else in or around this repo.
The house voice is plain and unfussy, and plain punctuation reads better in a
menu bar and in a short README than a dash does.

This file deliberately contains no em dash of its own, so that the check below
stays meaningful. That is also why the examples show only the wanted form.

Use a comma, a colon, a full stop, or brackets instead. Almost every em dash is
one of those in disguise:

| Situation | Write |
| --- | --- |
| Status text | `On, no chatter yet` |
| A definition after a name | `ChatterFix: menu bar app that...` |
| An error and its remedy | `not found. Run ./build_app.sh` |
| A reason following a claim | `misleading, because there is nothing to update` |
| A label and its count | `Space: 12x` |

En dashes are not wanted either. A plain hyphen is fine.

To check before committing, matching the character by codepoint so this file
does not match itself:

```sh
git grep -nP '\x{2014}'   # em dash, must return nothing
git grep -nP '\x{2013}'   # en dash, must return nothing
```

Two more standing rules on wording:

- The project is **source available**, not open source. It is MIT plus the
  Commons Clause, and a use restriction fails the OSI definition. Say "free" and
  "source available". Never add "open source" phrasing or OSI badges.
- **No AI or Claude attribution** anywhere: no co-author trailers, no "generated
  with" lines, no mention in commits, pull requests, or code.

## Product decisions worth knowing

- **There is no auto-update, deliberately.** A signed in-app updater was built
  and then removed in `6f75fb0`. It was disproportionate for a tool this small,
  and dropping it means neither app makes any network request at all, which
  matters for something holding Accessibility permission on macOS and a
  low-level keyboard hook on Windows. Do not reintroduce it unasked.
- **Start at Login is on by default**, set once on first run rather than
  enforced. A user who turns it off is never overridden. On macOS this is
  guarded to `/Applications` and `~/Applications` only, because an app opened
  straight from the .dmg is translocated to a randomized temporary path that
  does not survive, and a login item recorded there points at nothing.
- The licence file ships inside the .dmg and next to the .exe. The Commons
  Clause requires the notice to travel with every copy.

## Releasing

The site's download buttons resolve through
`/releases/latest/download/ChatterFix.dmg` and `.exe`, so:

- **Release assets must be named exactly `ChatterFix.dmg` and `ChatterFix.exe`.**
  A versioned filename gives every visitor a 404.
- **Both assets must be attached to every release**, even when one platform is
  unchanged, because `latest` resolves against the newest release only. The
  Windows binary can be carried forward from the previous release when
  `windows/ChatterFix.cs` has not changed.
- Bump `mac/Info.plist` (both `CFBundleShortVersionString` and `CFBundleVersion`)
  and `mac/chatterfix.swift` together, and the `softwareVersion` in the JSON-LD
  block in `docs/index.html`.

## Verifying

macOS behaviour is easy to get wrong from reasoning alone. Three traps already
hit during development:

- A locally built app is never quarantined, so it does not reproduce Gatekeeper
  at all. Test a real download to see what a user sees.
- A quarantined app opened from the .dmg runs from
  `/private/var/folders/.../AppTranslocation/...`, not from `/Volumes`. Watch for
  that when checking which path the app is running from.
- Swift stores string literals of 15 bytes or fewer inline, so `strings` on the
  binary cannot find them. Absence of a short string proves nothing.
