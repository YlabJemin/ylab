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

func composeText(_ base: CGContext, text: String, size: CGFloat, dy: CGFloat, name: String) {
    let c = ctx(); c.draw(base.makeImage()!, in: CGRect(x: 0, y: 0, width: N, height: N))
    draw(c) { let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor(white: 0.06, alpha: 1)]
        let sz = (text as NSString).size(withAttributes: a); (text as NSString).draw(at: NSPoint(x: (CGFloat(N) - sz.width) / 2, y: (CGFloat(N) - sz.height) / 2 + dy), withAttributes: a) }
    save(c, name) }
let base = edge(whiteSameShade(k: 0.6), r: 4, strength: 0.34)   // 세션 폴더(H9)와 같은 바탕
composeText(base, text: "y.", size: 200, dy: -22, name: "Y1_ydot")
composeText(base, text: "y.", size: 240, dy: -22, name: "Y2_ydot_big")
