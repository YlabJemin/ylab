// Donut 시험용 가짜 사진 만들기: swift make_samples.swift <출력 폴더>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let rgb = CGColorSpace(name: CGColorSpace.displayP3)!

func picture(_ w: Int, _ h: Int, alpha: Bool, noise: Bool) -> CGImage {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: rgb, bitmapInfo: info)!
    if !alpha {
        ctx.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    ctx.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.3, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: w / 4, y: h / 4, width: w / 2, height: h / 2))
    if noise, let p = ctx.data?.assumingMemoryBound(to: UInt8.self) {
        var seed: UInt32 = 12345
        for y in 0..<h {
            let row = p + y * ctx.bytesPerRow
            for x in 0..<(w * 4) where x % 4 != 3 {
                seed = seed &* 1664525 &+ 1013904223
                row[x] = UInt8(seed >> 24)
            }
        }
    }
    return ctx.makeImage()!
}

func write(_ img: CGImage, _ name: String, _ type: UTType, _ props: [CFString: Any] = [:]) {
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}

let exif: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "시험 렌즈"]]
write(picture(3000, 2000, alpha: false, noise: false), "작은사진.jpg", .jpeg, exif)
write(picture(3000, 2000, alpha: false, noise: false), "세로회전.jpg", .jpeg, exif.merging([kCGImagePropertyOrientation: 6]) { $1 })
write(picture(1200, 800, alpha: false, noise: false), "작은웹.png", .png)
write(picture(5000, 4000, alpha: false, noise: true), "큰사진.tif", .tiff, exif)
write(picture(9000, 7000, alpha: true, noise: true), "큰투명.png", .png)
