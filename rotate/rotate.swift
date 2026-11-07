// rotate <파일...> : 사진을 시계방향 90도 회전
//   JPG·HEIC·TIFF: 다시 압축하지 않고 방향 태그만 바꿈 (화질 그대로)
//   PNG·GIF·BMP: 픽셀을 실제로 돌려 같은 형식으로 저장 (PNG는 무손실)
//   RAW·그 밖의 파일: 건너뜀
// 결과 한 줄 출력: "회전 N장" (+ 건너뛴 파일 수)
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

let tagTypes: Set<String> = ["jpg", "jpeg", "heic", "heif", "tif", "tiff"]
let pixelTypes: Set<String> = ["png", "gif", "bmp"]
// 현재 방향 → 시계방향 90도 더 돌린 방향 (EXIF 1~8)
let cw: [Int: Int] = [1: 6, 6: 3, 3: 8, 8: 1, 2: 7, 7: 4, 4: 5, 5: 2]

func replace(_ url: URL, _ tmp: URL) throws {
    _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)   // 원래 파일 자리에 바꿔 넣음 (만든 날짜 등 유지)
}

func rotateTag(_ url: URL) -> Bool {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(src) else { return false }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    let cur = props[kCGImagePropertyOrientation] as? Int ?? 1
    let tmp = url.deletingLastPathComponent().appendingPathComponent(".cc-rotate-\(UUID().uuidString)." + url.pathExtension)
    guard let dst = CGImageDestinationCreateWithURL(tmp as CFURL, type, 1, nil) else { return false }
    let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil).flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
    let next = (cw[cur] ?? 6) as CFNumber
    CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, next)
    let opts: [CFString: Any] = [kCGImageDestinationMetadata: meta, kCGImageDestinationMergeMetadata: true]
    var err: Unmanaged<CFError>?
    guard CGImageDestinationCopyImageSource(dst, src, opts as CFDictionary, &err) else { try? FileManager.default.removeItem(at: tmp); return false }
    do { try replace(url, tmp); return true } catch { try? FileManager.default.removeItem(at: tmp); return false }
}

func rotatePixels(_ url: URL) -> Bool {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(src),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
    let w = img.width, h = img.height
    guard let ctx = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                              space: img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    ctx.translateBy(x: 0, y: CGFloat(w)); ctx.rotate(by: -.pi / 2)        // 시계방향 90도
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let out = ctx.makeImage() else { return false }
    let tmp = url.deletingLastPathComponent().appendingPathComponent(".cc-rotate-\(UUID().uuidString)." + url.pathExtension)
    guard let dst = CGImageDestinationCreateWithURL(tmp as CFURL, type, 1, nil) else { return false }
    CGImageDestinationAddImage(dst, out, CGImageSourceCopyPropertiesAtIndex(src, 0, nil))
    guard CGImageDestinationFinalize(dst) else { try? FileManager.default.removeItem(at: tmp); return false }
    do { try replace(url, tmp); return true } catch { try? FileManager.default.removeItem(at: tmp); return false }
}

var done = 0, skipped = 0
for p in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: p), ext = url.pathExtension.lowercased()
    let ok = tagTypes.contains(ext) ? rotateTag(url) : pixelTypes.contains(ext) ? rotatePixels(url) : false
    if ok { done += 1 } else { skipped += 1 }
}
print(skipped > 0 ? "회전 \(done)장 · 건너뜀 \(skipped)개" : "회전 \(done)장")
