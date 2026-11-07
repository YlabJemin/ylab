// 시험용: 스크롤 이벤트를 보기만 하고(바꾸지 않음) 보낸 프로세스를 기록
import Cocoa
func procName(_ pid: Int32) -> String {
  var buf = [CChar](repeating: 0, count: 4096)
  return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "?"
}
var last = ""
let cb: CGEventTapCallBack = { _, type, ev, _ in
  if type == .scrollWheel {
    let pid = Int32(ev.getIntegerValueField(.eventSourceUnixProcessID))
    let cont = ev.getIntegerValueField(.scrollWheelEventIsContinuous)
    let d1 = ev.getIntegerValueField(.scrollWheelEventDeltaAxis1), d2 = ev.getIntegerValueField(.scrollWheelEventDeltaAxis2), f2 = ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), p2 = ev.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    let s = "pid=\(pid) \(procName(pid).split(separator: "/").last ?? "") 연속=\(cont) 세로=\(d1) 가로=\(d2) 가로fp=\(f2) 가로pt=\(p2)"
    if s != last { print(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium), s); fflush(stdout); last = s }
  }
  return Unmanaged.passUnretained(ev)
}
guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
  eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue, callback: cb, userInfo: nil) else { print("tap 실패(권한)"); exit(1) }
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
CGEvent.tapEnable(tap: t, enable: true)
print("시작"); fflush(stdout)
CFRunLoopRunInMode(.defaultMode, Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60, false)
print("끝")
