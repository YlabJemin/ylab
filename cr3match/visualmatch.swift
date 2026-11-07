// 카톡 등으로 받은 JPG가 RAW(CR3) 중 어느 사진인지 모양으로 찾기 (읽기만)
// 사용: visualmatch <RAW 폴더> <jpg> [jpg…]  → jpg마다 가장 닮은 RAW 3개와 점수
// 방법: 둘 다 작은 흑백(48×32)으로 줄이고 밝기 차이(경계) 모양을 비교 — 보정 색감이 달라도 구도·윤곽으로 맞춤
import Foundation
import ImageIO
import CoreGraphics
let W = 48, H = 32
func vec(_ url: URL) -> [Float]? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opt: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: false, kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                                kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailWithTransform: true]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opt as CFDictionary) else { return nil }
    // 3:2 가운데로 잘라 맞춤 (가로/세로 모두)
    let iw = CGFloat(img.width), ih = CGFloat(img.height), landscape = iw >= ih
    let tw = landscape ? W : H, th = landscape ? H : W
    var px = [UInt8](repeating: 0, count: tw * th)
    let ctx = CGContext(data: &px, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: tw, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.interpolationQuality = .high
    let ar = CGFloat(tw) / CGFloat(th); var r = CGRect(x: 0, y: 0, width: iw, height: ih)
    if iw / ih > ar { r.size.width = ih * ar; r.origin.x = (iw - r.width) / 2 } else { r.size.height = iw / ar; r.origin.y = (ih - r.height) / 2 }
    guard let crop = img.cropping(to: r) else { return nil }
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: tw, height: th))
    // 가로 기준으로 통일 + 밝기 기울기(경계) → 평균0·크기1
    var g = [Float](); g.reserveCapacity(tw * th * 2)
    for y in 0..<th { for x in 0..<tw {
        let c = Float(px[y * tw + x]), rr = x + 1 < tw ? Float(px[y * tw + x + 1]) : c, d = y + 1 < th ? Float(px[(y + 1) * tw + x]) : c
        g.append(rr - c); g.append(d - c) } }
    g.append(landscape ? 1000 : -1000)   // 방향 다르면 크게 어긋나게
    let m = g.reduce(0, +) / Float(g.count); var n: Float = 0
    for i in g.indices { g[i] -= m; n += g[i] * g[i] }; n = sqrt(max(n, 1e-6))
    return g.map { $0 / n }
}
let a = CommandLine.arguments
let rawDir = URL(fileURLWithPath: a[1])
let raws = ((try? FileManager.default.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: nil)) ?? []).filter { ["cr3", "cr2", "nef", "arw", "dng"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
var rv: [(String, [Float])] = []
let lock = NSLock()
DispatchQueue.concurrentPerform(iterations: raws.count) { i in if let v = vec(raws[i]) { lock.lock(); rv.append((raws[i].lastPathComponent, v)); lock.unlock() } }
for j in a.dropFirst(2) {
    guard let q = vec(URL(fileURLWithPath: j)) else { print(j, "못 읽음"); continue }
    let s = rv.map { ($0.0, zip($0.1, q).reduce(0) { $0 + $1.0 * $1.1 }) }.sorted { $0.1 > $1.1 }
    print((j as NSString).lastPathComponent, "→", s.prefix(3).map { "\($0.0)(\(String(format: "%.3f", $0.1)))" }.joined(separator: "  "))
}
