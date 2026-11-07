import Foundation
import Vision
import ImageIO
// 사진의 방향을 반영해 얼굴·눈 위치를 찾음. 출력: 이미지 가로 세로, 두 눈 중심(정규화, 왼쪽 위 기준), 눈 사이 거리(가로 대비), 얼굴 상자
for path in CommandLine.arguments.dropFirst() {
  let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
  let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2000]
  let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)!
  let req = VNDetectFaceLandmarksRequest()
  try! VNImageRequestHandler(cgImage: img).perform([req])
  guard let f = req.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }), let lm = f.landmarks,
        let le = lm.leftPupil?.normalizedPoints.first, let re = lm.rightPupil?.normalizedPoints.first else { print("얼굴 못 찾음", path); continue }
  let bb = f.boundingBox
  func g(_ p: CGPoint) -> CGPoint { CGPoint(x: bb.minX + p.x * bb.width, y: 1 - (bb.minY + p.y * bb.height)) }
  let a = g(le), b = g(re)
  let W = Double(img.width), H = Double(img.height)
  let cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2
  let dx = (a.x - b.x) * W, dy = (a.y - b.y) * H
  let d = (dx * dx + dy * dy).squareRoot() / W
  let ang = atan2((b.y - a.y) * H, (b.x - a.x) * W) * 180 / Double.pi
  print(String(format: "각도 %.2f  ", ang), terminator: "")
  print(String(format: "%d %d %.5f %.5f %.5f %.5f %.5f %.5f %.5f", img.width, img.height, cx, cy, d, bb.minX, 1 - bb.maxY, bb.width, bb.height), (path as NSString).lastPathComponent)
}
