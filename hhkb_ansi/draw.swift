import AppKit
// (라벨, 너비, JIS 기본, JIS 시프트, ANSI 기본, ANSI 시프트, 종류) 종류: c=글자키, m=특수키
struct K { var w: CGFloat; var jn: String; var js: String; var an: String; var as_: String; var mod: Bool }
func c(_ jn: String,_ js: String,_ an: String,_ a: String,_ w: CGFloat = 1) -> K { K(w:w,jn:jn,js:js,an:an,as_:a,mod:false) }
func m(_ t: String,_ w: CGFloat = 1, _ sub: String = "") -> K { K(w:w,jn:t,js:sub,an:t,as_:sub,mod:true) }
func L(_ s: String) -> K { c(s,"",s,"") }
let rows: [[K]] = [
 [m("Esc"), c("1","!","1","!"), c("2","\"","2","@"), c("3","#","3","#"), c("4","$","4","$"), c("5","%","5","%"), c("6","&","6","^"), c("7","'","7","&"), c("8","(","8","*"), c("9",")","9","("), c("0","","0",")"), c("-","=","-","_"), c("^","~","=","+"), c("¥","|","✕","✕"), m("BS")],
 [m("Tab",1.5)] + "QWERTYUIOP".map{L(String($0))} + [c("@","`","[","{"), c("[","{","]","}"), m("Enter",1.5)],
 [m("한/영",1.75,"Caps")] + "ASDFGHJKL".map{L(String($0))} + [c(";","+",";",":"), c(":","*","'","\""), c("]","}","\\","|"), m("",1.25)],
 [m("Shift",2)] + "ZXCVBNM".map{L(String($0))} + [c(",","<",",","<"), c(".",">",".",">"), c("/","?","/","?"), c("_","ろ","✕","✕"), m("↑"), m("Shift")],
 [m("Fn"), m("Ctrl"), m("Opt"), m("⌘"), m("英数"), m("",3), m("英数"), m("Opt"), m("⌘"), m("Fn"), m("←"), m("↓"), m("→")],
]
let U: CGFloat = 92, gap: CGFloat = 8, pad: CGFloat = 50, top: CGFloat = 150, legendH: CGFloat = 170
let W = pad*2 + U*15, H = top + U*5 + legendH + pad
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
NSColor(calibratedRed:0.96,green:0.96,blue:0.95,alpha:1).setFill(); NSRect(x:0,y:0,width:W,height:H).fill()
func txt(_ s: String,_ x: CGFloat,_ y: CGFloat,_ size: CGFloat,_ col: NSColor,_ bold: Bool = false,_ center: Bool = false,_ w: CGFloat = 0) {
  let f = bold ? NSFont.systemFont(ofSize: size, weight: .bold) : NSFont.systemFont(ofSize: size, weight: .regular)
  let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: col]
  let str = NSAttributedString(string: s, attributes: a)
  let sz = str.size()
  str.draw(at: NSPoint(x: center ? x + (w - sz.width)/2 : x, y: y))
}
let ink = NSColor(calibratedWhite:0.12,alpha:1), gray = NSColor(calibratedWhite:0.55,alpha:1)
let hot = NSColor(calibratedRed:0.86,green:0.33,blue:0.12,alpha:1), hotBg = NSColor(calibratedRed:1,green:0.90,blue:0.82,alpha:1)
let xBg = NSColor(calibratedRed:0.86,green:0.86,blue:0.88,alpha:1), red = NSColor(calibratedRed:0.75,green:0.15,blue:0.15,alpha:1)
txt("HHKB Type-S 일본어 배열 → 맥에서 '영어 배열(ANSI)'로 설정하면", pad, 34, 34, ink, true)
txt("ABC(영문) 입력 기준 · 회색 작은 글자 = 키캡에 인쇄된 글자 · 굵은 글자 = 실제로 입력되는 글자 (위: Shift / 아래: 그냥)", pad, 88, 20, gray)
var changed = 0
for (ri,row) in rows.enumerated() {
  var x = pad
  for k in row {
    let r = NSRect(x: x+gap/2, y: top + CGFloat(ri)*U + gap/2, width: k.w*U-gap, height: U-gap)
    let diff = !k.mod && (k.jn != k.an || k.js != k.as_)
    let dead = k.an == "✕"
    if diff { changed += 1 }
    (dead ? xBg : diff ? hotBg : k.mod ? NSColor(calibratedWhite:0.84,alpha:1) : NSColor.white).setFill()
    let p = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10); p.fill()
    (diff ? hot : NSColor(calibratedWhite:0.75,alpha:1)).setStroke(); p.lineWidth = diff ? 3 : 1.5; p.stroke()
    if k.mod {
      txt(k.jn, r.minX, r.midY - (k.js.isEmpty ? 13 : 24), 20, ink, true, true, r.width)
      if !k.js.isEmpty { txt(k.js, r.minX, r.midY + 2, 15, gray, false, true, r.width) }
    } else if !diff {
      txt(k.jn, r.minX+12, r.maxY-44, 28, ink, true)
      if !k.js.isEmpty { txt(k.js, r.minX+12, r.minY+6, 24, ink, true) }
    } else if dead {
      txt(k.js+" "+k.jn, r.minX+8, r.minY+6, 15, gray)
      txt("입력", r.minX, r.midY-14, 17, red, true, true, r.width)
      txt("안 됨", r.minX, r.midY+6, 17, red, true, true, r.width)
    } else {
      txt(k.js, r.maxX-26, r.minY+5, 15, gray); txt(k.jn, r.maxX-26, r.maxY-26, 15, gray)
      txt(k.as_, r.minX+10, r.minY+4, 26, hot, true); txt(k.an, r.minX+10, r.maxY-40, 26, hot, true)
    }
    x += k.w*U
  }
}
let ly = top + U*5 + 30
func swatch(_ x: CGFloat,_ bg: NSColor,_ st: NSColor,_ t: String) { let r = NSRect(x:x,y:ly,width:34,height:34); bg.setFill(); let p = NSBezierPath(roundedRect:r,xRadius:6,yRadius:6); p.fill(); st.setStroke(); p.lineWidth=2; p.stroke(); txt(t, x+46, ly+4, 21, ink) }
swatch(pad, hotBg, hot, "키캡과 다르게 입력되는 키")
swatch(pad+380, xBg, NSColor(calibratedWhite:0.75,alpha:1), "아무것도 입력 안 되는 키 (¥ · ろ)")
swatch(pad+800, NSColor.white, NSColor(calibratedWhite:0.75,alpha:1), "그대로인 키 (알파벳 · 숫자 · , . / 등)")
txt("※ 기호는 미국 키보드 위치대로 바뀜 (예: Shift+2 = @, @키 = [, :키 = ').  아랫줄·한/영 등 키맵 툴로 바꾼 키는 그대로.", pad, ly+62, 20, gray)
txt("※ 한글 입력(2벌식)일 때 글자는 같고, 기호만 위와 같이 바뀜.", pad, ly+96, 20, gray)
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("바뀌는 키", changed)
