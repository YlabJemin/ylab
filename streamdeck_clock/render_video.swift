// render_video <render_page.html> <출력.mp4> [초=16] [fps=60] : WebKit으로 장면을 한 장씩 그려 부드러운 H.264 영상으로 (반복 재생용)
import Cocoa
import WebKit
import AVFoundation

let a = CommandLine.arguments
let page = URL(fileURLWithPath: a[1]), outURL = URL(fileURLWithPath: a[2])
let secs = a.count > 3 ? Double(a[3])! : 16, fps = a.count > 4 ? Int(a[4])! : 60
let W = 992, H = 232, N = Int(secs) * fps
let baseMs = (Date().timeIntervalSince1970 * 1000 / (secs * 1000)).rounded(.down) * secs * 1000   // 반복 주기에 맞춘 시작 시각

class R: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H))
    var writer: AVAssetWriter!, input: AVAssetWriterInput!, adaptor: AVAssetWriterInputPixelBufferAdaptor!
    var i = 0
    var win: NSWindow!
    func start() {
        try? FileManager.default.removeItem(at: outURL)
        writer = try! AVAssetWriter(outputURL: outURL, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]])
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        // 화면 밖 창에 붙여야 WebKit이 실제로 그림
        win = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: W, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = web; win.orderBack(nil)
        web.navigationDelegate = self
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { next() }
    func next() {
        if i >= N { input.markAsFinished(); writer.finishWriting { print("완료: \(N)장 → \(outURL.path)"); exit(0) }; return }
        web.callAsyncJavaScript("return draw(i, fps, base)", arguments: ["i": i, "fps": fps, "base": baseMs], in: nil, in: .page) { _ in
            let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: W); cfg.afterScreenUpdates = true
            self.web.takeSnapshot(with: cfg) { img, _ in
                guard let img = img, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("스냅샷 실패"); exit(1) }
                var pb: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, self.adaptor.pixelBufferPool!, &pb)
                CVPixelBufferLockBaseAddress(pb!, [])
                let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!),
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
                CVPixelBufferUnlockBaseAddress(pb!, [])
                while !self.input.isReadyForMoreMediaData { usleep(1000) }
                self.adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(self.i), timescale: CMTimeScale(fps)))
                if self.i % 120 == 0 { print("\(self.i)/\(N)") }
                self.i += 1; self.next()
            }
        }
    }
}
let app = NSApplication.shared
let r = R(); r.start()
app.run()
