// 레오폴드 FC750R(0x04b4:0x0510)의 키 입력만 골라 키 이름으로 출력
// 사용: keytest [초] [로그파일]   (기본 120초)
import Foundation
import IOKit.hid

let vendorID = 0x04b4, productID = 0x0510
let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 120 : 120
let logPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

var kb: [Int: String] = [:]
for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { kb[0x04 + i] = String(c) }
for (i, c) in "1234567890".enumerated() { kb[0x1E + i] = String(c) }
for i in 1...12 { kb[0x39 + i] = "F\(i)" }
for i in 13...24 { kb[0x68 + i - 13] = "F\(i)" }
let named: [Int: String] = [
  0x28: "Enter", 0x29: "Esc", 0x2A: "Backspace", 0x2B: "Tab", 0x2C: "Space",
  0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\", 0x32: "#(비US)", 0x33: ";",
  0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/", 0x39: "CapsLock",
  0x46: "PrintScreen", 0x47: "ScrollLock", 0x48: "Pause", 0x49: "Insert", 0x4A: "Home",
  0x4B: "PageUp", 0x4C: "Delete", 0x4D: "End", 0x4E: "PageDown", 0x4F: "→", 0x50: "←",
  0x51: "↓", 0x52: "↑", 0x53: "NumLock", 0x54: "KP /", 0x55: "KP *", 0x56: "KP -",
  0x57: "KP +", 0x58: "KP Enter", 0x59: "KP 1", 0x5A: "KP 2", 0x5B: "KP 3", 0x5C: "KP 4",
  0x5D: "KP 5", 0x5E: "KP 6", 0x5F: "KP 7", 0x60: "KP 8", 0x61: "KP 9", 0x62: "KP 0",
  0x63: "KP .", 0x64: "\\(비US)", 0x65: "Menu(Application)", 0x67: "KP =",
  0x87: "International1(ろ)", 0x88: "International2(かな)", 0x89: "International3(¥)",
  0x8A: "International4(変換)", 0x8B: "International5(無変換)",
  0x90: "LANG1(한/영)", 0x91: "LANG2(한자)",
  0xE0: "Left Ctrl", 0xE1: "Left Shift", 0xE2: "Left Alt(Option)", 0xE3: "Left Win(Command)",
  0xE4: "Right Ctrl", 0xE5: "Right Shift", 0xE6: "Right Alt(Option)", 0xE7: "Right Win(Command)",
]
kb.merge(named) { $1 }
let consumer: [Int: String] = [
  0xB5: "다음 곡", 0xB6: "이전 곡", 0xB7: "정지", 0xCD: "재생/일시정지", 0xE2: "음소거",
  0xE9: "볼륨 업", 0xEA: "볼륨 다운", 0x183: "미디어 앱", 0x18A: "메일", 0x192: "계산기",
  0x194: "내 컴퓨터", 0x221: "검색", 0x223: "홈(브라우저)", 0x224: "뒤로", 0x225: "앞으로",
]

let logHandle: FileHandle? = logPath.flatMap {
  FileManager.default.createFile(atPath: $0, contents: nil); return FileHandle(forWritingAtPath: $0)
}
func out(_ s: String) {
  print(s); fflush(stdout)
  logHandle?.write((s + "\n").data(using: .utf8)!)
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
  let el = IOHIDValueGetElement(value)
  let page = Int(IOHIDElementGetUsagePage(el)), usage = Int(IOHIDElementGetUsage(el))
  let v = IOHIDValueGetIntegerValue(value)
  if page == 0x07 {
    guard usage >= 0x04 && usage <= 0xE7 else { return }  // 누를 때만
    out(String(format: "키보드   0x%02X  %@  %@", usage, kb[usage] ?? "(알 수 없음)", v != 0 ? "누름" : "뗌"))
  } else if page == 0x0C {
    guard v != 0 else { return }
    out(String(format: "미디어   0x%03X  %@", usage, consumer[usage] ?? "(알 수 없음)"))
  } else if page == 0x01 && usage >= 0x81 && usage <= 0x83 && v != 0 {
    out(["전원", "잠자기", "깨우기"][usage - 0x81])
  } else if page != 0x07 && page != 0x08 {
    out(String(format: "기타     페이지 0x%04X  용도 0x%04X  값 %ld", page, usage, v))
  }
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if r != kIOReturnSuccess {
  out("열기 실패 (코드 \(r)). 시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링 에서 권한을 허용해 주세요.")
  exit(1)
}
let n = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0
out("준비됨: 장치 \(n)개 인식. \(Int(seconds))초 동안 키를 눌러 보세요.")
CFRunLoopRunInMode(.defaultMode, seconds, false)
out("끝")
