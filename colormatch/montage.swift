// montage <출력.jpg> <높이> <이미지...> : 같은 높이로 맞춰 가로로 이어 붙임
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let a = CommandLine.arguments
let H = Int(a[2])!
let imgs: [CGImage] = a[3...].map {
    let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: $0) as CFURL, nil)!
    return CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: H * 2, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)!
}
let ws = imgs.map { Int(Double($0.width) * Double(H) / Double($0.height)) }
let gap = 12, W = ws.reduce(0, +) + gap * (imgs.count - 1)
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(gray: 0.15, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
ctx.interpolationQuality = .high
var x = 0
for (i, im) in imgs.enumerated() { ctx.draw(im, in: CGRect(x: x, y: 0, width: ws[i], height: H)); x += ws[i] + gap }
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
CGImageDestinationFinalize(d)
