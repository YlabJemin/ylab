// typechar: 글자를 지금 입력 중인 곳에 바로 보냄 (Karabiner에서 호출)
// 사용: typechar "·" [키코드, 기본 0]
import Foundation
import CoreGraphics
let args = CommandLine.arguments
guard args.count >= 2 else { print("사용: typechar 글자 [키코드]"); exit(1) }
let text = Array(args[1].utf16)
let keycode = CGKeyCode(args.count >= 3 ? Int(args[2]) ?? 0 : 0)
let src = CGEventSource(stateID: .privateState)
for down in [true, false] {
  guard let e = CGEvent(keyboardEventSource: src, virtualKey: keycode, keyDown: down) else { exit(2) }
  e.flags = []
  e.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
  e.post(tap: .cgSessionEventTap)
  usleep(8_000)
}
usleep(30_000) // 바로 끝나면 맥이 받기 전에 사라짐
