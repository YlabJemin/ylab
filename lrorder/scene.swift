// scene <미리보기폴더> <출력폴더> : 미리보기 JPG마다 사람을 회색으로 가린 뒤 장면 특징(Vision FeaturePrint)을 <이름>.fp(float32)로 저장
// → 사람·포즈보다 '배경 장소'가 비슷한지로 비교하기 위함
import Foundation
import ImageIO
import CoreGraphics
import Vision

let inDir = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for f in try! FileManager.default.contentsOfDirectory(atPath: inDir).filter({ $0.hasSuffix(".jpg") }).sorted() {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(inDir)/\(f)") as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    let W = img.width, H = img.height
    var px = [UInt8](repeating: 0, count: W * H * 4)
    let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
    let req = VNGeneratePersonSegmentationRequest(); req.qualityLevel = .balanced
    if (try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])) != nil, let mb = req.results?.first?.pixelBuffer {
        CVPixelBufferLockBaseAddress(mb, .readOnly)
        let mw = CVPixelBufferGetWidth(mb), mh = CVPixelBufferGetHeight(mb), st = CVPixelBufferGetBytesPerRow(mb)
        let base = CVPixelBufferGetBaseAddress(mb)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<H { for x in 0..<W where base[(y * mh / H) * st + (x * mw / W)] > 76 {
            let i = (y * W + x) * 4; px[i] = 128; px[i + 1] = 128; px[i + 2] = 128     // 사람 → 회색
        } }
        CVPixelBufferUnlockBaseAddress(mb, .readOnly)
    }
    let masked = ctx.makeImage()!
    let fr = VNGenerateImageFeaturePrintRequest()
    guard (try? VNImageRequestHandler(cgImage: masked, options: [:]).perform([fr])) != nil,
          let obs = fr.results?.first as? VNFeaturePrintObservation else { continue }
    let name = (f as NSString).deletingPathExtension
    try! obs.data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).fp"))
}
print("ok")
