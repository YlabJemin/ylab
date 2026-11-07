// sheet <order.json> <미리보기폴더> <출력.jpg> : 묶음별 한 줄씩, 새 순서 번호와 묶음 이름을 붙인 미리보기 시트
import Foundation
import AppKit

let a = CommandLine.arguments
let j = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[1]))) as! [String: Any]
var groups = j["groups"] as! [[String]]
var gnames = j["names"] as? [String]
if ProcessInfo.processInfo.environment["SHEET_FLAT"] != nil { groups = [groups.flatMap { $0 }]; gnames = nil }
let env = ProcessInfo.processInfo.environment   // SHEET_TH=사진 높이, SHEET_PER=한 줄 장수, SHEET_FLAT=1 이면 묶음 없이 쭉
let flat = env["SHEET_FLAT"] != nil
let TH = CGFloat(Double(env["SHEET_TH"] ?? "170")!), gap: CGFloat = 8, perRow = Int(env["SHEET_PER"] ?? "12")!, labelW: CGFloat = flat ? 8 : 70
var rows: [[(String, Int)]] = [], rowGroup: [Int] = []
var k = 0
for (gi, g) in groups.enumerated() {
    var cur: [(String, Int)] = []
    for n in g { k += 1; cur.append((n, k)); if cur.count == perRow { rows.append(cur); rowGroup.append(gi); cur = [] } }
    if !cur.isEmpty { rows.append(cur); rowGroup.append(gi) }
}
let cellW = TH * 0.75
let W = labelW + CGFloat(perRow) * (cellW + gap) + gap
let rowH = TH + 26 + (gnames == nil ? 0 : 24)   // 묶음 이름 자리
var H: CGFloat = 0
for (i, _) in rows.enumerated() { H += rowH + ((i > 0 && rowGroup[i] != rowGroup[i - 1]) ? 14 : 0) }
let img = NSImage(size: NSSize(width: W, height: H + 10))
img.lockFocus()
NSColor(white: 0.13, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H + 10).fill()
var y = H + 10
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: flat ? 15 : 11, weight: .regular), .foregroundColor: NSColor(white: 0.75, alpha: 1)]
for (i, row) in rows.enumerated() {
    if i > 0 && rowGroup[i] != rowGroup[i - 1] {
        y -= 14
        NSColor(white: 0.35, alpha: 1).setFill(); NSRect(x: 8, y: y + 6, width: W - 16, height: 1).fill()
    }
    y -= rowH
    if !flat && (i == 0 || rowGroup[i] != rowGroup[i - 1]) {
        ("\(rowGroup[i] + 1)" as NSString).draw(at: NSPoint(x: 10, y: y + TH - 14), withAttributes: attrs)
        ("\(groups[rowGroup[i]].count)장" as NSString).draw(at: NSPoint(x: 10, y: y + TH - 32), withAttributes: small)
        if let gn = gnames { (gn[rowGroup[i]] as NSString).draw(at: NSPoint(x: labelW, y: y + TH + 28), withAttributes: attrs) }
    }
    var x = labelW
    for (n, num) in row {
        if let t = NSImage(contentsOfFile: "\(a[2])/\(n).jpg") {
            let s = t.size, sc = min(cellW / s.width, TH / s.height)
            let w = s.width * sc, h = s.height * sc
            t.draw(in: NSRect(x: x + (cellW - w) / 2, y: y + 22 + (TH - h) / 2, width: w, height: h))
        }
        ("\(num)  \(n)" as NSString).draw(at: NSPoint(x: x, y: y + 4), withAttributes: small)
        x += cellW + gap
    }
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: URL(fileURLWithPath: a[3]))
