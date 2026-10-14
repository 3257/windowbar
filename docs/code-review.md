# Maintainability review

The initial prototype combined lifecycle, platform APIs, UI drawing, Dock preference changes, browser commands, and developer tools in one 899-line file. The refactor keeps the existing UX while making those responsibilities independently understandable and testable.

| Finding | Change | Evidence |
| --- | --- | --- |
| Window discovery, actions, and drawing were coupled | Separate service interfaces and views; dependency injection in the coordinator | Native menu and window-switching smoke checks |
| A late background scan could overwrite a newer selection | Generation-based rejection of stale scans | Core state test |
| A delayed callback could raise an obsolete window | Cancel stale activation and check the foreground app before raising | Window action implementation and browser interaction smoke check |
| Layout logic was embedded in AppKit drawing | Pure `BarLayout` with explicit size limits and focus weights | Empty, dense, overflow, and multiple-focus cases |
| An app timeout could temporarily erase all its window buttons | Retain that app's last successful snapshot on transient AX timeout | Serial discovery service; behavior remains dependent on app Accessibility support |
| Dock backup data used untyped dictionaries | Codable snapshot preserving absent values | Backup round-trip and prototype compatibility tests |
| GUI and crash guard could race while restoring settings | Instance lock and serialized Dock transactions | Normal-quit and force-quit desktop smoke checks |
| Some smoke-test failures printed JSON but returned success | Throwing checks, nonzero exit status, cleanup scopes, shared helpers | Tabs and menus smoke suites |
| Build was tied to one CPU architecture and source file | Swift Package Manager and host-native bundle packaging | Release build, unit tests, bundle validation |
| No reproducible documentation or CI | README, architecture notes, sample screenshots, macOS build/test workflow | PR checks and checked-in screenshot recipe |
| Chrome profile selection was missing | Direct profile items from local metadata, profile-specific launch | Parser tests and live enumeration/launch check |
| Developer launches stopped with their session host | Independent process session, closed stdin and redirected output | Lifetime check closes the launching process group |
| New daily-use features could couple more platform code into views | Separate preference/order, management-menu, login/install, hotkey, capture and diagnostics services | Injected backend and native-control checks |
| Pin edits could affect the macOS Dock or reappear after removing everything | Independent persisted pins with distinct uninitialized/empty states | Pin/unpin/reorder, round-trip and empty-list checks |
| Profile labels could mistake page text for account identity | Bounded Chrome control traversal excluding web areas; exact unique matching; manual override | Match/ambiguity tests and native badge menu actions |
| Thumbnails could prompt during hover or reopen a dismissed card | Preflight gate, unambiguous window/PID target and hover generations | Denied-permission, cache, late-completion and removal checks |
| Shortcut conflicts could leave partial registration | Validation, disable and rollback behavior with injected backend | Conflict rollback and routing checks |
| Installing an update could overwrite a live app | Verified staging, running-copy checks and rollback | Temporary installation/protection tests and signature validation |
| Testing features could disrupt ongoing work | Separate candidate build, offscreen native checks, live-state comparison | Taskbar PID and exact Dock state preserved during feature checks |

The daily-use update has 28 core XCTest cases plus isolated native service/UI verification. The user selected Quiet Shelf after reviewing three mockups; native light/dark screenshots were inspected, and the leading W was removed. Live login registration, real screen capture, global hotkey delivery, and physical monitor changes were deferred to respect the user's active work; injected checks cover their app-side behavior and failures.

This is a maintainability refactor, not a formal correctness proof. Known limitations remain documented in the README: Accessibility support varies by app, native “New…” menu discovery currently uses English File/Shell titles, custom Chrome user-data directories need additional configuration, and the bar overlays desktop space rather than reserving it.
