# WindowBar design study

These mockups explore a calmer native macOS taskbar before production view changes. All titles, profiles, previews, and app state are sample data. The running taskbar and the user's apps were left alone.

- [Interactive comparison](mockups.html): three concepts, light/dark appearance, 5/10/18 windows, hover previews, selection, drag reordering, profile menus, and simulated settings.
- [Light contact sheet](concepts-light.png)
- [Dark contact sheet](concepts-dark.png)
- [Crowded contact sheet](concepts-crowded.png)

Open the HTML from Finder to explore it when convenient. It is self-contained, works offline, and never launches apps, changes settings, or captures the desktop. The Settings window at the bottom is a visual sketch, not a working preference editor.

## Recommendation

**Selected by the user: Quiet Shelf.** It best fits the app's purpose: distinguish individual windows quickly while keeping the visual weight close to macOS. It retains useful window titles and Chrome profile names, gives focus a larger surface and a small accent indicator, and puts pinned apps in a separate area on the right. Production implementation proceeds with this direction; the other two concepts remain comparison references.

| Concept | Strength | Tradeoff |
| --- | --- | --- |
| Quiet Shelf | Readable titles, gentle focus, clear profile identity | Uses more height than the ribbon |
| Work Ribbon | Dense 54-point row; good with many windows | Smaller labels and tighter targets; busy desktops feel more crowded |
| Floating Dock | Familiar centered shape and larger icons | Repeated Chrome/Terminal icons become harder to scan; long titles disappear sooner |

The blue in these mockups represents a system accent, not a hard-coded product color. Use native vibrancy, installed app icons, SF Symbols, and system typography in AppKit. Follow system appearance rather than forcing dark mode.

The final shelf omits the leading brand mark at the user's request, giving its space to window buttons.

## Suggested native behavior

| Element | Suggested treatment |
| --- | --- |
| Shelf | Approximately 64 points high; 16-point radius; 8-point internal insets; subtle material and border |
| Window button | Approximately 46 points high; 10-point radius; 5–6-point gaps; 12-point title and 10-point secondary label |
| Focus | 1.3× the width of ordinary buttons; a slightly raised surface and 2–3-point accent underline; avoid a heavy outline on every button |
| Narrow buttons | Shrink to approximately 46 points; retain icon, window ordinal, and known profile cue; expose the full title through hover and accessibility |
| Overflow | Horizontal scrolling once the minimum target size is reached; keep pinned apps and Settings available; never create a second row |
| Pinned apps | Trailing/right area separated by a fine divider; native context menu, running dot, and reorder feedback |
| Chrome identity | Name/initial plus optional color only when the window's profile can be identified; otherwise show Chrome without guessing |
| Hover preview | Approximately 260 points wide, above its window button; 400–500 ms intent delay; immediate dismissal during drag; title-only fallback |
| Motion | Short 140–220 ms transitions; no bouncing or automatic zoom; honor Reduce Motion, Increase Contrast, and Reduce Transparency |

Do not rely on color alone for profile identity, focus, or minimized state. The accessible window label should include the title, app, known profile, and minimized state. Preserve keyboard focus across list updates, and keep focused windows visible when navigating the row.

The context menus in the HTML illustrate only the design-relevant items. Production menus should retain all existing native New Window/New Tab commands, every Chrome profile directly at the root, the window list, Hide/Show, Quit, and Show in Finder.

## Companion Settings

Keep the taskbar menu short. A small native Settings window can hold four pages:

- **General:** Start at Login, windows on all displays or this display, title-only or thumbnail hover previews, and appearance inherited from macOS.
- **Pinned Apps:** editable list with drag handles, Add App, and Remove. Avoid accidentally launching an app while rearranging it.
- **Shortcuts:** shortcut recorder, conflict feedback, and Clear. The `⌃⌥W` shown in the sketch is an example, not a mandated default; VoiceOver uses Control–Option, so shortcuts should be configurable and checked against accessibility settings.
- **Diagnostics:** current version, permission status, recent lifecycle events, Reveal Logs, and Export. App logs should omit window titles and Chrome account/profile details by default.

Request Screen Recording only after the user chooses thumbnail previews. A denied permission should leave title previews working and offer a clear Settings link. Reading the preference must never trigger a permission dialog.

## Rendering and checks

The PNG files are snapshots of this project's own HTML, made by an offscreen AppKit/WKWebView process. It sets an activation policy of `.prohibited`, never orders its window, and never captures the screen. No dependency installation is required.

```sh
xcrun swiftc docs/design/render.swift -o /tmp/windowbar-design-render
/tmp/windowbar-design-render "$(pwd)/docs/design"
```

The renderer checks 15 sample DOM behaviors: initial and crowded window counts, keyboard navigation, focus synchronization, drag reorder, Terminal hover preview, disabling previews, four-profile menu contents and opening, a profile action, settings opening, login state, display filtering, and both appearances. These are mockup interaction checks, not production integration tests. The PNGs were also visually inspected for clipped text, menu placement, crowded states, and the settings sketch.

Production acceptance should additionally cover real Chrome and Terminal windows, monitor attachment/removal, denied thumbnail permission, keyboard-only navigation, reordered pin persistence, installed-app login registration, lifecycle logs, and accessibility contrast/motion settings. Those checks should be run against the app without disrupting the user's active desktop.
