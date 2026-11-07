// Donut 끌기 자동 시험. 시험 폴더의 파인더 창 src·dst만 씀: droptest <시험 폴더> <캡처 폴더>
import AppKit
import ApplicationServices

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let shots = CommandLine.arguments[2]
var shiftOn = false
var shotN = 0

let hid = CGEventSource(stateID: .hidSystemState)   // 하드웨어 상태까지 바꿔야 끄는 중에도 쉬프트 떼기가 반영됨
func post(_ t: CGEventType, _ p: CGPoint) {
    let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!
    if shiftOn { e.flags = .maskShift }
    e.post(tap: .cghidEventTap)
}
func key(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags = []) {
    let e = CGEvent(keyboardEventSource: hid, virtualKey: code, keyDown: down)!
    e.flags = flags
    e.post(tap: .cghidEventTap)
}
func shift(_ on: Bool) {
    shiftOn = on
    let e = CGEvent(keyboardEventSource: hid, virtualKey: 56, keyDown: on)!
    e.flags = on ? .maskShift : []
    e.post(tap: .cghidEventTap)
    // 끄는 중에는 가짜 쉬프트 떼기만으로 상태가 안 풀려 아무 동작 없는 F20을 함께 보냄
    if !on { usleep(20000); key(90, true); usleep(20000); key(90, false) }
}
func waitFor(_ s: Double) { usleep(useconds_t(s * 1_000_000)) }
func dragTo(_ from: CGPoint, _ to: CGPoint, steps: Int = 25) {
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        usleep(12000)
    }
}
func jiggle(_ p: CGPoint, _ seconds: Double) {
    let n = Int(seconds / 0.05)
    for i in 0..<max(1, n) {
        post(.leftMouseDragged, CGPoint(x: p.x + Double(i % 2), y: p.y))
        usleep(50000)
    }
}
func shot(_ name: String, _ c: CGPoint) {
    shotN += 1
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-R", "\(Int(c.x) - 190),\(Int(c.y) - 190),380,380", String(format: "%@/%02d_%@.png", shots, shotN, name)]
    try? p.run(); p.waitUntilExit()
}
func script(_ s: String) -> String {
    var error: NSDictionary?
    let r = NSAppleScript(source: s)?.executeAndReturnError(&error)
    if let error { print("스크립트 오류:", error) }
    return r?.stringValue ?? ""
}
func donutWindows() -> [CGRect] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard (w[kCGWindowOwnerName as String] as? String) == "Donut",
              let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) else { return nil }
        return r
    }
}
func listing() -> [String] {
    let fm = FileManager.default
    let e = fm.enumerator(at: root, includingPropertiesForKeys: nil)
    var out: [String] = []
    while let u = e?.nextObject() as? URL {
        var d: ObjCBool = false
        fm.fileExists(atPath: u.path, isDirectory: &d)
        if !d.boolValue, !u.lastPathComponent.hasPrefix(".") {
            out.append(u.path.replacingOccurrences(of: root.path + "/", with: ""))
        }
    }
    return out.sorted()
}

func ax(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}
func findItem(_ el: AXUIElement, _ name: String, _ depth: Int = 0) -> AXUIElement? {
    for k in ["AXTitle", "AXFilename", "AXDescription", "AXValue"] {
        if (ax(el, k) as? String) == name, ax(el, "AXRole") as? String != "AXWindow" { return el }
    }
    guard depth < 9, let kids = ax(el, "AXChildren") as? [AXUIElement] else { return nil }
    for k in kids { if let f = findItem(k, name, depth + 1) { return f } }
    return nil
}
func itemCenter(_ window: String, _ name: String) -> CGPoint? {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
    let app = AXUIElementCreateApplication(finder.processIdentifier)
    guard let wins = ax(app, "AXWindows") as? [AXUIElement],
          let w = wins.first(where: { (ax($0, "AXTitle") as? String) == window }),
          let item = findItem(w, name), let pv = ax(item, "AXPosition"), let sv = ax(item, "AXSize") else { return nil }
    var pos = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sv as! AXValue, .cgSize, &size)
    return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
}

let started = Date()
func stamp(_ m: String) { print(String(format: "%.2f초 %@", Date().timeIntervalSince(started), m)); fflush(stdout) }

enum End { case drop, shiftUpEsc, shiftUpDrop }
var results: [String] = []
var aborted = false

func scenario(_ name: String, file: String, at p: CGPoint, offset: CGPoint, end: End, expect: String) {
    guard !aborted else { return }
    if ProcessInfo.processInfo.environment["TAIL"] != nil, name != "데스크톱자리" { return }
    if ProcessInfo.processInfo.environment["DUP"] != nil { return }
    waitFor(1.2)   // 앞 시험의 파일 이동을 파인더가 끝낼 때까지 기다림
    guard let src = itemCenter("src", file) else { results.append("× \(name): 원본 아이콘을 못 찾음"); return }
    let before = listing()
    script("tell application \"Finder\" to activate")
    waitFor(0.3)
    post(.mouseMoved, src); waitFor(0.2)
    post(.leftMouseDown, src); waitFor(0.15)
    // 첫 움직임이 크게 튀면 파인더가 끌기를 시작하지 않으므로 사람 손처럼 천천히 집음
    let lift = CGPoint(x: src.x + 24, y: src.y + 24)
    dragTo(src, lift, steps: 12)
    jiggle(lift, 0.15)
    dragTo(lift, p, steps: 40)
    jiggle(p, 0.3)
    shift(true)
    jiggle(p, 0.08); shot("\(name)_0.08s", p)
    jiggle(p, 0.7)
    let open = donutWindows().contains { $0.height > 300 }
    shot("\(name)_펼침", p)
    if !open {
        results.append("× \(name): 도넛이 안 뜸 → 중단")
        shift(false); key(53, true); key(53, false); waitFor(0.2); post(.leftMouseUp, p)
        aborted = true
        return
    }
    let q = CGPoint(x: p.x + offset.x, y: p.y + offset.y)
    dragTo(p, q, steps: 12)
    jiggle(q, 0.3)
    shot("\(name)_위치", p)
    switch end {
    case .drop:
        stamp("놓음 \(name)"); post(.leftMouseUp, q); waitFor(0.05); shift(false)
    case .shiftUpEsc:
        shift(false); jiggle(q, 0.5); shot("\(name)_뗌", p)
        key(53, true); key(53, false); waitFor(0.2); post(.leftMouseUp, q)
    case .shiftUpDrop:
        shift(false); jiggle(q, 0.5)
        post(.leftMouseUp, q)
    }
    waitFor(2.5)
    let after = listing()
    let added = after.filter { !before.contains($0) }, gone = before.filter { !after.contains($0) }
    let got = "추가\(added) 없어짐\(gone)"
    results.append((got == expect ? "○ " : "× ") + "\(name): \(got)" + (got == expect ? "" : " / 예상 \(expect)"))
}

let screen = NSScreen.screens[0].frame
print("화면:", screen.size)
results.append("원래 목록: \(listing())")
guard let inner = itemCenter("dst", "inner") else { print("inner를 못 찾음"); exit(1) }
let blank = CGPoint(x: 1240, y: 580)   // dst 창 {640, 80, 1840, 780}의 아이콘 없는 아래쪽

scenario("창_JPG오른쪽", file: "sample1.jpg", at: blank, offset: CGPoint(x: 105, y: 0), end: .drop, expect: "추가[\"dst/sample1.jpg\"] 없어짐[]")
if ProcessInfo.processInfo.environment["ONE"] != nil { print(results.joined(separator: "\n")); exit(0) }
scenario("창_PNG위", file: "sample1.jpg", at: blank, offset: CGPoint(x: 0, y: -105), end: .drop, expect: "추가[\"dst/sample1.png\"] 없어짐[]")
scenario("창_20MB아래_이미미만", file: "sample1.jpg", at: blank, offset: CGPoint(x: 0, y: 105), end: .drop, expect: "추가[\"dst/sample1_under20mb.jpg\"] 없어짐[]")
scenario("창_Web왼쪽", file: "sample1.jpg", at: blank, offset: CGPoint(x: -105, y: 0), end: .drop, expect: "추가[\"dst/sample1_web.jpg\"] 없어짐[]")
scenario("폴더아이콘", file: "sample1.jpg", at: inner, offset: CGPoint(x: 105, y: 0), end: .drop, expect: "추가[\"dst/inner/sample1.jpg\"] 없어짐[]")
scenario("쉬프트뗌_Esc", file: "move3.jpg", at: blank, offset: CGPoint(x: 105, y: 0), end: .shiftUpEsc, expect: "추가[] 없어짐[]")
scenario("가운데놓기", file: "sample1.jpg", at: blank, offset: CGPoint(x: 0, y: 0), end: .drop, expect: "추가[] 없어짐[]")
scenario("가운데테두리_r53", file: "sample1.jpg", at: blank, offset: CGPoint(x: 53, y: 0), end: .drop, expect: "추가[] 없어짐[]")
scenario("칸사이틈_45도", file: "sample1.jpg", at: blank, offset: CGPoint(x: 75, y: -73), end: .drop, expect: "추가[\"dst/sample1 2.jpg\"] 없어짐[]")
scenario("쉬프트뗀뒤놓기_평소끌기", file: "move1.jpg", at: blank, offset: CGPoint(x: 105, y: 0), end: .shiftUpDrop, expect: "추가[\"dst/move1.jpg\"] 없어짐[\"src/move1.jpg\"]")
scenario("바깥놓기_평소끌기", file: "move2.jpg", at: blank, offset: CGPoint(x: 0, y: -175), end: .drop, expect: "추가[\"dst/move2.jpg\"] 없어짐[\"src/move2.jpg\"]")

// 이름이 겹치는 두 장: 파인더에 창이 새로 뜨는지 확인
func extraWindows() -> [String] {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return [] }
    let wins = ax(AXUIElementCreateApplication(finder.processIdentifier), "AXWindows") as? [AXUIElement] ?? []
    return wins.compactMap { w in
        let title = ax(w, "AXTitle") as? String ?? ""
        return title == "src" || title == "dst" || (ax(w, "AXSubrole") as? String) == "AXDesktop" ? nil : "[\(title)] \(ax(w, "AXSubrole") as? String ?? "")"
    }
}
func dropTwo(_ name: String, from window: String, offset: CGPoint) {
    waitFor(1.2)
    raiseWindow(window)
    let dir = window
    script("tell application \"Finder\" to select {\(alias("\(dir)/sample1.jpg")), \(alias("\(dir)/sample2.jpg"))}")
    waitFor(0.5)
    print("\(name) 선택 수:", script("tell application \"Finder\" to get count of (get selection)")); fflush(stdout)
    guard let c = itemCenter(window, "sample1.jpg") else { print("\(name) 아이콘 못 찾음"); return }
    let before = listing()
    post(.mouseMoved, c); waitFor(0.2); post(.leftMouseDown, c); waitFor(0.15)
    let lift = CGPoint(x: c.x + 24, y: c.y + 24)
    dragTo(c, lift, steps: 12); jiggle(lift, 0.15)
    dragTo(lift, blank, steps: 40); jiggle(blank, 0.3)
    shift(true); jiggle(blank, 0.7)
    let open = donutWindows().contains { $0.height > 300 }
    let q = CGPoint(x: blank.x + offset.x, y: blank.y + offset.y)
    dragTo(blank, q, steps: 12); jiggle(q, 0.3)
    post(.leftMouseUp, q); waitFor(0.05); shift(false); waitFor(3)
    let added = listing().filter { !before.contains($0) }, gone = before.filter { !listing().contains($0) }
    let extra = extraWindows()
    print("\(name): 도넛=\(open) 추가\(added) 없어짐\(gone) 새 창\(extra)"); fflush(stdout)
    if !extra.isEmpty {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "\(shots)/대치창_\(name).png"]
        try? p.run(); p.waitUntilExit()
        print("대치 창 있음 → 여기서 멈춤"); exit(0)
    }
}
if ProcessInfo.processInfo.environment["DUP"] != nil {
    let right = CGPoint(x: 105, y: 0), web = CGPoint(x: -105, y: 0), top = CGPoint(x: 0, y: -105), bottom = CGPoint(x: 0, y: 105)
    dropTwo("src에서_JPG_1회", from: "src", offset: right)
    dropTwo("src에서_JPG_2회", from: "src", offset: right)
    dropTwo("src에서_Web_1회", from: "src", offset: web)
    dropTwo("src에서_Web_2회", from: "src", offset: web)
    dropTwo("src에서_Under_1회", from: "src", offset: bottom)
    dropTwo("src에서_PNG_1회", from: "src", offset: top)
    dropTwo("dst안에서_JPG", from: "dst", offset: right)
    print("마지막 목록:", listing())
    exit(0)
}

// 데스크톱: 창이 없는 자리를 찾아서 시험 (앱이 실제 데스크톱 대신 시험 폴더에 저장)
let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let rects = wins.compactMap { w -> CGRect? in
    guard ((w[kCGWindowLayer as String] as? Int) ?? 0) >= 0, let d = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: d)
}
var deskPoint: CGPoint?
outer: for sc in NSScreen.screens {
    let f = CGRect(x: sc.frame.minX, y: screen.maxY - sc.frame.maxY, width: sc.frame.width, height: sc.frame.height)
    for y in stride(from: f.minY + 200, to: f.maxY - 200, by: 60) {
        for x in stride(from: f.minX + 200, to: f.maxX - 200, by: 60) where !rects.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) {
            deskPoint = CGPoint(x: x, y: y); break outer
        }
    }
}
if let deskPoint {
    scenario("데스크톱자리", file: "sample1.jpg", at: deskPoint, offset: CGPoint(x: -105, y: 0), end: .drop, expect: "추가[\"desk/sample1_web.jpg\"] 없어짐[]")
} else {
    results.append("– 데스크톱자리: 창에 가려 빈 곳이 없어 시험 못 함")
}

func alias(_ rel: String) -> String { "POSIX file \"\(root.path)/\(rel)\" as alias" }
func raiseWindow(_ name: String) {
    script("tell application \"Finder\"\nactivate\nset index of (first window whose name is \"\(name)\") to 1\nend tell")
    waitFor(0.4)
}

if shiftOn { shift(false) }
print(results.joined(separator: "\n"))
print("마지막 목록:", listing())
