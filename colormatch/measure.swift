// measure <image> <x0,y0,x1,y1 as 0..1 fractions> ...  → 영역별 평균 sRGB / Lab / LCh
// crop <image> <x0,y0,x1,y1> <out.jpg>                 → 영역 잘라서 저장 (확인용)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func load(_ p: String) -> (CGImage, [UInt8], Int, Int) {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
    let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts)!
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!   // 모든 이미지를 sRGB로 변환해서 측정
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (img, buf, w, h)
}
func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
func lab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let R = lin(r), G = lin(g), B = lin(b)
    var x = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047
    var y = 0.2126 * R + 0.7152 * G + 0.0722 * B
    var z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883
    func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
    x = f(x); y = f(y); z = f(z)
    return (116 * y - 16, 500 * (x - y), 200 * (y - z))
}
func rect(_ s: String, _ w: Int, _ h: Int) -> (Int, Int, Int, Int) {
    let v = s.split(separator: ",").map { Double($0)! }
    return (Int(v[0] * Double(w)), Int(v[1] * Double(h)), Int(v[2] * Double(w)), Int(v[3] * Double(h)))
}
let a = CommandLine.arguments
let (img, buf, w, h) = load(a[2])
if a[1] == "crop" {
    let (x0, y0, x1, y1) = rect(a[3], w, h)
    let c = img.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[4]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c, nil); CGImageDestinationFinalize(d)
    exit(0)
}
print("size \(w)x\(h)")
if a[1] == "stats" {   // 전체 톤 분포 + 밝기대별 평균 색 (영역 주면 그 안만)
    var (x0, y0, x1, y1) = (0, 0, w, h)
    if a.count > 3 { (x0, y0, x1, y1) = rect(a[3], w, h) }
    var Ls = [Double](); var bands = [[Double]](repeating: [0, 0, 0], count: 10)
    for y in stride(from: y0, to: y1, by: 2) { for x in stride(from: x0, to: x1, by: 2) {
        let i = (y * w + x) * 4
        let (l, aa, bb) = lab(Double(buf[i]) / 255, Double(buf[i + 1]) / 255, Double(buf[i + 2]) / 255)
        Ls.append(l); let k = min(9, Int(l / 10)); bands[k][0] += aa; bands[k][1] += bb; bands[k][2] += 1
    } }
    Ls.sort(); let n = Double(Ls.count)
    print("L 백분위", [0.5, 2, 5, 10, 25, 50, 75, 90, 95, 98, 99.5].map { String(format: "p%g=%.1f", $0, Ls[min(Ls.count - 1, Int(n * $0 / 100))]) }.joined(separator: " "))
    for k in 0..<10 where bands[k][2] > n * 0.003 {
        let c = bands[k][2]
        print(String(format: "  L%2d~%3d  %4.1f%%  a %5.1f  b %5.1f", k * 10, k * 10 + 10, c / n * 100, bands[k][0] / c, bands[k][1] / c))
    }
    exit(0)
}
for s in a[3...] {
    let (x0, y0, x1, y1) = rect(s, w, h)
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0
    var sL = 0.0, sL2 = 0.0, sC = 0.0, sC2 = 0.0   // 픽셀별 L·채도 편차 (피부 균일도 확인용)
    for y in y0..<y1 { for x in x0..<x1 {
        let i = (y * w + x) * 4
        let pr = Double(buf[i]), pg = Double(buf[i + 1]), pb = Double(buf[i + 2])
        r += pr; g += pg; b += pb; n += 1
        let (l, aa, bb) = lab(pr / 255, pg / 255, pb / 255); let c = sqrt(aa * aa + bb * bb)
        sL += l; sL2 += l * l; sC += c; sC2 += c * c
    } }
    let sdL = sqrt(max(0, sL2 / n - pow(sL / n, 2))), sdC = sqrt(max(0, sC2 / n - pow(sC / n, 2)))
    r /= n * 255; g /= n * 255; b /= n * 255
    let (L, A, B) = lab(r, g, b)
    let C = sqrt(A * A + B * B), H = atan2(B, A) * 180 / .pi
    print(String(format: "%@  RGB %3.0f %3.0f %3.0f  Lab %5.1f %5.1f %5.1f  C %4.1f h %5.1f  sdL %4.1f sdC %4.1f", s, r * 255, g * 255, b * 255, L, A, B, C, H, sdL, sdC))
}
