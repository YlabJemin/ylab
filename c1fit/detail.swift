// detail <jpg...> (CROP=1 이면 원래 크기 가운데 잘라 봄) : 사진마다 질감 수치 한 줄 출력 (480×320 밝기 기준)
//   clar  = 중간 크기 부분 대비 (밝기 − 반경 8 흐림) 평균 절댓값   → 캡쳐원 클래리티
//   fine  = 가는 결 (반경 1 흐림 − 반경 3 흐림) 평균 절댓값          → 캡쳐원 스트럭처(텍스처)
//   grain = 평평한 곳(배경)의 잔 입자 크기 (밝기 − 반경 1 흐림) 표준편차 → 필름 그레인
import Foundation
import ImageIO
import CoreGraphics
let W = 480, H = 320
func load(_ p: String) -> [Double] {
    let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!, 0, nil)!
    var px = [UInt8](repeating: 0, count: W * H * 4)
    let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let env = ProcessInfo.processInfo.environment
    if env["CROP"] != nil {     // 원래 크기(SCALE=긴 변 px 이면 그 크기로 줄여서) 480×320 잘라 봄. CY = 자를 세로 위치(0 위 ~ 1 아래, 기본 0.5)
        let sc = env["SCALE"].map { Double($0)! / Double(max(img.width, img.height)) } ?? 1.0
        let iw = Double(img.width) * sc, ih = Double(img.height) * sc, cy = Double(env["CY"] ?? "0.5")!
        ctx.draw(img, in: CGRect(x: (Double(W) - iw) / 2, y: Double(H) / 2 - ih * (1 - cy), width: iw, height: ih))
    } else {
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
    }
    return (0..<(W * H)).map { 0.299 * Double(px[$0 * 4]) + 0.587 * Double(px[$0 * 4 + 1]) + 0.114 * Double(px[$0 * 4 + 2]) }
}
func blur(_ a: [Double], _ r: Int) -> [Double] {
    var I = [Double](repeating: 0, count: (W + 1) * (H + 1))
    for y in 0..<H { var s = 0.0; for x in 0..<W { s += a[y * W + x]; I[(y + 1) * (W + 1) + x + 1] = I[y * (W + 1) + x + 1] + s } }
    var o = [Double](repeating: 0, count: W * H)
    for y in 0..<H { for x in 0..<W {
        let x0 = max(0, x - r), x1 = min(W, x + r + 1), y0 = max(0, y - r), y1 = min(H, y + r + 1)
        o[y * W + x] = (I[y1 * (W + 1) + x1] - I[y0 * (W + 1) + x1] - I[y1 * (W + 1) + x0] + I[y0 * (W + 1) + x0]) / Double((x1 - x0) * (y1 - y0))
    } }
    return o
}
for p in CommandLine.arguments.dropFirst() {
    let Y = load(p), b1 = blur(Y, 1), b3 = blur(Y, 3), b8 = blur(Y, 8)
    var clar = 0.0, fine = 0.0, n = 0.0
    for y in 12..<(H - 12) { for x in 12..<(W - 12) { let i = y * W + x; clar += abs(Y[i] - b8[i]); fine += abs(b1[i] - b3[i]); n += 1 } }
    // 16×16 칸마다 (반경 8 흐림 기준) 평평한 정도와 잔 입자 표준편차 → 가장 평평한 20% 칸의 입자 평균
    var tiles: [(Double, Double)] = []
    for ty in stride(from: 16, to: H - 32, by: 16) { for tx in stride(from: 16, to: W - 32, by: 16) {
        var f = 0.0, s = 0.0, s2 = 0.0, m = 0.0
        for y in ty..<(ty + 16) { for x in tx..<(tx + 16) { let i = y * W + x; f += abs(b1[i] - b8[i]); let d = Y[i] - b1[i]; s += d; s2 += d * d; m += 1 } }
        tiles.append((f / m, (s2 / m - (s / m) * (s / m)).squareRoot()))
    } }
    tiles.sort { $0.0 < $1.0 }
    let k = max(1, tiles.count / 5); let grain = tiles[0..<k].map { $0.1 }.reduce(0, +) / Double(k)
    print(String(format: "%@\t%.3f\t%.3f\t%.3f", (p as NSString).lastPathComponent, clar / n, fine / n, grain))
}
