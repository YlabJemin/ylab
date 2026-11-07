import AppKit
// t: n=그대로, b=키보드 저장(어디서나), y=그 맥 설정 따라, g=입력 안 됨
struct K { var w: CGFloat; var main: String; var shift: String; var sub: String; var t: Character }
func c(_ n: String,_ s: String = "") -> K { K(w:1,main:n,shift:s,sub:"",t:"n") }
func m(_ n: String,_ w: CGFloat = 1,_ sub: String = "",_ t: Character = "n") -> K { K(w:w,main:n,shift:"",sub:sub,t:t) }
let rows: [[K]] = [
 [m("Esc"), c("1","!"), c("2","@"), c("3","#"), c("4","$"), c("5","%"), c("6","^"), c("7","&"), c("8","*"), c("9","("), c("0",")"), c("-","_"), c("=","+"), m("¥ 자리",1,"입력 안 됨","g"), m("BS")],
 [m("Tab",1.5)] + "QWERTYUIOP".map{c(String($0))} + [c("[","{"), c("]","}"), m("Enter",1.5)],
 [m("Caps",1.75,"한/영 여부는\n그 맥 설정","y")] + "ASDFGHJKL".map{c(String($0))} + [c(";",":"), c("'","\""), c("\\","|"), m("Enter",1.25)],
 [m("Shift",2)] + "ZXCVBNM".map{c(String($0))} + [c(",","<"), c(".",">"), c("/","?"), m("ろ 자리",1,"입력 안 됨","g"), m("↑"), m("Shift")],
 [m("Fn"), m("Ctrl",1,"半/全 자리","b"), m("⌥ Opt",1,"◇ 자리","b"), m("⌘ Cmd",1,"Alt 자리","b"), m("英数",1,"無変換 자리","y"), m("",3), m("英数",1,"変換 자리","y"), m("⌥ Opt",1,"かな 자리","b"), m("⌘ Cmd",1,"Alt 자리","b"), m("Fn"), m("←"), m("↓"), m("→")],
]
let U: CGFloat = 92, gap: CGFloat = 8, pad: CGFloat = 50, top: CGFloat = 150, footH: CGFloat = 330
let W = pad*2 + U*15, H = top + U*5 + footH
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
NSColor(calibratedRed:0.96,green:0.96,blue:0.95,alpha:1).setFill(); NSRect(x:0,y:0,width:W,height:H).fill()
func txt(_ s: String,_ x: CGFloat,_ y: CGFloat,_ size: CGFloat,_ col: NSColor,_ bold: Bool = false,_ center: Bool = false,_ w: CGFloat = 0) {
  let f = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
  let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: col])
  str.draw(at: NSPoint(x: center ? x + (w - str.size().width)/2 : x, y: y))
}
let ink = NSColor(calibratedWhite:0.12,alpha:1), gray = NSColor(calibratedWhite:0.5,alpha:1)
let pal: [Character:(NSColor,NSColor,NSColor)] = [ // 배경, 테두리, 보조글자
 "b": (NSColor(calibratedRed:0.86,green:0.92,blue:1,alpha:1), NSColor(calibratedRed:0.2,green:0.45,blue:0.85,alpha:1), NSColor(calibratedRed:0.15,green:0.35,blue:0.7,alpha:1)),
 "y": (NSColor(calibratedRed:1,green:0.96,blue:0.75,alpha:1), NSColor(calibratedRed:0.8,green:0.6,blue:0.1,alpha:1), NSColor(calibratedRed:0.55,green:0.4,blue:0.05,alpha:1)),
 "g": (NSColor(calibratedRed:0.86,green:0.86,blue:0.88,alpha:1), NSColor(calibratedRed:0.75,green:0.15,blue:0.15,alpha:1), NSColor(calibratedRed:0.75,green:0.15,blue:0.15,alpha:1)),
]
txt("다른 맥에 연결하면 (Karabiner 없음 · 키보드 종류 '영어 배열' 선택)", pad, 34, 34, ink, true)
txt("영어 배열 키캡 기준 · 키보드 자체에 저장된 키맵은 어느 기기에서나 같음", pad, 88, 20, gray)
for (ri,row) in rows.enumerated() {
  var x = pad
  for k in row {
    let r = NSRect(x: x+gap/2, y: top + CGFloat(ri)*U + gap/2, width: k.w*U-gap, height: U-gap)
    let p = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
    let isMod = k.shift.isEmpty && (k.main.count != 1 || "←↓→↑".contains(k.main))
    if let (bg, st, _) = pal[k.t] { bg.setFill(); p.fill(); st.setStroke(); p.lineWidth = 2.5; if k.t == "y" { p.setLineDash([6,4], count: 2, phase: 0) }; p.stroke() }
    else { (isMod ? NSColor(calibratedWhite:0.84,alpha:1) : NSColor.white).setFill(); p.fill(); NSColor(calibratedWhite:0.75,alpha:1).setStroke(); p.lineWidth = 1.5; p.stroke() }
    if !isMod {
      txt(k.main, r.minX+12, r.maxY-44, 28, ink, true)
      if !k.shift.isEmpty { txt(k.shift, r.minX+12, r.minY+6, 24, ink, true) }
    } else {
      let lines = k.sub.isEmpty ? [] : k.sub.split(separator: "\n").map(String.init)
      let subCol = pal[k.t]?.2 ?? gray
      let top0 = r.midY - (lines.isEmpty ? 13 : 13 + CGFloat(lines.count)*10)
      txt(k.main, r.minX, top0, k.t == "g" ? 16 : 20, k.t == "g" ? gray : ink, true, true, r.width)
      for (i,l) in lines.enumerated() { txt(l, r.minX, top0 + 28 + CGFloat(i)*19, 14, subCol, k.t == "g", true, r.width) }
    }
    x += k.w*U
  }
}
var ly = top + U*5 + 26
func swatch(_ x: CGFloat,_ t: Character?,_ s: String) {
  let r = NSRect(x:x,y:ly,width:34,height:34); let p = NSBezierPath(roundedRect:r,xRadius:6,yRadius:6)
  if let t = t, let (bg,st,_) = pal[t] { bg.setFill(); p.fill(); st.setStroke(); p.lineWidth = 2; if t == "y" { p.setLineDash([5,3], count: 2, phase: 0) }; p.stroke() }
  else { NSColor.white.setFill(); p.fill(); NSColor(calibratedWhite:0.75,alpha:1).setStroke(); p.lineWidth=2; p.stroke() }
  txt(s, x+46, ly+4, 21, ink)
}
swatch(pad, "b", "키보드에 저장 · 어디서나 같음")
swatch(pad+400, "y", "그 맥 설정에 따라 다름")
swatch(pad+730, "g", "입력 안 됨")
swatch(pad+930, nil, "키캡 그대로 입력")
ly += 64
txt("이 맥(Karabiner)에서만 되는 것 — 다른 맥에선 안 됨", pad, ly, 22, ink, true)
let notes = [
 "• 英数 누른 채 숫자 → 1·2 밝기(맥북+스튜디오 디스플레이 함께) · 3 미션 컨트롤 · 4 런치패드 · 7·8·9 이전/재생/다음 · 0 음소거 · -/= 음량",
 "• ¥ 자리(백스페이스 왼쪽) → · / Shift면 ~",
 "• 英数 키: 다른 맥에선 글자 없음 (그 맥에서 영문 입력으로 바뀔 수는 있음) · Caps: 그 맥에 'Caps Lock으로 한/영 전환'이 켜져 있으면 한/영",
 "• Fn 누른 채 쓰는 키(F1~F12, 방향키 Home/End/PgUp/PgDn 등)는 키보드 기본값이라 어디서나 같음",
]
for (i,n) in notes.enumerated() { txt(n, pad, ly + 38 + CGFloat(i)*34, 19, NSColor(calibratedWhite:0.3,alpha:1)) }
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
