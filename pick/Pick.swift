// Pick — 셀렉 앱 (화면은 ui/index.html, 이 파일은 캡쳐원·파일·미리보기 담당)
// 두 가지 방식
//   캡쳐원 연결: 캡쳐원 스크립트 메뉴 "Pick"으로 켜면 지금 문서 사진(2장 이상 골랐으면 그 사진들, 아니면 전체)
//     · 별점은 바꾸면 바로 캡쳐원 세션에 씀 (⌘Z 되돌리기도 같은 길)
//     · 미리보기: 캡쳐원 썸네일 캐시(보정 반영) → 레시피 cc-cull-preview(긴 변 1600)로 뽑은 JPG로 교체
//     · 스타일: 왼쪽 패널에서 누르면 고른 사진에 적용 → 조정값·미리보기 다시
//     · 꺼내기 보정본: 레시피 pick-export(JPEG 100, sRGB, 원본 크기)로 임시 폴더에 뽑고 다 써지면 데스크톱으로 옮김
//   폴더: 창이나 Dock 아이콘에 폴더를 끌어 놓으면 그 폴더 사진 (캡쳐원 없이 셀렉만)
//     · 별점은 앱 안에만 저장 (~/Library/Application Support/Pick/ratings.json, 파일 이름+촬영 시각으로 연결). 폴더 파일은 안 건드림
// 꺼내기(⌘C·⌘V·창 밖으로 끌기)는 데스크톱에 복사, ⌘Z면 복사한 파일을 휴지통으로
// 미리보기·임시 JPG는 ~/Library/Caches/Pick/ 에만 두고, 그 안의 .jpg만 지움
// 시험: Pick --fake <폴더> (폴더 방식, 별점 저장소·꺼내기 위치는 환경변수 PICK_STORE·PICK_DEST로 바꿀 수 있음)
//       Pick --dump (캡쳐원에서 읽기만 하고 요약 출력)
// 빌드: ./build.sh
import Cocoa
import WebKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

// MARK: - 사진
struct Item {
    var n: String          // 화면 번호 (촬영 순서 1…N)
    var id: String         // 캡쳐원 변형 id (폴더 방식은 파일 경로)
    let name: String       // 확장자 뺀 이름
    let ext: String        // ".CR3" 등
    let path: String       // 원본 파일
    var r: Int
    var t: Int
    var gone0 = false     // 캡쳐원에서 사라진 상태(화면엔 숨김)
    var adj: [String: Double] = [:]
    var iso: String = ""
}

let home = FileManager.default.homeDirectoryForCurrentUser.path
let env = ProcessInfo.processInfo.environment
let cacheRoot = home + "/Library/Caches/Pick"
let storePath = env["PICK_STORE"] ?? home + "/Library/Application Support/Pick/ratings.json"
let destDir = env["PICK_DEST"] ?? home + "/Desktop"
let photoExts: Set<String> = ["cr3", "cr2", "nef", "arw", "raf", "dng", "orf", "rw2", "jpg", "jpeg", "png", "tif", "tiff", "heic", "psd"]   // psd: 브릿지처럼 포토샵 파일도 (2026-11-03)

// MARK: - 캡쳐원 (osascript, 꺼져 있으면 절대 보내지 않음)
enum C1 {
    // 캡쳐원은 맥마다 버전·앱 이름이 다름(Capture One 23, Pro, 번들 ID captureone15/16 …) → 켜진 캡쳐원을 찾아 그 번들 ID로 명령을 보냄 (2026-11-05, 다른 맥에서 연동 안 됨)
    static var bundle = "com.captureone.captureone16"
    static func isC1(_ a: NSRunningApplication) -> Bool {
        let b = a.bundleIdentifier ?? ""
        return a.activationPolicy == .regular && (b.hasPrefix("com.captureone.") || b.hasPrefix("com.phaseone.captureone"))
    }
    // 스크립트 안의 application "Capture One"(따옴표가 이스케이프된 것 포함)을 application id "번들 ID"로
    static func target(_ s: String) -> String {
        s.replacingOccurrences(of: "application \"Capture One\"", with: "application id \"\(bundle)\"")
         .replacingOccurrences(of: "application \\\"Capture One\\\"", with: "application id \\\"\(bundle)\\\"")
    }
    static let q = DispatchQueue(label: "pick.c1")
    // 켜져 있는지: 앱 목록은 주 스레드에서만 믿을 수 있어서 프로세스 번호를 기억해 두고 백그라운드에선 그 번호로 확인
    static var pid: pid_t = 0
    static func refreshPid() {
        if let a = NSWorkspace.shared.runningApplications.first(where: isC1), let b = a.bundleIdentifier {
            if b != bundle { pickLog("캡쳐원 찾음: \(b) (\(a.localizedName ?? ""))"); quickCache = [:]; quickOrder = [] }   // 컴파일해 둔 명령은 옛 번들 ID로 묶여 있음
            bundle = b; pid = a.processIdentifier
        } else { pid = 0 }
    }
    static var running: Bool {
        if Thread.isMainThread { refreshPid() }
        else if pid == 0 { DispatchQueue.main.sync { refreshPid() } }
        return pid > 0 && kill(pid, 0) == 0
    }
    // 앱 안에서 바로 실행하는 짧은 애플스크립트 (osascript 띄우는 100ms 남짓이 없음). 메인 스레드에서 돎
    static func quickSelection() -> Set<String>? {
        guard let t = quick("tell application \"Capture One\"\nset AppleScript's text item delimiters to linefeed\nreturn (id of (variants of my curDoc() whose selected is true)) as text\nend tell") else { return nil }
        return Set(t.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }
    static let prefix = "on curDoc()\ntell application \"Capture One\"\nset d to missing value\ntry\nset d to current document\nend try\ntry\nget name of d\non error\nset d to document 1\nend try\nreturn d\nend tell\nend curDoc\n"
    static let quickOnMain = ProcessInfo.processInfo.environment["PICK_QMAIN"] != nil
    static var quickFails = 0, quickCache: [String: NSAppleScript] = [:], quickOrder: [String] = []
    // 앱 안에서 바로 실행 (osascript 프로세스를 띄우는 150~200ms가 없음, 보통 20~30ms). 텍스트 결과만 돌려줌. 자주 쓰는 짧은 명령용
    // 같은 명령문은 컴파일한 걸 다시 씀 (최근 40개)
    static func quick(_ src: String) -> String? {
        guard running else { return nil }
        let sc: NSAppleScript
        if let c = quickCache[src] { sc = c }
        else {
            guard let c = NSAppleScript(source: target(prefix + src)) else { return run(src) }
            if c.compileAndReturnError(nil) { quickCache[src] = c; quickOrder.append(src); if quickOrder.count > 40 { quickCache[quickOrder.removeFirst()] = nil } }
            sc = c
        }
        var err: NSDictionary?
        var r = NSAppleEventDescriptor()
        if quickOnMain, !Thread.isMainThread { DispatchQueue.main.sync { r = sc.executeAndReturnError(&err) } } else { r = sc.executeAndReturnError(&err) }
        if err == nil { return r.stringValue ?? "" }
        if let err { let n = (err[NSAppleScript.errorNumber] as? Int) ?? 0; quickFails += 1
            if quickFails <= 5 || quickFails % 50 == 0 { pickLog("빠른 실행 실패(\(n)): \((err[NSAppleScript.errorMessage] as? String ?? "").prefix(120))") }
            if n == -1743 || n == -600 { return run(src) }   // 권한 없음·앱 못 찾음이면 옛 길로
        }
        return nil
    }
    static func run(_ src: String) -> String? {
        guard running else { return nil }
        // 지금 문서가 없으면(다른 세션 창을 막 닫았을 때 등) 열린 첫 문서
        let full = target(prefix + src)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", full]
        let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            let m = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            NSLog("Pick osascript: %@", m)
            var where_ = ""
            if let r = m.range(of: #"^(\d+):(\d+)"#, options: .regularExpression) { let nums = m[r].split(separator: ":").compactMap { Int($0) }
                if nums.count == 2, let u = Array(full.utf16) as [UInt16]?, nums[0] < u.count { where_ = String(utf16CodeUnits: Array(u[nums[0]..<min(u.count, nums[1])]), count: min(u.count, nums[1]) - nums[0]) } }
            pickLog("osascript 오류: \(m.trimmingCharacters(in: .whitespacesAndNewlines)) · 위치: \(where_)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    static func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    static func vlist(_ ids: [String]) -> String { "set vs to {}\n" + ids.map { "set end of vs to (first variant of d whose id is \"\(esc($0))\")" }.joined(separator: "\n") }

    static let adjKeys: [(String, String)] = [("exp", "exposure"), ("temp", "temperature"), ("tint", "tint"), ("con", "contrast"), ("sat", "saturation"), ("hl", "highlight recovery"), ("sh", "shadow recovery")]

    // 한 번에 읽기 (500장 2초): 속성마다 목록 하나씩, 구분자로 이어서
    static func load() -> (String, [Item])? {
        var props: [(String, String)] = [
            ("id", "id of every variant of d"), ("name", "name of every variant of d"), ("r", "rating of every variant of d"),
            ("t", "color tag of every variant of d"), ("path", "path of parent image of every variant of d")]
        for (k, a) in adjKeys { props.append((k, "\(a) of adjustments of every variant of d")) }
        props += [("iso", "EXIF ISO of parent image of every variant of d"), ("sel", "id of (variants of d whose selected is true)")]
        guard let col = columns(props, head: "(name of d)"), let doc0 = col["_head"]?.first else { return nil }
        let doc = doc0.replacingOccurrences(of: ".cosessiondb", with: "").replacingOccurrences(of: ".cocatalog", with: "")
        let ids = col["id"] ?? []; let sel = Set(col["sel"] ?? [])
        var items: [Item] = []
        for i in ids.indices {
            func v(_ k: String) -> String { let a = col[k] ?? []; return i < a.count ? a[i] : "" }
            let path = v("path"), ext = (path as NSString).pathExtension
            var it = Item(n: "", id: ids[i], name: v("name"), ext: ext.isEmpty ? "" : "." + ext, path: path, r: Int(v("r")) ?? 0, t: Int(v("t")) ?? 0)
            for (k, _) in adjKeys { it.adj[k] = num(v(k)) }
            it.iso = v("iso").replacingOccurrences(of: "ISO ", with: "")
            items.append(it)
        }
        return (doc, numbered(items))
    }
    // 고른 사진들의 조정값만 다시 읽기 (스타일 적용 뒤)
    static func adjustments(_ ids: [String]) -> [String: [String: Double]] {
        let getters = adjKeys.map { "(\($0.1) of a as text)" }.joined(separator: " & tab & ")
        guard let raw = run("""
            tell application "Capture One"
            set d to my curDoc()
            \(vlist(ids))
            set out to ""
            repeat with v in vs
            set a to adjustments of v
            set out to out & (id of v) & tab & \(getters) & linefeed
            end repeat
            return out
            end tell
            """) else { return [:] }
        var out: [String: [String: Double]] = [:]
        for line in raw.split(separator: "\n") {
            let f = line.components(separatedBy: "\t"); guard f.count == adjKeys.count + 1 else { continue }
            var m: [String: Double] = [:]; for (k, (key, _)) in adjKeys.enumerated() { m[key] = num(f[k + 1]) }
            out[f[0]] = m
        }
        return out
    }
    // 스타일 되돌리기용: 사진마다 조정값(숫자·켜기끄기·방식) + 커브 점 + 컬러 에디터 기본 색조·채도를 글자로 저장
    // (스킨톤·컬러 에디터 밝기·마스크·레이어는 캡쳐원이 스크립트로 열어 주지 않아 저장 못 함)
    static let snapNum = ["temperature", "tint", "exposure", "brightness", "contrast", "saturation",
        "color balance master hue", "color balance master saturation", "color balance shadow hue", "color balance shadow saturation", "color balance shadow lightness",
        "color balance midtone hue", "color balance midtone saturation", "color balance midtone lightness", "color balance highlight hue", "color balance highlight saturation", "color balance highlight lightness",
        "black and white red sensitivity", "black and white yellow sensitivity", "black and white green sensitivity", "black and white cyan sensitivity", "black and white blue sensitivity", "black and white magenta sensitivity",
        "black and white split highlight hue", "black and white split highlight saturation", "black and white split shadow hue", "black and white split shadow saturation",
        "level highlight rgb", "level shadow rgb", "level highlight red", "level shadow red", "level highlight green", "level shadow green", "level highlight blue", "level shadow blue",
        "level target highlight rgb", "level target shadow rgb", "level target highlight red", "level target shadow red", "level target highlight green", "level target shadow green", "level target highlight blue", "level target shadow blue",
        "level midtone rgb", "level midtone red", "level midtone green", "level midtone blue",
        "highlight adjustment", "shadow recovery", "white recovery", "black recovery", "clarity amount", "clarity structure", "dehaze amount", "vignetting amount",
        "sharpening amount", "sharpening radius", "sharpening threshold", "sharpening halo suppression", "noise reduction luminance", "noise reduction details", "noise reduction color", "noise reduction single pixel",
        "film grain impact", "film grain granularity", "moire amount", "moire pattern"]
    static let snapWord = ["black and white", "clarity method", "vignetting method", "film grain type"]   // true/false·방식 이름 (따옴표 없이 다시 씀)
    static let snapText = ["color profile", "film curve"]
    static let curves = ["rgb curve", "luma curve", "red curve", "green curve", "blue curve"]
    static func snapshot(_ ids: [String]) -> [String: String] {
        var get = "set s to \"\"\n"
        for (k, p) in (snapNum + snapWord + snapText).enumerated() { get += "try\nset s to s & \"\(k)=\" & ((\(p) of a) as text) & (ASCII character 31)\nend try\n" }
        for c in curves { get += "try\nset s to s & \"c:\(c)=\" & ((brightness of every curve point of \(c) of a) as text) & \"/\" & ((amount of every curve point of \(c) of a) as text) & (ASCII character 31)\nend try\n" }
        get += "try\nset ce to color editor settings of a\nset s to s & \"ce=\" & ((hue change of every basic color correction of ce) as text) & \"/\" & ((saturation change of every basic color correction of ce) as text) & (ASCII character 31)\nend try\n"
        guard let raw = run("""
            tell application "Capture One"
            set d to my curDoc()
            \(vlist(ids))
            set AppleScript's text item delimiters to ","
            set out to ""
            repeat with v in vs
            set a to adjustments of v
            \(get)
            set AppleScript's text item delimiters to (ASCII character 28)
            set s to s & "st=" & ((styles of v) as text) & (ASCII character 31)
            set AppleScript's text item delimiters to ","
            set out to out & (id of v) & (ASCII character 30) & s & linefeed
            end repeat
            set AppleScript's text item delimiters to ""
            return out
            end tell
            """) else { return [:] }
        var out: [String: String] = [:]
        for line in raw.split(separator: "\n") { let f = line.components(separatedBy: "\u{1E}"); if f.count == 2 { out[f[0]] = f[1] } }
        return out
    }
    static func restore(_ snaps: [String: String]) -> Bool {
        let all = snapNum + snapWord + snapText
        var src = "tell application \"Capture One\"\nset d to my curDoc()\n"
        for (id, s) in snaps {
            src += "set v to (first variant of d whose id is \"\(esc(id))\")\nset a to adjustments of v\n"
            for part in s.components(separatedBy: "\u{1F}") where !part.isEmpty {
                guard let eq = part.firstIndex(of: "=") else { continue }
                let key = String(part[..<eq]), val = String(part[part.index(after: eq)...])
                if key == "st" {   // 적용된 스타일 목록도 넣기 전으로 (같은 스타일을 나중에 다시 넣을 수 있게)
                    let names = val.isEmpty ? [] : val.components(separatedBy: "\u{1C}")
                    src += "try\nset styles of v to {" + names.map { "\"\(esc($0))\"" }.joined(separator: ", ") + "}\nend try\n"
                } else if key == "ce" {
                    let hs = val.components(separatedBy: "/"); guard hs.count == 2 else { continue }
                    let h = hs[0].split(separator: ","), sa = hs[1].split(separator: ",")
                    for i in 0..<min(h.count, sa.count) { src += "try\nset ce to color editor settings of a\nset hue change of basic color correction \(i + 1) of ce to \(h[i])\nset saturation change of basic color correction \(i + 1) of ce to \(sa[i])\nend try\n" }
                } else if key.hasPrefix("c:") {
                    let c = String(key.dropFirst(2)), ba = val.components(separatedBy: "/"); guard ba.count == 2 else { continue }
                    let b = ba[0].split(separator: ","), am = ba[1].split(separator: ",")
                    src += "try\ndelete every curve point of \(c) of a\nend try\n"
                    for i in 0..<min(b.count, am.count) { src += "try\nmake new curve point at end of \(c) of a with properties {brightness:\(b[i]), amount:\(am[i])}\nend try\n" }
                } else if let k = Int(key), k < all.count {
                    let p = all[k]
                    let lit = snapText.contains(p) ? "\"\(esc(val))\"" : val
                    src += "try\nset \(p) of a to \(lit)\nend try\n"
                }
            }
        }
        src += "return \"ok\"\nend tell"
        return run(src) != nil
    }
    static func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    static func columns(_ props: [(String, String)], head: String, pre: String = "") -> [String: [String]]? {
        var src = "tell application \"Capture One\"\nset d to my curDoc()\n\(pre)\nset AppleScript's text item delimiters to (ASCII character 30)\nset out to \(head)\n"
        for (_, expr) in props { src += "set out to out & (ASCII character 29) & ((\(expr)) as text)\n" }
        src += "set AppleScript's text item delimiters to \"\"\nreturn out\nend tell"
        guard let raw = run(src) else { return nil }
        let blocks = raw.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1D}")
        guard blocks.count == props.count + 1 else { return nil }
        var col: [String: [String]] = ["_head": [blocks[0]]]
        for (k, (key, _)) in props.enumerated() { col[key] = blocks[k + 1].isEmpty ? [] : blocks[k + 1].components(separatedBy: "\u{1E}") }
        return col
    }
    static func setTags(_ list: [(String, Int)]) -> Bool {   // 색 태그 (0 없음 · 1 빨강 · 3 노랑 · 4 초록 · 5 파랑 …)
        guard !list.isEmpty else { return true }
        var src = "tell application \"Capture One\"\ntell current document\n"
        for (id, t) in list { src += "set color tag of (first variant whose id is \"\(esc(id))\") to \(max(0, min(7, t)))\n" }
        src += "end tell\nend tell\nreturn \"ok\""
        return run(src) != nil
    }
    static func setRatings(_ list: [(String, Int)]) -> Bool {
        guard !list.isEmpty else { return true }
        var src = "tell application \"Capture One\"\ntell current document\n"
        for (id, r) in list { src += "set rating of (first variant whose id is \"\(esc(id))\") to \(max(0, min(5, r)))\n" }
        src += "end tell\nend tell\nreturn \"ok\""
        return run(src) != nil
    }
    // 스타일 적용: 사진마다 이미지 레이어(첫 레이어)에
    static func applyStyle(_ name: String, _ ids: [String]) -> Bool {
        run("""
            tell application "Capture One"
            set d to my curDoc()
            \(vlist(ids))
            repeat with v in vs
            apply style (layer 1 of v) named "\(esc(name))"
            end repeat
            return "ok"
            end tell
            """) != nil
    }
    // 레시피 설정 (위치를 먼저 넣어야 '지정한 폴더'로 바뀜) 후 처리 요청. 처리 대상 id 목록을 돌려줌
    // 캡쳐원 편집 메뉴의 실행 취소/다시 실행 이름 (예: '변형들 삭제 실행 취소'). 비어 있으면 할 게 없음
    static func undoLabel(_ redo: Bool) -> String {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").hasPrefix("Capture One") }) else { return "" }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
        guard let bar = attr(ax, kAXMenuBarAttribute), let tops = attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement],
              let edit = tops.first(where: { ["편집", "Edit"].contains(attr($0, kAXTitleAttribute) as? String ?? "") }),
              let menu = (attr(edit, kAXChildrenAttribute) as? [AXUIElement])?.first,
              let items = attr(menu, kAXChildrenAttribute) as? [AXUIElement], items.count > 1 else { return "?" }
        let t = attr(items[redo ? 1 : 0], kAXTitleAttribute) as? String ?? ""
        return t == "실행 취소" || t == "다시 실행" || t == "Undo" || t == "Redo" ? "" : t
    }
    // 새로 들어온 변형들만 읽기 (테더링 촬영·가져오기)
    static func loadIDs(_ ids: [String]) -> [Item] {
        guard let out = run("""
            tell application "Capture One"
            set d to my curDoc()
            set out to ""
            repeat with i in {\(ids.map { "\"\(esc($0))\"" }.joined(separator: ","))}
            try
            set v to (first variant of d whose id is (contents of i))
            set out to out & (id of v) & tab & (name of v) & tab & (rating of v) & tab & (color tag of v) & tab & (path of parent image of v) & linefeed
            end try
            end repeat
            return out
            end tell
            """) else { return [] }
        return out.split(separator: "\n").compactMap { l in
            let t = l.components(separatedBy: "\t"); guard t.count >= 5 else { return nil }
            let ext = (t[4] as NSString).pathExtension
            return Item(n: "", id: t[0], name: t[1], ext: ext.isEmpty ? "" : "." + ext, path: t[4], r: Int(t[2]) ?? 0, t: Int(t[3]) ?? 0) }
    }
    // 캡쳐원에서 고른 변형(최대 8개)의 조정값 전체 + 스타일 → id별 지문
    static func fnv(_ sig: String) -> Int { var h: UInt64 = 1469598103934665603; for b in sig.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }; return Int(truncatingIfNeeded: h) }   // 다시 켜도 같은 값
    static func clean(_ x: Substring) -> String { x.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
    static func rawRun(_ body: String) -> [Substring]? {
        guard running else { return nil }
        let src = "on curDoc()\ntell application \"Capture One\"\nset d to missing value\ntry\nset d to current document\nend try\ntry\nget name of d\non error\nset d to document 1\nend try\nreturn d\nend tell\nend curDoc\ntell application \"Capture One\"\nset d to my curDoc()\n" + body + "\nend tell"
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-s", "s", "-e", target(src)]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return splitList(Substring(text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    struct Sigs { var adj: [String: Int] = [:], crop: [String: Int] = [:], r: [String: Int] = [:], t: [String: Int] = [:], sel = Set<String>() }
    // 전체 읽기: 세션 모든 사진의 조정값·스타일(adj)·크롭·별점·태그 — 695장에 약 1.9초 → 8초마다 안전장치로만
    static func fullSigs() -> Sigs? {
        guard let top = rawRun("return {id of every variant of d, properties of adjustments of every variant of d, styles of every variant of d, crop of every variant of d, id of (variants of d whose selected is true), rating of every variant of d, color tag of every variant of d}"), top.count == 7 else { return nil }
        let ids = splitList(top[0]).map(clean), ps = splitList(top[1]), ss = splitList(top[2]), cs = splitList(top[3]), rs = splitList(top[5]), ts = splitList(top[6])
        var g = Sigs(); g.sel = Set(splitList(top[4]).map(clean))
        for (i, id) in ids.enumerated() {
            g.adj[id] = fnv((i < ps.count ? String(ps[i]) : "") + (i < ss.count ? String(ss[i]) : ""))
            g.crop[id] = fnv(i < cs.count ? String(cs[i]) : "")
            g.r[id] = Int(i < rs.count ? String(rs[i]).trimmingCharacters(in: .whitespaces) : "") ?? 0
            g.t[id] = Int(i < ts.count ? String(ts[i]).trimmingCharacters(in: .whitespaces) : "") ?? 0
        }
        return g
    }
    struct Fast { var doc = "", sort = "", rev = false, ids: [String] = [], sigs = Sigs() }
    // 빠른 읽기(매초): 세션 이름·정렬·보이는 순서·새 사진 + (캡쳐원 쓰는 중이면) 별점·태그·크롭 전체와 '선택한 사진'의 조정값만
    static func fastRead(edits: Bool, light: Bool = false) -> Fast? {   // light: 별점·태그·자르기만 (조정값·스타일 목록 읽기는 캡쳐원이 앞에 있을 때 스타일 커서 미리보기를 끊을 수 있어 뒤로 미룸, 2026-11-04)
        let extra = edits ? (light ? ", rating of every variant of c, color tag of every variant of c, crop of every variant of c, {}, {}" : ", rating of every variant of c, color tag of every variant of c, crop of every variant of c, properties of adjustments of (variants of d whose selected is true), styles of (variants of d whose selected is true)") : ""
        guard let top = rawRun("set c to current collection of d\nif c is missing value then return {name of d}\nreturn {name of d, (sorting order of c) as text, sorting reversed of c, id of every variant of c, id of (variants of d whose selected is true)\(extra)}") else { return nil }
        var f = Fast(); guard let d0 = top.first else { return nil }
        f.doc = clean(d0).replacingOccurrences(of: ".cosessiondb", with: "").replacingOccurrences(of: ".cocatalog", with: "")
        guard top.count >= 5 else { return f }
        f.sort = clean(top[1]); f.rev = String(top[2]).contains("true"); f.ids = splitList(top[3]).map(clean)
        let selIds = splitList(top[4]).map(clean); f.sigs.sel = Set(selIds)
        if edits, top.count == 10 {
            let rs = splitList(top[5]), ts = splitList(top[6]), cs = splitList(top[7]), ps = splitList(top[8]), ss = splitList(top[9])
            for (i, id) in f.ids.enumerated() {
                f.sigs.r[id] = Int(i < rs.count ? String(rs[i]).trimmingCharacters(in: .whitespaces) : "") ?? 0
                f.sigs.t[id] = Int(i < ts.count ? String(ts[i]).trimmingCharacters(in: .whitespaces) : "") ?? 0
                f.sigs.crop[id] = fnv(i < cs.count ? String(cs[i]) : "")
            }
            for (j, id) in selIds.enumerated() where j < ps.count { f.sigs.adj[id] = fnv(String(ps[j]) + (j < ss.count ? String(ss[j]) : "")) }
        }
        return f
    }
    // "{a, {b, c}, \"d, e\"}" → 맨 바깥 목록의 항목들 (따옴표·중괄호 안 쉼표는 무시)
    static func splitList(_ s0: Substring) -> [Substring] {
        var s = s0[...]; while s.first == " " { s = s.dropFirst() }
        guard s.first == "{", s.last == "}" else { return s.isEmpty ? [] : [s] }
        s = s.dropFirst().dropLast()
        var out: [Substring] = [], depth = 0, inQ = false, esc = false, start = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if inQ { if esc { esc = false } else if c == "\\" { esc = true } else if c == "\"" { inQ = false } }
            else if c == "\"" { inQ = true } else if c == "{" || c == "«" { depth += 1 } else if c == "}" || c == "»" { depth -= 1 }
            else if c == ",", depth == 0 { out.append(s[start..<i]); start = s.index(after: i) }
            i = s.index(after: i)
        }
        if start < s.endIndex { out.append(s[start..<s.endIndex]) }
        return out.map { var t = $0; while t.first == " " { t = t.dropFirst() }; return t }
    }
    // 지금 컬렉션의 정렬 기준·거꾸로·보이는 순서(변형 id)
    static func order() -> (sort: String, rev: Bool, ids: [String])? {
        guard let out = run("""
            tell application "Capture One"
            set d to my curDoc()
            set c to current collection of d
            if c is missing value then return ""
            set AppleScript's text item delimiters to linefeed
            set ids to ""
            try
            if (count of variants of c) > 0 then set ids to (id of every variant of c) as text
            end try
            return (sorting order of c as text) & tab & (sorting reversed of c as text) & linefeed & ids
            end tell
            """) else { return nil }
        var lines = out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }
        let head = lines.removeFirst().components(separatedBy: "\t")
        return (head.first ?? "", head.count > 1 && head[1] == "true", lines.filter { !$0.isEmpty })
    }
    static let sortNames = ["by name", "by date", "by rating", "by manual", "by color tag", "by file size", "by sequence ID", "by extension"]
    static func setSort(_ sort: String, rev: Bool) {
        guard sortNames.contains(sort) else { return }
        _ = run("""
            tell application "Capture One"
            set d to my curDoc()
            set c to current collection of d
            set sorting order of c to \(sort)
            set sorting reversed of c to \(rev)
            end tell
            """)
    }
    // 캡쳐원이 처리하면서 앞으로 튀어나오면 → 원래 앞에 있던 앱(픽·Finder·포토샵 등)을 다시 앞으로 (3초 동안 지켜봄)
    static func keepFront(_ prev: NSRunningApplication?) {
        guard let prev, !(prev.localizedName ?? "").hasPrefix("Capture One") else { return }
        for k in 1...12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(k)) {
                if let f = NSWorkspace.shared.frontmostApplication, (f.localizedName ?? "").hasPrefix("Capture One") { prev.activate() }
            }
        }
    }
    static let previewLongEdge = 2600   // 미리보기 긴 변(픽셀). 레티나 미리보기 창(세로 ~2600px)에서 선명하게. 바꾸면 옛 미리보기는 크기로 걸러 다시 만듦
    static var recipeReady = Set<String>()   /* 이 실행에서 이미 속성을 맞춘 레시피(이름+저장 위치) — 매번 비교하면 0.4초 */
    static func process(_ ids: [String], recipe: String, into dir: String, fullSize: Bool) -> Set<String> {
        guard !dir.isEmpty, !ids.isEmpty else { return [] }   // 세션 바뀌는 중 등 저장 위치가 비었을 때
        let rkey = recipe + "|" + dir, configured = recipeReady.contains(rkey)
        let prev = NSWorkspace.shared.frontmostApplication
        defer { keepFront(prev) }
        // 값이 다를 때만 바꿈 → 캡쳐원 레시피 목록이 계속 깜빡이지 않게
        func put(_ prop: String, _ val: String) -> String { "try\nif (\(prop) of r) is not \(val) then set \(prop) of r to \(val)\non error\nset \(prop) of r to \(val)\nend try" }
        let scale = (fullSize
            ? [put("JPEG quality", "100"), put("scaling method", "Fixed"), put("upscale", "false")]
            : [put("JPEG quality", "88"), put("scaling method", "Long_Edge"), put("scaling unit", "pixels"), put("primary scaling value", "\(previewLongEdge)"), put("upscale", "false")]).joined(separator: "\n")
        let filter = fullSize ? "set big to vs" : """
            set big to {}
            repeat with v in vs
            set dm to dimensions of (parent image of v)
            if (item 1 of dm) > \(previewLongEdge) or (item 2 of dm) > \(previewLongEdge) then set end of big to v
            end repeat
            """
        let out = run("""
            tell application "Capture One"
            set d to my curDoc()
            if not (exists recipe "\(recipe)" of d) then make new recipe at d with properties {name:"\(recipe)"}
            set r to recipe "\(recipe)" of d
            \(configured ? "" : """
            \(put("output format", "JPEG"))
            \(put("color profile", "\"sRGB Color Space Profile\""))
            \(scale)
            set want to POSIX file "\(esc(dir))"
            set cur to ""
            try
            set cur to POSIX path of (root folder location of r as alias)
            end try
            if cur is not "\(esc(dir))/" and cur is not "\(esc(dir))" then set root folder location of r to want
            \(put("root folder type", "custom location"))
            \(put("output sub folder", "\"\""))
            \(put("existing files", fullSize ? "add suffix" : "overwrite"))
            \(put("enabled", "false"))
            if (root folder type of r) is not custom location then error "위치 설정 실패"
            """)
            \(vlist(ids))
            \(filter)
            set out to ""
            repeat with v in big
            set out to out & (id of v) & linefeed
            end repeat
            if (count of big) > 0 then process big recipe "\(recipe)"
            return out
            end tell
            """)
        if out != nil { recipeReady.insert(rkey) }
        return Set((out ?? "").split(separator: "\n").map(String.init))
    }
}

// 촬영 순서(이름 순)로 번호 붙이기
func numbered(_ items: [Item]) -> [Item] {
    items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.enumerated().map { k, it in var x = it; x.n = String(k + 1); return x }
}

// MARK: - 촬영 정보 (파일 머리글만 읽음)
func exif(_ path: String) -> [String: String] {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let pr = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return [:] }
    let ex = pr[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
    let tiff = pr[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
    var o: [String: String] = [:]
    if let t = ex[kCGImagePropertyExifExposureTime as String] as? Double, t > 0 { o["ss"] = t < 1 ? "1/\(Int((1 / t).rounded()))" : "\(t)" }
    if let f = ex[kCGImagePropertyExifFNumber as String] as? Double { o["f"] = String(format: f == f.rounded() ? "%.0f" : "%.1f", f) }
    if let fl = ex[kCGImagePropertyExifFocalLength as String] as? Double { o["fl"] = "\(Int(fl.rounded()))" }
    if let l = ex[kCGImagePropertyExifLensModel as String] as? String { o["lens"] = l }
    if let d = ex[kCGImagePropertyExifDateTimeOriginal as String] as? String, d.count >= 16 {
        let a = Array(d); o["dt"] = String(a[0..<4]) + "-" + String(a[5..<7]) + "-" + String(a[8..<10]) + " " + String(a[11..<16]); o["dtfull"] = d }
    if let m = tiff[kCGImagePropertyTIFFModel as String] as? String { o["cam"] = m }
    if let isos = ex[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let i = isos.first, i > 0 { o["iso"] = "\(i)" }
    if let w = pr[kCGImagePropertyPixelWidth as String] as? Double, let h = pr[kCGImagePropertyPixelHeight as String] as? Double, w > 0, h > 0 {   // 화면 비율 (회전 5~8이면 가로세로 바꿈) → 필름스트립·맵 칸을 처음부터 맞는 모양으로
        let rot = (pr[kCGImagePropertyOrientation as String] as? Int ?? 1) >= 5
        o["a"] = String(format: "%.4f", rot ? h / w : w / h) }
    o["o"] = String(pr[kCGImagePropertyOrientation as String] as? Int ?? 1)   // 파일의 회전값 (보정 xmp의 회전과 비교용, 화면엔 안 보냄)
    return o
}

// MARK: - 이미지 (줄여서 JPG로)
let rawExts: Set<String> = ["cr3", "cr2", "nef", "arw", "raf", "dng", "orf", "rw2"]
func jpegThumb(_ path: String, max: Int) -> Data? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let raw = rawExts.contains((path as NSString).pathExtension.lowercased())
    var cg: CGImage? = nil
    if raw {   // RAW: 안에 든 미리보기 JPG로 (전체 현상보다 7배 빠름). 미리보기가 너무 작으면 아래에서 원본으로
        cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageIfAbsent: true, kCGImageSourceThumbnailMaxPixelSize: max, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        if let c = cg, Swift.max(c.width, c.height) < Int(Double(max) * 0.75) { cg = nil }
    }
    if cg == nil { cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) }
    guard let cg else { return nil }
    return jpegEncode(cg)
}
func jpegEncode(_ cg: CGImage) -> Data? {
    let d = NSMutableData()
    guard let dst = CGImageDestinationCreateWithData(d, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dst, cg, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    return CGImageDestinationFinalize(dst) ? d as Data : nil
}
func mtime(_ p: String) -> Date? { (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date }
func jpegComplete(_ p: String) -> Bool {
    guard let h = FileHandle(forReadingAtPath: p) else { return false }; defer { try? h.close() }
    guard let end = try? h.seekToEnd(), end > 2 else { return false }
    try? h.seek(toOffset: end - 2); return h.readData(ofLength: 2) == Data([0xFF, 0xD9])
}
// 같은 이름이 있으면 '이름 2.jpg', '이름 3.jpg' …
// 카톡용: 19.5MB 넘는 JPG만 화질 95→90→…→40 낮춰 다시 저장 (해상도 그대로)
func kakaoShrink(_ f: String) {
    let limit = 19_500_000, fm = FileManager.default
    func size(_ p: String) -> Int { (try? fm.attributesOfItem(atPath: p)[.size] as? Int) ?? 0 }
    guard size(f) > limit else { return }
    let tmp = NSTemporaryDirectory() + "kakao-\(UUID().uuidString).jpg"
    var q = 95
    while q >= 40 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sips"); p.arguments = ["-s", "format", "jpeg", "-s", "formatOptions", "\(q)", f, "--out", tmp]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { break }; p.waitUntilExit()
        if size(tmp) <= limit || q == 40 { _ = try? fm.removeItem(atPath: f); try? fm.moveItem(atPath: tmp, toPath: f); return }
        q -= 5
    }
    try? fm.removeItem(atPath: tmp)
}
func uniquePath(_ dir: String, _ file: String) -> String {
    let fm = FileManager.default, base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
    var p = dir + "/" + file, i = 2
    while fm.fileExists(atPath: p) { p = dir + "/" + base + " \(i)" + (ext.isEmpty ? "" : "." + ext); i += 1 }
    return p
}

// MARK: - 캐시 정리 (안전장치: ~/Library/Caches/Pick/ 바로 아래 폴더의 .jpg만 지우고, 빈 폴더면 폴더도)
func cleanCache(_ dir: String, removeFolder: Bool = false) {
    let fm = FileManager.default
    guard dir.hasPrefix(cacheRoot + "/"), !dir.dropFirst(cacheRoot.count + 1).contains("/"),
          let files = try? fm.contentsOfDirectory(atPath: dir) else { return }
    for f in files where f.lowercased().hasSuffix(".jpg") { try? fm.removeItem(atPath: dir + "/" + f) }
    if removeFolder, (try? fm.contentsOfDirectory(atPath: dir))?.isEmpty == true { try? fm.removeItem(atPath: dir) }
}

// MARK: - XMP 별점·색 라벨 (브릿지 방식, 2026-11-03 실측): RAW = 옆 '이름.xmp' 파일, JPG·TIFF·PNG·HEIC·DNG = 사진 파일 안, PSD = 파일 안(1060 자원)
enum XMPRating {
    static func ext(_ p: String) -> String { (p as NSString).pathExtension.lowercased() }
    static func isRaw(_ path: String) -> Bool { let e = ext(path); return rawExts.contains(e) && e != "dng" }   // DNG는 브릿지처럼 파일 안에
    static func isPSD(_ path: String) -> Bool { ext(path) == "psd" }
    static func sidecar(_ path: String) -> String { (path as NSString).deletingPathExtension + ".xmp" }
    static let ratingRe = try! NSRegularExpression(pattern: "xmp:Rating=\"(-?\\d+)\"|<xmp:Rating>(-?\\d+)</xmp:Rating>")
    static let labelRe = try! NSRegularExpression(pattern: "\\s*xmp:Label=\"([^\"]*)\"|\\s*<xmp:Label>([^<]*)</xmp:Label>")
    // 라벨은 글자로 저장되고, 브릿지는 자기 설정의 이름과 글자가 같을 때만 색으로 보여 줌. 기본 이름이 언어마다 달라서 맥 언어에 맞춰 쓰고, 읽을 때는 다 받음
    static let labelKo = [1: "선택", 3: "재청", 4: "검토 완료", 5: "검토", 7: "할 일"]          // 한국어 브릿지 기본값 (Bridge 2026 strings.dict)
    static let labelEn = [1: "Select", 3: "Second", 4: "Approved", 5: "Review", 7: "To Do"]   // 영어 브릿지 기본값
    static let labelLR = [1: "Red", 2: "Orange", 3: "Yellow", 4: "Green", 5: "Blue", 6: "Pink", 7: "Purple"]   // 라이트룸·캡쳐원식 색 이름
    static let korean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
    static func labelText(_ t: Int) -> String { (korean ? labelKo[t] : labelEn[t]) ?? labelLR[t] ?? "" }
    static func tag(fromLabel s: String) -> Int? {   // 모르는 글자면 nil (브릿지는 흰 라벨로 보여 줌)
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines); if v.isEmpty { return 0 }
        for d in [labelKo, labelEn, labelLR] { if let k = d.first(where: { $0.value.caseInsensitiveCompare(v) == .orderedSame })?.key { return k } }
        return nil
    }
    struct Meta { var r: Int? = nil, t: Int? = nil, text: String? = nil }   // text = XMP 원문 (RAW 옆 파일·PSD일 때만)
    static func parse(_ t: String) -> (r: Int?, t: Int?) {
        var r: Int? = nil, tag: Int? = nil
        let ns = NSRange(t.startIndex..., in: t)
        if let m = ratingRe.firstMatch(in: t, range: ns) { for g in 1...2 { if let rr = Range(m.range(at: g), in: t) { r = max(0, min(5, Int(t[rr]) ?? 0)) } } }
        if let m = labelRe.firstMatch(in: t, range: ns) { for g in 1...2 { if let rr = Range(m.range(at: g), in: t) { tag = XMPRating.tag(fromLabel: String(t[rr])) ?? 0 } } }
        return (r, tag)
    }
    static func read(_ path: String) -> Int? { readMeta(path).r }
    static func readMeta(_ path: String) -> Meta {   // 없으면 nil
        if isRaw(path) { guard let t = try? String(contentsOfFile: sidecar(path), encoding: .utf8) else { return Meta() }; let p = parse(t); return Meta(r: p.r, t: p.t, text: t) }
        if isPSD(path) { guard let t = PSDXMP.read(path) else { return Meta() }; let p = parse(t); return Meta(r: p.r, t: p.t, text: t) }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let md = CGImageSourceCopyMetadataAtIndex(src, 0, nil) else { return Meta() }
        let r = (CGImageMetadataCopyStringValueWithPath(md, nil, "xmp:Rating" as CFString) as String?).flatMap { Int($0) }.map { max(0, min(5, $0)) }
        let l = CGImageMetadataCopyStringValueWithPath(md, nil, "xmp:Label" as CFString) as String?
        return Meta(r: r, t: l.map { tag(fromLabel: $0) ?? 0 }, text: nil)
    }
    // XMP 글(옆 파일·PSD)에서 별점·라벨 속성만 바꿈. 라벨 0 = 속성 지움
    static func updated(_ t0: String, rating: Int?, tag: Int?) -> String? {
        var t = t0
        if let r = rating {
            if let m = ratingRe.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let rr = Range(m.range, in: t) {
                t.replaceSubrange(rr, with: m.range(at: 1).location != NSNotFound ? "xmp:Rating=\"\(r)\"" : "<xmp:Rating>\(r)</xmp:Rating>")
            } else if !insertAttr(&t, "xmp:Rating=\"\(r)\"") { return nil }
        }
        if let g = tag {
            if let m = labelRe.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let rr = Range(m.range, in: t) {
                let attr = m.range(at: 1).location != NSNotFound
                t.replaceSubrange(rr, with: g == 0 ? "" : (attr ? "\n   xmp:Label=\"\(labelText(g))\"" : "\n   <xmp:Label>\(labelText(g))</xmp:Label>"))
            } else if g != 0, !insertAttr(&t, "xmp:Label=\"\(labelText(g))\"") { return nil }
        }
        return t
    }
    static func insertAttr(_ t: inout String, _ attr: String) -> Bool {   // 첫 rdf:Description 시작 태그에 속성 추가 (xmp 이름공간도 그 태그 안에 없으면 같이)
        guard let d = t.range(of: "<rdf:Description"), let close = t[d.upperBound...].firstIndex(of: ">") else { return false }
        let tagText = t[d.lowerBound..<close]
        t.insert(contentsOf: (tagText.contains("xmlns:xmp=") ? "" : " xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"") + " " + attr, at: d.upperBound); return true
    }
    static func newPacket(_ attrs: [String]) -> String {
        """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Pick">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"\(attrs.map { " " + $0 }.joined())/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
    @discardableResult static func write(_ path: String, _ r: Int) -> Bool { write(path, rating: r) }
    @discardableResult static func write(_ path: String, rating: Int? = nil, tag: Int? = nil) -> Bool {
        if rating == nil && tag == nil { return true }
        let fm = FileManager.default
        if isRaw(path) {
            let sc = sidecar(path)
            if let t = try? String(contentsOfFile: sc, encoding: .utf8) { guard let n = updated(t, rating: rating, tag: tag) else { return false }; return (try? n.write(toFile: sc, atomically: true, encoding: .utf8)) != nil }
            let attrs = [rating.map { "xmp:Rating=\"\($0)\"" }, tag.flatMap { $0 == 0 ? nil : "xmp:Label=\"\(labelText($0))\"" }].compactMap { $0 }
            if attrs.isEmpty { return true }
            return (try? newPacket(attrs).write(toFile: sc, atomically: true, encoding: .utf8)) != nil
        }
        if isPSD(path) {   // 포토샵 파일: 이미지 자원 1060(XMP)만 바꿔 씀 (브릿지도 파일 안에 씀)
            guard let n = updated(PSDXMP.read(path) ?? newPacket([]), rating: rating, tag: tag) else { return false }
            return PSDXMP.write(path, n)
        }
        // 사진 파일 안에: 다시 압축하지 않고 정보만 바꿔 씀 (CGImageDestinationCopyImageSource). 있던 XMP를 복사해 별점·라벨만 바꾸고 통째로 다시 씀 (라벨 지우기가 되게)
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let type = CGImageSourceGetType(src) else { return false }
        let md = CGImageSourceCopyMetadataAtIndex(src, 0, nil).map { CGImageMetadataCreateMutableCopy($0) ?? CGImageMetadataCreateMutable() } ?? CGImageMetadataCreateMutable()
        func set(_ name: String, _ v: String) -> Bool {
            guard let tag = CGImageMetadataTagCreate(kCGImageMetadataNamespaceXMPBasic, kCGImageMetadataPrefixXMPBasic, name as CFString, .string, v as CFString) else { return false }
            return CGImageMetadataSetTagWithPath(md, nil, ("xmp:" + name) as CFString, tag) }
        if let r = rating, !set("Rating", "\(r)") { return false }
        if let g = tag { if g == 0 { CGImageMetadataRemoveTagWithPath(md, nil, "xmp:Label" as CFString) } else if !set("Label", labelText(g)) { return false } }
        let tmp = (path as NSString).deletingLastPathComponent + "/.pick-\(UUID().uuidString.prefix(8))." + (path as NSString).pathExtension
        guard let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: tmp) as CFURL, type, 1, nil) else { return false }
        var err: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dst, src, [kCGImageDestinationMetadata: md, kCGImageDestinationMergeMetadata: false] as CFDictionary, &err) else { try? fm.removeItem(atPath: tmp); return false }
        do { _ = try fm.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp)); return true } catch { try? fm.removeItem(atPath: tmp); return false }
    }
}
let xmpQ = DispatchQueue(label: "pick.xmp")   // 쓰기는 한 줄로 차례대로

// MARK: - PSD 안의 XMP (이미지 자원 1060). 포토샵 파일 구조: 머리 26B · 색상 모드 자료 · 이미지 자원 목록 · 레이어 · 픽셀
enum PSDXMP {
    struct Block { let id: Int, start: Int, end: Int, dataStart: Int, dataLen: Int }   // 위치는 자원 목록 시작(첫 블록) 기준
    struct Layout { let resStart: Int, resLen: Int, blocks: [Block] }   // resStart = 첫 블록의 파일 위치
    static func be16(_ d: Data, _ i: Int) -> Int { Int(d[d.startIndex + i]) << 8 | Int(d[d.startIndex + i + 1]) }
    static func be32(_ d: Data, _ i: Int) -> Int { be16(d, i) << 16 | be16(d, i + 2) }
    static func bytes32(_ v: Int) -> Data { Data([UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]) }
    static func layout(_ h: FileHandle) -> Layout? {
        try? h.seek(toOffset: 0)
        guard let hd = try? h.read(upToCount: 26), hd.count == 26, hd.prefix(4) == Data("8BPS".utf8), [1, 2].contains(be16(hd, 4)) else { return nil }   // PSD(1)·PSB(2) 모두 같은 구조
        guard let cl = try? h.read(upToCount: 4), cl.count == 4 else { return nil }
        let colorLen = be32(cl, 0); try? h.seek(toOffset: UInt64(30 + colorLen))
        guard let rl = try? h.read(upToCount: 4), rl.count == 4 else { return nil }
        let resLen = be32(rl, 0)
        guard resLen >= 0, resLen < 256 * 1024 * 1024, let res = try? h.read(upToCount: resLen), res.count == resLen else { return nil }
        var blocks: [Block] = [], p = 0
        while p + 12 <= resLen {
            guard let sig = String(data: res[p..<p + 4], encoding: .ascii), ["8BIM", "MeSa", "PHUT", "AgHg", "DCSR"].contains(sig) else { return nil }
            let id = be16(res, p + 4), nameLen = Int(res[p + 6])
            var q = p + 6 + 1 + nameLen; if (1 + nameLen) % 2 == 1 { q += 1 }   // 이름(파스칼 문자열)은 짝수 길이로 채움
            guard q + 4 <= resLen else { return nil }
            let size = be32(res, q), dataStart = q + 4; var end = dataStart + size; if size % 2 == 1 { end += 1 }
            guard end <= resLen else { return nil }
            blocks.append(Block(id: id, start: p, end: end, dataStart: dataStart, dataLen: size)); p = end
        }
        guard p == resLen else { return nil }
        return Layout(resStart: 34 + colorLen, resLen: resLen, blocks: blocks)
    }
    static func read(_ path: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }; defer { try? h.close() }
        guard let L = layout(h), let b = L.blocks.first(where: { $0.id == 1060 }) else { return nil }
        try? h.seek(toOffset: UInt64(L.resStart + b.dataStart)); guard let d = try? h.read(upToCount: b.dataLen) else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func padded(_ text: String, to len: Int) -> Data? {   // 끝 표시(<?xpacket end) 앞에 빈칸을 채워 정확히 len 바이트로
        var t = text; let cur = t.utf8.count; guard cur <= len else { return nil }
        t.insert(contentsOf: String(repeating: " ", count: len - cur), at: t.range(of: "<?xpacket end=")?.lowerBound ?? t.endIndex)
        let d = Data(t.utf8); return d.count == len ? d : nil
    }
    @discardableResult static func write(_ path: String, _ xmp: String) -> Bool {
        let fm = FileManager.default
        guard let h = FileHandle(forUpdatingAtPath: path) else { return false }
        guard let L = layout(h) else { try? h.close(); return false }
        let old = L.blocks.first { $0.id == 1060 }
        // 1) 있던 자리에 들어가면 그 자리에만 바꿔 씀 (어도비도 이렇게 끝의 빈칸을 바꿔 써서 큰 파일을 다시 쓰지 않음)
        if let o = old, let d = padded(xmp, to: o.dataLen) {
            try? h.seek(toOffset: UInt64(L.resStart + o.dataStart)); h.write(d); try? h.synchronize(); try? h.close(); return true
        }
        // 2) 안 들어가면: 머리 + 새 자원 목록 + 나머지 전체를 새 파일로 쓰고 바꿔 끼움 (큰 PSD는 몇 초). 다음에는 1)로 되게 2KB 여유를 둠
        var text = xmp; if !text.contains("<?xpacket end=") { text += "\n<?xpacket end=\"w\"?>" }
        let want = text.utf8.count + 2048 + (text.utf8.count % 2)
        guard let data = padded(text, to: want) else { try? h.close(); return false }
        let size = (try? h.seekToEnd()) ?? 0
        let tmp = (path as NSString).deletingLastPathComponent + "/.pick-\(UUID().uuidString.prefix(8)).psd"
        guard fm.createFile(atPath: tmp, contents: nil), let out = FileHandle(forWritingAtPath: tmp) else { try? h.close(); return false }
        func copy(_ from: Int, _ len: Int) -> Bool {
            try? h.seek(toOffset: UInt64(from)); var left = len
            while left > 0 { guard let c = try? h.read(upToCount: min(left, 8 << 20)), !c.isEmpty else { return false }; out.write(c); left -= c.count }
            return true }
        var ok = copy(0, L.resStart - 4)   // 머리 + 색상 모드 자료 (자원 목록 길이 바로 앞까지)
        var blocks = Data()
        func newBlock() { blocks.append(Data("8BIM".utf8)); blocks.append(Data([0x04, 0x24, 0, 0])); blocks.append(bytes32(data.count)); blocks.append(data) }   // 0x0424 = 1060, 이름 없음(2바이트 0)
        var placed = false
        for b in L.blocks {
            if b.id == 1060 { newBlock(); placed = true; continue }
            try? h.seek(toOffset: UInt64(L.resStart + b.start)); guard let c = try? h.read(upToCount: b.end - b.start), c.count == b.end - b.start else { ok = false; break }; blocks.append(c)
        }
        if !placed { newBlock() }
        if ok { out.write(bytes32(blocks.count)); out.write(blocks); ok = copy(L.resStart + L.resLen, Int(size) - (L.resStart + L.resLen)) }
        try? out.synchronize(); try? out.close(); try? h.close()
        // 확인: 크기 차이가 자원 목록 차이와 같고, 맥이 그림으로 읽을 수 있어야 바꿔 끼움
        let newSize = (try? fm.attributesOfItem(atPath: tmp)[.size] as? Int) ?? -1
        let oldW = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }?["PixelWidth"] as? Int
        let newW = CGImageSourceCreateWithURL(URL(fileURLWithPath: tmp) as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }?["PixelWidth"] as? Int
        guard ok, newSize == Int(size) - L.resLen + blocks.count, oldW != nil, oldW == newW else { try? fm.removeItem(atPath: tmp); pickLog("PSD XMP 쓰기 확인 실패: \((path as NSString).lastPathComponent)"); return false }
        do { _ = try fm.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp)); return true } catch { try? fm.removeItem(atPath: tmp); return false }
    }
}


// MARK: - 카메라 로우 보정값 (옆 .xmp의 crs:*) → 맥 기본 RAW 엔진으로 비슷하게 (브릿지처럼 보정된 모습의 썸네일)
struct CRSEdits {
    var exposure = 0.0, contrast = 0.0, highlights = 0.0, shadows = 0.0, saturation = 0.0, vibrance = 0.0
    var wbCustom = false, temperature = 0.0, tint = 0.0, gray = false
    var crop: (l: Double, t: Double, r: Double, b: Double)? = nil, angle = 0.0
    var orientation: Int? = nil   // tiff:Orientation (브릿지 회전)
    var colorEdits: Bool { exposure != 0 || contrast != 0 || highlights != 0 || shadows != 0 || saturation != 0 || vibrance != 0 || wbCustom || gray }
    func isEdited(fileOrientation fo: Int) -> Bool { colorEdits || crop != nil || (orientation != nil && CRSEdits.deg(orientation!) != CRSEdits.deg(fo)) }
    var sig: String {   // 캐시 열쇠용 (별점만 바뀐 .xmp로는 썸네일을 다시 만들지 않게, 보정값만)
        var s = String(format: "e%.2f c%.0f h%.0f s%.0f sa%.0f v%.0f", exposure, contrast, highlights, shadows, saturation, vibrance)
        if wbCustom { s += String(format: " wb%.0f/%.0f", temperature, tint) }; if gray { s += " bw" }
        if let c = crop { s += String(format: " crop%.4f,%.4f,%.4f,%.4f@%.2f", c.l, c.t, c.r, c.b, angle) }; if let o = orientation { s += " o\(o)" }
        return s
    }
    static func deg(_ o: Int) -> Int { [3: 180, 4: 180, 5: 90, 6: 90, 7: 270, 8: 270][o] ?? 0 }   // 화면에 보일 때 돌리는 각도 (시계 방향)
    static var reCache: [String: NSRegularExpression] = [:]; static let reLock = NSLock()
    static func attr(_ t: String, _ name: String) -> String? {
        reLock.lock(); let re: NSRegularExpression
        if let r = reCache[name] { re = r } else { re = try! NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "=\"([^\"]*)\"|<" + NSRegularExpression.escapedPattern(for: name) + ">([^<]*)</"); reCache[name] = re }
        reLock.unlock()
        guard let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        for g in 1...2 { if let r = Range(m.range(at: g), in: t) { return String(t[r]) } }
        return nil
    }
    static func parse(_ t: String) -> CRSEdits? {
        guard t.contains("crs:") else { return nil }
        func num(_ k: String) -> Double { Double((attr(t, k) ?? "0").replacingOccurrences(of: "+", with: "")) ?? 0 }
        var e = CRSEdits()
        e.exposure = num("crs:Exposure2012"); e.contrast = num("crs:Contrast2012"); e.highlights = num("crs:Highlights2012"); e.shadows = num("crs:Shadows2012")
        e.saturation = num("crs:Saturation"); e.vibrance = num("crs:Vibrance")
        e.gray = attr(t, "crs:ConvertToGrayscale") == "True"
        if let wb = attr(t, "crs:WhiteBalance"), wb != "As Shot", wb != "" { let k = num("crs:Temperature"); if k >= 2000, k <= 50000 { e.wbCustom = true; e.temperature = k; e.tint = num("crs:Tint") } }
        if attr(t, "crs:HasCrop") == "True" {
            let l = num("crs:CropLeft"), tp = num("crs:CropTop"), r = num("crs:CropRight"), b = num("crs:CropBottom")
            if r > l + 0.01, b > tp + 0.01, l >= 0, tp >= 0, r <= 1, b <= 1, (r - l < 0.999 || b - tp < 0.999) { e.crop = (l, tp, r, b); e.angle = num("crs:CropAngle") }
        }
        if let o = attr(t, "tiff:Orientation").flatMap({ Int($0) }), (1...8).contains(o) { e.orientation = o }
        return e
    }
}
let ciCtx = CIContext(options: [.cacheIntermediates: false])
let rawSem = DispatchSemaphore(value: 2)   // RAW 전체 현상은 메모리를 많이 써서 동시에 2장까지
func fileOrientation(_ path: String) -> Int {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let pr = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return 1 }
    return pr[kCGImagePropertyOrientation as String] as? Int ?? 1
}
// 보정 반영 그림. 색 보정이 있으면 RAW를 맥 엔진으로 현상(노출·화이트밸런스는 엔진 값으로, 대비·하이라이트·섀도·채도·흑백은 필터로 흉내), 회전·자르기만이면 안에 든 미리보기로 빠르게
func editedImage(_ path: String, _ e: CRSEdits, fileOrientation fo: Int, max: Int) -> CGImage? {
    var img: CIImage; let outO = e.orientation ?? fo
    if e.colorEdits {
        rawSem.wait(); defer { rawSem.signal() }
        guard let r = CIRAWFilter(imageURL: URL(fileURLWithPath: path)) else { return nil }
        let long = Swift.max(r.nativeSize.width, r.nativeSize.height)
        r.scaleFactor = Float(Swift.min(1, Double(max) * 1.05 / Double(long)))
        r.exposure = Float(e.exposure)
        if e.wbCustom { r.neutralTemperature = Float(e.temperature); r.neutralTint = Float(e.tint) }
        if let o = e.orientation, let co = CGImagePropertyOrientation(rawValue: UInt32(o)) { r.orientation = co }
        guard var x = r.outputImage else { return nil }
        if e.contrast != 0 || e.saturation != 0 || e.gray { x = x.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + e.contrast / 200, kCIInputSaturationKey: e.gray ? 0 : Swift.max(0, 1 + e.saturation / 100)]) }
        if e.highlights < 0 || e.shadows != 0 { x = x.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": Swift.max(0.0, 1 + e.highlights / 100), "inputShadowAmount": Swift.max(-1.0, Swift.min(1.0, e.shadows / 100))]) }
        if e.vibrance != 0, !e.gray { x = x.applyingFilter("CIVibrance", parameters: ["inputAmount": Swift.max(-1.0, Swift.min(1.0, e.vibrance / 100))]) }
        img = x
    } else {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        var cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageIfAbsent: true, kCGImageSourceThumbnailMaxPixelSize: max, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        if let c = cg, Swift.max(c.width, c.height) < Int(Double(max) * 0.75) { cg = nil }
        if cg == nil { cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) }
        guard let c = cg else { return nil }
        img = CIImage(cgImage: c)
        let d = (CRSEdits.deg(outO) - CRSEdits.deg(fo) + 360) % 360
        if d != 0 { img = img.oriented(d == 90 ? .right : d == 180 ? .down : .left) }
    }
    if let c = e.crop {   // 자르기 값은 원본(센서) 기준 0~1 → 화면 방향으로 바꿔서 적용
        var l = c.l, t = c.t, r = c.r, b = c.b
        switch CRSEdits.deg(outO) { case 180: (l, t, r, b) = (1 - c.r, 1 - c.b, 1 - c.l, 1 - c.t); case 90: (l, t, r, b) = (1 - c.b, c.l, 1 - c.t, c.r); case 270: (l, t, r, b) = (c.t, 1 - c.r, c.b, 1 - c.l); default: break }
        if e.angle != 0 { let E = img.extent; img = img.transformed(by: CGAffineTransform(translationX: E.midX, y: E.midY).rotated(by: CGFloat(-e.angle) * .pi / 180).translatedBy(x: -E.midX, y: -E.midY)) }   // (근사) 기울기 보정
        let E = img.extent
        let rect = CGRect(x: E.minX + l * E.width, y: E.minY + (1 - b) * E.height, width: (r - l) * E.width, height: (b - t) * E.height).integral.intersection(E)
        if rect.width > 2, rect.height > 2 { img = img.cropped(to: rect) }
    }
    return ciCtx.createCGImage(img, from: img.extent)
}

final class RatingStore {
    var map: [String: Int] = [:]
    var dirty = false
    init() {
        if let d = FileManager.default.contents(atPath: storePath), let m = try? JSONSerialization.jsonObject(with: d) as? [String: Int] { map = m }
    }
    static func key(_ it: Item, _ dt: String?) -> String { it.name + it.ext + "|" + (dt ?? "?") }
    func set(_ k: String, _ r: Int) { if r == 0 { map.removeValue(forKey: k) } else { map[k] = r }; dirty = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.save() } }
    func save() {
        guard dirty else { return }; dirty = false
        try? FileManager.default.createDirectory(atPath: (storePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]) { try? d.write(to: URL(fileURLWithPath: storePath), options: .atomic) }
    }
}

// 진단 기록: ~/Library/Logs/Pick.log
func pickLog(_ t: String) {
    let p = home + "/Library/Logs/Pick.log", line = "\(Date()) \(t)\n"
    if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() } else { try? line.write(toFile: p, atomically: true, encoding: .utf8) }
}
final class KeyWindow: NSWindow {
    // 픽이 안 쓰는 키(누르고 있는 Z 등)에 맥이 '삐' 소리 내지 않게
    override func noResponder(for eventSelector: Selector) { if eventSelector != #selector(NSResponder.keyDown(with:)) { super.noResponder(for: eventSelector) } }
    override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }

// MARK: - 캡쳐원: 세션 열기·지금 세션·휴지통·되돌리기·변형 복제
extension C1 {
    static func docPath() -> String? { run("tell application \"Capture One\" to return POSIX path of (path of my curDoc() as alias)")?.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func docName() -> String? { run("tell application \"Capture One\" to return name of my curDoc()")?.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func docDir() -> String? {   /* 세션 폴더(POSIX). 캡쳐원 전용 밖에 있는 세션도 */
        guard let p = run("tell application \"Capture One\" to return POSIX path of (path of my curDoc() as alias)")?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else { return nil }
        var d = p; if d.hasSuffix("/") { d.removeLast() }; if d.hasSuffix(".cosessiondb") { d = (d as NSString).deletingLastPathComponent }
        /* 캡쳐원은 세션의 '부모 폴더'를 돌려줌(확인) → 세션 이름 폴더를 붙임. 그 폴더에 .cosessiondb가 있으면 그것, 아니면 받은 그대로 */
        if let n = docName()?.replacingOccurrences(of: ".cosessiondb", with: ""), FileManager.default.fileExists(atPath: d + "/" + n + "/" + n + ".cosessiondb") { d += "/" + n }
        return d }
    static func openSession(_ path: String) -> Bool { run("tell application \"Capture One\" to open (POSIX file \"\(esc(path))\")") != nil }
    // 삭제 계획: 같은 사진(파일)의 변형 수를 보고, 고른 게 전부면 파일째 휴지통 / 일부면 그 변형만
    // 돌려줌: (휴지통으로 보낼 id들, 변형만 지울 id들과 그 사진에서 남는 다른 변형 id)
    static func planDelete(_ ids: [String]) -> ([String], [(String, String)])? {
        guard let raw = run("""
            tell application "Capture One"
            set d to my curDoc()
            \(vlist(ids))
            set out to ""
            repeat with v in vs
            set sib to id of every variant of (parent image of v)
            set AppleScript's text item delimiters to ","
            set out to out & (id of v) & tab & (sib as text) & linefeed
            set AppleScript's text item delimiters to ""
            end repeat
            return out
            end tell
            """) else { return nil }
        let chosen = Set(ids)
        var whole: [String] = [], part: [(String, String)] = []
        for line in raw.split(separator: "\n") {
            let f = line.components(separatedBy: "\t"); guard f.count == 2 else { continue }
            let sibs = f[1].components(separatedBy: ","), rest = sibs.filter { !chosen.contains($0) }
            if rest.isEmpty { whole.append(f[0]) } else { part.append((f[0], rest[0])) }
        }
        return (whole, part)
    }
    // 변형만 지우기 (파일·다른 복제본은 그대로)
    static func deleteVariants(_ ids: [String]) -> Bool {
        run("""
            tell application "Capture One"
            set d to my curDoc()
            \(vlist(ids))
            repeat with v in vs
            delete (contents of v)
            end repeat
            return "ok"
            end tell
            """) != nil
    }
    // 지운 변형 되살리기: 남은 형제 변형을 복제 → 저장해 둔 보정값·별점 넣기
    static func revive(_ sib: String, snap: String, rating: Int) -> String? {
        guard let nid = run("""
            tell application "Capture One"
            set d to my curDoc()
            set nv to clone variant (first variant of d whose id is "\(esc(sib))")
            set rating of nv to \(rating)
            return id of nv
            end tell
            """)?.trimmingCharacters(in: .whitespacesAndNewlines), !nid.isEmpty else { return nil }
        _ = restore([nid: snap]); return nid
    }
    // 세션 휴지통으로 (캡쳐원 '삭제'와 같음). 되돌리기는 원래 있던 폴더 컬렉션으로
    static func trash(_ ids: [String]) -> String? {
        run("""
            tell application "Capture One"
            set d to my curDoc()
            set src to name of current collection of d
            \(vlist(ids))
            move inside (first collection of d whose name is "Trash") variants vs
            return src
            end tell
            """)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func retrash(_ names: [String]) -> Bool {
        run("""
            tell application "Capture One"
            set d to my curDoc()
            set vs to {}
            repeat with n in {\(names.map { "\"\(esc($0))\"" }.joined(separator: ", "))}
            try
            set end of vs to (first variant of d whose name is (contents of n))
            end try
            end repeat
            if (count of vs) > 0 then move inside (first collection of d whose name is "Trash") variants vs
            return count of vs
            end tell
            """) != nil
    }
    static func untrash(_ names: [String], to folder: String) -> Bool {
        run("""
            tell application "Capture One"
            set d to my curDoc()
            set t to (first collection of d whose name is "Trash")
            set vs to {}
            repeat with n in {\(names.map { "\"\(esc($0))\"" }.joined(separator: ", "))}
            try
            set end of vs to (first variant of t whose name is (contents of n))
            end try
            end repeat
            if (count of vs) > 0 then move inside (first collection of d whose name is "\(esc(folder))") variants vs
            set current collection of d to (first collection of d whose name is "\(esc(folder))")
            return count of vs
            end tell
            """) != nil
    }
    static func clone(_ ids: [String]) -> Bool {
        run("""
            tell application "Capture One"
            set d to my curDoc()
            \(vlist(ids))
            repeat with v in vs
            clone variant (contents of v)
            end repeat
            return "ok"
            end tell
            """) != nil
    }
}

// MARK: - 왼쪽 패널 자료: 캡쳐원 세션 목록·폴더
let sessionsRoot = env["PICK_SESSIONS"] ?? home + "/Desktop/세션"   // 시험 땐 PICK_SESSIONS로 시험 폴더
func sessionList() -> [[String: String]] {
    let fm = FileManager.default
    var out: [[String: String]] = []
    for d in ((try? fm.contentsOfDirectory(atPath: sessionsRoot)) ?? []).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
        let dir = sessionsRoot + "/" + d
        if let f = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).first(where: { $0.hasSuffix(".cosessiondb") }) {
            // 사진 수(Capture 폴더 사진 파일) · 최근에 쓴 시각(세션 파일 수정 시각)
            let n = ((try? fm.contentsOfDirectory(atPath: dir + "/Capture")) ?? []).filter { photoExts.contains(($0 as NSString).pathExtension.lowercased()) }.count
            let t = ((try? fm.attributesOfItem(atPath: dir + "/" + f))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            out.append(["name": d, "path": dir + "/" + f, "count": String(n), "t": String(Int(t))])
        }
    }
    return out.sorted { (Int($0["t"] ?? "") ?? 0) > (Int($1["t"] ?? "") ?? 0) }   // 최근에 쓴 세션이 위로
}
func subfolders(_ path: String) -> [String] {
    let fm = FileManager.default
    return ((try? fm.contentsOfDirectory(atPath: path)) ?? []).filter { n in
        var isDir: ObjCBool = false
        return !n.hasPrefix(".") && !n.hasSuffix(".app") && !n.hasSuffix(".cosessiondb") && fm.fileExists(atPath: path + "/" + n, isDirectory: &isDir) && isDir.boolValue
    }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

func subfolderRows(_ path: String) -> [[Any]] {   // [[이름, 하위폴더 있음 1/0]] — 왼쪽 패널 트리용
    let fm = FileManager.default
    return subfolders(path).map { [$0, fm.displayName(atPath: path + "/" + $0), subfolders(path + "/" + $0).isEmpty ? 0 : 1] }   // [실제 이름, 표시 이름(사용자·응용 프로그램…), 하위 폴더 있음]
}
func diskList() -> [[String: Any]] {   // 꽂힌 디스크: 시동 디스크 먼저, 나머지 이름순. 뺄 수 있는 건 eject=1
    let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsBrowsableKey, .volumeIsRootFileSystemKey]
    var out: [[String: Any]] = []
    for u in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? [] {
        guard let v = try? u.resourceValues(forKeys: keys), v.volumeIsBrowsable ?? true else { continue }
        let root = v.volumeIsRootFileSystem ?? (u.path == "/")
        if !root && !u.path.hasPrefix("/Volumes/") { continue }   // 시스템 내부 마운트(/System/Volumes/…)는 뺌
        let eject = !root && ((v.volumeIsEjectable ?? false) || (v.volumeIsRemovable ?? false) || !(v.volumeIsInternal ?? true))
        out.append(["name": v.volumeName ?? (u.lastPathComponent), "path": u.path, "eject": eject ? 1 : 0, "root": root ? 1 : 0])
    }
    return out.sorted { a, b in
        if (a["root"] as! Int) != (b["root"] as! Int) { return (a["root"] as! Int) > (b["root"] as! Int) }
        return (a["name"] as! String).localizedStandardCompare(b["name"] as! String) == .orderedAscending }
}

// 폴더 방식 영구 썸네일 캐시: ~/Library/Caches/Pick/folders/<해시>_s.jpg (420px) · _m.jpg (900px). 해시 = 경로+수정시각+크기
let folderCacheDir = cacheRoot + "/folders"
let folderCacheDays = 30.0, folderCacheBytes: Int64 = 2 * 1024 * 1024 * 1024   // 30일 안 본 건 지움 · 전체 2GB 넘으면 오래된 것부터
func folderCacheKey(_ path: String, sig: String = "") -> String? {   // sig = 보정값 요약 (보정된 RAW는 보정이 바뀌면 새 썸네일)
    guard let a = try? FileManager.default.attributesOfItem(atPath: path), let m = a[.modificationDate] as? Date, let sz = a[.size] as? Int64 else { return nil }
    let d = SHA256.hash(data: Data("\(path)|\(Int(m.timeIntervalSince1970))|\(sz)\(sig.isEmpty ? "" : "|" + sig)".utf8))
    return d.map { String(format: "%02x", $0) }.joined().prefix(24).description
}
func folderCached(_ path: String, _ kind: String, sig: String = "", _ make: () -> Data?) -> Data? {
    guard let k = folderCacheKey(path, sig: sig) else { return make() }
    let fm = FileManager.default, f = folderCacheDir + "/" + k + "_" + kind + ".jpg"
    if let d = fm.contents(atPath: f) {
        if let m = mtime(f), Date().timeIntervalSince(m) > 86400 { try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: f) }   // 본 날짜 갱신 (하루 한 번)
        return d }
    guard let d = make() else { return nil }
    try? fm.createDirectory(atPath: folderCacheDir, withIntermediateDirectories: true)
    try? d.write(to: URL(fileURLWithPath: f), options: .atomic)
    return d
}
// 켤 때 뒤에서: 끌기용 임시 폴더(drag-*)는 하루 지난 것, 세션 미리보기 캐시는 60일 안 쓴 것 삭제 (전엔 끌기 때만 정리해 1.5GB가 남아 있었음, 2026-11-04)
func cleanStaleCaches() {
    let fm = FileManager.default
    for d in (try? fm.contentsOfDirectory(atPath: cacheRoot)) ?? [] where d != "folders" {
        let p = cacheRoot + "/" + d; var isDir: ObjCBool = false
        guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue, let t = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date else { continue }
        let age = Date().timeIntervalSince(t)
        if d.hasPrefix("drag-") ? age > 86400 : age > 60 * 86400 { try? fm.removeItem(atPath: p); pickLog("캐시 정리: \(d) (\(Int(age / 86400))일)") }
    }
}
func cleanFolderCache() {   // 켤 때 뒤에서: 30일 지난 것 삭제, 2GB 넘으면 오래된 것부터
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: folderCacheDir) else { return }
    var files: [(String, Date, Int64)] = []
    for n in names { let p = folderCacheDir + "/" + n; if let a = try? fm.attributesOfItem(atPath: p), let m = a[.modificationDate] as? Date, let sz = a[.size] as? Int64 { files.append((p, m, sz)) } }
    var total: Int64 = 0, removed = 0
    for f in files { if Date().timeIntervalSince(f.1) > folderCacheDays * 86400 { try? fm.removeItem(atPath: f.0); removed += 1 } else { total += f.2 } }
    if total > folderCacheBytes { for f in files.sorted(by: { $0.1 < $1.1 }) where total > folderCacheBytes { if fm.fileExists(atPath: f.0) { try? fm.removeItem(atPath: f.0); total -= f.2; removed += 1 } } }
    if removed > 0 { pickLog("폴더 썸네일 캐시 정리: \(removed)개 지움, 남은 용량 \(total / 1024 / 1024)MB") }
}

// MARK: - 앱
final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKURLSchemeHandler {
    var win: NSWindow!
    var web: PickWebView?
    var hint: NSTextField!, splash: NSView!, splashParts: (NSView, NSTextField)?
    func layoutSplash() { guard let (b, l) = splashParts, let s = splash else { return }; let c = NSPoint(x: s.bounds.midX, y: s.bounds.midY)
        l.frame.origin = NSPoint(x: c.x - l.frame.width / 2, y: c.y - l.frame.height / 2 + 6)
        b.frame = NSRect(x: c.x - 280, y: c.y - 120, width: 560, height: 240) }
    func hideSplash() { guard let s = splash, s.alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.45; s.animator().alphaValue = 0 }, completionHandler: { s.isHidden = true }) }
    func reveal(_ w: NSView) {   // 화면 페이드 인 + 로고 페이드 아웃 (교차)
        if let o = overlay { o.removeFromSuperview(); overlay = nil; hideSplash(); return }   // 폴더 바꿈: 새 화면이 그려진 순간 덮개를 걷음 (전환 화면 없음)
        guard w.alphaValue < 1 else { return }
        if let o = oldWeb { w.alphaValue = 1; o.removeFromSuperview(); oldWeb = nil; hideSplash(); return }
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.3; w.animator().alphaValue = 1 }); hideSplash() }
    // 도움말: 별도 창 (ui/help.html). ? 또는 아래 ? 단추로 열고 닫음, 창 안에서 Esc·?로 닫음
    var helpWin: NSWindow?
    func showHelp(_ on: Bool?) {
        if helpWin == nil {
            let cfg = WKWebViewConfiguration(); cfg.setURLSchemeHandler(self, forURLScheme: "pick"); cfg.userContentController.add(self, name: "pick")
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 760), configuration: cfg); wv.autoresizingMask = [.width, .height]
            wv.load(URLRequest(url: URL(string: "pick://app/help.html")!))
            let hw = NSPanel(contentRect: wv.frame, styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)   /* 포커스를 뺏지 않는 패널 → 픽 창에서 ? 키·단추가 그대로 먹힘 */
            hw.title = "Pick 도움말"; hw.contentView = wv; hw.isReleasedWhenClosed = false; hw.minSize = NSSize(width: 380, height: 400); hw.becomesKeyOnlyIfNeeded = true; hw.isFloatingPanel = true
            if let w = win { hw.setFrameOrigin(NSPoint(x: w.frame.maxX - 480, y: w.frame.maxY - 790)) }
            helpWin = hw
        }
        guard let hw = helpWin else { return }
        let want = on ?? !hw.isVisible
        if want { hw.orderFront(nil) } else { hw.orderOut(nil) }
    }
    func showSplash() { guard let s = splash else { return }; s.isHidden = false; s.alphaValue = 1; layoutSplash() }
    var mode = "c1"                       // "c1" 캡쳐원 연결 · "folder" 폴더
    var testC1Lock = false                // 시험 스크립트 실행 중 실제 캡쳐원 세션이 열려 있으면 true → 세션 모드 진입 차단
    var doc = "", items: [Item] = [], byN: [String: Int] = [:], byID: [String: Int] = [:], keys: [String: String] = [:]
    var cacheDir = ""
    var announced = Set<String>(), expected = Set<String>()
    var timer: Timer?
    let thumbs = NSCache<NSString, NSData>()
    let ioq = DispatchQueue(label: "pick.io", qos: .userInitiated, attributes: .concurrent)
    let store = RatingStore()
    var openedWithFolder = false
    var folderPath = ""                       // 폴더 방식일 때 연 폴더
    var docWatch: Timer?, switching = false   // 캡쳐원에서 세션을 바꾸면 따라감
    var trashed: [Int: (String, [String], [String])] = [:]   // 삭제 되돌리기: 토큰 → (원래 폴더 컬렉션 / 이름들 / 폴더 방식이면 휴지통 경로)
    var c1Trashed: [Int: (String, [String])] = [:]   // C1.q 에서만 씀
    // 캡쳐원 자체 실행 취소로 되돌리기: 픽이 캡쳐원을 바꾼 횟수(c1Mut)와 삭제 기록
    var c1Mut = 0
    // 픽이 캡쳐원을 바꾼 일의 순서 (화면을 다시 불러와도 남음). del = 통째로 세션 휴지통에 옮긴 삭제(캡쳐원 기록에 안 남아 픽이 직접 되돌림)
    var opStack: [(String, Int)] = [], redoStack: [(String, Int)] = [], lastUndoKind = ""
    let useC1MenuDelete = false   /* 손쉬운 사용 권한이 필요한 메뉴 누르기 경로 — 끔 (픽에 삭제 기능이 없어 호출도 안 됨). 권한을 묻지 않게 */
    var c1Undo: [Int: (mut: Int, at: Date, ids: [String], names: [String: String])] = [:]
    var madeFiles = Set<String>()   // 꺼내기로 만든 파일 (⌘Z 취소 때 이것만 휴지통으로)
    let dragOut = DragOut()
    var c1Revive: [Int: [(String, String, String, Int)]] = [:]   // 변형만 지운 것 되살리기용 (원래 id, 형제 id, 보정값, 별점)
    // 되살린 변형은 id가 새로 생겨서 목록을 다시 불러옴 (지금 보던 사진 근처 유지는 안 함)
    func remapIDs(_ m: [String: String]) {
        var js: [String: String] = [:]
        for (old, nid) in m { guard let k = byID[old] else { continue }; items[k].id = nid; byID[old] = nil; byID[nid] = k; js[items[k].n] = nid }
        if let d = try? JSONSerialization.data(withJSONObject: js), let t = String(data: d, encoding: .utf8) { self.js("PickApp.remap(\(t))") }
    }
    func reloadSoon() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if self.mode == "c1" { self.openC1() } } }

    func applicationWillFinishLaunching(_ n: Notification) {
        buildMenu()
        win = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 1500, height: 950), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true; win.titleVisibility = .hidden; win.title = "Pick"
        win.minSize = NSSize(width: 900, height: 600); win.center(); win.setFrameAutosaveName("PickMain")
        win.backgroundColor = .windowBackgroundColor
        let drop = DropView(frame: win.contentView!.bounds); drop.autoresizingMask = [.width, .height]; drop.onFolder = { [weak self] p in self?.openFolder(p) }
        win.contentView = drop
        if let u = Bundle.main.resourceURL?.appendingPathComponent("ui/fonts/GowunDodum-Regular.ttf") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }   // 네이티브 글자도 앱 글꼴로
        hint = NSTextField(labelWithString: ""); hint.textColor = .secondaryLabelColor; hint.font = NSFont(name: "GowunDodum-Regular", size: 14) ?? .systemFont(ofSize: 14); hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        drop.addSubview(hint)
        NSLayoutConstraint.activate([hint.centerXAnchor.constraint(equalTo: drop.centerXAnchor), hint.centerYAnchor.constraint(equalTo: drop.centerYAnchor, constant: 150)])
        // 켜질 때 로고: 'Pick' 글씨 뒤에 코랄 블러셔 (앱 안 선택 표시와 같은 느낌). 화면이 뜨면 서서히 사라짐
        splash = NSView(frame: drop.bounds); splash.autoresizingMask = [.width, .height]; splash.wantsLayer = true
        let blush = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 240)); blush.wantsLayer = true
        blush.layer?.backgroundColor = NSColor(red: 0.953, green: 0.761, blue: 0.698, alpha: 1).cgColor; blush.layer?.cornerRadius = 120   // --pl1 #f3c2b2
        blush.layer?.masksToBounds = false
        let blur = CIFilter(name: "CIGaussianBlur"); blur?.setValue(55, forKey: kCIInputRadiusKey); blush.layerUsesCoreImageFilters = true; blush.layer?.filters = blur.map { [$0] }
        let logo = NSTextField(labelWithString: "Pick"); logo.font = NSFont(name: "Noteworthy-Light", size: 96) ?? .systemFont(ofSize: 92, weight: .light)   // 시작 로고 글씨체: Noteworthy (사용자 선택)
        logo.textColor = NSColor(red: 0.541, green: 0.275, blue: 0.204, alpha: 1); logo.alignment = .center; logo.sizeToFit()   // --acctx #8a4634
        splash.addSubview(blush); splash.addSubview(logo); splashParts = (blush, logo)
        drop.addSubview(splash)
        layoutSplash()
    }
    // 처음 켜는 맥에서도 바로 쓰게: 데스크톱에 '세션' 폴더를 만들고 캡쳐원 모양 흰 폴더 아이콘(Resources/c1folder.png)을 입힘 (이미 아이콘이 있으면 그대로)
    func ensureSessionsRoot() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: sessionsRoot) { try? fm.createDirectory(atPath: sessionsRoot, withIntermediateDirectories: true) }
        guard !fm.fileExists(atPath: sessionsRoot + "/Icon\r"), let p = Bundle.main.path(forResource: "c1folder", ofType: "png"), let src = NSImage(contentsOfFile: p) else { return }
        let icon = NSImage(size: NSSize(width: 512, height: 512))
        for px in [512, 256, 128, 64, 32, 16] {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: 512, height: 512)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep); NSGraphicsContext.current?.imageInterpolation = .high
            src.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512)); NSGraphicsContext.restoreGraphicsState(); icon.addRepresentation(rep) }
        NSWorkspace.shared.setIcon(icon, forFile: sessionsRoot, options: [])
    }
    var clipPaths: [String] = []
    var moved: [Int: [(String, String, Bool)]] = [:]   // 폴더로 옮기기 되돌리기: 토큰 → (원래 자리, 새 자리, 복사였나)
    // 맥 기본 입력 대화상자 (이름 입력). 취소면 nil
    func askText(_ title: String, _ msg: String, _ initial: String, ok: String) -> String? {
        if let t = env["PICK_TESTANSWER"] { return t }   // 시험용: 대화상자 없이 정해진 답
        let a = NSAlert(); a.messageText = title; a.informativeText = msg; a.addButton(withTitle: ok); a.addButton(withTitle: "취소")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); tf.stringValue = initial; a.accessoryView = tf; a.window.initialFirstResponder = tf
        while true {
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return nil }
            let v = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if v.isEmpty { continue }
            if v.contains("/") || v.contains(":") { a.informativeText = "/ 나 : 는 쓸 수 없어요"; continue }
            return v
        }
    }
    func askNewSession() {   // ＋ 새 세션: 맥 대화상자. 적는 동안 바로 검사 → 문제 있으면 칸 아래 주황 글씨 + '만들기' 흐리게 (2026-11-07 사용자 요청)
        guard C1.running else { toast("캡쳐원이 꺼져 있어요 · 캡쳐원을 켠 뒤 다시 해 주세요"); return }
        let names = Set(sessionList().compactMap { $0["name"]?.precomposedStringWithCanonicalMapping })
        let a = NSAlert(); a.messageText = "새 세션"; a.informativeText = "위치: 데스크톱 › \((sessionsRoot as NSString).lastPathComponent.precomposedStringWithCanonicalMapping)\n만들면 캡쳐원이 이 세션을 열어요"; a.addButton(withTitle: "만들기"); a.addButton(withTitle: "취소")
        let tf = NSTextField(frame: NSRect(x: 0, y: 20, width: 260, height: 24)); tf.stringValue = ""; tf.placeholderString = "세션 이름"   // 기본값 빈칸
        let warn = NSTextField(labelWithString: ""); warn.frame = NSRect(x: 1, y: 0, width: 260, height: 16); warn.font = .systemFont(ofSize: 11); warn.textColor = .systemOrange
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 44)); box.addSubview(tf); box.addSubview(warn)
        a.accessoryView = box; a.window.initialFirstResponder = tf
        let make = a.buttons[0]
        func problem() -> String? {   // nil = 만들 수 있음 · "" = 빈칸(문구 없이 흐리게만)
            let v = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if v.isEmpty { return "" }
            if v.contains("/") || v.contains(":") { return "/ 나 : 는 쓸 수 없어요" }
            if names.contains(v.precomposedStringWithCanonicalMapping) { return "이미 있는 세션이에요" }
            return nil
        }
        func update() { let p = problem(); warn.stringValue = p ?? ""; make.isEnabled = p == nil }
        update()
        let obs = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: tf, queue: nil) { _ in update() }   // queue nil = 모달 중에도 바로
        defer { NotificationCenter.default.removeObserver(obs) }
        while true {
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
            if problem() != nil { update(); continue }   // 흐린 버튼이 어떻게든 눌려도 만들지 않음
            createSession(tf.stringValue.trimmingCharacters(in: .whitespaces)); return
        }
    }
    func createSession(_ name: String) {   // 캡쳐원 전용 안에 만들고 캡쳐원·픽에서 바로 엶
        guard !name.isEmpty, !name.contains("/"), !name.contains(":") else { toast("이름에 / 나 : 는 쓸 수 없어요"); return }
        guard !FileManager.default.fileExists(atPath: sessionsRoot + "/" + name) else { toast("이미 있는 세션이에요"); return }
        if !C1.running { toast("캡쳐원이 꺼져 있어요"); return }
        try? FileManager.default.createDirectory(atPath: sessionsRoot, withIntermediateDirectories: true)
        switching = true; hint.stringValue = "캡쳐원에서 '\(name.precomposedStringWithCanonicalMapping)' 세션 만드는 중…"; reset()
        C1.q.async {
            let ok = C1.run("""
                with timeout of 600 seconds
                tell application "Capture One"
                set oldDocs to every document
                make new document with properties {name:"\(C1.esc(name))", path:(POSIX file "\(C1.esc(sessionsRoot))"), kind:session}
                repeat with d in oldDocs
                try
                save d
                close d
                end try
                end repeat
                end tell
                end timeout
                """) != nil
            var opened = false
            if ok { for _ in 0..<40 { if C1.docName()?.hasPrefix(name) == true { opened = true; break }; Thread.sleep(forTimeInterval: 0.5) } }
            DispatchQueue.main.async { self.switching = false; if opened { self.openC1() } else { self.hint.stringValue = "세션을 만들지 못했어요"; self.toast("세션을 만들지 못했어요") } }
        }
    }
    @objc func menuNewSession() { askNewSession() }
    func applicationDidFinishLaunching(_ n: Notification) {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in   // 픽으로 돌아오면: 캡쳐원이 앞에 있는 동안 미뤄 둔 조정값·전체 대조를 바로
            guard let self, self.mode == "c1" else { return }
            self.evRead?.cancel(); self.adjWaiting = false; self.evPending = true; self.lastFast = .distantPast; self.lastFull = .distantPast; self.syncTick() }
        if env["PICK_SESSIONS"] == nil { ensureSessionsRoot() }   // 시험 폴더(PICK_SESSIONS)일 땐 건드리지 않음
        watchDoc()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { cleanFolderCache(); cleanStaleCaches() }
        C1.refreshPid(); Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in C1.refreshPid() }
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if env["PICK_TESTJS"] != nil { pickLog("mainwin \(win.windowNumber)") }   // 시험: 창 번호(screencapture -l 용)
        let a = CommandLine.arguments
        if env["PICK_TESTJS"] != nil {   // 안전장치: 시험 스크립트는 시험 폴더(스크래치패드·작업중·/tmp)에서만. 실제 폴더·캡쳐원 세션에선 안 돎
            let path = a.firstIndex(of: "--fake").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } ?? ""
            let testDir = { (p: String) in p.hasPrefix("/private/tmp/") || p.hasPrefix("/tmp/") || p.hasPrefix(home + "/Desktop/cc/작업중/") }
            let c1Doc = C1.running ? (C1.docPath() ?? "") : ""   // 캡쳐원 모드 시험: 지금 캡쳐원에 열린 세션이 시험 폴더 안에 있을 때만 (실제 세션이면 거부)
            let ok = !path.isEmpty && testDir(path)
            if !ok { pickLog("시험 거부: 시험 폴더가 아님 (\(path))"); NSApp.terminate(nil); return }
            testC1Lock = !(c1Doc.isEmpty || testDir(c1Doc))   // 캡쳐원에 실제 세션이 열려 있으면: 폴더 시험은 되지만 캡쳐원 세션은 열지 않음 (openC1·openSession 차단)
            if testC1Lock { pickLog("시험: 캡쳐원에 실제 세션(\(c1Doc))이 열려 있어 세션 모드는 잠금") }
        }
        if let i = a.firstIndex(of: "--fake"), i + 1 < a.count { openFolder(a[i + 1]); return }
        // 디스크를 꽂거나 빼면 왼쪽 패널에 바로 반영. 보고 있던 폴더의 디스크를 빼면 데스크톱으로
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard let self else { return }
                self.js("PickApp.disks(\(self.json(diskList())))")
                if name == NSWorkspace.didUnmountNotification, self.mode == "folder", let p = (n.userInfo?["NSDevicePath"] as? String), !p.isEmpty, self.folderPath.hasPrefix(p + "/") || self.folderPath == p { self.openFolder(home + "/Desktop") }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {   // 폴더를 끌어 놓아서 켜졌거나 캡쳐원 메뉴(pick://c1)로 켜졌으면 그쪽이 먼저
            guard !self.openedWithFolder else { return }
            self.openFolder(home + "/Desktop")   // 브릿지처럼 데스크톱 폴더로 시작 (사진이 없어도 화면은 뜸)
        }
    }
    // Dock 아이콘·Finder '다음으로 열기'로 폴더 · 캡쳐원 스크립트 메뉴에서 pick://c1 → 지금 열린 세션 연결
    func application(_ a: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "pick" && $0.host == "c1" }) { openedWithFolder = true; if C1.running { openC1() } else { openFolder(home + "/Desktop"); toast("캡쳐원이 꺼져 있어요") }; return }
        if let u = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }) { openedWithFolder = true; openFolder(u.path) }
    }

    var oldWeb: PickWebView?, loadGen = 0, folderT0 = Date(), overlay: NSImageView?   // overlay: 같은 웹뷰로 다시 불러오는 동안 덮어 두는 이전 화면 스냅샷   // oldWeb: 새 폴더 화면이 그려질 때까지 남겨 두는 이전 화면 · loadGen: 늦게 끝난 이전 불러오기가 덮어쓰지 않게
    func reset(keepWeb: Bool = false) {
        timer?.invalidate(); timer = nil; syncTimer?.invalidate(); syncTimer = nil
        // 미리보기는 지우지 않음 (다시 열 때 바뀐 것만 새로 만듦 — 전엔 열 때마다 전부 다시 만들어 캡쳐원 대기열이 수천 개로 쌓였음)
        if keepWeb, let w = web { oldWeb?.removeFromSuperview(); oldWeb = w; web = nil }   // 폴더 → 폴더: 로고 화면 없이 이전 화면 유지
        else { oldWeb?.removeFromSuperview(); oldWeb = nil; overlay?.removeFromSuperview(); overlay = nil; web?.removeFromSuperview(); web = nil; showSplash() }
        items = []; byN = [:]; byID = [:]; keys = [:]; announced = []; expected = []; cacheDir = ""; thumbs.removeAllObjects(); docDirCache = ""
    }
    func watchDoc() { startSync() }
    // 캡쳐원 ↔ 픽 동기화 루프 (0.25초마다 깨어나되 한 번에 하나씩):
    //  · 매초 빠른 읽기: 세션 바뀜 / 정렬·직접 순서 / 새 사진(테더링) — 늘
    //  · 캡쳐원을 쓰는 동안(앞에 있을 때 + 4초): 별점·태그·크롭 전체 + 선택한 사진 조정값도 매초 → 바뀐 사진 다시 그림
    //  · 캡쳐원을 쓰는 동안 8초마다: 전체 조정값 한 번 (안전장치)
    var syncTimer: Timer?, syncBusy = false, lastFast = Date.distantPast, lastFull = Date.distantPast, collNoted = false
    var selPending: [String]?, lastC1Sel = Set<String>(), pushedSel = Set<String>(), c1Order: [String] = []   // 선택 동기화
    var pushAt = Date.distantPast   // 픽이 마지막으로 선택을 보낸 때
    var jumpPairs: [Set<String>] = [], jumpPairsMain: [Set<String>] = []   // jumpPairsMain: 메인 스레드용 사본   // 픽에서 뛰어 고른 {옛,새} 쌍 (캡쳐원 기록이 2개라 되돌릴 때 한 번에 두 단계) — C1.q에서만
    var adjLast: [String: Int] = [:], cropLast: [String: Int] = [:]
    var editLast: [String: Int] { var m: [String: Int] = [:]; for (k, a) in adjLast { m[k] = a &+ (cropLast[k] ?? 0) &* 31 }; return m }   // 미리보기 기록용 합친 지문
    var editPending = Set<String>(), editQuiet: DispatchWorkItem?, editAllSel = false, editNotifyAt = Date(), redrawT0: [String: Date] = [:]
    // 캡쳐원 알림 스크립트: 선택·보정·촬영이 바뀌는 순간 캡쳐원이 이 파일들을 건드림 → 픽이 바로 반응 (1초 기다릴 필요 없음)
    let evDir = cacheRoot + "/ev"
    var evSrcs: [DispatchSourceFileSystemObject] = [], evSeen: [String: Date] = [:]
    func installHooks() {
        try? FileManager.default.createDirectory(atPath: evDir, withIntermediateDirectories: true)
        for n in ["sel", "adj", "cap"] where !FileManager.default.fileExists(atPath: evDir + "/" + n) { FileManager.default.createFile(atPath: evDir + "/" + n, contents: nil) }   // 있으면 그대로 (새로 만들면 감시 중인 파일이 옛것이 됨)
        let d = evDir
        guard C1.running else { return }   // 캡쳐원이 꺼져 있으면 건드리지 않음 (켜 버리지 않게)
        C1.q.async {
            // 알림 본문은 캡쳐원이 자체 컴파일하므로 문자열로 조립해 넘김 (여러 줄은 linefeed로 이어 붙임)
            /* 빈 세션·선택 없음이면 빈 목록을 text로 못 바꿔 캡쳐원이 오류 창을 띄움 → try로 감싸고 빈 글자로 */
            let selBody = ["set AppleScript's text item delimiters to \",\"", "set theIds to \"\"", "try", "tell application \"Capture One\"", "set theList to (id of (variants of current document whose selected is true))", "if (count of theList) > 0 then set theIds to theList as text", "end tell", "end try", "do shell script \"printf %s '\" & theIds & \"' > '\(d)/sel'\""]
            let adjBody = ["tell application \"Capture One\"", "set theId to \"\"", "try", "set theId to id of primary variant of current document", "end try", "end tell", "do shell script \"printf %s '\" & theId & \"' > '\(d)/adj'\""]
            func lit(_ lines: [String]) -> String { lines.map { "\"" + C1.esc($0) + "\"" }.joined(separator: " & linefeed & ") }
            _ = C1.run("tell application \"Capture One\"\nset selection changed script to \(lit(selBody))\nset primary variant adjusted script to \(lit(adjBody))\ntry\nset capture done script to \"do shell script \\\"/usr/bin/touch '\(d)/cap'\\\"\"\nend try\nend tell")
        }
        if evSrcs.isEmpty {   // 파일마다 따로 감시 (폴더 감시로는 touch가 안 잡힘)
            for n in ["sel", "adj", "cap"] {
                let fd = open(evDir + "/" + n, O_EVTONLY); guard fd >= 0 else { continue }
                let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .attrib, .extend], queue: .main)
                src.setEventHandler { [weak self] in self?.evFired() }
                src.setCancelHandler { close(fd) }
                src.resume(); evSrcs.append(src)
            }
        }
    }
    func removeHooks() {
        guard C1.running else { return }
        _ = C1.run("tell application \"Capture One\"\nset selection changed script to \"\"\nset primary variant adjusted script to \"\"\ntry\nset capture done script to \"\"\nend try\nend tell")
    }
    var lastSelEv = Date.distantPast, evRead: DispatchWorkItem?
    var evPending = false, adjWaiting = false, evLogOn = ProcessInfo.processInfo.environment["PICK_EVLOG"] != nil
    func evFired() {
        var what = Set<String>()
        for n in ["sel", "adj", "cap"] {
            if let t = (try? FileManager.default.attributesOfItem(atPath: evDir + "/" + n))?[.modificationDate] as? Date, t != evSeen[n] { evSeen[n] = t; what.insert(n) }
        }
        guard !what.isEmpty, mode == "c1", !switching else { return }
        if evLogOn { pickLog("캡쳐원 알림: \(what.sorted().joined(separator: ","))") }
        // 선택 동기화는 하지 않음 (2026-11-01 사용자 결정) — 선택 알림은 목록 변화 확인 계기로만 씀
        let now = Date()
        if what.contains("sel") { lastSelEv = now }
        let realAdj = what.contains("adj") && now.timeIntervalSince(lastSelEv) > 0.4   // 선택이 바뀌면 대표 변형도 바뀌어 보정 알림이 같이 옴 → 그건 보정이 아님
        if realAdj || what.contains("cap") { evRead?.cancel(); let w = DispatchWorkItem { [weak self] in self?.adjWaiting = false; self?.evPending = true; self?.lastFast = .distantPast; self?.syncTick() }; evRead = w
            let c1Front = (NSWorkspace.shared.frontmostApplication?.localizedName ?? "").hasPrefix("Capture One")
            let delay = what.contains("cap") ? 0.15 : (c1Front ? 2.5 : 0.15); adjWaiting = realAdj && c1Front   // 캡쳐원이 앞이면 스타일 커서 미리보기를 끊지 않게 2.5초 조용해진 뒤에, 픽으로 돌아오면 바로
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w) }
        else if what.contains("sel") { evRead?.cancel(); let w = DispatchWorkItem { [weak self] in self?.lastFast = .distantPast; self?.syncTick() }; evRead = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w) }   // 조용해지면 목록 확인(캡쳐원에서 지운 것 등)
    }
    func startSync() {
        if ProcessInfo.processInfo.environment["PICK_QSTEST"] != nil { for _ in 0..<3 { let t = Date(); let r = C1.quickSelection(); pickLog("빠른 선택 읽기 \(Int(Date().timeIntervalSince(t) * 1000))ms → \(r?.sorted() ?? [])") } }
        syncTimer?.invalidate(); syncTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.syncTick() }; installHooks() }
    func watchEdits() { adjLast = [:]; cropLast = [:]; editPending = [] }
    var c1Was = false
    func syncTick() {
        let run = C1.running
        if run != c1Was { c1Was = run; if run, mode == "c1" { installHooks() } }   // 캡쳐원을 다시 켰으면 알림 스크립트도 다시 걸어 둠
        guard mode == "c1", !switching, !syncBusy, !loading, run else { return }
        if (NSWorkspace.shared.frontmostApplication?.localizedName ?? "").hasPrefix("Capture One") { c1FrontAt = Date() }
        let c1Front = Date().timeIntervalSince(c1FrontAt) < 4
        let editing = c1Front || evPending
        let now = Date()
        if editing, !c1Front || evPending, now.timeIntervalSince(lastFull) >= 8 {   // 캡쳐원이 앞에 있는 동안은 전체 대조를 쉼 (스타일 미리보기 보호) → 픽으로 돌아오면 바로
            syncBusy = true; lastFull = now
            C1.q.async { let g = C1.fullSigs(); DispatchQueue.main.async { self.syncBusy = false; if let g { self.applySigs(g, full: true) } } }
            return
        }
        guard editing || now.timeIntervalSince(lastFast) >= (now.timeIntervalSince(c1FrontAt) < 4 ? 1 : 2.5) else { return }
        syncBusy = true; lastFast = now; let fromEvent = evPending; evPending = false
        C1.q.async {
            guard let f = C1.fastRead(edits: editing, light: c1Front && !fromEvent) else { DispatchQueue.main.async { self.syncBusy = false }; return }   // 캡쳐원이 앞이면 별점·태그만, 조정 알림을 기다렸다 읽을 때만 조정값까지
            // 목록 차이: 처음 보는 id(새 사진·되살아난 사진) / 사라진 id(캡쳐원에서 지움) — 세션 이름이 픽과 같을 때만
            let (fresh, missing, total) = DispatchQueue.main.sync { () -> ([String], Int, Int) in
                guard f.doc == self.doc, !self.items.isEmpty else { return ([], 0, 0) }
                let now = Set(f.ids)
                let returned = self.items.contains { $0.gone0 && now.contains($0.id) }   // 숨겨 둔 사진이 다시 보임
                return (f.ids.filter { self.byID[$0] == nil } + (returned ? ["<back>"] : []), self.items.filter { !$0.gone0 && !now.contains($0.id) }.count, self.items.count) }
            // 캡쳐원에서 다른 컬렉션(휴지통·앨범 등)을 보는 중이면 대부분이 사라진 걸로 보임 → 건드리지 않음
            let switched = total >= 5 && missing >= Int(Double(total) * 0.8) && fresh.count < total / 4
            if switched { DispatchQueue.main.async { self.syncBusy = false }; if !self.collNoted { self.collNoted = true; pickLog("캡쳐원이 다른 컬렉션을 보는 중 → 목록 비교 쉼") }; return }
            self.collNoted = false
            if (!fresh.isEmpty || missing > 0) && !f.sort.isEmpty { self.resyncC1(); DispatchQueue.main.async { self.syncBusy = false }; return }   // 지운 사진 숨김·되살아난 사진 복귀·새 사진 추가
            let add: [Item] = []
            DispatchQueue.main.async {
                self.syncBusy = false
                guard self.mode == "c1", !self.switching, !self.loading else { return }   // 불러오는 중에 시작된 읽기 결과는 버림
                if !f.doc.isEmpty, !self.doc.isEmpty, f.doc != self.doc { pickLog("캡쳐원 세션 바뀜 → \(f.doc)"); self.opStack = []; self.redoStack = []; self.openC1(); return }
                if self.items.isEmpty, !f.ids.isEmpty { self.openC1(); return }   // 빈 세션에 첫 사진
                if !add.isEmpty { self.addCaptured(add) }
                let sig = f.sort + "\(f.rev)" + f.ids.joined(separator: ",")
                if !f.sort.isEmpty, sig != self.orderSig { self.orderSig = sig; self.js("PickApp.order(\(self.json(["sort": f.sort, "rev": f.rev, "ids": f.ids])))") }
                self.c1Order = f.ids
                if editing { self.applySigs(f.sigs, full: false); self.lastC1Sel = f.sigs.sel }   // 선택은 따라가지 않음(사용자 결정)
            }
        }
    }
    // 읽어 온 값과 비교: 별점·태그는 바로 반영, 조정값·크롭이 바뀐 사진은 0.7초 뒤 다시 그림
    func applySigs(_ g: C1.Sigs, full: Bool) {
        var rt: [String: Any] = [:]
        for (id, v) in g.r { if let k = byID[id], items[k].r != v { items[k].r = v; var m = rt[items[k].n] as? [String: Int] ?? [:]; m["r"] = v; rt[items[k].n] = m } }
        for (id, v) in g.t { if let k = byID[id], items[k].t != v { items[k].t = v; var m = rt[items[k].n] as? [String: Int] ?? [:]; m["t"] = v; rt[items[k].n] = m } }
        if !rt.isEmpty { js("PickApp.synced(\(json(rt)))"); pickLog("캡쳐원 별점·태그 반영: \(rt.count)장") }
        var changed = Set<String>(), selChanged = false
        for (id, v) in g.adj { if let old = adjLast[id], old != v, byID[id] != nil { changed.insert(id); if g.sel.contains(id) { selChanged = true } }; adjLast[id] = v }
        for (id, v) in g.crop { if let old = cropLast[id], old != v, byID[id] != nil { changed.insert(id) }; cropLast[id] = v }
        guard !changed.isEmpty else { return }
        editPending.formUnion(changed); if selChanged { editAllSel = true }
        editQuiet?.cancel(); editNotifyAt = Date()
        let w = DispatchWorkItem { [weak self] in self?.redrawEdited() }
        editQuiet = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)   /* 전 0.7초 */
    }
    var c1FrontAt = Date.distantPast
    // 캡쳐원 ⌘Z로 되돌리기 (C1.q에서 부름). 조건: 지운 뒤 픽이 캡쳐원을 바꾼 일 없음 + 사용자가 캡쳐원을 쓰지 않음 + 손쉬운 사용 권한
    func undoInC1(_ u: (mut: Int, at: Date, ids: [String], names: [String: String])) -> Set<String> {
        let (mut, front) = DispatchQueue.main.sync { (self.c1Mut, self.c1FrontAt) }
        guard mut == u.mut + 1, front < u.at else { pickLog("되돌리기: 캡쳐원 실행 취소 못 씀(그 뒤 다른 변경 있음) → 복제본으로"); return [] }
        guard AXIsProcessTrusted() else { pickLog("되돌리기: 손쉬운 사용 권한 없음 → 복제본으로"); DispatchQueue.main.async { self.askAccessibility() }; return [] }
        let ids0 = Set((C1.run("tell application \"Capture One\"\nset AppleScript's text item delimiters to linefeed\nreturn (id of every variant of my curDoc()) as text\nend tell") ?? "").split(separator: "\n").map(String.init))
        DispatchQueue.main.sync {
            NSWorkspace.shared.runningApplications.first { ($0.localizedName ?? "").hasPrefix("Capture One") }?.activate()
        }
        Thread.sleep(forTimeInterval: 0.35)
        let src = CGEventSource(stateID: .hidSystemState)
        for _ in u.ids {   // 지운 변형 수만큼 ⌘Z
            let d = CGEvent(keyboardEventSource: src, virtualKey: 6, keyDown: true)!; d.flags = .maskCommand; d.post(tap: .cghidEventTap)
            usleep(40000); let e = CGEvent(keyboardEventSource: src, virtualKey: 6, keyDown: false)!; e.flags = .maskCommand; e.post(tap: .cghidEventTap)
            usleep(150000)
        }
        DispatchQueue.main.sync { NSApp.activate(ignoringOtherApps: true); self.win.makeKeyAndOrderFront(nil) }
        var fresh: [String] = []
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = (C1.run("tell application \"Capture One\"\nset AppleScript's text item delimiters to linefeed\nreturn (id of every variant of my curDoc()) as text\nend tell") ?? "").split(separator: "\n").map(String.init)
            fresh = now.filter { !ids0.contains($0) }; if fresh.count >= u.ids.count { break }
        }
        guard !fresh.isEmpty else { pickLog("되돌리기: 캡쳐원 실행 취소가 안 먹음 → 복제본으로"); return [] }
        // 돌아온 변형(새 id)을 이름으로 짝지음
        let back = C1.loadIDs(fresh); var used = Set<String>(), remap: [String: String] = [:]
        for old in u.ids { if let m = back.first(where: { !used.contains($0.id) && $0.name == u.names[old] }) { used.insert(m.id); remap[old] = m.id } }
        DispatchQueue.main.sync { self.remapIDs(remap) }
        pickLog("되돌리기: 캡쳐원 실행 취소로 \(remap.count)개 그대로 되살림")
        return Set(remap.keys)
    }
    // 캡쳐원을 잠깐 활성으로 → 편집 메뉴의 '○○ 실행 취소'(또는 다시 실행) 항목을 직접 누름 → 픽으로. 누른 항목 이름을 돌려줌
    // (⌘Z 키는 캡쳐원이 막 앞으로 온 순간엔 빠질 수 있어서 메뉴를 누름. 그동안 픽 창은 맨 위에 떠 있음)
    // 캡쳐원을 잠깐 활성으로 → 메뉴(예: 편집 › 삭제) 항목을 직접 누름 → 픽으로. 누른 항목 이름(못 누르면 "-")
    // 캡쳐원에 버튼 달린 창(시작 창·내보내기·경고 등)이 떠 있는지 — 있으면 메뉴를 누르지 않음 (엉뚱한 걸 누를 수 있어서)
    func c1HasDialog() -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").hasPrefix("Capture One") }) else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
        for w in attr(ax, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            let sub = attr(w, kAXSubroleAttribute) as? String ?? ""
            guard sub == "AXDialog" || sub == "AXSheet" || sub == "AXSystemDialog" else { continue }
            let btns = (attr(w, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { (attr($0, kAXRoleAttribute) as? String) == kAXButtonRole }
            if !btns.isEmpty { return true }
        }
        return false
    }
    // 캡쳐원이 지금 고른 사진 → 픽도 같게 (지우기·되돌리기 뒤: 캡쳐원 규칙 그대로)
    func followC1Selection() { }   // 선택 동기화 안 함 (2026-11-01)
    func followC1Selection_old() {
        let sel = (C1.quick("tell application \"Capture One\"\nset AppleScript's text item delimiters to linefeed\nreturn (id of (variants of my curDoc() whose selected is true)) as text\nend tell") ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        DispatchQueue.main.async { self.lastC1Sel = Set(sel); self.js(sel.isEmpty ? "PickApp.clearSel()" : "PickApp.selectIds(\(self.json(sel)))") }
    }
    func pressC1Menu(_ top: [String], _ item: [String], confirm: Bool = false, selectFirst: String? = nil) -> String {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").hasPrefix("Capture One") }) else { return "" }
        DispatchQueue.main.sync { self.win.level = .floating; app.activate() }
        for _ in 0..<30 { if NSWorkspace.shared.frontmostApplication == app { break }; usleep(10000) }
        usleep(80000)   // 캡쳐원 화면이 선택을 반영할 짬
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
        var label = "-"
        if let bar = attr(ax, kAXMenuBarAttribute), let tops = attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement],
           let m = tops.first(where: { top.contains(attr($0, kAXTitleAttribute) as? String ?? "") }),
           let menu = (attr(m, kAXChildrenAttribute) as? [AXUIElement])?.first {
            var it: AXUIElement?, on = false, name = ""
            for attempt in 0..<6 {   // 캡쳐원 화면이 선택을 반영하기 전엔 항목이 꺼져 있을 수 있음 → 잠깐 뒤 다시
                AXUIElementPerformAction(m, kAXPressAction as CFString); usleep(50000)   // 메뉴를 열어야 켜짐 상태가 새로 바뀜
                let items = attr(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
                // 이름이 선택에 따라 바뀜 (예: '삭제(세션 휴지통으로 이동)', '삭제(변형)') → 앞부분으로 찾음
                it = items.first(where: { let t = (attr($0, kAXTitleAttribute) as? String ?? "").precomposedStringWithCanonicalMapping; return item.contains(where: { t.hasPrefix($0) }) })
                on = it.flatMap { attr($0, kAXEnabledAttribute) as? Bool } ?? false   // 메뉴가 열려 있을 때 읽어야 정확
                name = it.flatMap { attr($0, kAXTitleAttribute) as? String } ?? ""
                AXUIElementPerformAction(menu, kAXCancelAction as CFString); usleep(30000)
                if on || it == nil { break }; pickLog("메뉴 '\(name)' 아직 꺼짐 → 다시 (\(attempt + 1))")
                if let sel = selectFirst { _ = C1.run(sel) }   // 선택을 한 번 더 보내고 다시
                usleep(120000)
            }
            if let it, on { AXUIElementPerformAction(it, kAXPressAction as CFString); label = name }
            // 캡쳐원 확인 창('삭제하시겠습니까? [취소][문서에서 제거]')이 뜨면 기본 버튼 — 캡쳐원에서 지우고 확인 누른 것과 같음
            if confirm, label != "-" {
                for _ in 0..<20 {
                    usleep(50000)
                    var done = false
                    for w in attr(ax, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                        let titles = (attr(w, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { (attr($0, kAXRoleAttribute) as? String) == kAXButtonRole }.compactMap { attr($0, kAXTitleAttribute) as? String }
                        // 삭제 확인 창만: [취소] + [문서에서 제거/삭제/Remove/Delete] 두 개짜리 (시작 창 등 다른 창은 절대 건드리지 않음)
                        let okNames = ["문서에서 제거", "삭제", "Remove", "Delete", "휴지통으로 이동", "Move to Trash"]
                        guard titles.count <= 3, titles.contains("취소") || titles.contains("Cancel"), titles.contains(where: { t in okNames.contains { t.hasPrefix($0) } }) else { continue }
                        let btns = (attr(w, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { (attr($0, kAXRoleAttribute) as? String) == kAXButtonRole }
                        if let go = btns.first(where: { let t = attr($0, kAXTitleAttribute) as? String ?? ""; return okNames.contains { t.hasPrefix($0) } }) {
                            let gn = attr(go, kAXTitleAttribute) as? String ?? ""; AXUIElementPerformAction(go, kAXPressAction as CFString); pickLog("캡쳐원 확인 창: \(titles) → '\(gn)'"); done = true }
                    }
                    if done { break }
                }
            }
        }
        usleep(20000)
        DispatchQueue.main.sync { NSApp.activate(ignoringOtherApps: true); self.win.makeKeyAndOrderFront(nil); self.win.level = .normal }
        return label
    }
    func pressC1Undo(_ redo: Bool, again: (() -> Bool)? = nil) -> String {
        let t0 = Date()
        guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").hasPrefix("Capture One") }) else { return "" }
        let wasFront = NSWorkspace.shared.frontmostApplication == app   // 사용자가 캡쳐원을 쓰는 중이면 그대로 누름
        if !wasFront {
            DispatchQueue.main.sync { self.win.level = .floating; app.activate() }
            for _ in 0..<30 { if NSWorkspace.shared.frontmostApplication == app { break }; usleep(10000) }
            usleep(20000)
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
        var label = ""
        if let bar = attr(ax, kAXMenuBarAttribute), let tops = attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement],
           let edit = tops.first(where: { ["편집", "Edit"].contains(attr($0, kAXTitleAttribute) as? String ?? "") }),
           let menu = (attr(edit, kAXChildrenAttribute) as? [AXUIElement])?.first,
           let items = attr(menu, kAXChildrenAttribute) as? [AXUIElement], items.count > 1 {
            let it = items[redo ? 1 : 0]
            // 메뉴를 열지 않고 바로 누름 (열면 화면에 메뉴가 펼쳐져 깜빡임). 이름은 안 열면 옛것일 수 있어 참고만
            let t = attr(it, kAXTitleAttribute) as? String ?? ""
            AXUIElementPerformAction(it, kAXPressAction as CFString)
            label = ["실행 취소", "Undo", "다시 실행", "Redo", ""].contains(t) ? (redo ? "다시 실행" : "실행 취소") : t
            // 뛰어 고른 쌍({옛,새})이 나오면 한 단계 더 — 캡쳐원이 앞에 있는 동안 한 번에
            if let again, again() { AXUIElementPerformAction(it, kAXPressAction as CFString); label += " ×2" }
        }
        if !wasFront {
            usleep(15000)
            DispatchQueue.main.sync { NSApp.activate(ignoringOtherApps: true); self.win.makeKeyAndOrderFront(nil); self.win.level = .normal }
        }
        pickLog("캡쳐원 \(redo ? "다시 실행" : "실행 취소"): \(label) · \(wasFront ? "캡쳐원이 앞인 채로" : "앞에 있던 시간 \(Int(Date().timeIntervalSince(t0) * 1000))ms")")
        return label
    }
    // 캡쳐원 상태 다시 읽어 픽에 맞춤: 사라진 사진은 숨김, 돌아온 사진은 (지웠던 것이면) 그 자리에 되살림·아니면 새로 추가, 별점·태그 바뀐 것 반영
    func resyncC1() {
        guard let col = C1.columns([("id", "id of every variant of d"), ("name", "name of every variant of d"), ("r", "rating of every variant of d"), ("t", "color tag of every variant of d")], head: "(name of d)") else { return }
        let ids = col["id"] ?? [], names = col["name"] ?? [], rs = col["r"] ?? [], ts = col["t"] ?? []
        DispatchQueue.main.sync {
            let now = Set(ids)
            var gone: [String] = [], back: [[String: String]] = [], upd: [String: Any] = [:], fresh: [Item] = []
            for it in items where !now.contains(it.id) { gone.append(it.n) }
            for it in items where it.gone0 && now.contains(it.id) { back.append(["n": it.n, "id": it.id]) }   // 캡쳐원 ⌘Z 등으로 같은 번호 그대로 돌아옴
            for k in items.indices { items[k].gone0 = !now.contains(items[k].id) }
            var usedGone = Set<String>()
            for (i, id) in ids.enumerated() {
                let r = Int(i < rs.count ? rs[i] : "") ?? 0, t = Int(i < ts.count ? ts[i] : "") ?? 0, nm = i < names.count ? names[i] : ""
                if let k = byID[id] { if items[k].r != r || items[k].t != t { items[k].r = r; items[k].t = t; upd[items[k].n] = ["r": r] } ; continue }
                // 처음 보는 id: 지금 없는(지워진) 같은 이름 사진이면 그걸 되살림
                if let k = items.indices.first(where: { !now.contains(items[$0].id) && items[$0].name == nm && !usedGone.contains(items[$0].n) }) {
                    usedGone.insert(items[k].n); byID[items[k].id] = nil; items[k].id = id; byID[id] = k; items[k].r = r
                    back.append(["n": items[k].n, "id": id]); gone.removeAll { $0 == items[k].n }
                } else { fresh.append(Item(n: "", id: id, name: nm, ext: "", path: "", r: r, t: t)) }
            }
            if !gone.isEmpty || !back.isEmpty || !fresh.isEmpty { pickLog("캡쳐원 목록 맞춤: 사라짐 \(gone.count) · 돌아옴 \(back.count) · 새 사진 \(fresh.count)") }
            js("PickApp.c1state(\(json(["gone": gone, "back": back, "upd": upd])))")
            if !fresh.isEmpty { C1.q.async { let add = C1.loadIDs(fresh.map(\.id)); if !add.isEmpty { DispatchQueue.main.async { self.addCaptured(add) } } } }
        }
    }
    func askAccessibility() {
        guard !UserDefaults.standard.bool(forKey: "pick.askedAX") else { return }
        UserDefaults.standard.set(true, forKey: "pick.askedAX")
        toast("지운 변형을 캡쳐원처럼 그대로 되돌리려면 '손쉬운 사용'에서 Pick을 켜 주세요")
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    var rendered: [String: Int] = [:]   // id → 그 미리보기를 만들 때의 보정 지문
    var docDirCache = ""
    func sessionDir() -> String? { if !docDirCache.isEmpty { return docDirCache }; return sessionList().first { $0["name"] == doc }.flatMap { $0["path"] }.map { ($0 as NSString).deletingLastPathComponent } }
    func saveSigs() {
        guard mode == "c1", !cacheDir.isEmpty, let d = try? JSONSerialization.data(withJSONObject: rendered) else { return }
        try? d.write(to: URL(fileURLWithPath: cacheDir + "/rendered.json"))
    }
    func redrawEdited() {
        for id in editPending { rendered[id] = nil }
        let snap = editLast
        if editAllSel {   // 바뀐 게 보이면 캡쳐원에서 선택한 사진 전부 (여러 장에 한꺼번에 스타일 입힌 경우)
            editAllSel = false
            C1.q.async { let sel = (C1.run("tell application \"Capture One\"\nset AppleScript's text item delimiters to linefeed\nreturn (id of (variants of my curDoc() whose selected is true)) as text\nend tell") ?? "").split(separator: "\n").map(String.init)
                DispatchQueue.main.async { self.editPending.formUnion(sel.filter { self.byID[$0] != nil }); self.redrawEdited() } }
            return
        }
        let ids = Array(editPending); editPending = []
        let ns = ids.compactMap { byID[$0] }.map { items[$0].n }
        guard !ns.isEmpty else { return }
        let t0 = Date(); redrawT0[ns.joined(separator: ",")] = t0
        pickLog("조정 연동: 다시 그림 \(ns.joined(separator: ",")) (알림 뒤 \(String(format: "%.2f", t0.timeIntervalSince(editNotifyAt)))초 대기)")
        for n in ns { announced.remove(n); expected.insert(n) }   // 그리는 동안은 지금 그림 그대로
        let fm = FileManager.default
        let groups = byRank(ids).map { (r, g) -> (Int, [String], String) in   // 순번마다 고정된 임시 폴더 (레시피 저장 위치가 안 바뀌게)
            let st = cacheDir + "/.redo-r\(r)"; try? fm.createDirectory(atPath: st, withIntermediateDirectories: true)
            for f in (try? fm.contentsOfDirectory(atPath: st)) ?? [] { try? fm.removeItem(atPath: st + "/" + f) }
            return (r, g, st) }
        C1.q.async {
            // 캡쳐원은 저장된 조정값으로 처리함 → 방금 바꾼 조정값을 먼저 저장
            _ = C1.run("tell application \"Capture One\"\nwith timeout of 30 seconds\nsave my curDoc()\nend timeout\nend tell")
            let t1 = Date(); pickLog(String(format: "조정 연동 시간: 저장 %.2f초", t1.timeIntervalSince(t0)))
            for (r, g, st) in groups { _ = C1.process(g, recipe: "cc-cull-redo-r\(r)", into: st, fullSize: false) }
            pickLog(String(format: "조정 연동 시간: 처리 명령 %.2f초", Date().timeIntervalSince(t1)))
            // 다 써지면 원래 자리로 바꿔 넣음 → watch()가 화면에 알림
            var waited = 0.0
            func poll() {
                let ready = groups.allSatisfy { (_, g, st) in (((try? fm.contentsOfDirectory(atPath: st)) ?? []).filter { $0.lowercased().hasSuffix(".jpg") && jpegComplete(st + "/" + $0) }).count >= g.count }
                if ready || waited > 60 {
                    pickLog(String(format: "조정 연동 시간: 파일 완성 %.2f초 (시작부터)", Date().timeIntervalSince(t0)))
                    DispatchQueue.main.async {
                        for (r, _, st) in groups {
                            let dir = self.rankDir(r); try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                            for f in ((try? fm.contentsOfDirectory(atPath: st)) ?? []) where f.lowercased().hasSuffix(".jpg") { let to = dir + "/" + f; try? fm.removeItem(atPath: to); try? fm.moveItem(atPath: st + "/" + f, toPath: to) }
                            for f in (try? fm.contentsOfDirectory(atPath: st)) ?? [] { try? fm.removeItem(atPath: st + "/" + f) }   // 폴더는 남김(다음에도 같은 위치)
                        }
                        if self.timer == nil { self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.watch() } }
                        self.watch()   /* 바로 화면에 알림 (전엔 1초 타이머를 기다림) */
                    }
                    return
                }
                waited += 0.08; DispatchQueue.global().asyncAfter(deadline: .now() + 0.08, execute: poll)
            }
            DispatchQueue.global().async(execute: poll)
        }
    }
    // 테더링: 새로 찍힌(들어온) 사진을 화면에 바로 덧붙임 → 맨 앞으로 보여 줌
    func addCaptured(_ add0: [Item]) {
        let add1 = add0.filter { byID[$0.id] == nil }; guard !add1.isEmpty else { return }
        var next = (items.compactMap { Int($0.n) }.max() ?? 0) + 1
        var add = add1; for k in add.indices { add[k].n = String(next); next += 1 }
        DispatchQueue.global(qos: .userInitiated).async {
            let info = add.map { exif($0.path) }
            DispatchQueue.main.async {
                var seen: [String: Int] = [:]; for it in self.items { seen[it.name, default: 0] += 1 }
                var meta: [String: Any] = [:]
                for (k, it) in add.enumerated() {
                    self.byN[it.n] = self.items.count; self.byID[it.id] = self.items.count; self.items.append(it)
                    self.dupRank[it.n] = seen[it.name, default: 0]; seen[it.name, default: 0] += 1
                    var m: [String: Any] = [:]; for (a, b) in info[k] where a != "dtfull" { m[a] = b }; meta[it.n] = m
                }
                pickLog("테더링: 새 사진 \(add.count)장 \(add.map(\.name).joined(separator: ","))")
                self.js("PickApp.added(\(self.json(add.map { ["n": $0.n, "id": $0.id, "name": $0.name, "ext": $0.ext, "r": $0.r, "t": $0.t] })),\(self.json(meta)))")
                self.makePreviews(add.map(\.id))
                self.orderSig = ""; self.pushOrder(force: true)
            }
        }
    }
    var orderSig = ""
    func pushOrder(force: Bool = false) {
        guard mode == "c1" else { return }
        C1.q.async {
            guard let o = C1.order() else { return }
            // 캡쳐원 세션이 막 바뀐 순간이면 새 사진으로 착각하지 않게 (세션 이름이 픽과 같을 때만)
            let dn = (C1.docName() ?? "").replacingOccurrences(of: ".cosessiondb", with: "").replacingOccurrences(of: ".cocatalog", with: "")
            guard DispatchQueue.main.sync(execute: { dn == self.doc }) else { return }
            let fresh = DispatchQueue.main.sync { o.ids.filter { self.byID[$0] == nil } }
            if !fresh.isEmpty, DispatchQueue.main.sync(execute: { self.mode == "c1" && !self.switching }) {
                if DispatchQueue.main.sync(execute: { self.items.isEmpty }) { DispatchQueue.main.async { self.openC1() }; return }
                let add = C1.loadIDs(fresh)
                if !add.isEmpty { DispatchQueue.main.async { self.addCaptured(add) } }
            }
            let sig = o.sort + "\(o.rev)" + o.ids.joined(separator: ",")
            DispatchQueue.main.async {
                guard self.mode == "c1", force || sig != self.orderSig else { return }
                self.orderSig = sig
                self.js("PickApp.order(\(self.json(["sort": o.sort, "rev": o.rev, "ids": o.ids])))")
            }
        }
    }
    var c1UndoKeyAt = Date.distantPast, c1UndoKeyRedo = false, keyTap: CFMachPort?
    // 캡쳐원이 앞에 있을 때 눌린 ⌘Z/⇧⌘Z를 기억해 둠 → 바로 뒤 선택 알림이 '뛰어 고른 쌍'이면 한 단계 더 (캡쳐원에서도 두 장 상태를 안 보게)
    func startKeyTap() {
        guard keyTap == nil else { return }
        let cb: CGEventTapCallBack = { _, type, ev, _ in
            if type == .keyDown, ev.getIntegerValueField(.keyboardEventKeycode) == 6, ev.flags.contains(.maskCommand), !ev.flags.contains(.maskAlternate), !ev.flags.contains(.maskControl),
               (NSWorkspace.shared.frontmostApplication?.localizedName ?? "").hasPrefix("Capture One") {
                let redo = ev.flags.contains(.maskShift)
                DispatchQueue.main.async { if let a = NSApp.delegate as? App { a.c1UndoKeyAt = Date(); a.c1UndoKeyRedo = redo } }
            }
            return Unmanaged.passUnretained(ev)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: cb, userInfo: nil) else { pickLog("키 듣기 탭 못 만듦 (손쉬운 사용·입력 모니터링 권한 확인)"); return }
        keyTap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    static var fontB64: String?
    static var iconCache: [String: Data] = [:]
    let qlPanel = QLPanel()
    var loading = false, initialOrder: (sort: String, rev: Bool, ids: [String])?   // 불러오는 중엔 동기화 틱이 또 불러오지 않게
    func openC1() {
        if testC1Lock { pickLog("시험 잠금: 캡쳐원 세션 열기 거부"); return }
        if evLogOn { pickLog("openC1 호출: " + Thread.callStackSymbols.dropFirst().prefix(4).map { String($0.split(separator: " ").dropFirst(3).prefix(1).joined()).replacingOccurrences(of: "$s4Pick", with: "") }.joined(separator: " < ")) }
        loadGen += 1; reset(); mode = "c1"; loading = true; hint.stringValue = "캡쳐원에서 사진을 불러오는 중…"
        C1.q.async {
            if let (doc, list) = C1.load(), !list.isEmpty { self.initialOrder = C1.order(); self.withInfo(doc, list); return }   // 캡쳐원 순서도 같이 → 첫 화면부터 제자리
            DispatchQueue.main.async { self.loading = false }
            // 사진 없는 세션(막 만든 세션 등)도 화면은 띄움 → 왼쪽 패널로 다른 세션 고를 수 있게, 촬영하면 바로 채워짐
            if let n = C1.docName(), !n.isEmpty { self.withInfo(n.replacingOccurrences(of: ".cosessiondb", with: "").replacingOccurrences(of: ".cocatalog", with: ""), []); return }
            DispatchQueue.main.async { self.hint.stringValue = "캡쳐원에서 사진을 가져오지 못했어요" }
        }
    }
    func openFolder(_ dir: String) {
        openedWithFolder = true; folderPath = dir; loadGen += 1; let gen = loadGen; pendingJS = []; pageReady = false
        let keep = mode == "folder" && (web != nil || oldWeb != nil)
        if keep { if web == nil, let o = oldWeb { web = o; oldWeb = nil } ; js("PickApp.navFolder(\(json(dir)))") }   // 빠르게 연달아 바꿀 때도 보이는 화면 하나는 유지. 왼쪽 패널 표시는 먼저 옮김
        reset(keepWeb: keep); mode = "folder"; if !keep { hint.stringValue = "폴더를 불러오는 중…" }
        let t0 = Date(); folderT0 = t0
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let files = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") && photoExts.contains(($0 as NSString).pathExtension.lowercased()) }
            var list = numbered(files.map { f in
                let p = dir + "/" + f
                return Item(n: "", id: p, name: (f as NSString).deletingPathExtension, ext: "." + (f as NSString).pathExtension, path: p, r: 0, t: 0) })
            let doc = fm.displayName(atPath: dir)
            DispatchQueue.main.async {   // 목록 먼저 (사진이 없어도 화면은 띄움) — 촬영 정보·별점은 아래서 뒤따라 채움
                guard gen == self.loadGen else { return }
                for k in list.indices { self.keys[list[k].id] = RatingStore.key(list[k], nil) }
                pickLog(String(format: "폴더 열기: 목록 %d장 %.0fms", list.count, Date().timeIntervalSince(t0) * 1000))
                self.start(doc, list, [[String: String]](repeating: [:], count: list.count)); self.hint.stringValue = ""
                pickLog(String(format: "폴더 열기: 웹뷰 만들고 load 호출 %.0fms", Date().timeIntervalSince(t0) * 1000))
            }
            let step = 40
            for s0 in stride(from: 0, to: list.count, by: step) {
                guard gen == self.loadGen else { return }
                let range = s0..<min(s0 + step, list.count)
                var info = [[String: String]](repeating: [:], count: range.count)
                DispatchQueue.concurrentPerform(iterations: range.count) { k in info[k] = exif(list[s0 + k].path) }
                var upd: [String: Any] = [:]
                for (j, k) in range.enumerated() {
                    let key = RatingStore.key(list[k], info[j]["dtfull"]), path = list[k].path
                    let meta = XMPRating.readMeta(path)   // 브릿지·라이트룸 별점·라벨(XMP) 먼저, 없으면 픽에 저장해 둔 것
                    let r = meta.r ?? self.store.map[key] ?? 0, t = meta.t ?? self.store.map[key + "#t"] ?? 0
                    var m: [String: Any] = [:]; for (a, b) in info[j] where a != "dtfull" && a != "o" { m[a] = b }; m["r"] = r; m["t"] = t
                    if XMPRating.isRaw(path), let txt = meta.text, let e = CRSEdits.parse(txt) {   // 카메라 로우 보정이 있으면: 표시 + 화면 비율도 보정 뒤 모양으로
                        let fo = Int(info[j]["o"] ?? "") ?? 1; self.setEdits(path, e)
                        if e.isEdited(fileOrientation: fo) { m["e"] = 1
                            if var a = Double(info[j]["a"] ?? "") , a > 0 {
                                let d = (CRSEdits.deg(e.orientation ?? fo) - CRSEdits.deg(fo) + 360) % 360; if d == 90 || d == 270 { a = 1 / a }
                                if let c = e.crop, e.angle == 0 { let o = e.orientation ?? fo; let sw = CRSEdits.deg(o) == 90 || CRSEdits.deg(o) == 270; let cw = sw ? (c.b - c.t) : (c.r - c.l), ch = sw ? (c.r - c.l) : (c.b - c.t); if ch > 0 { a = a * cw / ch } }
                                m["a"] = String(format: "%.4f", a) } }
                    }
                    list[k].r = r; list[k].t = t; upd[list[k].n] = m
                    DispatchQueue.main.async { guard gen == self.loadGen else { return }; self.keys[list[k].id] = key; if let i = self.byN[list[k].n] { self.items[i].r = r; self.items[i].t = t } }
                }
                DispatchQueue.main.async { guard gen == self.loadGen else { return }; self.jsReady("PickApp.synced(\(self.json(upd)))") }
            }
            DispatchQueue.main.async { guard gen == self.loadGen else { return }; self.jsReady("PickApp.infoDone()"); pickLog(String(format: "폴더 열기: 정보 다 읽음 %.0fms", Date().timeIntervalSince(t0) * 1000)) }
        }
    }
    // 촬영 정보(여러 개 동시에) 읽고 화면 시작
    func withInfo(_ doc: String, _ list0: [Item], gen: Int? = nil) {
        var list = list0
        var info = [[String: String]](repeating: [:], count: list.count)
        DispatchQueue.concurrentPerform(iterations: list.count) { k in info[k] = exif(list[k].path) }
        DispatchQueue.main.async {
            if let g = gen, g != self.loadGen { return }   // 그 사이 다른 폴더·세션을 열었으면 버림
            if self.mode == "folder" {
                for k in list.indices { let key = RatingStore.key(list[k], info[k]["dtfull"]); self.keys[list[k].id] = key; list[k].r = self.store.map[key] ?? 0 }
            }
            self.start(doc, list, info); self.hint.stringValue = ""
        }
    }

    func start(_ doc: String, _ list: [Item], _ info: [[String: String]]) {
        self.doc = doc; items = list; loading = false
        for (k, it) in list.enumerated() { byN[it.n] = k; byID[it.id] = k }
        var metaInfo: [String: Any] = [:]
        for (k, it) in list.enumerated() {
            var m: [String: Any] = it.adj; for (a, b) in info[k] where a != "dtfull" && a != "o" { m[a] = b }
            if !it.iso.isEmpty { m["iso"] = it.iso }
            metaInfo[it.n] = m
        }
        var payload: [String: Any] = [
            "doc": doc, "mode": mode,
            "items": list.map { ["n": $0.n, "id": $0.id, "name": $0.name, "ext": $0.ext, "r": $0.r, "t": $0.t] },
            "meta": ["info": metaInfo, "styles": mode == "c1" ? styles() : []],
            "dirs": mode == "folder" ? subfolderRows(folderPath) : [],   // 필름스트립 폴더 칸 (브릿지 콘텐츠 패널처럼)
            "nav": ["sessions": sessionList(), "folder": mode == "folder" ? folderPath : "",
                    "roots": [home + "/Desktop", home + "/Downloads"].map { [FileManager.default.displayName(atPath: $0), $0] }, "disks": diskList()]]   // 이름은 Finder 표시 이름(데스크탑·다운로드)
        payload["gen"] = loadGen; payload["clip"] = clipPaths.count
        if mode == "c1", let o = initialOrder, !o.sort.isEmpty { payload["order"] = ["sort": o.sort, "rev": o.rev, "ids": o.ids]; orderSig = o.sort + "\(o.rev)" + o.ids.joined(separator: ",") }
        initialOrder = nil
        let json = self.json(payload)
        let index = URL(string: "pick://app/index.html")!
        pageReady = false   // 새 화면: 'ready' 올 때까지 정보는 모아 둠 (pendingJS는 비우지 않음 — 이번 폴더 것)
        if let w = oldWeb {   // 폴더 → 폴더: 페이지를 다시 열지 않고 PickApp.load로 데이터만 교체 (글꼴·화면 코드 재사용 → 수십 ms, 2026-11-04). 그동안 이전 화면 스냅샷을 덮어 둠
            web = w; oldWeb = nil
            let gen = loadGen, code = "PickApp.load(\(json))"
            let run = { [weak self] in w.evaluateJavaScript(code) { _, e in if let e { pickLog("폴더 전환 load 오류: \(e.localizedDescription)"); self?.reveal(w) } } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in if let self, self.loadGen == gen { self.reveal(w) } }   // 안전장치
            if overlay != nil || env["PICK_NOSNAP"] != nil { run(); return }
            let ts = Date()
            w.takeSnapshot(with: nil) { [weak self] img, _ in
                pickLog(String(format: "폴더 열기: 스냅샷 %.0fms", Date().timeIntervalSince(ts) * 1000))
                guard let self else { return }
                if let img, self.overlay == nil, self.web === w { let iv = NSImageView(frame: w.frame); iv.image = img; iv.imageScaling = .scaleAxesIndependently; iv.autoresizingMask = [.width, .height]; self.win.contentView!.addSubview(iv, positioned: .above, relativeTo: w); self.overlay = iv }
                if self.loadGen == gen { run() } }
            return
        }
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(self, forURLScheme: "pick")
        cfg.userContentController.add(self, name: "pick")
        cfg.userContentController.addUserScript(WKUserScript(source: "window.PICK=\(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // 시험용: PICK_TESTJS 파일이 있으면 페이지가 뜬 뒤 실행 (평소엔 없음)
        if let t = env["PICK_TESTJS"], let code = try? String(contentsOfFile: t, encoding: .utf8) { cfg.userContentController.addUserScript(WKUserScript(source: code, injectionTime: .atDocumentEnd, forMainFrameOnly: true)) }
        let w = PickWebView(frame: win.contentView!.bounds, configuration: cfg)
        w.autoresizingMask = [.width, .height]; w.setValue(false, forKey: "drawsBackground")
        w.onFolder = { [weak self] p in self?.openFolder(p) }
        w.wantsLayer = true; w.alphaValue = 0   // 페이지가 첫 프레임을 그렸다고("painted") 알릴 때까지 로고 화면 유지 → 흰 화면·글자 튀는 깜빡임 없음
        win.contentView!.addSubview(w); web = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self, weak w] in if let w { self?.reveal(w) } }   // 안전장치: 알림이 안 와도 3초 뒤엔 보여 줌
        w.load(URLRequest(url: index))
        win.makeFirstResponder(w)
        if mode == "c1" {
            cacheDir = cacheRoot + "/" + doc.replacingOccurrences(of: "/", with: "_")
            try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            // 다시 그리기 임시 폴더만 비움 (미리보기는 남김)
            for d in (try? FileManager.default.contentsOfDirectory(atPath: cacheDir)) ?? [] where d.hasPrefix(".redo-") && !d.hasPrefix(".redo-r") { try? FileManager.default.removeItem(atPath: cacheDir + "/" + d) }
            dupRank = [:]; var seen: [String: Int] = [:]
            for it in list.sorted(by: { (Int($0.n) ?? 0) < (Int($1.n) ?? 0) }) { dupRank[it.n] = seen[it.name, default: 0]; seen[it.name, default: 0] += 1 }
            watchEdits()
            // 한 번에 전체 조정값 지문을 읽어, 미리보기가 없거나 지난번과 달라진 사진만 캡쳐원에 맡김
            let dir = cacheDir
            C1.q.async {
                let dd = C1.docDir() ?? ""
                let g = C1.fullSigs() ?? C1.Sigs()
                var now: [String: Int] = [:]; for (k, a) in g.adj { now[k] = a &+ (g.crop[k] ?? 0) &* 31 }
                let saved = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/rendered.json")))) as? [String: Int] ?? [:]   // 미리보기를 만든 때의 보정 지문
                // 이미 캡쳐원 처리 대기열에 있는 사진은 다시 맡기지 않음 (픽을 다시 켜도 중복으로 안 쌓이게)
                let queued = Set((C1.run("tell application \"Capture One\"\nset AppleScript's text item delimiters to linefeed\nreturn (id of (variants of my curDoc() whose queued is true)) as text\nend tell") ?? "").split(separator: "\n").map(String.init))
                DispatchQueue.main.async {
                    guard self.cacheDir == dir else { return }
                    self.docDirCache = dd
                    var need: [String] = [], have: [String] = []
                    for it in self.items {
                        let ok = FileManager.default.fileExists(atPath: self.previewPath(it)) && (self.dupRank[it.n] ?? 0) < 4 && self.previewBigEnough(self.previewPath(it))
                        // 만든 때와 보정이 같을 때만 그대로, 아니면 새로
                        if ok, let a = now[it.id], saved[it.id] == a { have.append(it.n) } else if (self.dupRank[it.n] ?? 0) < 4, !queued.contains(it.id) { need.append(it.id) } else if queued.contains(it.id) { self.expected.insert(it.n) }
                    }
                    pickLog("미리보기: 그대로 \(have.count)장 · 새로 \(need.count)장")
                    self.expected.formUnion(have); if self.timer == nil, !have.isEmpty { self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.watch() } }
                    self.adjLast = g.adj; self.cropLast = g.crop; self.rendered = saved.filter { k, _ in self.byID[k] != nil }
                    self.lastFull = Date(); self.startSync()
                    if !need.isEmpty { self.makePreviews(need) }   // items는 번호 순 = 대체로 촬영 순서
                }
            }
        }
    }
    func makePreviews(_ ids: [String]) {
        let groups = byRank(ids).filter { $0.key < 4 }.sorted { $0.key < $1.key }.map { ($0.key, $0.value, rankDir($0.key)) }
        for (_, _, d) in groups { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }
        C1.q.async {
            var got = Set<String>()
            for (r, g, d) in groups { got.formUnion(C1.process(g, recipe: r == 0 ? "cc-cull-preview" : "cc-cull-preview-r\(r)", into: d, fullSize: false)) }
            DispatchQueue.main.async {
                self.expected.formUnion(got.compactMap { self.byID[$0] }.map { self.items[$0].n })
                self.status()
                if self.timer == nil { self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.watch() } }
            }
        }
    }

    // 스타일 목록 (캡쳐원 Styles 폴더: 맨 위 = My Styles, 하위 폴더 = 그 이름)
    func styles() -> [[Any]] {
        let base = home + "/Library/Application Support/Capture One/Styles"
        let fm = FileManager.default
        func list(_ d: String) -> [String] { ((try? fm.contentsOfDirectory(atPath: d)) ?? []).filter { $0.hasSuffix(".costyle") }.map { String($0.dropLast(8)) }.sorted() }
        var out: [[Any]] = [["My Styles", list(base)]]
        for d in ((try? fm.contentsOfDirectory(atPath: base)) ?? []).sorted() {
            var isDir: ObjCBool = false
            if !d.hasPrefix("zz_"), !d.hasPrefix("."), fm.fileExists(atPath: base + "/" + d, isDirectory: &isDir), isDir.boolValue {
                let l = list(base + "/" + d); if !l.isEmpty { out.append([d, l]) } }
        }
        return out
    }

    // 큰 미리보기가 다 써지면 화면에 알림
    var dupRank: [String: Int] = [:]   // 같은 이름 중 몇 번째인지 (n → 0,1,2…)
    func rankDir(_ r: Int) -> String { r == 0 ? cacheDir : cacheDir + "/r\(r)" }
    // 미리보기가 지금 기준 크기(또는 원본이 더 작으면 원본 크기)로 만들어졌는지 (옛 1600px 미리보기는 다시 만들게)
    func previewBigEnough(_ path: String) -> Bool {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return true }
        return max(w, h) >= C1.previewLongEdge - 2 || max(w, h) >= 1700   // 1700 넘으면 원본이 작아서 그런 것(1600 기준으로 만든 게 아님)
    }
    func previewPath(_ it: Item) -> String { rankDir(dupRank[it.n] ?? 0) + "/" + it.name + ".jpg" }
    // id들을 '같은 이름 중 순번'별로 나눔 → 순번마다 따로 처리하면 같은 폴더에 같은 이름이 안 생김
    func byRank(_ ids: [String]) -> [Int: [String]] {
        var g: [Int: [String]] = [:]
        for id in ids { guard let k = byID[id] else { continue }; g[dupRank[items[k].n] ?? 0, default: []].append(id) }
        return g
    }
    func watch() {
        var ready: [String] = []
        for n in expected.subtracting(announced) {
            guard let k = byN[n] else { continue }
            let p = previewPath(items[k])
            if FileManager.default.fileExists(atPath: p), jpegComplete(p) { ready.append(n) }
        }
        if !ready.isEmpty {
            announced.formUnion(ready)
            if mode == "c1" { for n in ready { if let k = byN[n], let sg = editLast[items[k].id] { rendered[items[k].id] = sg } }; saveSigs() }
            for n in ready { thumbs.removeObject(forKey: ("s" + n) as NSString) }
            js("PickApp.previewReady(\(json(ready)))"); if let k = redrawT0.keys.first(where: { k in ready.contains { k.split(separator: ",").map(String.init).contains($0) } }), let t = redrawT0[k] { pickLog(String(format: "조정 연동 시간: 화면 반영 %.2f초 (시작부터)", Date().timeIntervalSince(t))); redrawT0[k] = nil }
            status()
        }
        if announced.count >= expected.count { timer?.invalidate(); timer = nil }
    }
    func status() {
        let t = announced.count >= expected.count ? "" : "보정 반영 미리보기 \(announced.count) / \(expected.count)"
        js("PickApp.status(\(json(t)))")
    }
    func json(_ o: Any) -> String {   // 못 바꾸는 값(NaN 등)이 섞여도 앱이 죽지 않게 (배포 대비 2026-11-04)
        do { return String(data: try JSONSerialization.data(withJSONObject: o, options: .fragmentsAllowed), encoding: .utf8) ?? "null" } catch { pickLog("JSON 변환 실패: \(error)"); return "null" } }
    func js(_ s: String) { web?.evaluateJavaScript(s, completionHandler: nil) }
    var pageReady = false, pendingJS: [String] = []
    func jsReady(_ s: String) { if pageReady { js(s) } else { pendingJS.append(s) } }   // 화면이 아직 안 떴으면 모아 뒀다가 'ready' 때 보냄 (작은 폴더에서 별점·비율이 버려지던 문제)
    func toast(_ t: String) { pickLog("알림: " + t); js("PickApp.toast(\(json(t)))") }
    // 화면의 우클릭 메뉴를 진짜 맥 메뉴로. 고른 항목 id(취소면 "")를 PickApp.ctxPick으로 돌려줌
    var ctxPicked = false
    func showCtxMenu(_ items: [[String: Any]]) {
        let m = NSMenu(); m.autoenablesItems = false; ctxPicked = false
        for d in items {
            if d["sep"] != nil { m.addItem(.separator()); continue }
            let it = NSMenuItem(title: d["label"] as? String ?? "", action: #selector(ctxPick(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = d["id"] as? String ?? ""; it.isEnabled = !((d["disabled"] as? Bool) ?? false)
            if let c = d["checked"] as? Bool { it.state = c ? .on : .off }   // 체크 항목 (왼쪽 패널 섹션 보이기 등)
            if d["key"] as? String == "⌫" { it.keyEquivalent = "\u{08}"; it.keyEquivalentModifierMask = [] }
            m.addItem(it)
        }
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)   // 닫힐 때까지 여기서 기다림
        DispatchQueue.main.async { if !self.ctxPicked { self.js("PickApp.ctxPick(\"\")") } }
    }
    @objc func ctxPick(_ s: NSMenuItem) { ctxPicked = true; js("PickApp.ctxPick(\(json(s.representedObject as? String ?? "")))") }

    // MARK: 화면 → 앱
    func userContentController(_ uc: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let b = m.body as? [String: Any], let cmd = b["cmd"] as? String else { return }
        if let o = oldWeb, m.webView === o { return }   // 교체 대기 중인 이전 화면의 메시지는 무시
        switch cmd {
        case "painted": if let g = b["gen"] as? Int, g != loadGen { return }; if let w = web { reveal(w) }; if mode == "folder" { pickLog(String(format: "폴더 열기: 화면 그림 %.0fms", Date().timeIntervalSince(folderT0) * 1000)) }   // 화면이 첫 프레임을 그림
        case "ctxMenu": showCtxMenu(b["items"] as? [[String: Any]] ?? [])
        case "ready": orderSig = ""; pushOrder(force: true)
            pageReady = true; let q = pendingJS; pendingJS = []; for x in q { js(x) }   // 화면 준비 전에 온 정보 보내기
        case "setSort":   // 픽에서 정렬 바꿈 → 캡쳐원에도
            let sort = b["sort"] as? String ?? "by date", rev = b["rev"] as? Bool ?? false
            C1.q.async { C1.setSort(sort, rev: rev); DispatchQueue.main.async { self.pushOrder(force: true) } }
        case "rate": c1Mut += 1; opStack.append(("c1", 0)); redoStack = []
            let list = (b["items"] as? [[String: Any]] ?? []).compactMap { d -> (String, Int)? in
                guard let id = d["id"] as? String, let r = d["r"] as? Int else { return nil }; return (id, r) }
            for (id, r) in list { if let k = byID[id] { items[k].r = r } }
            if mode == "folder" {
                for (id, r) in list { if let key = keys[id] { store.set(key, r) } }
                xmpQ.async { var bad = 0; for (id, r) in list { if !XMPRating.write(id, r) { bad += 1 } }   // 폴더 방식 id = 파일 경로
                    if bad > 0 { pickLog("XMP 별점 못 씀 \(bad)장") } }
                return }
            C1.q.async { if !C1.setRatings(list) { DispatchQueue.main.async { self.toast("캡쳐원에 별점을 넣지 못했어요 · 캡쳐원이 켜져 있는지 확인해 주세요") } } }
        case "tag": c1Mut += 1
            let list = (b["items"] as? [[String: Any]] ?? []).compactMap { d -> (String, Int)? in
                guard let id = d["id"] as? String, let t = d["t"] as? Int else { return nil }; return (id, t) }
            for (id, t) in list { if let k = byID[id] { items[k].t = t } }
            if mode == "folder" {   // 폴더 방식: 브릿지처럼 XMP 라벨로 저장 (RAW는 옆 .xmp, 그 외는 파일 안)
                for (id, t) in list { if let key = keys[id] { store.set(key + "#t", t) } }
                xmpQ.async { var bad = 0; for (id, t) in list { if !XMPRating.write(id, tag: t) { bad += 1 } }
                    if bad > 0 { pickLog("XMP 라벨 못 씀 \(bad)장") } }
                return }
            C1.q.async { if !C1.setTags(list) { DispatchQueue.main.async { self.toast("캡쳐원에 색 태그를 넣지 못했어요 · 캡쳐원이 켜져 있는지 확인해 주세요") } } }
        case "style": c1Mut += 1; opStack.append(("c1", 0)); redoStack = []
            guard mode == "c1", let name = b["name"] as? String, let ids = b["ids"] as? [String], !ids.isEmpty else { return }
            applyStyle(name, ids)
        case "dragOut":   // 창 밖으로 끌고 나가면 → 맥의 진짜 파일 끌기로 바꿈 (놓은 폴더로 꺼내기)
            let ns = b["ns"] as? [String] ?? []
            let list = ns.compactMap { byN[$0] }.map { items[$0] }
            guard !list.isEmpty, let w = web, let win = w.window else { return }
            let loc = w.convert(win.mouseLocationOutsideOfEventStream, from: nil)
            let ev = NSApp.currentEvent.flatMap { [.leftMouseDragged, .leftMouseDown].contains($0.type) ? $0 : nil }
                ?? NSEvent.mouseEvent(with: .leftMouseDragged, location: win.mouseLocationOutsideOfEventStream, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            dragOut.ns = ns; dragOut.dirs = []; dragOut.view = w
            dragOut.onMove = { [weak self] inside, q in self?.js(inside ? "PickApp.dragIn(\(q.x),\(q.y))" : "PickApp.dragLeft()") }
            dragOut.onEnd = { [weak self] q in self?.js(q.map { "PickApp.dragDropIn(\($0.x),\($0.y),\(NSEvent.modifierFlags.contains(.option)))" } ?? "PickApp.dragEnded()") }   // ⌥ 누른 채 놓으면 복사
            dragOut.onDrop = nil
            dragOut.fulfill = { [weak self] n, url, done in self?.fulfillPromise(n, url, done) ?? done(nil) }
            // 픽 안 끌기 그림과 같은 크기·그림자·잡은 자리 → 창 경계를 넘어도 그대로 이어짐
            let fanNs = (b["fan"] as? [String]) ?? [ns[0]]
            let fan = fanNs.compactMap { byN[$0] }.map { items[$0] }
            let it0 = fan.first ?? list[0]
            func pic(_ it: Item) -> NSImage { (thumbs.object(forKey: ("m" + it.n) as NSString) ?? thumbs.object(forKey: ("s" + it.n) as NSString)).flatMap { NSImage(data: $0 as Data) } ?? NSImage(contentsOfFile: previewPath(it)) ?? NSImage(contentsOfFile: it.path) ?? NSImage(named: NSImage.multipleDocumentsName)! }
            let gw = CGFloat(b["w"] as? Double ?? 150), gh = CGFloat(b["h"] as? Double ?? 100)   /* 화면이 보낸 크기 그대로 (화면 쪽에서 긴 변 150px로 통일) */
            let ox = CGFloat(b["ox"] as? Double ?? Double(gw / 2)), oy = CGFloat(b["oy"] as? Double ?? Double(gh / 2))
            let srcs = (fan.isEmpty ? [it0] : fan).map(pic)
            let padX: CGFloat = srcs.count > 1 ? gh * 0.3 + 26 : 26, padY: CGFloat = 26
            let img = DragOut.picture(srcs, w: gw, h: gh, padX: padX, padY: padY, count: list.count)
            let x0 = loc.x - ox - padX, y0 = w.isFlipped ? loc.y - oy - padY : loc.y - (gh - oy) - padY
            let clear = NSImage(size: img.size)
            // 맥 기본 끌기 그림 + 파일 약속. 보정본은 밖에 놓는 순간 만듦 (창 안에 놓거나 취소하면 안 만듦)
            let dis: [NSDraggingItem] = list.map { it in
                let isJpg = mode == "c1" || ["jpg", "jpeg"].contains(it.ext.lowercased().replacingOccurrences(of: ".", with: ""))
                let pv = PickPromise(fileType: isJpg ? "public.jpeg" : "public.image", delegate: dragOut)
                pv.userInfo = ["n": it.n, "file": it.name + (mode == "c1" ? ".jpg" : it.ext)]; let n = it.n
                pv.fileURL = { [weak self] in pickLog("끌기: 파일 주소 요청 \(n)"); self?.ensureDragRender(); return self?.dragFile(n, wait: 120).map { URL(fileURLWithPath: $0) } }
                return NSDraggingItem(pasteboardWriter: pv) }
            for (k, di) in dis.enumerated() { di.setDraggingFrame(NSRect(x: x0, y: y0, width: img.size.width, height: img.size.height), contents: k == 0 ? img : clear) }
            dragOut.dragImage = img; dragOut.inside = false; dragOut.grabOff = NSPoint(x: x0 - loc.x, y: y0 - loc.y)
            dragLock.lock(); dragFiles = [:]; dragDone = false; pendingRender = list; dragLock.unlock()
            let ses = w.beginDraggingSession(with: dis, event: ev, source: dragOut); ses.animatesToStartingPositionsOnCancelOrFail = true; ses.draggingFormation = .none
        case "export":
            let ids = b["ids"] as? [String] ?? [], token = b["token"] as? Int ?? 0
            var dest = (b["dest"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? destDir
            if !FileManager.default.fileExists(atPath: dest) { dest = destDir }   // 기본 위치가 사라졌으면 데스크톱
            let kinds = Set(b["kinds"] as? [String] ?? ((b["raw"] as? Bool ?? false) ? ["raw", "edit"] : ["edit"]))
            exportFiles(ids, kinds: kinds, kakao: b["kakao"] as? Bool ?? false, token: token, dest: dest, folder: b["folder"] as? String ?? "")
        case "chooseDir":   // 내보내기 위치 고르기
            let pnl = NSOpenPanel(); pnl.canChooseDirectories = true; pnl.canChooseFiles = false; pnl.canCreateDirectories = true; pnl.prompt = "여기로"
            pnl.directoryURL = URL(fileURLWithPath: (b["path"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? destDir)
            pnl.beginSheetModal(for: win) { r in if r == .OK, let u = pnl.url { self.js("PickApp.chosenDir(\(self.json([u.path]))[0])") } }
        case "trash":
            let paths = (b["paths"] as? [String] ?? []).filter { madeFiles.contains($0) }   // 꺼내기로 우리가 만든 것만
            var n = 0
            for p in paths { if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)) != nil { n += 1 } }
            toast("복사 취소 · 파일 \(n)개를 휴지통으로 옮겼어요")
        case "testdone":   // 시험 스크립트 결과 (PICK_TESTJS 쓸 때만)
            if let l = b["log"] as? String, let f = env["PICK_TESTOUT"] { try? l.write(toFile: f, atomically: true, encoding: .utf8) }
        case "selC1":   // (선택 동기화 안 함 — 2026-11-01 사용자 결정. 화면이 보내도 무시)
            return
            guard mode == "c1", NSApp.isActive, let ids = b["ids"] as? [String] else { return }
            selPending = ids
            C1.q.async {
                guard let ids = DispatchQueue.main.sync(execute: { () -> [String]? in defer { self.selPending = nil }; return self.selPending }) else { return }   // 밀린 건 마지막 것만
                let (old, order) = DispatchQueue.main.sync { (self.lastC1Sel, self.c1Order) }
                let new = Set(ids)
                DispatchQueue.main.sync { self.lastC1Sel = new; self.pushedSel = new; self.pushAt = Date() }
                if new == old { return }
                let t0 = Date(); defer { if self.evLogOn { pickLog("픽→캡쳐원 선택 보냄 \(Int(Date().timeIntervalSince(t0) * 1000))ms") } }
                // 한 장 → 바로 옆 한 장: 캡쳐원 방향키와 같은 명령 (실행 취소 기록 1개)
                if old.count == 1, new.count == 1, let oi = order.firstIndex(of: old.first!), let ni = order.firstIndex(of: new.first!), abs(ni - oi) == 1 {
                    _ = C1.quick("tell application \"Capture One\" to change selection my curDoc() to \(ni > oi ? "next" : "previous") variant"); return
                }
                // 그 밖엔: 새 것 먼저 고르고 옛 것 해제 ('선택 없음' 상태를 거치지 않음)
                if old.count == 1, new.count == 1 { self.jumpPairs.append(old.union(new)); if self.jumpPairs.count > 80 { self.jumpPairs.removeFirst() }; let cp = self.jumpPairs; DispatchQueue.main.async { self.jumpPairsMain = cp } }
                // 빠른 길: id 참조(variant id "X")로 새 것 select → 아는 옛 것 deselect (whose 검색 없음, 약 60ms)
                let refs = { (a: [String]) in a.map { "variant id \"\(C1.esc($0))\" of d" }.joined(separator: ", ") }
                let drop = old.subtracting(new).sorted()
                if !new.isEmpty, C1.quick("tell application \"Capture One\"\nset d to my curDoc()\nselect d variants {\(refs(ids))}\n\(drop.isEmpty ? "" : "deselect d variants {\(refs(drop))}")\nend tell") != nil { return }
                let vl = ids.map { "try\nset end of vs to (first variant of d whose id is \"\(C1.esc($0))\")\nend try" }.joined(separator: "\n")
                _ = C1.quick("tell application \"Capture One\"\nset d to my curDoc()\nset vs to {}\n\(vl)\nset oldVs to (every variant of d whose selected is true)\nif (count of vs) > 0 then select d variants vs\nset newIds to {\(ids.map { "\"\(C1.esc($0))\"" }.joined(separator: ", "))}\nset dropVs to {}\nrepeat with o in oldVs\nif newIds does not contain (id of o) then set end of dropVs to (contents of o)\nend repeat\nif (count of dropVs) > 0 then deselect d variants dropVs\nend tell")
            }
        case "sesClick":   // 세션 한 번 누름: 지금 캡쳐원에 열린 세션이면 다시 열 필요 없이 바로 픽만 돌아옴
            guard let path = b["path"] as? String else { return }
            let target = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            C1.q.async {
                let cur = C1.running ? (C1.docName() ?? "") : ""
                guard cur.hasPrefix(target) else { return }
                DispatchQueue.main.async { if !(self.mode == "c1" && self.doc == target) { self.openC1() } }
            }
        case "openSession":   // Pick에서 세션 고름 → 캡쳐원도 그 세션 열기 → 열리면 Pick도 다시 불러오기
            guard let path = b["path"] as? String else { return }
            if testC1Lock { pickLog("시험 잠금: 세션 열기 거부 \(path)"); return }
            opStack = []; redoStack = []
            let target = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if !C1.running { toast("캡쳐원이 꺼져 있어요"); return }
            switching = true; hint.stringValue = "캡쳐원에서 '\(target.precomposedStringWithCanonicalMapping)' 여는 중…"; reset()
            C1.q.async {
                _ = C1.openSession(path)
                var ok = false
                for _ in 0..<40 { if C1.docName()?.hasPrefix(target) == true { ok = true; break }; Thread.sleep(forTimeInterval: 0.5) }
                DispatchQueue.main.async { self.switching = false; if ok { self.openC1() } else { self.hint.stringValue = "캡쳐원에서 세션을 열지 못했어요" } }
            }
        case "newSessionDialog": askNewSession()
        case "newSession": createSession((b["name"] as? String ?? "").trimmingCharacters(in: .whitespaces))
        case "renameItem":   // 폴더 방식: 사진·폴더 이름 바꾸기 (맥 대화상자)
            guard mode == "folder", let path = b["path"] as? String else { return }
            let fm = FileManager.default; var isDir: ObjCBool = false; fm.fileExists(atPath: path, isDirectory: &isDir)
            let ext = isDir.boolValue ? "" : (path as NSString).pathExtension, base = isDir.boolValue ? (path as NSString).lastPathComponent : ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard let v = askText(isDir.boolValue ? "폴더 이름 바꾸기" : "사진 이름 바꾸기", ext.isEmpty ? "" : "확장자(.\(ext))는 그대로 둬요", base, ok: "바꾸기") else { return }
            let newName = ext.isEmpty ? v : v + "." + ext, dst = (path as NSString).deletingLastPathComponent + "/" + newName
            guard newName != (path as NSString).lastPathComponent else { return }
            guard !fm.fileExists(atPath: dst) else { toast("'\(newName)' 이름이 이미 있어요"); return }
            do { try fm.moveItem(atPath: path, toPath: dst) } catch { toast("이름을 바꾸지 못했어요 · \(error.localizedDescription)"); return }
            if !isDir.boolValue, XMPRating.isRaw(path), fm.fileExists(atPath: XMPRating.sidecar(path)) { try? fm.moveItem(atPath: XMPRating.sidecar(path), toPath: XMPRating.sidecar(dst)) }   // 옆 .xmp도 같은 이름으로
            if let old = keys[path], let bar = old.firstIndex(of: "|") { for sfx in ["", "#t"] { if let r = store.map[old + sfx] { store.set(String(newName + old[bar...]) + sfx, r); store.set(old + sfx, 0) } } }   // 별점·라벨(픽 저장분)은 새 이름으로 따라감
            openFolder(folderPath)
        case "newFolder":   // 폴더 방식: 지금 폴더 안에 새 폴더
            guard mode == "folder", let v = askText("새 폴더", "'\((folderPath as NSString).lastPathComponent.precomposedStringWithCanonicalMapping)' 안에 만들어요", "새 폴더", ok: "만들기") else { return }
            let dst = folderPath + "/" + v
            guard !FileManager.default.fileExists(atPath: dst) else { toast("'\(v)' 폴더가 이미 있어요"); return }
            do { try FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: false) } catch { toast("폴더를 만들지 못했어요"); return }
            openFolder(folderPath)
        case "trashDir":   // 폴더 방식: 하위 폴더를 휴지통으로 (확인창)
            guard mode == "folder", let path = b["path"] as? String else { return }
            let a = NSAlert(); a.messageText = "'\((path as NSString).lastPathComponent.precomposedStringWithCanonicalMapping)' 폴더를 휴지통으로 옮길까요?"; a.informativeText = "안에 든 파일도 함께 옮겨요. 휴지통에서 되살릴 수 있어요."; a.addButton(withTitle: "휴지통으로"); a.addButton(withTitle: "취소")
            guard env["PICK_TESTANSWER"] != nil || a.runModal() == .alertFirstButtonReturn else { return }
            if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)) != nil { toast("휴지통으로 옮겼어요"); openFolder(folderPath) } else { toast("휴지통으로 옮기지 못했어요") }
        case "moveFiles":   // 폴더 방식: 왼쪽 패널·필름스트립의 폴더에 끌어 놓음 = 같은 디스크면 이동, 다른 디스크면 복사, ⌥는 항상 복사 (브릿지처럼). ⌘Z로 되돌림
            guard mode == "folder", let paths = b["paths"] as? [String], let dest = b["dest"] as? String else { return }
            let token = b["token"] as? Int ?? 0, fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dest, isDirectory: &isDir), isDir.boolValue else { toast("놓은 폴더를 찾지 못했어요"); js("PickApp.moveDone(\(token),\(json(paths)),false)"); return }
            func vol(_ p: String) -> String { ((try? URL(fileURLWithPath: p).resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject)?.description ?? p }
            let copy = (b["copy"] as? Bool ?? false) || vol(dest) != vol(((paths.first ?? dest) as NSString).deletingLastPathComponent)
            var done: [(String, String, Bool)] = [], failed: [String] = [], dup = 0, n = 0
            for src in paths {
                guard fm.fileExists(atPath: src), (src as NSString).deletingLastPathComponent != dest else { failed.append(src); continue }
                let name = (src as NSString).lastPathComponent; var dst = dest + "/" + name
                if fm.fileExists(atPath: dst) { if copy { dst = uniquePath(dest, name) } else { dup += 1; failed.append(src); continue } }   // 이동은 같은 이름이 있으면 건너뜀 (덮어쓰지 않음)
                do { if copy { try fm.copyItem(atPath: src, toPath: dst) } else { try fm.moveItem(atPath: src, toPath: dst) } } catch { failed.append(src); continue }
                done.append((src, dst, copy)); n += 1
                let sc = XMPRating.sidecar(src), sd = XMPRating.sidecar(dst)   // RAW 옆 .xmp도 같이
                if XMPRating.isRaw(src), fm.fileExists(atPath: sc), !fm.fileExists(atPath: sd), (try? copy ? fm.copyItem(atPath: sc, toPath: sd) : fm.moveItem(atPath: sc, toPath: sd)) != nil { done.append((sc, sd, copy)) }
            }
            moved[token] = done
            let place = dest == home + "/Desktop" ? "데스크톱" : "'\((dest as NSString).lastPathComponent.precomposedStringWithCanonicalMapping)'"
            var msg = n > 0 ? "\(n)장 \(place)\(copy ? "에 복사했어요" : "로 옮겼어요")" : (copy ? "복사하지 못했어요" : "옮기지 못했어요")
            if dup > 0 { msg += " · 같은 이름이 있는 \(dup)장은 건너뜀" }
            toast(msg); pickLog("폴더로 \(copy ? "복사" : "이동") \(n)장 → \(dest)")
            js("PickApp.moveDone(\(token),\(json(failed)),\(copy))")
        case "unmove":   // ⌘Z: 옮긴 건 제자리로, 복사한 건 복사본을 휴지통으로
            guard let token = b["token"] as? Int, let list = moved.removeValue(forKey: token) else { return }
            let fm = FileManager.default; var n = 0
            for (src, dst, copied) in list.reversed() {
                if copied { if (try? fm.trashItem(at: URL(fileURLWithPath: dst), resultingItemURL: nil)) != nil { n += 1 } }
                else if !fm.fileExists(atPath: src), (try? fm.moveItem(atPath: dst, toPath: src)) != nil { n += 1 }
            }
            if n < list.count { toast("일부를 되돌리지 못했어요") }
        case "clipSet":   // 폴더 방식 ⌘C: 폴더를 옮겨 다녀도(화면이 다시 뜸) 복사 목록은 앱이 기억
            clipPaths = b["paths"] as? [String] ?? []
        case "pasteFiles":   // 폴더 방식 ⌘V: 복사해 둔 사진을 지금 폴더로 복사
            guard mode == "folder" else { return }
            guard !clipPaths.isEmpty else { toast("먼저 ⌘C로 복사해 주세요"); return }
            let fm = FileManager.default; var n = 0, skipped = 0
            for src in clipPaths {
                guard fm.fileExists(atPath: src) else { continue }
                if (src as NSString).deletingLastPathComponent == folderPath { skipped += 1; continue }   // 같은 폴더엔 복사 안 함
                var dst = folderPath + "/" + (src as NSString).lastPathComponent, k = 2
                let base = ((src as NSString).lastPathComponent as NSString).deletingPathExtension, ext = (src as NSString).pathExtension
                while fm.fileExists(atPath: dst) { dst = folderPath + "/" + base + " \(k)." + ext; k += 1 }
                if (try? fm.copyItem(atPath: src, toPath: dst)) != nil { n += 1
                    if XMPRating.isRaw(src), fm.fileExists(atPath: XMPRating.sidecar(src)) { try? fm.copyItem(atPath: XMPRating.sidecar(src), toPath: XMPRating.sidecar(dst)) } }   // 옆 .xmp도 같이
            }
            toast(n > 0 ? "\(n)장 붙여넣었어요" + (skipped > 0 ? " · 같은 폴더의 \(skipped)장은 건너뜀" : "") : (skipped > 0 ? "이미 이 폴더에 있는 사진이에요" : "붙여넣지 못했어요"))
            if n > 0 { openFolder(folderPath) }
        case "trashSession":   // 세션 폴더째 휴지통으로 (캡쳐원 전용 바로 아래 세션만, 지금 열린 세션은 안 됨)
            guard let path = b["path"] as? String else { return }
            let dir = (path as NSString).deletingLastPathComponent, name = (dir as NSString).lastPathComponent
            guard (dir as NSString).deletingLastPathComponent == sessionsRoot, path.hasSuffix(".cosessiondb") else { toast("지울 수 없는 위치예요"); return }
            C1.q.async {
                let cur = C1.running ? (C1.docName() ?? "") : ""
                DispatchQueue.main.async {
                    if cur.replacingOccurrences(of: ".cosessiondb", with: "") == name { self.toast("지금 캡쳐원에 열린 세션은 지울 수 없어요"); return }
                    if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: dir), resultingItemURL: nil)) != nil {
                        _ = try? FileManager.default.trashItem(at: URL(fileURLWithPath: cacheRoot + "/" + name), resultingItemURL: nil)   /* 픽 미리보기 캐시도 */
                        self.toast("'\(name)' 세션을 휴지통으로 옮겼어요"); self.js("PickApp.sessions(\(self.json(sessionList())))")
                    } else { self.toast("세션을 옮기지 못했어요") }
                }
            }
        case "emptySession":   /* 지금 열린 세션을 처음 만든 상태로: 캡쳐원 문서를 닫고 → 세션 폴더째 Mac 휴지통(되살릴 수 있음) → 같은 이름으로 새 세션을 만들어 다시 엶 */
            guard mode == "c1", let sd = sessionDir(), !sd.isEmpty, !switching else { toast("캡쳐원 세션이 열려 있을 때만 비울 수 있어요"); return }
            let total = items.count, name = doc, parent = (sd as NSString).deletingLastPathComponent
            let al = NSAlert(); al.messageText = "'\(name.precomposedStringWithCanonicalMapping)' 세션을 비울까요?"; al.informativeText = "사진 \(total)장(원본·보정본·선택본)을 Mac 휴지통으로 옮기고, 같은 이름의 빈 세션을 새로 만들어요. 휴지통에서 되살릴 수 있어요."
            al.addButton(withTitle: "비우기"); al.addButton(withTitle: "취소"); al.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true); guard al.runModal() == .alertFirstButtonReturn else { return }
            let fm = FileManager.default, cache = cacheDir
            switching = true; hint.stringValue = "세션 비우는 중…"; reset()
            C1.q.async {
                /* 안전장치: 캡쳐원에 지금 열린 문서가 그 세션일 때만 */
                let cur = (C1.docName() ?? "").replacingOccurrences(of: ".cosessiondb", with: "")
                guard cur == name else { pickLog("세션 비우기 중단: 캡쳐원 문서(\(cur)) ≠ 픽 세션(\(name))"); DispatchQueue.main.async { self.switching = false; self.toast("캡쳐원에 열린 세션이 달라서 비우지 않았어요"); self.openC1() }; return }
                let closed = C1.run("tell application \"Capture One\"\nwith timeout of 120 seconds\nset d to my curDoc()\nsave d\nclose d\nend timeout\nreturn \"ok\"\nend tell") != nil
                Thread.sleep(forTimeInterval: 1.0)
                guard closed, (C1.docName() ?? "").replacingOccurrences(of: ".cosessiondb", with: "") != name else { pickLog("세션 비우기 중단: 문서를 닫지 못함"); DispatchQueue.main.async { self.switching = false; self.toast("캡쳐원에서 세션을 닫지 못했어요"); self.openC1() }; return }
                let trashed = (try? fm.trashItem(at: URL(fileURLWithPath: sd), resultingItemURL: nil)) != nil
                if !cache.isEmpty { _ = try? fm.trashItem(at: URL(fileURLWithPath: cache), resultingItemURL: nil) }
                guard trashed else { pickLog("세션 비우기 중단: 폴더를 휴지통으로 못 옮김 \(sd)"); DispatchQueue.main.async { self.switching = false; self.toast("세션 폴더를 옮기지 못했어요") }; _ = C1.openSession(sd + "/" + name + ".cosessiondb"); return }
                let made = C1.run("""
                    with timeout of 600 seconds
                    tell application "Capture One"
                    make new document with properties {name:"\(C1.esc(name))", path:(POSIX file "\(C1.esc(parent))"), kind:session}
                    end tell
                    end timeout
                    """) != nil
                var opened = false
                if made { for _ in 0..<40 { if C1.docName()?.hasPrefix(name) == true { opened = true; break }; Thread.sleep(forTimeInterval: 0.5) } }
                pickLog("세션 비우기: \(name) 폴더 휴지통(\(trashed)) · 새 세션(\(made ? "만듦" : "실패")) · 열림(\(opened))")
                DispatchQueue.main.async { self.switching = false; if opened { self.toast("'\(name)' 세션을 비웠어요 · 사진은 Mac 휴지통에 있어요"); self.openC1() } else { self.hint.stringValue = "세션을 다시 만들지 못했어요"; self.toast("세션을 다시 만들지 못했어요 · 캡쳐원을 확인해 주세요") } }
            }
        case "help": showHelp(b["on"] as? Bool)
        case "reveal":
            if let path = b["path"] as? String { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        case "revealSession":
            if let path = b["path"] as? String, !path.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)]) }
            else if let sd = sessionDir() { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: sd)]) }
        case "openFolder":
            if let path = b["path"] as? String { openFolder(path) }
        case "listDir":
            if let path = b["path"] as? String { DispatchQueue.global(qos: .userInitiated).async { let rows = subfolderRows(path); DispatchQueue.main.async { self.js("PickApp.dir(\(self.json(path)),\(self.json(rows)))") } } }
        case "eject":   // 왼쪽 패널 디스크 ⏏
            if let path = b["path"] as? String {
                let name = (path as NSString).lastPathComponent
                if mode == "folder", folderPath == path || folderPath.hasPrefix(path + "/") { openFolder(home + "/Desktop") }
                DispatchQueue.global(qos: .userInitiated).async {
                    do { try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: path)); DispatchQueue.main.async { self.toast("'\(name)' 추출했어요 · 이제 빼도 돼요") } }
                    catch { DispatchQueue.main.async { self.toast("'\(name)' 추출 못 했어요 · 쓰는 중인 앱을 닫아 주세요") } }
                }
            }
        case "delete":
            c1Mut += 1; opStack.append(("del", b["token"] as? Int ?? 0)); redoStack = []
            let ids = b["ids"] as? [String] ?? [], token = b["token"] as? Int ?? 0
            let list = ids.compactMap { byID[$0] }.map { items[$0] }
            guard !list.isEmpty else { return }
            if mode == "c1" && useC1MenuDelete {   // (보류) 캡쳐원 메뉴로 지우기 — 확인 창·대상 확인이 덜 돼서 꺼 둠
                opStack.removeLast(); opStack.append(("c1", 0))   // 캡쳐원 기록에 남으니 ⌘Z는 캡쳐원 실행 취소로
                C1.q.async {
                    let selScript = """
                        tell application "Capture One"
                        set d to my curDoc()
                        \(C1.vlist(ids))
                        deselect d variants (every variant of d whose selected is true)
                        select d variants vs
                        return count of vs
                        end tell
                        """
                    let ok = C1.run(selScript) != nil   // 먼저 선택(캡쳐원이 뒤에 있을 때) → 활성화 → 메뉴
                    if self.c1HasDialog() { DispatchQueue.main.async { self.toast("캡쳐원에 열린 창이 있어요 · 닫고 다시 해 주세요"); self.js("PickApp.undeleted(\(token))") }; return }
                    let label = ok ? self.pressC1Menu(["이미지", "Image"], ["삭제", "Delete"], confirm: true, selectFirst: selScript) : ""   // 이미지 › 삭제(⌘⌫)
                    pickLog("지우기(캡쳐원 메뉴): \(label.isEmpty ? "실패" : label) \(ids.count)장")
                    if label.isEmpty || label == "-" { DispatchQueue.main.async { self.toast("삭제하지 못했어요"); self.js("PickApp.undeleted(\(token))") }; return }
                    Thread.sleep(forTimeInterval: 0.3)
                    self.resyncC1(); self.followC1Selection()
                }
                return
            }
            if mode == "c1" {
                let byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
                C1.q.async {   // 기록도 같은 줄(C1.q)에서 → 되돌리기가 삭제보다 먼저 처리되는 일 없음
                    var ok = true
                    guard let (whole, part) = C1.planDelete(ids) else { DispatchQueue.main.async { self.toast("삭제하지 못했어요"); self.js("PickApp.undeleted(\(token))") }; return }
                    // 복제본이 남는 사진: 그 변형만 (되살리기용 보정값·별점 먼저 저장)
                    var revives: [(String, String, String, Int)] = []
                    if !part.isEmpty {
                        let snaps = C1.snapshot(part.map(\.0))
                        for (id, sib) in part { revives.append((id, sib, snaps[id] ?? "", byId[id]?.r ?? 0)) }
                        ok = C1.deleteVariants(part.map(\.0)) && ok
                    }
                    var src: String?
                    if !whole.isEmpty { src = C1.trash(whole); ok = ok && src != nil }
                    self.c1Trashed[token] = (src ?? "", whole.compactMap { byId[$0]?.name })
                    self.c1Revive[token] = revives
                    // 변형만 지운 경우: 캡쳐원 실행 취소로 그대로 되돌릴 수 있게 기록
                    if whole.isEmpty, !part.isEmpty { let m = DispatchQueue.main.sync { self.c1Mut }
                        self.c1Undo[token] = (m, Date(), part.map(\.0), Dictionary(uniqueKeysWithValues: part.map { ($0.0, byId[$0.0]?.name ?? "") })) }
                    DispatchQueue.main.async { if !ok { self.toast("일부를 삭제하지 못했어요") } }
                }
            } else {
                var where_: [String] = []
                var origs: [String] = []
                for it in list {
                    var paths = [it.path]; let sc = XMPRating.sidecar(it.path); if XMPRating.isRaw(it.path), FileManager.default.fileExists(atPath: sc) { paths.append(sc) }   // RAW 옆 .xmp도 같이 (브릿지처럼)
                    for p in paths { var u: NSURL?; origs.append(p); if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: &u)) != nil { where_.append(u?.path ?? "") } else { where_.append("") } }
                }
                trashed[token] = ("", origs, where_)

            }
        case "c1undo", "c1redo":   // 픽 ⌘Z/⇧⌘Z = 캡쳐원 실행 취소/다시 실행 (통째로 지운 것만 픽이 직접)
            let redo = cmd == "c1redo"
            guard mode == "c1" else { return }
            guard AXIsProcessTrusted() else { askAccessibility(); toast("캡쳐원 실행 취소를 쓰려면 '손쉬운 사용'에서 Pick을 켜 주세요"); return }
            if c1HasDialog() { toast("캡쳐원에 열린 창이 있어요 · 닫고 다시 해 주세요"); return }
            let top = redo ? redoStack.popLast() : opStack.popLast()
            lastUndoKind = top?.0 ?? ""
            if let top { if redo { opStack.append(top) } else { redoStack.append(top) } }
            C1.q.async {
                if let top, top.0 == "del", let t = self.c1Trashed[top.1], !t.1.isEmpty {
                    // 통째로 지운 사진: 세션 휴지통 ↔ 원래 폴더 (캡쳐원 기록엔 없음)
                    let ok = redo ? C1.retrash(t.1) : C1.untrash(t.1, to: t.0)
                    pickLog("픽 \(redo ? "다시 지우기" : "되돌리기"): 통째로 지운 \(t.1.count)장 \(ok ? "됨" : "실패")")
                    if (self.c1Revive[top.1] ?? []).isEmpty {   // 변형만 지운 것도 같이 있었으면 아래 캡쳐원 실행 취소도
                        DispatchQueue.main.async { self.toast(redo ? "다시 지웠어요" : "지운 사진을 되돌렸어요") }; self.resyncC1(); return }
                }
                // 지금 한 장만 골라져 있고 그 사진이 뛰어 고른 쌍에 있으면, 되돌린 결과가 {옛,새}인지 보고 한 단계 더
                let before = DispatchQueue.main.sync { self.lastC1Sel }
                let maybePair = before.count == 1 && self.jumpPairs.contains { $0.contains(before.first!) }
                let again: (() -> Bool)? = maybePair ? {
                    usleep(25000)
                    guard let now = C1.quickSelection() else { return false }
                    return now.count == 2 && self.jumpPairs.contains(now)
                } : nil
                let label = self.pressC1Undo(redo, again: again)   // 예: 등급 실행 취소, 변형들 삭제 실행 취소
                if label.isEmpty { DispatchQueue.main.async { self.toast("캡쳐원을 찾지 못했어요") }; return }
                let shown = label
                DispatchQueue.main.async { self.toast(shown) }
                if label.contains("선택") || label.contains("Selection") { usleep(30000); self.followC1Selection() }   // 선택만 되돌린 것: 목록 다시 읽을 필요 없음
                else { Thread.sleep(forTimeInterval: 0.2); self.resyncC1(); self.followC1Selection() }
            }
        case "undelete":
            guard let token = b["token"] as? Int else { return }
            pickLog("되돌리기 요청 \(token) · 기록 \(c1Undo[token] != nil ? "캡쳐원취소가능" : "없음")")
            c1Mut += 1
            if mode == "c1" {
                C1.q.async {
                    pickLog("되돌리기 시작 \(token)")
                    guard let t = self.c1Trashed.removeValue(forKey: token) else { DispatchQueue.main.async { self.toast("되돌릴 삭제 기록이 없어요") }; return }
                    // 1) 이 삭제가 캡쳐원에서 마지막으로 한 일이면 → 캡쳐원 실행 취소(⌘Z)로 지운 그 변형을 그대로
                    var done = Set<String>()
                    if let u = self.c1Undo.removeValue(forKey: token) { done = self.undoInC1(u) }
                    if !done.isEmpty { self.c1Revive[token] = (self.c1Revive[token] ?? []).filter { !done.contains($0.0) } }   // 안 돌아온 것만 복제본으로
                    var ok = t.1.isEmpty ? true : C1.untrash(t.1, to: t.0)
                    // 되살린 변형은 캡쳐원 id만 새로 바뀜 → 화면 다시 불러오지 않고 id만 바꿔 끼움
                    var remap: [String: String] = [:]
                    for (old, sib, snap, r) in self.c1Revive.removeValue(forKey: token) ?? [] { if let nid = C1.revive(sib, snap: snap, rating: r) { remap[old] = nid } else { ok = false } }
                    if !remap.isEmpty { DispatchQueue.main.async { self.remapIDs(remap) } }
                    if !ok { DispatchQueue.main.async { self.toast("되돌리지 못했어요 · 캡쳐원 세션 휴지통에서 직접 옮겨 주세요") } }
                }
                return
            }
            guard let t = trashed[token] else { return }
            trashed.removeValue(forKey: token)
            do {
                var n = 0
                for (orig, inTrash) in zip(t.1, t.2) where !inTrash.isEmpty { if (try? FileManager.default.moveItem(atPath: inTrash, toPath: orig)) != nil { n += 1 } }
                if n < t.1.count { toast("일부를 되돌리지 못했어요 · 휴지통을 확인해 주세요") }
            }
        case "clone": c1Mut += 1; opStack.append(("clone", 0)); redoStack = []
            guard mode == "c1" else { toast("변형 복제는 캡쳐원 세션에서만 돼요"); return }
            let ids = b["ids"] as? [String] ?? []
            C1.q.async { let ok = C1.clone(ids); if ok { Thread.sleep(forTimeInterval: 0.3); self.resyncC1(); self.followC1Selection() }; DispatchQueue.main.async { self.toast(ok ? "변형 복제 \(ids.count)장" : "변형 복제를 못 했어요") } }
        case "qlShow", "qlHide", "qlZoom", "qlZ", "qlCap":   // 파인더식 미리보기 창 (픽 창과 별개). 자리(from/to)는 웹 좌표 → 화면 좌표
            guard let w = web, let win = w.window else { return }
            func scr(_ d: [String: Any]?) -> NSRect {
                let l = d?["l"] as? Double ?? 0, tt = d?["t"] as? Double ?? 0, ww = d?["w"] as? Double ?? 100, hh = d?["h"] as? Double ?? 100
                let r = NSRect(x: l, y: w.isFlipped ? tt : Double(w.bounds.height) - tt - hh, width: ww, height: hh)
                return win.convertToScreen(w.convert(r, to: nil)) }
            qlPanel.onClose = { [weak self] in self?.js("hideBig()") }
            qlPanel.onToggle = { [weak self] in self?.js("PickApp.qlToggleRej()") }
            if cmd == "qlHide" { qlPanel.hide(to: scr(b["to"] as? [String: Any])); return }
            if cmd == "qlZoom" { qlPanel.zoom(b["f"] as? Int ?? 0); return }
            if cmd == "qlZ" { qlPanel.scroll?.zHeld = b["on"] as? Bool ?? false; return }
            if cmd == "qlCap" { if let n = b["n"] as? String, let k = byN[n] { qlPanel.setCaption(name: items[k].name + (mode == "c1" ? ".jpg" : items[k].ext), cap: b) }; return }   // 전체화면 캡션(별점·색 라벨) 갱신
            guard let n = b["n"] as? String, let k = byN[n] else { return }
            let it = items[k], first = b["first"] as? Bool ?? true
            let small = (thumbs.object(forKey: ("m" + it.n) as NSString) ?? thumbs.object(forKey: ("s" + it.n) as NSString)).flatMap { NSImage(data: $0 as Data) }   // 캐시 키는 "s"/"m"+번호 (전엔 번호만 찾아 늘 비어 있었음 → 큰 그림 올 때까지 이전 사진이 보임)
            let pv = previewPath(it), path = it.path
            let isJpg = ["jpg", "jpeg"].contains(it.ext.lowercased().replacingOccurrences(of: ".", with: ""))   // 원본이 JPG면 원본 그대로(확대 때 원본 픽셀), RAW면 2600px 미리보기
            qlPanel.show(small: small, big: { (isJpg ? NSImage(contentsOfFile: path) : nil) ?? NSImage(contentsOfFile: pv) ?? NSImage(contentsOfFile: path) }, name: it.name + (mode == "c1" ? ".jpg" : it.ext), from: scr(b["from"] as? [String: Any]), screen: win.screen ?? NSScreen.main!, first: first, full: b["full"] as? Bool ?? false)
            qlPanel.setCaption(name: it.name + (mode == "c1" ? ".jpg" : it.ext), cap: b["cap"] as? [String: Any] ?? [:])
        case "jserr": pickLog("화면 오류: \(b["msg"] as? String ?? "")")
        case "topButtons":
            web?.topButtons = (b["rects"] as? [[Double]] ?? []).compactMap { $0.count == 4 ? NSRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
        default: break
        }
    }

    // 스타일 적용 → 조정값 다시 읽기 → 그 사진들 미리보기 다시
    func applyStyle(_ name: String, _ ids: [String]) {
        toast("'\(name)' 적용 중 · \(ids.count)장")
        C1.q.async {
            guard C1.applyStyle(name, ids) else { DispatchQueue.main.async { self.toast("스타일을 적용하지 못했어요") }; return }
            let adj = C1.adjustments(ids)
            DispatchQueue.main.async {
                var upd: [String: [String: Double]] = [:]
                for (id, m) in adj { if let k = self.byID[id] { self.items[k].adj = m; upd[self.items[k].n] = m } }
                let ns = ids.compactMap { self.byID[$0] }.map { self.items[$0].n }
                for n in ns { self.thumbs.removeObject(forKey: ("s" + n) as NSString) }
                self.announced.subtract(ns); self.expected.subtract(ns)
                for n in ns { if let k = self.byN[n] { try? FileManager.default.removeItem(atPath: self.previewPath(self.items[k])) } }
                self.js("PickApp.styled(\(self.json(upd)))")
                self.toast("'\(name)' 적용 완료 · 바뀐 색감으로 다시 불러오는 중")
                self.makePreviews(ids)
            }
        }
    }

    // 꺼내기: 원본 RAW는 그대로 복사, 보정본은 캡쳐원 레시피로(폴더 방식은 JPG·PNG 등만 그대로 복사)
    // 내보내기 (셀렉 내보내기와 같음): RAW 그대로 · 원본(보정 없는 JPG, rawjpg) · 보정본(캡쳐원 처리) · 카톡용(19.5MB 넘으면 화질만 낮춤) · 새 폴더
    func exportFiles(_ ids: [String], kinds kinds0: Set<String>, kakao: Bool, token: Int, dest base: String, folder: String) {
        let list = ids.compactMap { byID[$0] }.map { items[$0] }
        guard !list.isEmpty else { return }
        let fm = FileManager.default, kinds = mode == "folder" ? Set(["raw"]) : kinds0, isC1 = mode == "c1"
        var dest = base, newFolder: String?
        if !folder.isEmpty {
            dest = base + "/" + folder
            if !fm.fileExists(atPath: dest) { try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true); newFolder = dest }
        }
        let what = [kinds.contains("raw") ? (isC1 ? "RAW" : "사진") : nil, kinds.contains("orig") ? "원본" : nil, kinds.contains("edit") && isC1 ? "보정본" : nil].compactMap { $0 }.joined(separator: "·")
        toast("\(what) \(list.count)장 내보내는 중…")
        let inApp = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/rawjpg").path   // 앱 안에 같이 (2026-11-05: ydot·yap 없이도 동작)
        let rawjpg = fm.isExecutableFile(atPath: inApp) ? inApp : home + "/Library/Application Support/cc/rawjpg"
        DispatchQueue.global(qos: .userInitiated).async {
            var made: [String] = [], bad = 0
            if kinds.contains("raw") {
                for it in list { let to = uniquePath(dest, it.name + it.ext); if (try? fm.copyItem(atPath: it.path, toPath: to)) != nil { made.append(to); if kakao, ["jpg", "jpeg"].contains((to as NSString).pathExtension.lowercased()) { kakaoShrink(to) } } else { bad += 1 } }
            }
            if kinds.contains("orig") {
                for it in list {
                    let to = uniquePath(dest, it.name + "_원본.jpg")
                    let p = Process(); p.executableURL = URL(fileURLWithPath: rawjpg); p.arguments = [it.path, to]
                    if (try? p.run()) != nil { p.waitUntilExit() }
                    if p.terminationStatus == 0, fm.fileExists(atPath: to) { made.append(to); if kakao { kakaoShrink(to) } } else { bad += 1 }
                }
            }
            let done: ([String], String) -> Void = { edits, note in
                if kakao { edits.forEach(kakaoShrink) }
                let all = made + edits
                DispatchQueue.main.async { self.finishExport(newFolder.map { [$0] } ?? all, count: all.count, token: token, note: (bad > 0 ? " · \(bad)장 실패" : "") + note, dest: dest) }
            }
            guard kinds.contains("edit"), isC1 else { done([], ""); return }
            // 보정본: 임시 폴더에 뽑고, 다 써지면 옮김
            let stage = cacheRoot + "/export-\(Int(Date().timeIntervalSince1970))"
            try? fm.createDirectory(atPath: stage, withIntermediateDirectories: true)
            C1.q.async {
                let want = C1.process(list.map(\.id), recipe: "pick-export", into: stage, fullSize: true).count
                var waited = 0.0
                func poll() {
                    let files = ((try? fm.contentsOfDirectory(atPath: stage)) ?? []).filter { $0.lowercased().hasSuffix(".jpg") }
                    let ok = files.filter { jpegComplete(stage + "/" + $0) }
                    if ok.count >= want || waited > 1800 {
                        var edits: [String] = []
                        for f in ok.sorted() { let to = uniquePath(dest, f); if (try? fm.moveItem(atPath: stage + "/" + f, toPath: to)) != nil { edits.append(to) } }
                        cleanCache(stage, removeFolder: true)
                        done(edits, ok.count < want ? " · 보정본 \(want - ok.count)장은 시간 안에 못 만들었어요" : "")
                        return
                    }
                    waited += 1; DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: poll)
                }
                DispatchQueue.global().async(execute: poll)
            }
        }
    }
    // 창 밖에 놓은 사진 → 창 없이 바로 보정본(폴더 방식은 원본 파일). 끌기 시작할 때 미리 만들어 둠
    let dragLock = NSCondition()
    var dragFiles: [String: String] = [:], dragDone = true, dragStage = ""
    var pendingRender: [Item]?
    func ensureDragRender() { dragLock.lock(); let l = pendingRender; pendingRender = nil; dragLock.unlock(); if let l { pickLog("끌기: 놓음 → 보정본 \(l.count)장 만들기"); startDragRender(l) } }
    func startDragRender(_ list: [Item]) {
        dragLock.lock(); dragFiles = [:]; dragDone = false; dragLock.unlock()
        if mode != "c1" {
            dragLock.lock(); for it in list { dragFiles[it.n] = it.path }; dragDone = true; dragLock.broadcast(); dragLock.unlock(); return
        }
        let fm = FileManager.default, stage = cacheRoot + "/drag-\(UUID().uuidString.prefix(8))"
        try? fm.createDirectory(atPath: stage, withIntermediateDirectories: true)
        // 포토샵 등이 열어 둔 파일일 수 있어 바로 안 지움 → 하루 지난 것만 정리
        for d in (try? fm.contentsOfDirectory(atPath: cacheRoot)) ?? [] where d.hasPrefix("drag-") {
            let p = cacheRoot + "/" + d
            if let t = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, Date().timeIntervalSince(t) > 86400 { cleanCache(p, removeFolder: true) } }
        dragStage = stage
        C1.q.async {
            let want = C1.process(list.map(\.id), recipe: "pick-export", into: stage, fullSize: true).count
            var waited = 0.0, lastOk = 0
            func poll() {
                let files = ((try? fm.contentsOfDirectory(atPath: stage)) ?? []).filter { $0.lowercased().hasSuffix(".jpg") }.sorted()
                let ok = files.filter { jpegComplete(stage + "/" + $0) }
                if ok.count != lastOk { lastOk = ok.count }
                if ok.count >= want || waited > 600 {
                    var got: [String: String] = [:]; var used = Set<String>()
                    for it in list {   // 같은 이름(복제본)은 순서대로
                        if let f = ok.first(where: { !used.contains($0) && ($0 as NSString).deletingPathExtension.hasPrefix(it.name) }) { used.insert(f); got[it.n] = stage + "/" + f }
                    }
                    self.dragLock.lock(); self.dragFiles = got; self.dragDone = true; self.dragLock.broadcast(); self.dragLock.unlock()
                    return
                }
                waited += 0.4; DispatchQueue.global().asyncAfter(deadline: .now() + 0.4, execute: poll)
            }
            DispatchQueue.global().async(execute: poll)
        }
    }
    // 그 사진의 보정본 파일 (다 만들어질 때까지 기다림)
    func dragFile(_ n: String, wait: TimeInterval) -> String? {
        dragLock.lock(); defer { dragLock.unlock() }
        let until = Date().addingTimeInterval(wait)
        while !dragDone { if !dragLock.wait(until: until) { break } }
        return dragFiles[n]
    }
    func fulfillPromise(_ n: String, _ url: URL, _ done: @escaping (Error?) -> Void) {
        DispatchQueue.global().async {
            pickLog("끌기: 파일 약속 채우기 \(n)"); self.ensureDragRender()
            guard let src = self.dragFile(n, wait: 600) else { done(NSError(domain: "Pick", code: 2, userInfo: [NSLocalizedDescriptionKey: "보정본을 만들지 못했어요"])); return }
            let fm = FileManager.default
            // 포토샵 등은 받을 자리에 빈 파일을 먼저 만들어 두고 그 파일을 엶 → 비어 있으면 그 자리에 그대로 씀
            let empty = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int) == 0
            if empty { try? fm.removeItem(at: url) }
            let to = empty ? url.path : uniquePath(url.deletingLastPathComponent().path, url.lastPathComponent)
            pickLog("끌기: 약속 → \(to)\(empty ? " (빈 자리)" : "")")
            if (try? fm.copyItem(atPath: src, toPath: to)) != nil { done(nil); self.promised([to]) }
            else { done(NSError(domain: "Pick", code: 1, userInfo: [NSLocalizedDescriptionKey: "보정본을 옮기지 못했어요"])) }
        }
    }
    func promised(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        DispatchQueue.main.async { self.madeFiles.formUnion(paths); self.js("PickApp.droppedDone(\(self.json(paths)))") }
    }
    func finishExport(_ paths: [String], count: Int, token: Int, note: String, dest: String) {
        madeFiles.formUnion(paths)
        js("PickApp.exported(\(token),\(json(paths)))")
        let place = dest == home + "/Desktop" ? "데스크톱" : "'\((dest as NSString).lastPathComponent)'"
        toast("\(place)에 \(count)개 파일 내보내기 완료" + note)
        NSSound(named: "Glass")?.play()
    }

    // MARK: pick:// 주소 → 파일·이미지
    func webView(_ w: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let host = url.host ?? "", parts = url.path.split(separator: "/").map(String.init)
        if host == "app" {
            let rel = parts.joined(separator: "/"), base = Bundle.main.resourcePath! + "/ui/"
            guard !rel.contains(".."), let d = FileManager.default.contents(atPath: base + rel) else { pickLog("앱 파일 못 읽음: \(rel)"); fail(task); return }
            let ext = (rel as NSString).pathExtension
            /* 글꼴은 pick://app/fonts/… URL로 (한때 base64로 심었으나, 같은 웹뷰에서 폴더를 바꿀 때마다 435KB를 다시 디코딩해 60~200ms 걸림. URL이면 WebKit이 캐시) · 못 받으면 index.html의 JS가 fetch로 다시 시도 */
            reply(task, url, d, ["html": "text/html", "ttf": "font/ttf", "woff2": "font/woff2", "js": "text/javascript", "css": "text/css"][ext] ?? "application/octet-stream"); return
        }
        if host == "icon" {   // 폴더·디스크의 Finder 아이콘. ?s=크기(px), 기본 32 (왼쪽 패널) · 필름스트립·미리보기는 512
            let path = url.path, px = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "s" }?.value ?? "") ?? 32
            let key = path + "@\(px)"
            if let d = App.iconCache[key] { reply(task, url, d, "image/png"); return }
            let img = NSWorkspace.shared.icon(forFile: path)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep); NSGraphicsContext.current?.imageInterpolation = .high; img.draw(in: NSRect(x: 0, y: 0, width: px, height: px)); NSGraphicsContext.restoreGraphicsState()
            guard let d = rep.representation(using: .png, properties: [:]) else { fail(task); return }
            App.iconCache[key] = d; reply(task, url, d, "image/png"); return
        }
        guard host == "img", parts.count == 2, let k = byN[parts[1]] else { fail(task); return }
        let it = items[k], size = parts[0]
        ioq.async {
            let d = size == "s" ? self.small(it) : size == "m" ? self.medium(it) : self.big(it)
            DispatchQueue.main.async { if let d = d { self.reply(task, url, d, "image/jpeg") } else { self.fail(task) } }
        }
    }
    func webView(_ w: WKWebView, stop task: WKURLSchemeTask) {}
    func reply(_ t: WKURLSchemeTask, _ url: URL, _ d: Data, _ type: String) {
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type, "Content-Length": "\(d.count)", "Cache-Control": "max-age=3600"])!
        t.didReceive(r); t.didReceive(d); t.didFinish()
    }
    func fail(_ t: WKURLSchemeTask) { t.didFailWithError(NSError(domain: "pick", code: 404)) }

    // 캡쳐원 썸네일 캐시: <사진 폴더>/CaptureOne/Cache/Thumbnails/<파일명>.[...].cot (가장 최근 것)
    func c1thumb(_ it: Item) -> String? {
        let url = URL(fileURLWithPath: it.path)
        let dir = url.deletingLastPathComponent().appendingPathComponent("CaptureOne/Cache/Thumbnails")
        let prefix = url.lastPathComponent + "."
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        return files.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".cot") }.map { dir.appendingPathComponent($0).path }
            .max { (mtime($0) ?? .distantPast) < (mtime($1) ?? .distantPast) }
    }
    func small(_ it: Item) -> Data? {
        let key = ("s" + it.n) as NSString
        if let d = thumbs.object(forKey: key) { return d as Data }
        var d: Data?
        if mode == "c1", announced.contains(it.n) { d = jpegThumb(previewPath(it), max: 420) }
        if d == nil, mode == "c1", let c = c1thumb(it) { d = jpegThumb(c, max: 420) }
        if d == nil { d = mode == "folder" ? folderThumb(it, max: 420, kind: "s") : jpegThumb(it.path, max: 420) }
        if let d = d { thumbs.setObject(d as NSData, forKey: key) }
        return d
    }
    func medium(_ it: Item) -> Data? {   // 맵 확대용 900px (큰 그림 1600px은 디코드가 무거움)
        let key = ("m" + it.n) as NSString
        if let d = thumbs.object(forKey: key) { return d as Data }
        var d: Data?
        if mode == "c1", announced.contains(it.n) { d = jpegThumb(previewPath(it), max: 900) }
        if d == nil, mode == "c1", let c = c1thumb(it) { d = jpegThumb(c, max: 900) }
        if d == nil { d = mode == "folder" ? folderThumb(it, max: 900, kind: "m") : jpegThumb(it.path, max: 900) }
        if let d = d { thumbs.setObject(d as NSData, forKey: key) }
        return d
    }
    func big(_ it: Item) -> Data? {
        if mode == "c1", announced.contains(it.n), let d = FileManager.default.contents(atPath: previewPath(it)) { return d }
        if mode == "c1", let c = c1thumb(it), let d = jpegThumb(c, max: 1600) { return d }
        if mode == "folder", let e = edits(for: it.path) { return folderThumb(it, max: 1600, kind: "b", edits: e) }   // 보정 RAW의 큰 그림은 현상이 무거워 캐시
        return jpegThumb(it.path, max: 1600)
    }
    // 폴더 방식 썸네일: 카메라 로우 보정(.xmp)이 있으면 보정 반영 그림(근사), 아니면 그대로. 둘 다 영구 캐시
    var crsCache: [String: (Date, CRSEdits?, Int)] = [:]; let crsLock = NSLock()   // 경로 → (xmp 수정시각, 보정값, 파일 회전)
    func setEdits(_ path: String, _ e: CRSEdits?) { let m = mtime(XMPRating.sidecar(path)) ?? .distantPast; crsLock.lock(); crsCache[path] = (m, e, crsCache[path]?.2 ?? 0); crsLock.unlock() }
    func edits(for path: String) -> CRSEdits? {   // 보정이 있어 그림이 달라져야 할 때만 값, 아니면 nil
        guard XMPRating.isRaw(path) else { return nil }
        let sc = XMPRating.sidecar(path); guard let m = mtime(sc) else { return nil }
        crsLock.lock(); var c = crsCache[path]; crsLock.unlock()
        if c == nil || c!.0 != m { let e = (try? String(contentsOfFile: sc, encoding: .utf8)).flatMap { CRSEdits.parse($0) }; c = (m, e, c?.2 ?? 0); crsLock.lock(); crsCache[path] = c; crsLock.unlock() }
        guard let e = c?.1 else { return nil }
        var fo = c?.2 ?? 0
        if fo == 0 { fo = fileOrientation(path); crsLock.lock(); crsCache[path] = (m, e, fo); crsLock.unlock() }
        return e.isEdited(fileOrientation: fo) ? e : nil
    }
    func folderThumb(_ it: Item, max: Int, kind: String, edits e0: CRSEdits? = nil) -> Data? {
        guard let e = e0 ?? edits(for: it.path) else { return folderCached(it.path, kind) { jpegThumb(it.path, max: max) } }
        crsLock.lock(); let fo = crsCache[it.path]?.2 ?? 1; crsLock.unlock()
        return folderCached(it.path, kind, sig: e.sig) { let t0 = Date(); defer { pickLog(String(format: "보정 반영 썸네일 %@ %dpx %.0fms", it.name, max, Date().timeIntervalSince(t0) * 1000)) }
            return editedImage(it.path, e, fileOrientation: fo, max: max).flatMap(jpegEncode) ?? jpegThumb(it.path, max: max) }
    }

    // MARK: 메뉴 (⌘C·⌘V·⌘Z·⌘1~3은 화면이 받도록 편집 메뉴는 두지 않음)
    func buildMenu() {
        let main = NSMenu(), appItem = NSMenuItem(); main.addItem(appItem)
        let m = NSMenu()
        m.addItem(withTitle: "Pick 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        m.addItem(.separator())
        m.addItem(withTitle: "Pick 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = m
        let fItem = NSMenuItem(); main.addItem(fItem)
        let f = NSMenu(title: "파일")
        f.addItem(withTitle: "폴더 열기…", action: #selector(chooseFolder), keyEquivalent: "o").target = self
        let nsi = NSMenuItem(title: "새 세션…", action: #selector(menuNewSession), keyEquivalent: "n"); nsi.target = self; f.addItem(nsi)
        let c1i = NSMenuItem(title: "캡쳐원에서 다시 불러오기", action: #selector(reloadC1), keyEquivalent: "r"); c1i.keyEquivalentModifierMask = [.command, .shift]; c1i.target = self; f.addItem(c1i)
        f.addItem(.separator())
        f.addItem(withTitle: "폴더 썸네일 캐시 비우기…", action: #selector(clearFolderCache), keyEquivalent: "").target = self
        f.addItem(withTitle: "캐시 폴더 Finder에서 보기", action: #selector(revealCache), keyEquivalent: "").target = self
        fItem.submenu = f
        let wItem = NSMenuItem(); main.addItem(wItem)
        let w = NSMenu(title: "윈도우")
        w.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        w.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fs = NSMenuItem(title: "전체 화면", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"); fs.keyEquivalentModifierMask = [.command, .control]; w.addItem(fs)
        wItem.submenu = w
        NSApp.mainMenu = main
    }
    @objc func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "열기"
        if p.runModal() == .OK, let u = p.url { openFolder(u.path) }
    }
    @objc func clearFolderCache() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folderCacheDir)) ?? []
        let bytes = names.reduce(Int64(0)) { $0 + (((try? fm.attributesOfItem(atPath: folderCacheDir + "/" + $1))?[.size] as? Int64) ?? 0) }
        let a = NSAlert(); a.messageText = "폴더 썸네일 캐시를 비울까요?"; a.informativeText = "\(names.count)개 · \(bytes / 1024 / 1024)MB (\(folderCacheDir.replacingOccurrences(of: home, with: "~")))\n지워도 폴더를 다시 열면 그때 다시 만들어요. 캡쳐원 세션 썸네일은 그대로예요."
        a.addButton(withTitle: "비우기"); a.addButton(withTitle: "취소")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        try? fm.removeItem(atPath: folderCacheDir); thumbs.removeAllObjects(); toast("폴더 썸네일 캐시를 비웠어요 · \(bytes / 1024 / 1024)MB")
    }
    @objc func revealCache() { try? FileManager.default.createDirectory(atPath: folderCacheDir, withIntermediateDirectories: true); NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folderCacheDir)]) }
    @objc func reloadC1() { if C1.running { openC1() } else { hint.stringValue = "캡쳐원이 꺼져 있어요" } }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { store.save(); if mode == "c1" { removeHooks() } }
}

// 폴더를 끌어 놓으면 열기 (빈 창)
final class DropView: NSView {
    var onFolder: ((String) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    static func folder(_ s: NSDraggingInfo) -> String? {
        guard let u = (s.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
              (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
        return u.path
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { DropView.folder(s) != nil ? .copy : [] }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { guard let p = DropView.folder(s) else { return false }; onFolder?(p); return true }
}

// 위 바 빈 곳을 끌면 창 이동, 두 번 누르면 확대 (버튼 자리는 화면이 알려 줌). 폴더를 끌어 놓으면 그 폴더 열기
// 파일 약속 + 파일 주소. 파일 주소는 놓는 곳이 달라고 할 때 만들어 줌(.promised) — 포토샵 문서 탭 등
final class PickPromise: NSFilePromiseProvider {
    var fileURL: (() -> URL?)?
    static let names = NSPasteboard.PasteboardType("NSFilenamesPboardType")   // 옛 방식 '파일 이름 목록' (포토샵 탭 줄 등)
    override func writableTypes(for p: NSPasteboard) -> [NSPasteboard.PasteboardType] { super.writableTypes(for: p) + [.fileURL, PickPromise.names] }
    override func writingOptions(forType t: NSPasteboard.PasteboardType, pasteboard p: NSPasteboard) -> NSPasteboard.WritingOptions {
        t == .fileURL || t == PickPromise.names ? .promised : super.writingOptions(forType: t, pasteboard: p) }
    override func pasteboardPropertyList(forType t: NSPasteboard.PasteboardType) -> Any? {
        if t == .fileURL { return fileURL?()?.absoluteString }
        if t == PickPromise.names { return fileURL?().map { [$0.path] } }
        return super.pasteboardPropertyList(forType: t) }
}

// 창 밖으로 끌어낸 사진: 파일은 '약속'만 하고, 놓은 폴더를 알아내서 꺼내기 창을 띄움 (파일은 고른 뒤에 만듦)
// 파인더 훑어보기 같은 미리보기 창: 픽 창과 별개의 패널(픽 화면은 그대로). 가운데 사진 자리에서 화면 97%까지 커짐
// 미리보기 창의 스크롤 뷰: 연속 확대(z: 1=맞춤), 사진 밖으로는 못 옮김(문서 = 사진 크기, 작으면 가운데), Z+휠·Z+끌기(오른쪽=크게)·핀치·더블클릭
final class QLScroll: NSScrollView {
    var onDouble: (() -> Void)?, dragStart: NSPoint?, originStart: NSPoint = .zero, zHeld = false, zDrag: (x0: CGFloat, z0: CGFloat, anchor: NSPoint)?
    var px = NSSize(width: 2, height: 3), z: CGFloat = 1, zMax: CGFloat = 8, anim: Timer?, zTarget: CGFloat = 1
    func scrollClamped(_ p: NSPoint) { let r = contentView.constrainBoundsRect(NSRect(origin: p, size: contentView.bounds.size)); contentView.scroll(to: r.origin); reflectScrolledClipView(contentView) }
    var fitScale: CGFloat { let v = contentView.bounds.size; return min(v.width / max(1, px.width), v.height / max(1, px.height)) }
    var pixelScale: CGFloat { fitScale * z * (NSScreen.main?.backingScaleFactor ?? 2) }   // 화면 픽셀 / 사진 픽셀 (1 = 100%)
    func docSize(_ zz: CGFloat) -> NSSize { let s = fitScale * zz; return NSSize(width: px.width * s, height: px.height * s) }
    // 배율 적용. anchor(보이는 영역 안 좌표) 아래 사진 점이 그대로 있게
    func apply(_ zz: CGFloat, anchor: NSPoint? = nil) {
        guard let d = documentView else { return }
        let vis = contentView.bounds, a = anchor ?? NSPoint(x: vis.width / 2, y: vis.height / 2)
        let old = d.frame.size, o = vis.origin
        let rx = old.width > 0 ? (o.x + a.x) / old.width : 0.5, ry = old.height > 0 ? (o.y + a.y) / old.height : 0.5
        z = max(1, min(zMax, zz)); let n = docSize(z)
        d.frame = NSRect(origin: .zero, size: n)
        scrollClamped(NSPoint(x: rx * n.width - a.x, y: ry * n.height - a.y))
        onZ?(z)
    }
    var onZ: ((CGFloat) -> Void)?
    // 부드럽게 (⌘+ ⌘- ⌘0): 0.28초 ease-out
    func animate(to zz: CGFloat, anchor: NSPoint? = nil, dur: Double = 0.28) {
        anim?.invalidate(); let z0 = z, z1 = max(1, min(zMax, zz)), t0 = Date(); zTarget = z1
        anim = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] tm in guard let self else { tm.invalidate(); return }
            let k = min(1, Date().timeIntervalSince(t0) / dur), e = 1 - pow(1 - k, 3)
            self.apply(z0 + (z1 - z0) * e, anchor: anchor); if k >= 1 { tm.invalidate() } }
    }
    override func layout() { super.layout(); if let d = documentView { let n = docSize(z); if d.frame.size != n { d.frame = NSRect(origin: .zero, size: n); scrollClamped(contentView.bounds.origin) } } }
    override func scrollWheel(with e: NSEvent) {
        let p = contentView.convert(e.locationInWindow, from: nil), a = NSPoint(x: p.x - contentView.bounds.origin.x, y: p.y - contentView.bounds.origin.y)
        animate(to: zTarget * exp(e.scrollingDeltaY * 0.018), anchor: a, dur: 0.26) }   // 미리보기 창 안에서만 (시스템 스크롤 속도와 무관)   // 스크롤 = 커서 기준 확대·축소 (위로 = 크게), 목표값으로 부드럽게. 이동은 끌기
    override func magnify(with e: NSEvent) { let p = contentView.convert(e.locationInWindow, from: nil); apply(z * (1 + e.magnification), anchor: NSPoint(x: p.x - contentView.bounds.origin.x, y: p.y - contentView.bounds.origin.y)) }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { onDouble?(); return }
        if zHeld { let p = contentView.convert(e.locationInWindow, from: nil); zDrag = (e.locationInWindow.x, z, NSPoint(x: p.x - contentView.bounds.origin.x, y: p.y - contentView.bounds.origin.y)); return }
        dragStart = e.locationInWindow; originStart = contentView.bounds.origin }
    override func mouseDragged(with e: NSEvent) {
        if let zd = zDrag { apply(zd.z0 * exp((e.locationInWindow.x - zd.x0) * 0.006), anchor: zd.anchor); return }   // Z+끌기: 오른쪽 = 크게
        guard let s = dragStart else { return }; let d = e.locationInWindow
        scrollClamped(NSPoint(x: originStart.x - (d.x - s.x), y: originStart.y - (d.y - s.y))) }
    override func mouseUp(with e: NSEvent) { dragStart = nil; zDrag = nil }
}
final class QLClip: NSClipView {   // 문서가 보이는 영역보다 작으면 가운데에
    override func constrainBoundsRect(_ r: NSRect) -> NSRect { var r = super.constrainBoundsRect(r); guard let d = documentView else { return r }
        if d.frame.width < r.width { r.origin.x = (d.frame.width - r.width) / 2 }; if d.frame.height < r.height { r.origin.y = (d.frame.height - r.height) / 2 }; return r }
}
final class QLPanel: NSObject {
    var panel: NSPanel?, root: NSView!, bar: NSView!, img: NSImageView!, title: NSTextField!, scroll: QLScroll!
    var cap: NSTextField!   // 전체화면(브릿지) 사진 아래 작은 캡션: 이름 · ★★★☆☆ · ● 색 라벨 (2026-11-04)
    let capH: CGFloat = 30
    var zoomLevel: Int { scroll.z > 1.001 ? 1 : 0 }
    // ⌘+ / ⌘- : 1.5배씩 부드럽게, ⌘0: 맞춤. 더블클릭: 맞춤 ↔ 100%
    func zoom(_ step: Int) {
        if step == 0 { scroll.animate(to: 1); return }
        scroll.animate(to: scroll.z * (step > 0 ? 1.5 : 1 / 1.5)) }
    func toggle100() { if scroll.z > 1.001 { scroll.animate(to: 1) } else { scroll.animate(to: max(1.0001, 1 / (scroll.fitScale * (NSScreen.main?.backingScaleFactor ?? 2)))) } }   // 100% = 화면 픽셀 1:1
    func pixelSize(_ i: NSImage) -> NSSize { if let r = i.representations.first { return NSSize(width: r.pixelsWide, height: r.pixelsHigh) }; return i.size }
    var onClose: (() -> Void)?, onToggle: (() -> Void)?
    var aspect: CGFloat = 2.0 / 3.0, token = 0
    // 큰 그림은 창이 다 커진 뒤에 끼움(커지는 동안 24MP 원본을 매 프레임 줄여 그리면 버벅). 보통은 화면 크기(2배)로 줄인 그림을 쓰고, 1배 넘게 확대할 때만 원본으로
    var fullImg: NSImage?, dispImg: NSImage?, pendingBig: NSImage?, opening = false, showingFull = false
    func downsample(_ i: NSImage, maxPx: CGFloat) -> NSImage {
        let ps = pixelSize(i); let m = max(ps.width, ps.height); if m <= maxPx { return i }
        let k = maxPx / m, w = Int(ps.width * k), h = Int(ps.height * k)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return i }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep); NSGraphicsContext.current?.imageInterpolation = .high
        i.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1); NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: rep.size); out.addRepresentation(rep); return out }
    func applyBig(_ b: NSImage, _ disp: NSImage, screen: NSScreen) {
        guard let p = panel else { return }
        fullImg = b; dispImg = disp; showingFull = scroll.z > 1.001; img.image = showingFull ? b : disp
        let a = b.size.width / max(1, b.size.height); scroll.px = pixelSize(b); scroll.needsLayout = true; scroll.layoutSubtreeIfNeeded()
        if abs(a - aspect) > 0.01 { aspect = a; let t2 = bigRect(on: screen); NSAnimationContext.runAnimationGroup { c in c.duration = 0.2; p.animator().setFrame(t2, display: true) } } }
    func ensure() {
        if panel != nil { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .popUpMenu; p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]; p.animationBehavior = .none
        root = NSView(frame: p.contentView!.bounds); root.autoresizingMask = [.width, .height]; root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor; root.layer?.cornerRadius = 14; root.layer?.cornerCurve = .continuous
        root.layer?.borderWidth = 1; root.layer?.borderColor = NSColor(white: 0, alpha: 0.14).cgColor; root.layer?.masksToBounds = true
        p.contentView!.addSubview(root)
        // 제목 줄 36pt: ⊗ ⊘ 회색 원 아이콘 + 파일 이름 (오른쪽엔 아무것도 없음)
        bar = NSView(frame: NSRect(x: 0, y: root.bounds.height - 36, width: root.bounds.width, height: 36)); bar.autoresizingMask = [.width, .minYMargin]
        func btn(_ sym: String, _ x: CGFloat, _ sel: Selector) -> NSButton {
            let b = NSButton(frame: NSRect(x: x, y: 8, width: 20, height: 20)); b.isBordered = false; b.bezelStyle = .regularSquare
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            b.contentTintColor = NSColor(red: 0.53, green: 0.53, blue: 0.55, alpha: 1); b.imagePosition = .imageOnly; b.target = self; b.action = sel; return b }
        bar.addSubview(btn("xmark.circle.fill", 14, #selector(closeTap)))   // ⊗ 닫기만 (선택 불가 버튼은 뺌)
        title = NSTextField(labelWithString: ""); title.frame = NSRect(x: 44, y: 9, width: bar.bounds.width - 58, height: 18); title.autoresizingMask = [.width]
        if let u = Bundle.main.resourceURL?.appendingPathComponent("ui/fonts/GowunDodum-Regular.ttf") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }   // 앱 글꼴(고운돋움)과 맞춤
        title.font = NSFont(name: "GowunDodum-Regular", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold); title.textColor = NSColor(red: 0.29, green: 0.29, blue: 0.29, alpha: 1); title.lineBreakMode = .byTruncatingTail
        bar.addSubview(title); root.addSubview(bar)
        // 사진: 양옆·아래 8pt 베젤, 10pt 모서리. 스크롤 뷰 안에 두어 확대(100% 원본 픽셀)·끌어서 이동 가능
        scroll = QLScroll(frame: NSRect(x: 8, y: 8, width: root.bounds.width - 16, height: root.bounds.height - 36 - 8)); scroll.autoresizingMask = [.width, .height]
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false; scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10; scroll.layer?.cornerCurve = .continuous; scroll.layer?.masksToBounds = true; scroll.layer?.backgroundColor = NSColor.white.cgColor
        scroll.contentView = QLClip(); scroll.contentView.drawsBackground = false
        img = NSImageView(frame: scroll.bounds); img.imageScaling = .scaleProportionallyUpOrDown; img.imageAlignment = .alignCenter
        scroll.documentView = img; root.addSubview(scroll)
        cap = NSTextField(labelWithString: ""); cap.alignment = .center; cap.lineBreakMode = .byTruncatingMiddle; cap.isHidden = true; cap.font = NSFont(name: "GowunDodum-Regular", size: 12) ?? .systemFont(ofSize: 12); root.addSubview(cap)
        scroll.onDouble = { [weak self] in self?.toggle100() }
        panel = p
    }
    func setCaption(name: String, cap: [String: Any]) {   // 이름(흰 60%) · 별 5칸(찍힌 별 흰 85%, 빈 별 흰 22%) · 색 라벨 점+이름
        ensure(); guard self.cap != nil else { return }
        let r = max(0, min(5, cap["r"] as? Int ?? 0)), tc = cap["tc"] as? String ?? "", tn = cap["tn"] as? String ?? ""
        let f = self.cap.font ?? .systemFont(ofSize: 12), a = NSMutableAttributedString()
        let ps = NSMutableParagraphStyle(); ps.alignment = .center; ps.lineBreakMode = .byTruncatingMiddle
        func add(_ t: String, _ c: NSColor) { a.append(NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c, .paragraphStyle: ps])) }   // 속성 문자열은 단락 스타일로 가운데 정렬
        add(name.precomposedStringWithCanonicalMapping, NSColor(white: 1, alpha: 0.6)); add("   ", .clear)
        add(String(repeating: "★", count: r), NSColor(white: 1, alpha: 0.85)); add(String(repeating: "★", count: 5 - r), NSColor(white: 1, alpha: 0.22))
        if !tc.isEmpty, let col = NSColor(hex: tc) { add("   ", .clear); add("●", col); add(" " + tn, NSColor(white: 1, alpha: 0.6)) }
        self.cap.attributedStringValue = a
    }
    @objc func closeTap() { onClose?() }
    @objc func toggleTap() { onToggle?() }
    func bigRect(on screen: NSScreen) -> NSRect {
        if full { return screen.frame }
        let v = screen.visibleFrame, k: CGFloat = 0.97
        let ih = min(v.height * k - 44, (v.width * k - 16) / aspect), w = ih * aspect + 16, h = ih + 44
        return NSRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h).integral
    }
    var isOpen: Bool { panel?.isVisible ?? false }
    func show(small: NSImage?, big: @escaping () -> NSImage?, name: String, from: NSRect, screen: NSScreen, first: Bool, full: Bool = false) {
        ensure(); guard let p = panel else { return }
        self.full = full; p.level = full ? .mainMenu + 1 : .popUpMenu   /* 전체 화면이면 메뉴 막대 위까지 */
        if env["PICK_TESTJS"] != nil { p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1); pickLog("qlwin \(p.windowNumber)") }   // 시험: 바탕화면 뒤에 띄워 사용자 화면을 가리지 않고 screencapture -l 로 확인
        token += 1; let my = token
        title.stringValue = name.precomposedStringWithCanonicalMapping; scroll.anim?.invalidate(); scroll.z = 1; scroll.zTarget = 1   // 파일 이름 분리 자모(NFD) → 완성형. 확대 배율은 열 때마다 1로
        if let small { img.image = small; aspect = small.size.width / max(1, small.size.height); scroll.px = pixelSize(small) }
        let target = bigRect(on: screen)
        fullImg = nil; dispImg = nil; pendingBig = nil; showingFull = false; opening = true
        scroll.onZ = { [weak self] z in guard let self, let f = self.fullImg, let d = self.dispImg else { return }; let want = z > 1.001; if want != self.showingFull { self.showingFull = want; self.img.image = want ? f : d } }
        let done = { [weak self] in guard let self, self.token == my, let p = self.panel else { return }; self.opening = false; self.chromeTimer?.invalidate(); self.chrome = self.full ? 0 : 1; self.layoutChrome(); p.hasShadow = true; p.invalidateShadow(); if let b = self.pendingBig { self.pendingBig = nil; self.applyBig(b, self.dispImg ?? b, screen: screen) } }
        p.hasShadow = false   /* 커지는 동안은 그림자 없이 (투명 창 그림자는 프레임마다 다시 계산돼 번쩍·버벅) */
        if full {   // 필름스트립(브릿지) 전체화면: 애니메이션 없이 바로 (사용자 요청 2026-11-03)
            chrome = 0; layoutChrome(); p.setFrame(target, display: true); p.alphaValue = 1; p.orderFrontRegardless(); done()
        } else if first {
            p.setFrame(from, display: false); p.alphaValue = 1
            chrome = 0; layoutChrome(); p.contentView?.layoutSubtreeIfNeeded()   /* 첫 프레임 = 카드와 같은 모습(사진만, 꾸밈 없음) */
            p.orderFrontRegardless()
            if !full { animateChrome(to: 1, dur: 0.32) }
            NSAnimationContext.runAnimationGroup({ c in c.duration = 0.32; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.25, 1); p.animator().setFrame(target, display: true) }, completionHandler: done)
        } else {
            chrome = full ? 0 : 1; layoutChrome()
            NSAnimationContext.runAnimationGroup({ c in c.duration = 0.22; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.25, 1); p.animator().setFrame(target, display: true) }, completionHandler: done)
        }
        let maxPx = maxDispPx(screen)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in   // 큰 그림은 뒤에서 읽고(화면 크기로 줄인 판도 만들어) 창이 다 커진 뒤 끼움
            guard let self, let b = big() else { return }
            let disp = self.downsample(b, maxPx: maxPx)
            DispatchQueue.main.async { guard self.token == my, self.panel != nil else { return }
                if self.opening { self.pendingBig = b; self.dispImg = disp; self.fullImg = b } else { self.applyBig(b, disp, screen: screen) } }
        }
    }
    func maxDispPx(_ screen: NSScreen) -> CGFloat { max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor }
    // 창 꾸밈(제목 줄 36pt·베젤 8pt·모서리 14pt)의 정도 0~1. 0이면 사진이 창을 꽉 채워 맵 카드와 똑같이 보임 → 첫 프레임에 '번쩍' 없음
    var chrome: CGFloat = 1, chromeTimer: Timer?, full = false   /* full: 브릿지 미리보기 = 화면 전체·검정 바탕·꾸밈 없음 */
    func layoutChrome() {
        guard let root else { return }; let b = root.bounds, c = full ? 0 : chrome
        let bg = full ? NSColor.black.cgColor : NSColor.white.cgColor; root.layer?.backgroundColor = bg; scroll.layer?.backgroundColor = bg
        bar.frame = NSRect(x: 0, y: b.height - 36 * c, width: b.width, height: 36); bar.alphaValue = c
        if full { scroll.frame = NSRect(x: 0, y: capH, width: b.width, height: max(1, b.height - capH)); cap.frame = NSRect(x: 24, y: 7, width: b.width - 48, height: 17); cap.isHidden = false }   // 아래 30pt 띠에 캡션, 사진은 그 위
        else { cap.isHidden = true; scroll.frame = NSRect(x: 8 * c, y: 8 * c, width: b.width - 16 * c, height: max(1, b.height - 36 * c - 8 * c)) }
        root.layer?.cornerRadius = 14 * c; scroll.layer?.cornerRadius = 10 * c; root.layer?.borderColor = NSColor(white: 0, alpha: 0.14 * c).cgColor
        scroll.needsLayout = true; scroll.layoutSubtreeIfNeeded() }
    func animateChrome(to c1: CGFloat, dur: Double) {
        chromeTimer?.invalidate(); let c0 = chrome, t0 = Date()
        chromeTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] tm in guard let self else { tm.invalidate(); return }
            let k = min(1, Date().timeIntervalSince(t0) / dur), e = 1 - pow(1 - k, 3); self.chrome = c0 + (c1 - c0) * e; self.layoutChrome(); if k >= 1 { tm.invalidate() } }
        RunLoop.main.add(chromeTimer!, forMode: .common) }
    func hide(to: NSRect) {
        guard let p = panel, p.isVisible else { return }
        token += 1; p.hasShadow = false
        if full { p.orderOut(nil); return }   // 전체화면은 바로 사라짐
        animateChrome(to: 0, dur: 0.3)
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.3; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.25, 1); p.animator().setFrame(to, display: true); p.animator().alphaValue = 0.0 }, completionHandler: { p.orderOut(nil); p.alphaValue = 1 })
    }
}
final class DragOut: NSObject, NSDraggingSource, NSFilePromiseProviderDelegate {
    var ns: [String] = [], dirs = Set<String>(), onDrop: ((String) -> Void)?, fired = false
    weak var view: NSView?
    var onMove: ((Bool, NSPoint) -> Void)?, onEnd: ((NSPoint?) -> Void)?   // 창 안 여부·화면 좌표 / 창 안에 놓으면 그 좌표
    var inside = false, dragImage: NSImage?, grabOff = NSPoint.zero   /* 끌기 틀 원점 − 커서(뷰 좌표) */
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { c == .outsideApplication ? [.copy, .generic, .link] : [] }
    func draggingSession(_ s: NSDraggingSession, willBeginAt p: NSPoint) { fired = false; inside = false }
    // 창 안으로 돌아오면: 맥 끌기 그림은 숨기고 픽 안의 끌기 모습으로 (나가면 다시 맥 그림)
    func draggingSession(_ s: NSDraggingSession, movedTo p: NSPoint) {
        guard let v = view, let w = v.window else { return }
        let now = w.frame.contains(p)
        if now != inside {   /* 창 안팎 모두 네이티브 사진 그림 하나만: 파인더가 파일 아이콘+이름으로 바꿔 둔 것을 창 안에 들어오면 우리 사진 그림으로 되돌림 (밖에선 파인더가 다시 바꿈) */
            inside = now; s.animatesToStartingPositionsOnCancelOrFail = !now
            var k = 0
            let vp = v.convert(w.convertPoint(fromScreen: p), from: nil)   /* 파인더가 틀을 아이콘 크기로 줄여 두므로 틀(크기·잡은 자리)도 함께 복구 */
            s.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self, NSFilePromiseReceiver.self], searchOptions: [:]) { di, _, _ in
                if k == 0, let img = self.dragImage { di.setDraggingFrame(NSRect(origin: NSPoint(x: vp.x + self.grabOff.x, y: vp.y + self.grabOff.y), size: img.size), contents: img) }
                else { di.setDraggingFrame(NSRect(origin: di.draggingFrame.origin, size: NSSize(width: 1, height: 1)), contents: NSImage(size: NSSize(width: 1, height: 1))) }
                k += 1 }
        }
        onMove?(now, local(p))
    }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        let w = view?.window
        onEnd?(operation == [] && (w?.frame.contains(p) ?? false) ? local(p) : nil)
    }
    // 화면 좌표 → 웹 화면 좌표 (위가 0)
    func local(_ p: NSPoint) -> NSPoint {
        guard let v = view, let w = v.window else { return .zero }
        let q = v.convert(w.convertPoint(fromScreen: p), from: nil)
        return NSPoint(x: q.x, y: v.isFlipped ? q.y : v.bounds.height - q.y)
    }
    var fulfill: ((String, URL, @escaping (Error?) -> Void) -> Void)?
    let promiseQ: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 4; return q }()
    func filePromiseProvider(_ p: NSFilePromiseProvider, fileNameForType t: String) -> String { ((p.userInfo as? [String: String])?["file"]) ?? "사진.jpg" }
    // 놓은 곳(Finder 폴더·데스크톱·다른 앱)이 파일을 달라고 하면 보정본을 만들어 그 자리에 씀
    func filePromiseProvider(_ p: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let n = (p.userInfo as? [String: String])?["n"], let f = fulfill else { completionHandler(nil); return }
        f(n, url, completionHandler)
    }
    func operationQueue(for p: NSFilePromiseProvider) -> OperationQueue { promiseQ }
    // 사진(가득 채움) + 그림자 + 여러 장이면 개수 표시 — 픽 안 .ghost와 같은 모습
    // 사진(가득 채움) + 그림자. 여러 장이면 카드 패처럼 부채꼴(픽 안 makeGhost와 같은 각도) + 개수 표시
    static func picture(_ srcs: [NSImage], w: CGFloat, h: CGFloat, padX: CGFloat, padY: CGFloat, count: Int) -> NSImage {
        NSImage(size: NSSize(width: w + 2 * padX, height: h + 2 * padY), flipped: true) { _ in
            func card(_ src: NSImage, angle: CGFloat, main: Bool) {
                NSGraphicsContext.saveGraphicsState()
                // 회전 중심: 카드 가운데 아래 15% 밖 (CSS transform-origin 50% 115%)
                let cx = padX + w / 2, cy = padY + h * 1.15
                let t = NSAffineTransform(); t.translateX(by: cx + angle * w * 0.012, yBy: cy); t.rotate(byDegrees: angle); t.translateX(by: -cx, yBy: -cy); t.concat()
                let r = NSRect(x: padX, y: padY, width: w, height: h)
                NSGraphicsContext.saveGraphicsState()
                let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: main ? 0.32 : 0.26); sh.shadowBlurRadius = main ? 16 : 12; sh.shadowOffset = NSSize(width: 0, height: main ? 9 : 6); sh.set()
                NSColor.white.setFill(); r.fill()
                NSGraphicsContext.restoreGraphicsState()
                let s = src.size, k = max(w / max(s.width, 1), h / max(s.height, 1)), cw = w / k, ch = h / k
                src.draw(in: r, from: NSRect(x: (s.width - cw) / 2, y: (s.height - ch) / 2, width: cw, height: ch), operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            }
            // 뒤 카드부터 (JS: 뒤쪽일수록 먼저 prepend → 나중 것이 더 뒤)
            let others = Array(srcs.dropFirst())
            for i in stride(from: others.count - 1, through: 0, by: -1) {
                card(others[i], angle: CGFloat(i + 1) * 4, main: false)   // JS fanAngle과 같게 (오른쪽으로 4°씩)
            }
            if let m = srcs.first { card(m, angle: 0, main: true) }
            if count > 1 {
                let t = NSAttributedString(string: "\(count)", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white])
                let tw = max(24, t.size().width + 14), b = NSRect(x: padX + w + 10 - tw, y: padY - 10, width: tw, height: 24)
                NSColor(white: 0.13, alpha: 1).setFill(); NSBezierPath(roundedRect: b, xRadius: 12, yRadius: 12).fill()
                t.draw(at: NSPoint(x: b.midX - t.size().width / 2, y: b.midY - t.size().height / 2))
            }
            return true
        }
    }
}

final class PickWebView: WKWebView {
    var topButtons: [NSRect] = []
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }   /* 창이 뒤에 있어도 첫 클릭이 단추에 바로 먹힘 */
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) { menu.removeAllItems() }   /* 웹뷰 기본 메뉴(다시 로드 등) 없음 — 픽 메뉴는 showCtxMenu로 */
    // 트랙패드식 스크롤의 단계(손가락 댐·뗌·관성)를 화면에 알려 줌 → 끝에서 당기기/튕기기 구분
    override func scrollWheel(with e: NSEvent) {
        var p: String?
        if e.phase.contains(.began) { p = "down" } else if e.phase.contains(.ended) || e.phase.contains(.cancelled) { p = "up" }
        else if e.momentumPhase.contains(.began) { p = "mom" } else if e.momentumPhase.contains(.ended) || e.momentumPhase.contains(.cancelled) { p = "idle" }
        if let p { evaluateJavaScript("window.__wp&&__wp('\(p)')", completionHandler: nil) }
        let mouse = !e.hasPreciseScrollingDeltas   // 마우스 휠(딸깍) / 트랙패드·매직마우스(부드러움) 구분 → 바뀔 때만 화면에 알림
        if mouse != lastMouseWheel { lastMouseWheel = mouse; evaluateJavaScript("window.__mouseWheel=\(mouse)", completionHandler: nil) }
        super.scrollWheel(with: e)
    }
    var onFolder: ((String) -> Void)?
    var lastMouseWheel = false
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil), y = isFlipped ? p.y : bounds.height - p.y
        if y < 44, p.x > 80, !topButtons.contains(where: { $0.insetBy(dx: -4, dy: -4).contains(NSPoint(x: p.x, y: y)) }) {
            if e.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: e) }
            return
        }
        super.mouseDown(with: e)
    }
    // 픽에서 끌고 나갔다 돌아온 사진은 웹 화면이 받지 않음 (놓으면 픽 안의 끌기로 처리)
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { s.draggingSource is DragOut ? [] : DropView.folder(s) != nil ? .copy : super.draggingEntered(s) }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { s.draggingSource is DragOut ? [] : DropView.folder(s) != nil ? .copy : super.draggingUpdated(s) }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool { s.draggingSource is DragOut ? false : super.prepareForDragOperation(s) }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        if let p = DropView.folder(s) { onFolder?(p); return true }
        return super.performDragOperation(s)
    }
}

// 시험: Pick --dump → 캡쳐원에서 읽기만 하고 요약 출력 후 끝 (아무것도 안 씀)
if CommandLine.arguments.contains("--dump") {
    guard let (doc, list) = C1.load() else { print("읽기 실패"); exit(1) }
    print("문서 \(doc) · \(list.count)장 · 별점 있음 \(list.filter { $0.r > 0 }.count)")
    for it in list.prefix(3) { print(it.n, it.name + it.ext, "r\(it.r)", it.adj, "ISO", it.iso, exif(it.path)) }
    if let first = list.first { print("조정값 다시 읽기:", C1.adjustments([first.id])) }
    exit(0)
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

extension NSColor {   // "#rrggbb" → 색 (전체화면 캡션의 색 라벨 점)
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces); if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}
