import AppKit
let font = CTFontCreateWithName("SFProDisplay-Bold" as CFString, 100, nil) as CTFont
let f = NSFont.systemFont(ofSize: 100, weight: .bold) as CTFont
let s = NSAttributedString(string: "y.", attributes: [.font: f])
let line = CTLineCreateWithAttributedString(s), runs = CTLineGetGlyphRuns(line) as! [CTRun]
let path = CGMutablePath()
for r in runs { let n = CTRunGetGlyphCount(r); var g = [CGGlyph](repeating: 0, count: n), p = [CGPoint](repeating: .zero, count: n)
  CTRunGetGlyphs(r, CFRange(location: 0, length: n), &g); CTRunGetPositions(r, CFRange(location: 0, length: n), &p)
  let rf = (CTRunGetAttributes(r) as NSDictionary)[kCTFontAttributeName] as! CTFont
  for i in 0..<n { if let gp = CTFontCreatePathForGlyph(rf, g[i], nil) { path.addPath(gp, transform: CGAffineTransform(translationX: p[i].x, y: p[i].y)) } } }
let b = path.boundingBoxOfPath; var box = CGRect(x: 0, y: 0, width: b.width, height: b.height)
let out = CommandLine.arguments[1]
let ctx = CGContext(URL(fileURLWithPath: out) as CFURL, mediaBox: &box, nil)!
ctx.beginPDFPage(nil); ctx.translateBy(x: -b.minX, y: -b.minY); ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.07, alpha: 1)); ctx.fillPath(); ctx.endPDFPage(); ctx.closePDF()
print(b)
