// Pick 앱 아이콘 그리기 → Pick.iconset (iconutil로 .icns)
import AppKit
func draw(_ s: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let k = s / 1024, inset = 100 * k
        let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: 185 * k, yRadius: 185 * k)
        NSGradient(starting: NSColor(red: 1, green: 0.93, blue: 0.95, alpha: 1), ending: NSColor(red: 0.97, green: 0.78, blue: 0.85, alpha: 1))!.draw(in: bg, angle: -90)
        // 사진 카드 두 장 (뒤 살짝 기울임)
        func card(_ x: CGFloat, _ y: CGFloat, _ deg: CGFloat, _ fill: NSColor) {
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform(); t.translateX(by: x * k, yBy: y * k); t.rotate(byDegrees: deg); t.concat()
            let r = NSRect(x: -170 * k, y: -230 * k, width: 340 * k, height: 460 * k)
            let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.18); sh.shadowBlurRadius = 30 * k; sh.shadowOffset = NSSize(width: 0, height: -12 * k); sh.set()
            NSColor.white.setFill(); NSBezierPath(roundedRect: r, xRadius: 18 * k, yRadius: 18 * k).fill()
            NSShadow().set()
            fill.setFill(); NSBezierPath(roundedRect: r.insetBy(dx: 22 * k, dy: 22 * k).offsetBy(dx: 0, dy: 30 * k).insetBy(dx: 0, dy: 30 * k), xRadius: 8 * k, yRadius: 8 * k).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        card(450, 540, 9, NSColor(red: 0.86, green: 0.87, blue: 0.9, alpha: 1))
        card(560, 500, -6, NSColor(red: 0.93, green: 0.88, blue: 0.86, alpha: 1))
        // 별
        let c = NSPoint(x: 700 * k, y: 300 * k), R = 135 * k, r = 58 * k, star = NSBezierPath()
        for i in 0..<10 { let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5, rr = i % 2 == 0 ? R : r
            let p = NSPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr); i == 0 ? star.move(to: p) : star.line(to: p) }
        star.close(); star.lineJoinStyle = .round
        let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.2); sh.shadowBlurRadius = 20 * k; sh.shadowOffset = NSSize(width: 0, height: -6 * k); sh.set()
        NSColor(red: 0.95, green: 0.55, blue: 0.7, alpha: 1).setFill(); star.fill()
        NSColor.white.setStroke(); star.lineWidth = 14 * k; star.stroke()
        return true
    }
}
let dir = "Pick.iconset"; try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (s, n) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    let img = draw(CGFloat(s)); let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: s, height: s)); NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/icon_\(n).png"))
}
