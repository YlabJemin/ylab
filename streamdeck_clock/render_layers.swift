// render_layers <render_layers.html> <출력폴더> [fps=30] [초=16] : 플러그인용 층별 장면 PNG (bottom/NNN.png 불투명, top/NNN.png 투명)
import Cocoa
import WebKit
let a = CommandLine.arguments
let page = URL(fileURLWithPath: a[1]), out = a[2]
let fps = a.count > 3 ? Int(a[3])! : 30, secs = a.count > 4 ? Int(a[4])! : 16
let W = 496, H = 116, N = fps * secs, layers = ["bottom", "top"]
class R: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H)); var win: NSWindow!
    var li = 0, i = 0
    func start() {
        for l in layers { try? FileManager.default.createDirectory(atPath: "\(out)/\(l)", withIntermediateDirectories: true) }
        web.setValue(false, forKey: "drawsBackground")
        win = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: W, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.contentView = web; win.orderBack(nil)
        web.navigationDelegate = self; web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { next() }
    func next() {
        if i >= N { i = 0; li += 1 }
        if li >= layers.count { print("완료"); exit(0) }
        let layer = layers[li]
        web.callAsyncJavaScript("return draw(i, fps, layer)", arguments: ["i": i, "fps": fps, "layer": layer], in: nil, in: .page) { _ in
            let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: W / 2); cfg.afterScreenUpdates = true   // 레티나 2배라 점 단위 절반 → 496×116 픽셀
            self.web.takeSnapshot(with: cfg) { img, _ in
                guard let img = img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { print("실패"); exit(1) }
                try! png.write(to: URL(fileURLWithPath: "\(out)/\(layer)/\(String(format: "%03d", self.i)).png"))
                if self.i % 60 == 0 { print(layer, self.i, "/", N) }
                self.i += 1; self.next()
            }
        }
    }
}
let app = NSApplication.shared; let r = R(); r.start(); app.run()
