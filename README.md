# WindowBar

A small native macOS taskbar with one button per window, including separate Chrome and Terminal windows. Built in Swift and AppKit with no dependencies or network calls. Requires macOS 14 or later; this build targets Apple silicon.

## Build and run

```sh
zsh build.sh
open build/WindowBar.app
```

Click **Enable Accessibility** in the bar, then enable **WindowBar** in System Settings → Privacy & Security → Accessibility. If it is not listed, use the **+** button and select `build/WindowBar.app`. If the bar does not update after permission changes, quit from its menu bar icon and reopen it. Screen Recording access is not required.

## Use

- Click a window button to switch directly to that window, restoring it if minimized.
- Right-click a button to minimize, restore, or close that window. An app can still display its normal unsaved-changes confirmation.
- Right-click a pinned app to see its windows, open, hide/show, quit, or show it in Finder. Running apps expose their native File/Shell “New…” actions, including Chrome's New Tab, New Window, and New Incognito Window and Terminal's profile submenus.
- The focused window button is 30% wider and has a stronger blue border and highlight.
- Focus, hover, and button resizing have short, smooth transitions. Reduce Motion disables these animations.
- Scroll over the bar when there are more windows than fit. Hover to see the full title.
- The bar stays on one row. Window buttons shrink as more windows open, then show numbered icons at narrow sizes. Hover for the full window title. Extremely large window counts can still scroll horizontally.
- Use **⋯** or the menu bar icon to hide the bar, show it on all displays, refresh, or quit.

The bar replaces the Dock by default and includes your existing pinned app shortcuts plus Finder. Each open window has its own labeled button. Downloads and Trash are available from the menu. **Replace macOS Dock** toggles replacement mode; turning it off places WindowBar just above the original Dock. The all-displays option mirrors the complete window list on each display.

Replacement mode saves the original auto-hide preferences before temporarily hiding the Dock. Quitting or hiding WindowBar restores them. A separate background guard also restores the Dock if WindowBar crashes or is force-quit. The preference backup lives in `~/Library/Application Support/WindowBar/dock-backup.plist`. Demo and diagnostic modes never change Dock settings.

## Diagnostics and preview

```sh
build/WindowBar.app/Contents/MacOS/WindowBar --diagnose
build/WindowBar.app/Contents/MacOS/WindowBar --render-preview build/preview.png
open build/WindowBar.app --args --demo
```

The preview/demo uses sample windows. Diagnostics reports permission state and window counts without logging window titles.

## Prototype limits

WindowBar polls Accessibility every 1.5 seconds on a background queue with short per-app timeouts. Apps that do not expose standard Accessibility windows may not appear. Full-screen/Space switching depends on the app and macOS behavior. The bar overlays existing desktop space rather than reserving an area from other windows. There are no thumbnail previews or launch-at-login controls yet. Pinned-app menus offer the common Dock actions and native English File/Shell “New…” commands; they do not reproduce every app-specific Dock extension or Dock option.

This is an ad-hoc signed local build. Rebuilding can require granting Accessibility again. Quit the running app before rebuilding it.

## Verified on this Mac

`python3 verify_dock.py` checks replacement mode, exact restoration on normal quit, and automatic restoration after force-quit. Run it with WindowBar closed. The live bar is also checked through macOS Accessibility for its height and separate controls for multiple Chrome and Terminal windows.

`verify_tabs.swift` checks a real mouse click on a window button, keyboard focus in Chrome, Command-T, and Chrome's + button using an isolated temporary window. It closes that test window and returns focus to the previous app. Both tab-opening methods passed after switching through WindowBar.

`verify_menus.swift` checks pinned-app right-click menus, Chrome's native New Window and New Tab actions, Terminal's native Shell actions, and the focused button's larger width. It uses an isolated Chrome window and restores the previous app afterward.
