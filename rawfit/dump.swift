// 폴더 안 JPG → 120x80 sRGB 픽셀(.rgb)로 저장
import Foundation
import ImageIO
import CoreGraphics
let inDir=CommandLine.arguments[1], outDir=CommandLine.arguments[2]; let W=120,H=80
try? FileManager.default.createDirectory(atPath:outDir,withIntermediateDirectories:true)
for f in try! FileManager.default.contentsOfDirectory(atPath:inDir).filter({$0.hasSuffix(".jpg")}) {
  let img=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath:inDir+"/"+f) as CFURL,nil)!,0,nil)!
  var px=[UInt8](repeating:0,count:W*H*4)
  let ctx=CGContext(data:&px,width:W,height:H,bitsPerComponent:8,bytesPerRow:W*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.draw(img,in:CGRect(x:0,y:0,width:W,height:H))
  var rgb=[UInt8](); rgb.reserveCapacity(W*H*3)
  for i in 0..<(W*H) { rgb.append(px[i*4]); rgb.append(px[i*4+1]); rgb.append(px[i*4+2]) }
  try! Data(rgb).write(to:URL(fileURLWithPath:outDir+"/"+f.replacingOccurrences(of:".jpg",with:".rgb")))
}
