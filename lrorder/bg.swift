// bg <출력폴더> <사진...> : 사진마다 (1) 긴 변 600 미리보기 JPG 저장 (2) 사람을 뺀 배경의 색·밝기 특징 출력
// 출력 한 줄(탭 구분): 파일이름  배경L a b  배경밝기편차  사람비율  격자특징(3×3 칸별 배경 L,a,b)
// RAW는 안에 든 미리보기 JPG를 씀 (원본은 읽기만)
import Foundation
import ImageIO
import CoreGraphics
import Vision
import UniformTypeIdentifiers

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func lab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let R = lin(r), G = lin(g), B = lin(b)
    let X = (0.4124564 * R + 0.3575761 * G + 0.1804375 * B) / 0.95047
    let Y = 0.2126729 * R + 0.7151522 * G + 0.0721750 * B
    let Z = (0.0193339 * R + 0.1191920 * G + 0.9503041 * B) / 1.08883
    func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
    return (116 * f(Y) - 16, 500 * (f(X) - f(Y)), 200 * (f(Y) - f(Z)))
}

for p in CommandLine.arguments.dropFirst(2) {
    let url = URL(fileURLWithPath: p)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: false,
              kCGImageSourceCreateThumbnailFromImageIfAbsent: true, kCGImageSourceThumbnailMaxPixelSize: 600,
              kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { print("\(url.lastPathComponent)\tERR"); continue }
    let name = url.deletingPathExtension().lastPathComponent
    if let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/\(name).jpg") as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary); CGImageDestinationFinalize(d)
    }
    let W = img.width, H = img.height
    var px = [UInt8](repeating: 0, count: W * H * 4)
    let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
    // 사람 영역 (정확도 균형)
    var mask = [Float](repeating: 0, count: W * H)
    let req = VNGeneratePersonSegmentationRequest(); req.qualityLevel = .balanced
    if (try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])) != nil, let mb = req.results?.first?.pixelBuffer {
        CVPixelBufferLockBaseAddress(mb, .readOnly)
        let mw = CVPixelBufferGetWidth(mb), mh = CVPixelBufferGetHeight(mb), stride = CVPixelBufferGetBytesPerRow(mb)
        let base = CVPixelBufferGetBaseAddress(mb)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<H { for x in 0..<W {
            let v = base[(y * mh / H) * stride + (x * mw / W)]; mask[y * W + x] = Float(v) / 255
        } }
        CVPixelBufferUnlockBaseAddress(mb, .readOnly)
    }
    var sL = 0.0, sa = 0.0, sb = 0.0, sL2 = 0.0, n = 0.0, person = 0.0
    var grid = [[Double]](repeating: [0, 0, 0, 0], count: 9)
    for y in stride(from: 0, to: H, by: 2) { for x in stride(from: 0, to: W, by: 2) {
        let i = y * W + x
        if mask[i] > 0.3 { person += 1; continue }
        let (L, a, b) = lab(Double(px[i * 4]) / 255, Double(px[i * 4 + 1]) / 255, Double(px[i * 4 + 2]) / 255)
        sL += L; sa += a; sb += b; sL2 += L * L; n += 1
        let g = min(2, y * 3 / H) * 3 + min(2, x * 3 / W)
        grid[g][0] += L; grid[g][1] += a; grid[g][2] += b; grid[g][3] += 1
    } }
    let tot = n + person; n = max(n, 1)
    let mL = sL / n, sd = (max(0, sL2 / n - mL * mL)).squareRoot()
    let gs = grid.map { $0[3] > 20 ? String(format: "%.1f,%.1f,%.1f", $0[0] / $0[3], $0[1] / $0[3], $0[2] / $0[3]) : "-" }.joined(separator: ";")
    print(String(format: "%@\t%.1f\t%.1f\t%.1f\t%.1f\t%.2f\t%@", name, mL, sa / n, sb / n, sd, person / max(tot, 1), gs))
}
