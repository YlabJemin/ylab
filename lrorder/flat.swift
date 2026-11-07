// flat <order.json> <미리보기폴더> <출력.jpg> [높이=420] [줄 너비=3600] : 묶음 없이 순서대로 쭉, 사진 높이를 같게 맞춰 줄 바꿈 (가로 사진도 크게)
import Foundation
import AppKit

let a = CommandLine.arguments
let j = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[1]))) as! [String: Any]
let order = (j["order"] as? [String]) ?? (j["groups"] as! [[String]]).flatMap { $0 }
let H: CGFloat = a.count > 4 ? CGFloat(Double(a[4])!) : 420
let maxW: CGFloat = a.count > 5 ? CGFloat(Double(a[5])!) : 3600
let gap: CGFloat = 10, lab: CGFloat = 30
let imgs = order.map { NSImage(contentsOfFile: "\(a[2])/\($0).jpg") }
// 줄 나누기
var rows: [[Int]] = [[]], w: CGFloat = gap
for (i, im) in imgs.enumerated() {
    let iw = im.map { H * $0.size.width / $0.size.height } ?? H * 0.67
    if w + iw + gap > maxW && !rows[rows.count - 1].isEmpty { rows.append([]); w = gap }
    rows[rows.count - 1].append(i); w += iw + gap
}
let total = CGFloat(rows.count) * (H + lab + gap) + gap
let canvas = NSImage(size: NSSize(width: maxW, height: total))
canvas.lockFocus()
NSColor(white: 0.13, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: maxW, height: total).fill()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor(white: 0.8, alpha: 1)]
var y = total
for r in rows {
    y -= H + lab + gap
    var x = gap
    for i in r {
        let im = imgs[i]; let iw = im.map { H * $0.size.width / $0.size.height } ?? H * 0.67
        im?.draw(in: NSRect(x: x, y: y + lab, width: iw, height: H))
        ("\(i + 1)  \(order[i])" as NSString).draw(at: NSPoint(x: x, y: y + 4), withAttributes: attrs)
        x += iw + gap
    }
}
canvas.unlockFocus()
let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: URL(fileURLWithPath: a[3]))
