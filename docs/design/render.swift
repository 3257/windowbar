// Offscreen-only design renderer. Never orders a window or activates an app.
// xcrun swiftc docs/design/render.swift -o /tmp/windowbar-design-render
// /tmp/windowbar-design-render /absolute/path/to/docs/design
import AppKit
import WebKit

final class DesignRenderer: NSObject, WKNavigationDelegate {
    let directory: URL
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1340, height: 2350))
    let window = NSWindow(
        contentRect: NSRect(x: -10000, y: -10000, width: 1340, height: 2350),
        styleMask: [.borderless], backing: .buffered, defer: false)
    var output = "concepts-light.png"
    var stage = 0
    var contentHeight: CGFloat = 2350

    init(directory: URL) {
        self.directory = directory
        super.init()
        webView.navigationDelegate = self
        window.contentView = webView
        window.isReleasedWhenClosed = false
    }

    func start() {
        webView.loadFileURL(directory.appendingPathComponent("mockups.html"), allowingReadAccessTo: directory)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Interactions affect sample DOM only. This never sends events to other apps.
        let test = """
        (() => {
            const staticStyle = document.createElement('style');
            staticStyle.textContent = '*{transition:none!important}';
            document.head.appendChild(staticStyle);
            let checks = 0;
            const assert = (ok, message) => { if (!ok) throw new Error(message); checks++; };
            assert(document.querySelectorAll('.window').length === 15, 'Five windows per concept');
            const first = document.querySelector('.quiet .window'); first.focus();
            first.dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight',bubbles:true}));
            assert(document.activeElement.dataset.id === '1', 'Keyboard window navigation');
            document.activeElement.blur();
            const count = document.getElementById('count');
            count.value = '18'; count.dispatchEvent(new Event('change'));
            assert(document.querySelectorAll('.window').length === 54, 'Crowded windows per concept');
            document.querySelector('.quiet .window[data-id="2"]').click();
            assert(document.querySelectorAll('.window.active[data-id="2"]').length === 3, 'Focus synchronized');
            const transfer = new DataTransfer(); transfer.setData('text/plain', '2');
            document.querySelector('.quiet .window[data-id="0"]').dispatchEvent(new DragEvent('drop', {bubbles:true,cancelable:true,dataTransfer:transfer}));
            assert(document.querySelector('.quiet .window').dataset.id === '2', 'Drag to reorder');
            document.querySelector('.quiet .window[data-id="2"]').dispatchEvent(new PointerEvent('pointerenter'));
            assert(document.querySelector('.quiet .preview').classList.contains('visible'), 'Terminal hover preview');
            document.getElementById('preview-toggle').click();
            assert(document.querySelectorAll('.preview.visible').length === 0, 'Previews disabled');
            document.getElementById('preview-toggle').click();
            document.querySelector('.quiet [data-pin="chrome"]').dispatchEvent(new MouseEvent('contextmenu', {bubbles:true,cancelable:true}));
            assert(document.querySelector('.quiet .profile-menu').classList.contains('open'), 'Chrome profile menu');
            assert(document.querySelectorAll('.quiet [data-profile]').length === 6, 'Four Chrome profiles plus actions');
            document.querySelector('.quiet [data-profile="Client"]').click();
            assert(document.getElementById('live-status').textContent.includes('Client'), 'Profile action status');
            document.querySelector('.quiet .more').click();
            assert(document.querySelector('.quiet .settings-menu').classList.contains('open'), 'Settings menu');
            document.querySelector('.quiet [data-setting="login"]').click();
            assert(document.querySelectorAll('[data-setting="login"][aria-checked="false"]').length === 3, 'Login setting synchronized');
            document.getElementById('display-toggle').click();
            assert(document.querySelector('.quiet .display-label').textContent.includes('All displays'), 'All displays mode');
            document.getElementById('dark').click();
            assert(document.body.classList.contains('dark'), 'Dark appearance');
            document.getElementById('light').click();
            assert(!document.body.classList.contains('dark'), 'Light appearance');
            document.getElementById('display-toggle').click();
            count.value = '5'; count.dispatchEvent(new Event('change'));
            document.getElementById('live-status').textContent = '';
            document.querySelector('.quiet .window').dispatchEvent(new PointerEvent('pointerenter'));
            document.querySelector('.quiet [data-pin="chrome"]').dispatchEvent(new MouseEvent('contextmenu', {bubbles:true,cancelable:true}));
            return { checks, height:Math.ceil(document.body.getBoundingClientRect().height) };
        })()
        """
        webView.evaluateJavaScript(test) { value, error in
            guard error == nil else { self.fail("DOM checks: \(error!)"); return }
            print("Design DOM checks: \(value ?? "none")")
            if let result = value as? [String: Any], let height = result["height"] as? Double {
                self.contentHeight = height
            }
            self.snapshot()
        }
    }

    func snapshot() {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 1340, height: contentHeight)
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { image, error in
            guard let image, let tiff = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff),
                let data = bitmap.representation(using: .png, properties: [:])
            else { self.fail("Snapshot: \(String(describing: error))"); return }
            do { try data.write(to: self.directory.appendingPathComponent(self.output)) }
            catch { self.fail("Write: \(error)"); return }
            print("Rendered \(self.output), \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
            self.stage += 1
            let script: String
            switch self.stage {
            case 1:
                self.output = "concepts-dark.png"
                script = "document.getElementById('dark').click(); true"
            case 2:
                self.output = "concepts-crowded.png"
                script = "document.getElementById('count').value='18';document.getElementById('count').dispatchEvent(new Event('change'));document.getElementById('live-status').textContent='';document.querySelector('.quiet [data-pin=chrome]').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}));true"
            default:
                NSApplication.shared.stop(nil)
                exit(0)
            }
            self.webView.evaluateJavaScript(script) { _, error in
                guard error == nil else { self.fail("Variant: \(error!)"); return }
                self.snapshot()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("Navigation: \(error)")
    }

    func fail(_ message: String) {
        fputs(message + "\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render /absolute/path/to/docs/design\n", stderr)
    exit(1)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = DesignRenderer(directory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
renderer.start()
// An offscreen web process that fails to return cannot leave a developer tool running.
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { renderer.fail("Render timed out") }
app.run()
withExtendedLifetime(renderer) {}
