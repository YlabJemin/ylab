import Cocoa; import UniformTypeIdentifiers
let out = CommandLine.arguments[1]; let N = 512
let cs = CGColorSpaceCreateDeviceRGB()
func ctx() -> CGContext { CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! }
func draw(_ c: CGContext, _ f: () -> Void) { NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false); f(); NSGraphicsContext.restoreGraphicsState() }
func save(_ c: CGContext, _ name: String) { let img = c.makeImage()!; let d = NSMutableData(); let dst = CGImageDestinationCreateWithData(d, UTType.png.identifier as CFString, 1, nil)!; CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst); try! (d as Data).write(to: URL(fileURLWithPath: out + "/" + name + ".png")) }
let ws = NSWorkspace.shared
let plain = ws.icon(for: .folder), c1 = ws.icon(forFile: "/Applications/Capture One.app")
func whiteFolder(lo: CGFloat, hi: CGFloat) -> CGContext {
    let c = ctx(); draw(c) { plain.draw(in: NSRect(x: 0, y: 0, width: N, height: N)) }
    let d = c.data!.assumingMemoryBound(to: UInt8.self)
    for i in stride(from: 0, to: N * N * 4, by: 4) { let a = CGFloat(d[i + 3]) / 255; if a == 0 { continue }
        let l = (0.299 * CGFloat(d[i]) + 0.587 * CGFloat(d[i + 1]) + 0.114 * CGFloat(d[i + 2])) / 255 / a
        let v = lo + (hi - lo) * min(1, max(0, (l - 0.3) / 0.55)); let pv = UInt8(min(255, v * a * 255)); d[i] = pv; d[i + 1] = pv; d[i + 2] = pv }
    return c }
func ring() -> (CGImage, CGRect) {
    let c = ctx(); draw(c) { c1.draw(in: NSRect(x: 0, y: 0, width: N, height: N)) }
    let o = ctx(); let sd = c.data!.assumingMemoryBound(to: UInt8.self), od = o.data!.assumingMemoryBound(to: UInt8.self)
    var minX = N, maxX = 0, minY = N, maxY = 0
    for y in 0..<N { for x in 0..<N { let i = (y * N + x) * 4; let ca = CGFloat(sd[i + 3]) / 255; let l = ca > 0 ? (0.299 * CGFloat(sd[i]) + 0.587 * CGFloat(sd[i + 1]) + 0.114 * CGFloat(sd[i + 2])) / 255 / ca : 1
        let dx = Double(x - N / 2), dy = Double(y - N / 2); let inC = dx * dx + dy * dy < Double(N * N) / 9
        let a = inC ? max(0, min(1, (0.6 - l) / 0.5)) * ca : 0
        od[i] = UInt8(0.06 * a * 255); od[i + 1] = od[i]; od[i + 2] = od[i]; od[i + 3] = UInt8(a * 255)
        if a > 0.3 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } } }
    return (o.makeImage()!, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) }   // makeImage 좌표 = 버퍼 좌표(위가 0) → crop에 그대로
// 가장자리만 살짝 어둡게: 바깥(투명)에서 r픽셀 안쪽까지 회색으로 섞음 (흰색은 그대로)
func edge(_ base: CGContext, r: Int, strength: CGFloat) -> CGContext {
    let c = ctx(); c.draw(base.makeImage()!, in: CGRect(x: 0, y: 0, width: N, height: N))
    let d = c.data!.assumingMemoryBound(to: UInt8.self), sd = base.data!.assumingMemoryBound(to: UInt8.self)
    func alpha(_ x: Int, _ y: Int) -> UInt8 { (x < 0 || y < 0 || x >= N || y >= N) ? 0 : sd[(y * N + x) * 4 + 3] }
    for y in 0..<N { for x in 0..<N { let i = (y * N + x) * 4; let a = CGFloat(d[i + 3]) / 255; if a == 0 { continue }
        var near = r + 1   // 가장 가까운 투명 픽셀까지 거리
        for dy in -r...r { for dx in -r...r { if dx * dx + dy * dy <= r * r, alpha(x + dx, y + dy) < 128 { near = min(near, Int((Double(dx * dx + dy * dy)).squareRoot().rounded())) } } }
        if near > r { continue }
        let k = strength * (1 - CGFloat(near) / CGFloat(r + 1))   // 바깥쪽일수록 진하게
        for ch in 0..<3 { d[i + ch] = UInt8(CGFloat(d[i + ch]) * (1 - k)) } } }
    return c }
// 기본 파란 폴더의 명암 구조를 그대로 흰색으로: 가장 밝은 곳=흰색, 나머지는 원래 명암 차이의 k배
func whiteSameShade(k: CGFloat) -> CGContext {
    let c = ctx(); draw(c) { plain.draw(in: NSRect(x: 0, y: 0, width: N, height: N)) }
    let d = c.data!.assumingMemoryBound(to: UInt8.self)
    var lmax: CGFloat = 0; var ls = [CGFloat](repeating: 0, count: N * N)
    for p in 0..<(N * N) { let i = p * 4; let a = CGFloat(d[i + 3]) / 255; if a < 0.9 { continue }
        let l = (0.299 * CGFloat(d[i]) + 0.587 * CGFloat(d[i + 1]) + 0.114 * CGFloat(d[i + 2])) / 255 / a; ls[p] = l; lmax = max(lmax, l) }
    for p in 0..<(N * N) { let i = p * 4; let a = CGFloat(d[i + 3]) / 255; if a == 0 { continue }
        let l = a < 0.9 ? (0.299 * CGFloat(d[i]) + 0.587 * CGFloat(d[i + 1]) + 0.114 * CGFloat(d[i + 2])) / 255 / a : ls[p]
        let v = min(1, 1 - k * (lmax - l) / lmax); let pv = UInt8(min(255, v * a * 255)); d[i] = pv; d[i + 1] = pv; d[i + 2] = pv }
    return c }
let (ringFull, rr) = ring(); let ringImg = ringFull.cropping(to: rr)!
print("고리 범위", rr)
func compose(_ base: CGContext, scale: CGFloat, dy: CGFloat, name: String, tile: Bool = false) {
    let c = ctx(); let bimg = base.makeImage()!
    c.draw(bimg, in: CGRect(x: 0, y: 0, width: N, height: N))
    let w = CGFloat(N) * scale; let dst = CGRect(x: (CGFloat(N) - w) / 2, y: (CGFloat(N) - w) / 2 + dy, width: w, height: w)
    if tile { c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: CGColor(gray: 0, alpha: 0.25)); c.setFillColor(CGColor(gray: 1, alpha: 1)); c.addPath(CGPath(roundedRect: dst.insetBy(dx: -w * 0.22, dy: -w * 0.22), cornerWidth: w * 0.3, cornerHeight: w * 0.3, transform: nil)); c.fillPath(); c.restoreGState() }
    c.draw(ringImg, in: dst); save(c, name) }
let wf = whiteFolder(lo: 0.74, hi: 0.99), gf = whiteFolder(lo: 0.62, hi: 0.93)
save(wf, "white_folder")
compose(wf, scale: 0.30, dy: -28, name: "E_white_ring")
compose(gf, scale: 0.30, dy: -28, name: "F_lightgray_ring")
compose(wf, scale: 0.22, dy: -28, name: "G_white_ring_tile", tile: true)
compose(wf, scale: 0.38, dy: -28, name: "H_white_ring_big")
compose(edge(wf, r: 3, strength: 0.22), scale: 0.38, dy: -28, name: "H4_edge")   // 흰색 그대로 + 가장자리 선 약하게
compose(edge(wf, r: 4, strength: 0.34), scale: 0.38, dy: -28, name: "H5_edge")   // 가장자리 선 조금 더
compose(edge(whiteFolder(lo: 0.86, hi: 1.0), r: 4, strength: 0.34), scale: 0.38, dy: -28, name: "H6_whiter")   // 더 희게 + H5 가장자리
compose(edge(whiteFolder(lo: 0.93, hi: 1.0), r: 4, strength: 0.34), scale: 0.38, dy: -28, name: "H7_whitest")   // 거의 순백
compose(edge(whiteSameShade(k: 1.0), r: 4, strength: 0.34), scale: 0.38, dy: -28, name: "H8_same")    // 기본 폴더와 같은 명암 차이
compose(edge(whiteSameShade(k: 0.6), r: 4, strength: 0.34), scale: 0.38, dy: -28, name: "H9_60")      // 명암 차이 60%
