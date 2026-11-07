// yap 앱 아이콘: 검정 둥근 네모 + 흰 "yap." (2026-11-05 사용자 선택 B) → iconset PNG
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (s, n) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
    let k = CGFloat(s) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.3); sh.shadowBlurRadius = 20 * k; sh.shadowOffset = NSSize(width: 0, height: -10 * k); sh.set()
    NSColor(srgbRed: 0.078, green: 0.078, blue: 0.086, alpha: 1).setFill(); NSBezierPath(roundedRect: r, xRadius: 185 * k, yRadius: 185 * k).fill()
    NSShadow().set()
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 260 * k, weight: .heavy), .foregroundColor: NSColor.white, .kern: -6 * k]
    let t = "yap." as NSString, sz = t.size(withAttributes: a)
    t.draw(at: NSPoint(x: (CGFloat(s) - sz.width) / 2, y: (CGFloat(s) - sz.height) / 2 + 8 * k), withAttributes: a)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(n).png"))
}
