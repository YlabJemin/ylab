// ydot 앱 아이콘 생성: swiftc ydoticon.swift -o /tmp/x && /tmp/x <iconset 폴더> → iconutil -c icns (2026-11-03 만듦, 11-05 로고 2px 위로)
import Cocoa; import UniformTypeIdentifiers
let out = CommandLine.arguments[1]
func make(_ px: Int) -> CGImage {
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let S = CGFloat(px); let inset = S * 0.1   // 맥 앱 아이콘 규격: 전체의 80%가 네모
    let r = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03, color: CGColor(gray: 0, alpha: 0.25))
    c.addPath(CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.width * 0.225, transform: nil)); c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillPath(); c.restoreGState()
    c.saveGState(); c.addPath(CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.width * 0.225, transform: nil)); c.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 0.93, alpha: 1)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: []); c.restoreGState()
    c.addPath(CGPath(roundedRect: r.insetBy(dx: S * 0.004, dy: S * 0.004), cornerWidth: r.width * 0.22, cornerHeight: r.width * 0.22, transform: nil)); c.setStrokeColor(CGColor(gray: 0, alpha: 0.12)); c.setLineWidth(S * 0.006); c.strokePath()
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: S * 0.52, weight: .bold), .foregroundColor: NSColor(white: 0.07, alpha: 1)]
    let sz = ("y." as NSString).size(withAttributes: a); ("y." as NSString).draw(at: NSPoint(x: (S - sz.width) / 2, y: (S - sz.height) / 2 + S * (0.03 + 2.0 / 128)), withAttributes: a)   // 2026-11-05: 128px 기준 2px 위로
    NSGraphicsContext.restoreGraphicsState()
    return c.makeImage()!
}
for (px, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
    let d = NSMutableData(); let dst = CGImageDestinationCreateWithData(d, UTType.png.identifier as CFString, 1, nil)!; CGImageDestinationAddImage(dst, make(px), nil); CGImageDestinationFinalize(dst)
    try! (d as Data).write(to: URL(fileURLWithPath: out + "/" + name + ".png")) }
