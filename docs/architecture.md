# Architecture and maintenance

WindowBar uses Swift Package Manager, AppKit, and public macOS Accessibility APIs. There are no third-party packages or network calls in the application.

## Responsibilities

| Component | Responsibility |
| --- | --- |
| `WindowBarCore` | Pure layout calculations, scan generations, command parsing, typed Dock backups, Chrome profile metadata decoding |
| `AppDelegate` | Compose dependencies, coordinate scans, lifecycle, settings, and display panels |
| `AccessibilityWindowService` | Discover app windows on one serial background queue; preserve the last app snapshot on transient timeouts |
| `WindowActions` | Activate, restore, minimize, and close windows; cancel obsolete delayed activation |
| `DockController` | Save and restore Dock settings, serialize preference transactions, run the crash guard |
| `ChromeProfileStore` | Read profile display metadata from Chrome's Local State |
| `ChromeProfileLauncher` | Launch a window with the selected profile directory |
| `LauncherMenuBuilder` | Construct app context menus and native File/Shell commands |
| `BarManagementMenus` | Add pin/unpin, move, and manual profile badge actions without replacing native app commands |
| `FeatureCoordinator` / `PreferencesStore` | Session order/profile overrides and persistent pinned apps/preferences |
| `LoginItemService` / `ApplicationInstaller` | Register the installed main app at login, verify/stage installation, protect running copies |
| `GlobalShortcuts` / `HotKeyBackend` | Validate, register, route and roll back configurable hotkeys |
| `WindowPreviews` / `WindowCaptureBackend` | Permission-gated single-window thumbnails with one bounded memory cache |
| `HoverPreviewController` | Intent delay, nonactivating cards and cancellation of stale captures |
| `Diagnostics` | Typed, bounded event logs and clean/unclean lifecycle detection |
| `Views` | Draw and animate the bar; publish user actions through callbacks |
| `Preview` | Synthetic fixtures, PNG rendering, and a controlled screenshot background |

The application depends on small `WindowDiscovering`, `WindowActing`, `DockReplacing`, and `LauncherMenuProviding` interfaces. Their implementations are injected into `AppDelegate`. Icon views do not discover profiles, manipulate Dock preferences, or construct native app commands. The layout and file decoders are independent of the running desktop and tested with XCTest.

## State and ownership

- The main thread owns AppKit views and application state. Window discovery owns its cache on one serial queue.
- Every selection or permission change invalidates earlier scans. A stale result cannot replace the current selection or repopulate windows after permission is revoked.
- A generation check cancels delayed activation after a newer selection. An app that has lost focus is not raised again by an old callback.
- A kernel file lock prevents duplicate WindowBar instances. Its descriptor is close-on-exec, so the crash guard cannot keep the GUI instance lock alive.
- Dock preference changes use a separate cross-process transaction lock. A late guard cannot restore an older snapshot over a newer app's settings.
- Backups preserve the difference between an absent preference and an existing false or zero value. If restoration fails, the original backup is retained and the failure is logged.
- Window ordering and manual profile badges are session state. Pinned app paths/preferences persist independently of Dock pins; a nil pin list imports Dock once, while an empty list stays empty.
- Display ownership uses the largest frame intersection, with a deterministic tie. Unknown bounds remain reachable instead of silently losing a window.
- Thumbnails require existing Screen Recording permission and an unambiguous capture target. Capture filters validate the window ID and owning PID. Hover generation checks discard late images; the cache holds one image for at most two seconds.
- Shortcuts are inactive by default. OS registration failure rolls back previous bindings. Settings cannot register login startup before the app is installed.
- Logs use a separate nonblocking file lock and rotate at approximately 512 KiB. Logging failures do not prevent shutdown or Dock restoration. Events omit content titles, account/profile names, URLs and images.

Login startup uses Apple's [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice). Thumbnails use [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) with a [desktop-independent single-window filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)). Permission requests are explicit Settings actions.

## Extending the app

To change sizing, edit `BarLayout` and its tests. Colors and drawing helpers live in `Views/Theme.swift`; button transitions live in `Views/WindowButton.swift`. To add another app-specific menu, extend a menu provider rather than the icon view. To add another browser's profiles, provide a reader and launcher with tests around its metadata format and launch arguments.

Chrome profile metadata is an internal browser format. WindowBar reads only display metadata and does not write Chrome files. Profile directory names are validated, and launch arguments are passed as an array. Removed directories are not created by an accidental profile launch. The checkmark marks Chrome's last-used profile, not a guarantee about the currently focused window. See Chromium's [user data directory](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md) and [startup switches](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/common/chrome_switches.cc) for the underlying conventions.

## Validation

Developer launches use `scripts/run.py` to put the app in its own process session, close inherited input, and redirect output to a local log. Running the GUI as a foreground tool child ties its lifetime to the coding host, which can terminate children when its session ends. The lifetime smoke check closes the launching process group and verifies that the same app process and Dock snapshot survive. Finder/LaunchServices launches already have an independent lifetime.

Unit tests run in CI without changing desktop preferences. GUI smoke tests are local and explicit: they require a desktop, Accessibility access, Chrome, and Terminal. The Dock smoke suite launches and force-quits WindowBar; run it with WindowBar closed. Browser tests create isolated blank windows, close their own windows, and restore the previously active app. Screenshots use sample titles and sample profile names.

`--self-test` adds isolated service/native UI checks using temporary files/preferences and injected login, hotkey, capture and Dock backends. It covers native drag/drop callbacks, settings/shortcut controls, profile/pin menus, hover cancellation, crowded layouts, and shutdown. Its process prohibits activation and never orders windows. `verify_isolation.py` also compares the live Dock state and taskbar PID before/after. CI runs this suite; real OS registration/capture/hotkey delivery and physical display changes remain explicit desktop integration checks.

Documentation rendering uses fixed sample launchers and profiles. Menu snapshots render NSMenu item state with native labels/separators without opening a popup. The selected Quiet Shelf design uses system appearance, a subtle accent, trailing pins and no leading brand mark; the design exploration is in `docs/design`.

Swift language mode is 5 for compatibility with the supported toolchain. A future Swift 6 migration should introduce explicit actor boundaries for AppKit and audited sendability of Accessibility snapshots; it should not add unchecked sendability merely to silence compiler errors.
