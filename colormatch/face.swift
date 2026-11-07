// face <이미지> : 가장 큰 얼굴을 찾아 볼·이마·턱 측정 영역을 0~1 좌표(위쪽 원점)로 출력
// 출력: 볼왼 볼오 (measure에 그대로 넣을 수 있는 x0,y0,x1,y1)
import Foundation
import Vision
import CoreGraphics
import ImageIO
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)!
let req = VNDetectFaceLandmarksRequest()
try! VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
guard let f = (req.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { print("NOFACE"); exit(1) }
let b = f.boundingBox  // 0~1, 아래쪽 원점
func r(_ fx0: Double, _ fy0: Double, _ fx1: Double, _ fy1: Double) -> String {
    // 얼굴 상자 안의 비율(위쪽 원점) → 이미지 비율(위쪽 원점)
    let x0 = b.minX + fx0 * b.width, x1 = b.minX + fx1 * b.width
    let top = 1 - b.maxY
    let y0 = top + fy0 * b.height, y1 = top + fy1 * b.height
    return String(format: "%.4f,%.4f,%.4f,%.4f", x0, y0, x1, y1)
}
// 볼: 눈 아래~코끝 높이, 코 양옆 (블러셔 중심은 피해서 안쪽)
var lips = "0,0,0.001,0.001"
if let ol = f.landmarks?.outerLips {  // 입술 바깥선 상자 → 가운데 아랫입술 쪽만
    let xs = ol.normalizedPoints.map { Double($0.x) }, ys = ol.normalizedPoints.map { Double($0.y) }
    let lx0 = xs.min()!, lx1 = xs.max()!, ly0 = 1 - ys.max()!, ly1 = 1 - ys.min()!
    lips = r(lx0 + (lx1 - lx0) * 0.3, ly0 + (ly1 - ly0) * 0.62, lx0 + (lx1 - lx0) * 0.7, ly0 + (ly1 - ly0) * 0.85)
}
print(r(0.18, 0.50, 0.32, 0.62), r(0.68, 0.50, 0.82, 0.62), lips, r(0.12, 0.30, 0.88, 1.0))
