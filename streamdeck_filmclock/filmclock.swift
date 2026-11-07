// filmclock <layers 폴더> : 플러그인 도우미. 한 줄 "장면번호 epoch밀리초" 를 받으면
//   bottom[장면] + 시간·날짜 글씨(실시간) + top[장면] 을 합쳐 JPEG base64 한 줄로 돌려줌 (Infobar 232×50 의 2배 = 464×100)
//   글씨는 vintage.js 와 같은 자리·크기: 시간 Futura 굵게 주황(#ff8a3c, 빛번짐 #ff6a1a), 초 작게, 오른쪽 요일·월일 Academy Engraved
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let dir = CommandLine.arguments[1]
let W = 496, H = 116, SC: CGFloat = 2, OW = 464, OH = 100   // 출력 = Infobar 232×50 의 2배
func load(_ p: String) -> CGImage? { guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) else { return nil }; return CGImageSourceCreateImageAtIndex(s, 0, nil) }
var bottoms: [CGImage] = [], tops: [CGImage] = []
var k = 0
while let b = load("\(dir)/bottom/\(String(format: "%03d", k)).png"), let t = load("\(dir)/top/\(String(format: "%03d", k)).png") { bottoms.append(b); tops.append(t); k += 1 }
FileHandle.standardError.write("장면 \(bottoms.count)장\n".data(using: .utf8)!)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor { CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a) }
func font(_ names: [String], _ size: CGFloat) -> CTFont {
    for n in names { let f = CTFontCreateWithName(n as CFString, size, nil); if (CTFontCopyPostScriptName(f) as String) == n { return f } }
    return CTFontCreateWithName(names[0] as CFString, size, nil)
}
let fTime = font(["Futura-Bold", "Futura-CondensedExtraBold"], 22.4), fSec = font(["Futura-Bold"], 11.76), fDate = font(["AcademyEngravedLetPlain", "Didot"], 7.65)
func line(_ s: String, _ f: CTFont, _ c: CGColor, kern: CGFloat = 0) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: f, kCTForegroundColorAttributeName as NSAttributedString.Key: c, kCTKernAttributeName as NSAttributedString.Key: kern]))
}
func width(_ l: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) }
let DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

func frame(_ idx: Int, _ ms: Double) -> String {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let i = ((idx % bottoms.count) + bottoms.count) % bottoms.count
    ctx.draw(bottoms[i], in: CGRect(x: 0, y: 0, width: W, height: H))
    // 좌표는 248×58 기준(위가 0) → 2배, 아래가 0 으로 뒤집기
    ctx.saveGState(); ctx.scaleBy(x: SC, y: SC)
    let d = Date(timeIntervalSince1970: ms / 1000), cal = Calendar.current, cp = cal.dateComponents([.hour, .minute, .second, .weekday, .month, .day], from: d)
    let hm = String(format: "%02d:%02d", cp.hour!, cp.minute!), ss = String(format: "%02d", cp.second!)
    let y = { (top: CGFloat) in 58 - top }
    func drawTime(_ main: CGColor, _ sec: CGColor) {
        let l1 = line(hm, fTime, main, kern: 0.6), l2 = line(ss, fSec, sec, kern: 0.6)
        let total = width(l1) + 2 + width(l2), x0 = 124 - total / 2
        ctx.textPosition = CGPoint(x: x0, y: y(38.5)); CTLineDraw(l1, ctx)
        ctx.textPosition = CGPoint(x: x0 + width(l1) + 2, y: y(38.5)); CTLineDraw(l2, ctx)
    }
    // 형광: 넓은 번짐 → 가까운 번짐 → 밝은 주황 심 (vintage.js 의 neonWide·blur 와 같은 느낌)
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 10, color: color(0xff6a1a, 0.95)); drawTime(color(0xff6a1a, 0.55), color(0xff6a1a, 0.55)); ctx.restoreGState()
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 3.4, color: color(0xff6a1a, 0.95)); drawTime(color(0xff6a1a, 0.9), color(0xff6a1a, 0.9)); ctx.restoreGState()
    drawTime(color(0xffb070), color(0xffb070))
    for (top, s) in [(25.0, DAYS[cp.weekday! - 1]), (36.0, "\(MONTHS[cp.month! - 1]) \(String(format: "%02d", cp.day!))")] {
        let l = line(s, fDate, color(0xf2b25a)); ctx.textPosition = CGPoint(x: 239 - width(l), y: y(CGFloat(top))); CTLineDraw(l, ctx)
    }
    ctx.restoreGState()
    ctx.draw(tops[i], in: CGRect(x: 0, y: 0, width: W, height: H))
    // Infobar 232×50 비율로: 폭 464 에 맞춰 줄이고(108.5) 가운데 100 만 남김
    let out = CGContext(data: nil, width: OW, height: OH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    out.interpolationQuality = .high
    let sh = CGFloat(H) * CGFloat(OW) / CGFloat(W)
    out.draw(ctx.makeImage()!, in: CGRect(x: 0, y: (CGFloat(OH) - sh) / 2, width: CGFloat(OW), height: sh))
    let data = NSMutableData()
    let dst = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, out.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    CGImageDestinationFinalize(dst)
    return (data as Data).base64EncodedString()
}
if CommandLine.arguments.count > 2 {          // 시험: filmclock <layers> <출력.jpg> → 지금 시각 장면 한 장 저장
    let b = Data(base64Encoded: frame(0, Date().timeIntervalSince1970 * 1000))!; try! b.write(to: URL(fileURLWithPath: CommandLine.arguments[2])); exit(0)
}
setvbuf(stdout, nil, _IOLBF, 0)
while let l = readLine() {
    let p = l.split(separator: " ")
    guard p.count == 2, let i = Int(p[0]), let ms = Double(p[1]) else { print(""); continue }
    print(frame(i, ms))
}
