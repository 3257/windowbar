# Classic Apple taskbar mockups

Visual studies only. These files do not modify the installed app, production views, settings, or version. All window content is sample data; icons were exported from locally installed applications.

Open [the interactive comparison](mockups.html) to switch light/dark appearance, compare five and twelve windows, try 48 pt icons, and toggle the full-window hover peek. Hovering a sample window for 0.6 seconds changes the sample peek. Clicking changes only its mock selection.

| Direction | Icons | Bar height | Character |
| --- | --- | --- | --- |
| **Aqua Shelf — recommended** | 40 pt | 78 pt | Pearl silver, soft blue inset selection, restrained depth |
| Silver Toolbar | 36 pt | 72 pt | Compact satin metal, straighter corners, pressed selection |
| Studio Glass | 44 pt | 86 pt | Larger icons, more space, milky glass and a bright edge |
| **Compact Edge — new** | 48 pt icon area | 52 pt | Icons fill the height, minimal padding, titles alongside |
| **Current Shelf · Larger Icons** | 36 pt, up from 27 pt | 66 pt | Existing taskbar geometry, colors, labels and focus treatment; moderately larger icons |

All five retain a separate labeled button per window, repeated app icons for separate windows, pinned apps on the right, a scrolling window region under load, and the existing 0.6-second full-window peek. The first four concepts keep button widths stable on selection. Current Shelf retains the existing 1.3× focused-window width, 52 pt buttons, 66 pt shelf, title/profile treatment, and trailing pins. Only the icon sizing is proposed to change: window icons from 27 to 36 pt, with larger 36 pt pinned icons. The concepts avoid Dock magnification and app grouping. Compact Edge removes the extra top/bottom spacing and uses larger image boxes to compensate for the transparent margins in native app icon assets.

- [Light comparison](comparison-light.png)
- [Dark comparison](comparison-dark.png)
- [Twelve-window comparison](crowded-light.png)
- [Aqua Shelf detail](aqua-shelf.png)
- [Silver Toolbar detail](silver-toolbar.png)
- [Studio Glass detail](studio-glass.png)
- [Compact Edge — light](compact-edge-light.png)
- [Compact Edge — dark](compact-edge-dark.png)
- [Current Shelf · Larger Icons — light](current-larger-icons-light.png)
- [Current Shelf · Larger Icons — dark](current-larger-icons-dark.png)

The PNGs are rendered from this local HTML using an offscreen WKWebView; they are not desktop captures. Render again with:

```sh
xcrun swiftc docs/design/classic-apple/render.swift -o /tmp/windowbar-classic-render
/tmp/windowbar-classic-render "$PWD/docs/design/classic-apple"
```

Appearance, assets, concept icon sizes, peek visibility, and the two window counts are checked by the renderer. These checks cover the mock document, not production application behavior.
