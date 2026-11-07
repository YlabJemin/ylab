// 키 재지정이 적용된 "뒤"에 맥이 실제로 받는 입력을 출력 (모든 키보드)
// 사용: eventtest [초] [로그파일]   (기본 120초)
import Cocoa

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 120 : 120
let logPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
let logHandle: FileHandle? = logPath.flatMap {
  FileManager.default.createFile(atPath: $0, contents: nil); return FileHandle(forWritingAtPath: $0)
}
func out(_ s: String) {
  print(s); fflush(stdout)
  logHandle?.write((s + "\n").data(using: .utf8)!)
}

func flagText(_ f: CGEventFlags) -> String {
  var s: [String] = []
  if f.contains(.maskSecondaryFn) { s.append("fn") }
  if f.contains(.maskControl) { s.append("⌃") }
  if f.contains(.maskAlternate) { s.append("⌥") }
  if f.contains(.maskShift) { s.append("⇧") }
  if f.contains(.maskCommand) { s.append("⌘") }
  return s.joined(separator: " ")
}
let fkeys: [Int64: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
  98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 110: "Menu(PC)", 63: "fn",
  55: "⌘ 왼쪽", 54: "⌘ 오른쪽", 58: "⌥ 왼쪽", 61: "⌥ 오른쪽", 59: "⌃ 왼쪽", 62: "⌃ 오른쪽", 179: "fn(🌐)"]
let media: [Int: String] = [0: "볼륨+", 1: "볼륨−", 2: "밝기+", 3: "밝기−", 7: "음소거",
  16: "재생", 17: "다음 곡", 18: "이전 곡", 19: "빨리감기", 20: "되감기"]

let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
  eventsOfInterest: mask, callback: { _, type, ev, _ in
    if type == .keyDown || type == .flagsChanged {
      let code = ev.getIntegerValueField(.keyboardEventKeycode)
      let kind = type == .keyDown ? "키 누름" : "보조키  "
      out("\(kind)  코드 \(code)  \(fkeys[code] ?? "")  [\(flagText(ev.flags))]")
    } else if type.rawValue == 14, let ns = NSEvent(cgEvent: ev), ns.subtype.rawValue == 8 {
      let key = (ns.data1 & 0xFFFF0000) >> 16, down = ((ns.data1 & 0xFF00) >> 8) == 0x0A
      if down { out("미디어    \(media[key] ?? "기타(\(key))")") }
    }
    return Unmanaged.passUnretained(ev)
  }, userInfo: nil) else {
  out("시작 실패. 시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링 에서 권한을 허용해 주세요.")
  exit(1)
}
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
out("준비됨. \(Int(seconds))초 동안 키를 눌러 보세요.")
CFRunLoopRunInMode(.defaultMode, seconds, false)
out("끝")
