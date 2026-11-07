// yinsta 앱 아이콘: 인스타 공식 로고(2016 SVG, viewBox 132×132) 수치 그대로 — 그라데이션 2겹 + 흰 둥근 네모 테두리(카메라 몸통), 안의 동그라미·점 대신 흰 'y.' 정중앙
// 사용법: icon <iconset 폴더> <ui/applogo.png>
import Cocoa; import UniformTypeIdentifiers; import CoreText
let args = CommandLine.arguments
let yDown: CGFloat = args.count > 3 ? CGFloat(Double(args[3]) ?? 0) : 0   // y. 를 네모 크기의 몇 % 내릴지 (예: 0.03)
let cs = CGColorSpaceCreateDeviceRGB()
func col(_ h: UInt32, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a])! }
let gradA = CGGradient(colorsSpace: cs, colors: [col(0xFFDD55), col(0xFFDD55), col(0xFF543E), col(0xC837AB)] as CFArray, locations: [0, 0.1, 0.5, 1])!       // 노랑→주황빨강→자홍 (왼쪽 아래 중심)
let gradB = CGGradient(colorsSpace: cs, colors: [col(0x3771C8), col(0x3771C8), col(0x6600FF, 0)] as CFArray, locations: [0, 0.128, 1])!                    // 위쪽 파랑, 아래로 투명하게

func render(_ N: Int, inset insetRatio: CGFloat) -> CGImage {
    let c = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let n = CGFloat(N), inset = n * insetRatio
    let r = CGRect(x: inset, y: inset, width: n - 2 * inset, height: n - 2 * inset)   // 그라데이션 네모 (맥 아이콘은 10% 여백)
    let u = r.width / 132   // SVG 1단위 = u 픽셀
    c.saveGState()
    c.addPath(CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.width * 0.225, transform: nil)); c.clip()
    // SVG 좌표계(132 단위, y 아래로)로 바꾼 뒤 공식 gradientTransform 그대로 적용
    c.translateBy(x: r.minX, y: r.maxY); c.scaleBy(x: u, y: -u)
    c.saveGState()
    c.concatenate(CGAffineTransform(a: 0, b: -1.98198, c: 1.8439, d: 0, tx: -1031.402, ty: 454.004))
    c.drawRadialGradient(gradA, startCenter: CGPoint(x: 158.429, y: 578.088), startRadius: 0, endCenter: CGPoint(x: 158.429, y: 578.088), endRadius: 65, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
    c.saveGState()
    c.concatenate(CGAffineTransform(a: 0.17394, b: 0.86872, c: -3.5818, d: 0.71718, tx: 1648.348, ty: -458.493))
    c.drawRadialGradient(gradB, startCenter: CGPoint(x: 147.694, y: 473.455), startRadius: 0, endCenter: CGPoint(x: 147.694, y: 473.455), endRadius: 65, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
    // 흰 둥근 네모 테두리: 공식 글리프 = 바깥 18~114, 선 굵기 8.65, 바깥 모서리 반지름 ≈ 28 (132 단위)
    let lw: CGFloat = 8.65, o: CGFloat = 18, rad: CGFloat = 28
    let box = CGRect(x: o + lw / 2, y: o + lw / 2, width: 132 - 2 * o - lw, height: 132 - 2 * o - lw)
    c.setStrokeColor(CGColor(colorSpace: cs, components: [1, 1, 1, 1])!); c.setLineWidth(lw)
    c.addPath(CGPath(roundedRect: box, cornerWidth: rad - lw / 2, cornerHeight: rad - lw / 2, transform: nil)); c.strokePath()
    c.restoreGState()
    // 'y.' — 글자 잉크의 가운데를 네모 중심에 (와이닷 글꼴: 시스템 볼드)
    let font = NSFont.systemFont(ofSize: r.width * 0.46, weight: .bold)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "y.", attributes: [.font: font, .foregroundColor: NSColor.white]))
    let ink = CTLineGetImageBounds(line, c)
    c.textPosition = CGPoint(x: r.midX - ink.midX, y: r.midY - ink.midY - r.width * yDown)
    CTLineDraw(line, c)
    return c.makeImage()!
}
func save(_ img: CGImage, _ path: String) {
    let d = NSMutableData(); let dst = CGImageDestinationCreateWithData(d, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst); try! (d as Data).write(to: URL(fileURLWithPath: path))
}
if args[1] == "--one" { save(render(512, inset: 0.1), args[2]); exit(0) }   // 미리보기 한 장: icon --one <out.png> <내림비율>
let outDir = args[1], logoPath = args[2]
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    save(render(px, inset: 0.1), outDir + "/icon_" + name + ".png")
}
save(render(256, inset: 0), logoPath)   // 앱 시작 화면 로고 (여백 없이)
