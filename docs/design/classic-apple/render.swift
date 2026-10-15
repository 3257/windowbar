// Render this design document offscreen. No desktop capture or application changes.
// xcrun swiftc docs/design/classic-apple/render.swift -o /tmp/windowbar-classic-render
import AppKit
import WebKit

final class MockupRenderer: NSObject, WKNavigationDelegate {
    let directory: URL
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1480, height: 3000))
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1480, height: 3000),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    var stage = 0
    let variants: [(String, String, String)] = [
        ("comparison-light.png", "document.getElementById('light').click()", "main"),
        ("comparison-dark.png", "document.getElementById('dark').click()", "main"),
        ("crowded-light.png", "document.getElementById('light').click(); document.getElementById('crowded').click()", "main"),
        ("aqua-shelf.png", "document.getElementById('normal').click()", "#aqua"),
        ("silver-toolbar.png", "void 0", "#silver"),
        ("studio-glass.png", "void 0", "#glass"),
        ("compact-edge-light.png", "void 0", "#compact"),
        ("compact-edge-dark.png", "document.getElementById('dark').click()", "#compact"),
        ("compact-edge-dark-bar.png", "void 0", "#compact .taskbar"),
        ("compact-edge-light-bar.png", "document.getElementById('light').click()", "#compact .taskbar"),
        ("current-larger-icons-light.png", "void 0", "#current"),
        ("current-larger-icons-dark.png", "document.getElementById('dark').click()", "#current"),
        ("current-larger-icons-dark-bar.png", "void 0", "#current .taskbar"),
        ("current-larger-icons-light-bar.png", "document.getElementById('light').click()", "#current .taskbar"),
    ]

    init(directory: URL) {
        self.directory = directory
        super.init()
        window.contentView = web
        window.isReleasedWhenClosed = false
        web.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let check = """
        (() => {
          const images = [...document.images];
          if (!images.every(i => i.complete && i.naturalWidth > 0)) throw Error('Missing icon asset');
          if (document.querySelectorAll('.win').length !== 25) throw Error('Window count');
          const sizes = [...document.querySelectorAll('.scene')].map(s => getComputedStyle(s).getPropertyValue('--icon').trim());
          if (sizes.join(',') !== '40px,36px,44px,48px,36px') throw Error('Concept icon sizes');
          document.getElementById('dark').click();
          if (!document.body.classList.contains('dark')) throw Error('Dark appearance');
          document.getElementById('light').click();
          document.getElementById('peek-toggle').click();
          if (!document.body.classList.contains('peek-hidden')) throw Error('Peek control');
          document.getElementById('peek-toggle').click();
          document.getElementById('crowded').click();
          if (document.querySelectorAll('.win').length !== 60) throw Error('Crowded state');
          document.getElementById('normal').click();
          const style = document.createElement('style');
          style.textContent = '*{transition:none!important}'; document.head.appendChild(style);
          return 'Assets, icon sizes, appearances, hover visibility and window counts verified';
        })()
        """
        web.evaluateJavaScript(check) { result, error in
            guard error == nil else { self.fail("Mockup check: \(error!)"); return }
            print(result ?? "")
            self.renderNext()
        }
    }

    func renderNext() {
        guard stage < variants.count else { exit(0) }
        let (filename, setup, selector) = variants[stage]
        let script = """
        (()=>{ \(setup); window.scrollTo(0,0);
        const r=document.querySelector('\(selector)').getBoundingClientRect();
        return {x:r.x,y:r.y,width:r.width,height:r.height}; })()
        """
        web.evaluateJavaScript(script) { result, error in
            guard error == nil, let rect = result as? [String: Double] else {
                self.fail("Layout: \(String(describing: error))"); return
            }
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: rect["x"]!, y: rect["y"]!, width: rect["width"]!, height: rect["height"]!)
            config.afterScreenUpdates = true
            self.web.takeSnapshot(with: config) { image, error in
                guard let image, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    self.fail("Snapshot: \(String(describing: error))"); return
                }
                do { try png.write(to: self.directory.appendingPathComponent(filename)) }
                catch { self.fail("Write: \(error)") }
                print("Rendered \(filename): \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
                self.stage += 1
                self.renderNext()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("Navigation: \(error)") }
    func fail(_ message: String) { fputs(message + "\n", stderr); exit(1) }
}

guard CommandLine.arguments.count == 2 else { fatalError("Pass the mockup directory") }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = MockupRenderer(directory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
renderer.web.loadFileURL(renderer.directory.appendingPathComponent("mockups.html"), allowingReadAccessTo: renderer.directory)
DispatchQueue.main.asyncAfter(deadline: .now() + 45) { renderer.fail("Render timed out") }
app.run()
withExtendedLifetime(renderer) {}
