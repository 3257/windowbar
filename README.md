# WindowBar

A native macOS taskbar with **one button per window**. Keep Chrome and Terminal windows visible in a single row, switch with one click, and open any Chrome profile from its pinned icon.

![WindowBar with sample Chrome and Terminal windows](docs/screenshots/windowbar.png)

## Features

- One row with automatically shrinking window buttons. Very narrow buttons show an app icon and window number; hover for the full title.
- A focused window button that is 30% wider, with a clear blue border and indicator.
- Smooth focus, hover, and resize transitions that respect macOS Reduce Motion.
- Your existing Dock app shortcuts, plus Finder. Right-click for app actions, a window list, native “New…” commands, hide/show, quit, and Show in Finder.
- **Every Chrome profile directly in the right-click menu.** Select a profile to open a new window in it. The checkmark marks Chrome's last-used profile.
- Minimize, restore, and close individual windows from their context menus.
- Optional bars on every display, mirroring the full window list.
- Temporary Dock replacement with automatic restoration when WindowBar quits, hides, or is force-quit.

## Screenshots

The documentation images are captured from WindowBar's own AppKit views and native menu, using sample titles and profile names. They do not contain personal window titles, accounts, or desktop contents.

![WindowBar overview](docs/screenshots/overview.png)

**Right-click Chrome:** profiles appear directly above its normal window and app actions.

![Chrome context menu showing four sample profiles](docs/screenshots/chrome-menu.png)

## Requirements

- macOS 14 Sonoma or later, on Apple silicon or Intel.
- Xcode Command Line Tools with Swift 5.10 or later to build. Run `xcode-select --install` if the tools are missing.
- Accessibility access for window discovery and control. Screen Recording is not required.

There are no third-party dependencies or application network calls. Chrome profile selection launches Chrome locally.

## Build and run

```sh
git clone https://github.com/SimeonLGeorgiev/windowbar.git
cd windowbar
zsh build.sh
open build/WindowBar.app
```

The repository is private, so cloning requires access. The build script compiles for the current Mac's architecture and creates an ad-hoc signed `build/WindowBar.app`. Quit WindowBar before rebuilding it.

When launching from a coding agent or terminal that manages its child processes, use `python3 scripts/run.py`. This developer launcher starts the app in its own session with closed input and redirects output to `~/Library/Logs/WindowBar/app.log`, so closing the launching session does not stop the taskbar. It requires Python 3. For everyday use, open the app from Finder or with `open` as shown above.

On first launch, click **Enable Accessibility**, then enable **WindowBar** in **System Settings → Privacy & Security → Accessibility**. If the app is missing, add `build/WindowBar.app` with the **+** button. Quit and reopen it if a changed permission is not reflected immediately. Rebuilding an ad-hoc signed app can require granting Accessibility again.

To keep the app in Applications, copy `build/WindowBar.app` there and grant permission to that installed copy. Keep one copy running.

## Daily use

| Action | Result |
| --- | --- |
| Click a window button | Switch to that window; restore it if minimized |
| Right-click a window button | Switch, minimize/restore, or close that window |
| Right-click a pinned app | App actions, its windows, and supported native New Window/New Tab commands |
| Right-click Chrome → select a profile | Open a new window in the chosen profile |
| Scroll over the bar | Reach windows when their count exceeds the minimum button width |
| **⋯** or menu bar icon | Hide/show, replace the Dock, choose displays, open Downloads/Trash, refresh, or quit |

Chrome profiles are read afresh when the menu opens. Duplicate display names are distinguished by their profile directory. Chrome data is read-only; profile selection does not create a directory that has been removed.

**Replace macOS Dock** is enabled by default once Accessibility access is available. Disable it to keep WindowBar above the original Dock. Hiding or quitting WindowBar restores the saved Dock preferences. A separate guard restores them after a crash or force-quit. Original settings are stored in `~/Library/Application Support/WindowBar/dock-backup.plist`; the app retains this backup if restoration fails.

## Development

The project uses Swift Package Manager. Open `Package.swift` in Xcode, or use the CLI:

```sh
swift test --scratch-path build/swiftpm
zsh build.sh
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
```

Formatting uses the checked-in `.swift-format` configuration. `swift-format` is included in current Swift toolchains; the build itself does not depend on it.

| Directory | Contents |
| --- | --- |
| `Sources/WindowBarCore` | Pure layout, state, command parsing, Dock snapshots, and Chrome profile decoding |
| `Sources/WindowBar/Services` | Accessibility, window actions, Dock lifecycle, native menus, Chrome profiles |
| `Sources/WindowBar/Views` | AppKit drawing, event callbacks, and animation |
| `Sources/WindowBar/Preview` | Synthetic fixtures and native documentation rendering |
| `Tests/WindowBarCoreTests` | XCTest cases that do not modify the running desktop |
| `Tests/Smoke` | Explicit local desktop integration checks |

Read the [architecture notes](docs/architecture.md) and [maintainability review](docs/code-review.md) before changing lifecycle or Dock handling. GitHub Actions builds the app, runs core tests, and validates the bundle on macOS.

### Local desktop checks

Run these on a Mac with Accessibility access, Chrome and Terminal open, and both apps pinned in the Dock. The menus, tabs, and terminal checks require WindowBar running; the Dock and lifetime checks require it closed.

```sh
zsh scripts/smoke.sh menus
zsh scripts/smoke.sh tabs
zsh scripts/smoke.sh terminal
# Quit WindowBar before this check:
zsh scripts/smoke.sh dock
zsh scripts/smoke.sh lifetime
```

Menu and tab checks create isolated blank Chrome windows and close their own windows afterward. The menu check also enumerates every local Chrome profile and opens a window in the last-used profile. The Dock check launches, quits, and force-quits WindowBar to verify exact restoration. The lifetime check closes the launching process group and verifies that the same taskbar survives for 45 seconds with Dock replacement active. Both lifecycle checks leave WindowBar closed and restore the original Dock preferences. Failed checks exit with a nonzero status.

The Terminal check creates an isolated window through the pinned menu, switches from Chrome to it with a real taskbar click, checks Command-T and the pinned New Tab action, and closes its created windows and tabs by their IDs. It follows Terminal's current focused Accessibility handle because that handle can change when a new tab opens.

### Diagnostics and documentation images

```sh
build/WindowBar.app/Contents/MacOS/WindowBar --diagnose
build/WindowBar.app/Contents/MacOS/WindowBar --demo
zsh scripts/screenshots.sh
```

Diagnostics prints permission state and per-app window counts without window titles. Demo mode uses sample windows and leaves Dock settings alone. The screenshot script renders native AppKit views and a native Chrome menu with sample data into `docs/screenshots`, without desktop capture or Screen Recording access. Chrome must be installed and running for its native New Window/New Tab actions to appear in the menu image.

## Current limits

WindowBar is a local prototype. It overlays desktop space rather than reserving an area from other windows. Apps that do not expose standard Accessibility windows may not appear. Full-screen and Space switching depend on the app and macOS behavior.

Native “New…” command discovery currently uses English **File** and **Shell** menu titles. Chrome profiles use the standard Chrome/Chrome Beta/Chrome Dev/Chrome Canary data locations; custom user-data directories are not configured through the UI. Chrome's internal metadata format can change, so its parser and tests should be reviewed when browser behavior changes.

There are no thumbnail previews, drag-to-reorder controls, launch-at-login setting, notarized release, or update service yet. Build on each architecture you intend to use.
