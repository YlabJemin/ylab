// 셀렉 휠 — 캡쳐원 연동 셀렉 창 (곡면 캐러셀)
// 캡쳐원 현재 문서: 선택한 사진이 2장 이상이면 그것만, 아니면 지금 컬렉션 전체
// 별점·색상 태그는 누르는 즉시 캡쳐원에 기록, 창이 앞으로 올 때 캡쳐원 값 다시 읽음
// 미리보기: 캡쳐원 썸네일 캐시(보정 반영, 작음)로 먼저 → 레시피 cc-cull-preview(긴 변 1600px)로 뽑은 큰 JPG로 교체
// 미리보기 JPG(~/Library/Caches/cc-cull/<세션>/)는 창을 닫을 때·다음에 켤 때 지움 (그 폴더의 .jpg만)
// 실행: "셀렉 휠.app" (캡쳐원 스크립트 메뉴 "셀렉 휠"이 open으로 띄움)
// 테스트: --fake <JPG 폴더> (캡쳐원 연결 없음), --snapshot <출력폴더> <JPG 폴더> (화면 이미지로 저장)
// 빌드: ~/Desktop/cc/tools/cull/build.sh
import SwiftUI
import AppKit
import ImageIO
import QuartzCore

// MARK: - 색
var lightTheme = UserDefaults.standard.object(forKey: "cc.cull.light") as? Bool ?? true
var navAnimation = UserDefaults.standard.object(forKey: "cc.cull.anim") as? Bool ?? true   // 방향키·스크롤로 넘길 때 회전 애니메이션   // 하얀 화면 여부 (오른쪽 위 버튼, 기억함)
enum P {
    static var bar: Color { lightTheme ? Color(white: 0.93) : Color(red: 0.2, green: 0.2, blue: 0.205) }
    static var text: Color { lightTheme ? Color(white: 0.2) : Color(white: 0.86) }
    static var sub: Color { lightTheme ? Color(white: 0.5) : Color(white: 0.55) }
    static var strong: Color { lightTheme ? .black : .white }                 // 강조 글자
    static var stage: Color { lightTheme ? .white : .black }                  // 화면 바탕 (끝 그라데이션 색도 같음)
    static var card: Color { lightTheme ? Color(white: 0.9) : Color(white: 0.12) }
    static var border: Color { lightTheme ? Color.black.opacity(0.1) : Color.white.opacity(0.12) }
    static var shadow: Double { lightTheme ? 0.22 : 0.75 }
    static var toastBg: Color { lightTheme ? Color(white: 0.97) : Color(white: 0.18) }
    static let accent = Color(red: 0.96, green: 0.55, blue: 0.14)
}
// 캡쳐원 색상 태그 번호 → 색·이름
let tagInfo: [Int: (Color, String)] = [1: (.red, "빨강"), 2: (.orange, "주황"), 3: (.yellow, "노랑"), 4: (.green, "초록"),
                                       5: (.blue, "파랑"), 6: (.pink, "분홍"), 7: (.purple, "보라")]
// 키 6·7·8·9 → 빨강·노랑·초록·파랑
let tagKeys: [String: Int] = ["6": 1, "7": 3, "8": 4, "9": 5]

// MARK: - 사진 한 장
struct Item: Identifiable, Equatable {
    let id: String          // 캡쳐원 variant id (가짜 모드: 파일 경로)
    let name: String        // 변형 이름 (확장자 없음)
    var rating: Int
    var tag: Int
    let imagePath: String   // 원본 파일 경로
}

// MARK: - 캡쳐원 연결 (osascript)
final class C1 {
    static let q = DispatchQueue(label: "cc.cull.c1")
    static var running: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.captureone.captureone16").isEmpty
    }
    @discardableResult
    static func run(_ src: String) -> String? {
        guard running else { return nil }          // 꺼져 있으면 절대 보내지 않음 (켜 버리지 않게)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", src]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }
    static func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

    // 사진 목록: (문서 이름, 사진들)
    static let pickVariants = """
        set vs to (variants of d whose selected is true)
        if (count of vs) < 2 then set vs to variants of d
        """
    static func list() -> (String, [Item])? {
        guard let out = run("""
            tell application "Capture One"
            set d to current document
            \(pickVariants)
            set out to (name of d) & linefeed
            repeat with v in vs
            set out to out & (id of v) & tab & (name of v) & tab & (rating of v) & tab & (color tag of v) & tab & (path of parent image of v) & linefeed
            end repeat
            return out
            end tell
            """) else { return nil }
        var lines = out.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return nil }
        let doc = lines.removeFirst()
        let items: [Item] = lines.compactMap { l in
            let f = l.components(separatedBy: "\t")
            guard f.count >= 5 else { return nil }
            return Item(id: f[0], name: f[1], rating: Int(f[2]) ?? 0, tag: Int(f[3]) ?? 0, imagePath: f[4])
        }
        return (doc, items)
    }
    static func setRating(_ id: String, _ r: Int) {
        run("tell application \"Capture One\" to set rating of (first variant of current document whose id is \"\(esc(id))\") to \(r)")
    }
    static func setTag(_ id: String, _ t: Int) {
        run("tell application \"Capture One\" to set color tag of (first variant of current document whose id is \"\(esc(id))\") to \(t)")
    }
    // 큰 미리보기 뽑기 (전용 레시피, 꺼진 상태로 둠). ids가 nil이면 목록 전체
    @discardableResult
    static func makePreviews(into dir: String, ids: [String]? = nil) -> Set<String> {
        let target: String
        if let ids = ids {
            target = "set vs to {}\n" + ids.map { "set end of vs to (first variant of d whose id is \"\(esc($0))\")" }.joined(separator: "\n")
        } else { target = pickVariants }
        let out = run("""
            tell application "Capture One"
            set d to current document
            if not (exists recipe "cc-cull-preview" of d) then make new recipe at d with properties {name:"cc-cull-preview"}
            set r to recipe "cc-cull-preview" of d
            set output format of r to JPEG
            set JPEG quality of r to 80
            set color profile of r to "sRGB Color Space Profile"
            set scaling method of r to Long_Edge
            set scaling unit of r to pixels
            set primary scaling value of r to 1600
            set upscale of r to false
            set root folder location of r to (POSIX file "\(esc(dir))")
            set root folder type of r to custom location
            set output sub folder of r to ""
            set existing files of r to overwrite
            set enabled of r to false
            \(target)
            -- 원본이 1600px보다 작은 사진은 뽑지 않음 (키울 수 없어서 캡쳐원이 "배율 조정" 경고를 띄움 → 썸네일로 충분)
            set big to {}
            set out to ""
            repeat with v in vs
            set dm to dimensions of (parent image of v)
            if (item 1 of dm) > 1600 or (item 2 of dm) > 1600 then
            set end of big to v
            set out to out & (id of v) & linefeed
            end if
            end repeat
            if (count of big) > 0 then process big recipe "cc-cull-preview"
            return out
            end tell
            """) ?? ""
        return Set(out.split(separator: "\n").map(String.init))
    }
}

// MARK: - 이미지 불러오기
func loadImage(_ path: String, max: Int) -> NSImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: max, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
func mtime(_ path: String) -> Date? { (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date }

// MARK: - 미리보기 정리 (안전장치: ~/Library/Caches/cc-cull/ 안의 .jpg 파일만 지움)
let cacheRoot = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Caches/cc-cull"
func cleanPreviews(only folder: String? = nil, keepFolders: Bool = false) {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: cacheRoot).standardizedFileURL.path
    guard root.hasSuffix("/Library/Caches/cc-cull"), fm.fileExists(atPath: root) else { return }
    let dirs: [String]
    if let f = folder {
        let d = URL(fileURLWithPath: f).standardizedFileURL.path
        guard d.hasPrefix(root + "/"), d != root else { return }          // cc-cull 바로 아래 세션 폴더만
        dirs = [d]
    } else {
        dirs = ((try? fm.contentsOfDirectory(atPath: root)) ?? []).map { root + "/" + $0 }
    }
    for d in dirs {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: d, isDirectory: &isDir), isDir.boolValue else { continue }
        for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where f.lowercased().hasSuffix(".jpg") {
            let p = d + "/" + f
            var sub: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &sub), !sub.boolValue { try? fm.removeItem(atPath: p) }
        }
        if !keepFolders, ((try? fm.contentsOfDirectory(atPath: d)) ?? []).isEmpty { try? fm.removeItem(atPath: d) }   // 빈 폴더만
    }
    if !keepFolders, ((try? fm.contentsOfDirectory(atPath: root)) ?? []).isEmpty { try? fm.removeItem(atPath: root) }
}

// MARK: - 상태
final class Store: ObservableObject {
    @Published var items: [Item] = []
    @Published var index = 0          // 실제 사진 번호 (0…n-1)
    @Published var pos: Double = 0    // 화면 회전 위치 (끝없이 이어지는 가상 번호, 애니메이션용)
    var vtarget = 0                   // 목표 가상 번호
    var armed = 0                     // 끝에서 한 번 눌렀으면 그 방향(-1/1) — 한 번 더 누르면 넘어감
    @Published var toast: String? = nil
    @Published var light = lightTheme
    @Published var anim = navAnimation
    func setAnim(_ on: Bool) {
        navAnimation = on
        UserDefaults.standard.set(on, forKey: "cc.cull.anim")
        anim = on
    }
    var onTheme: (() -> Void)?
    func setLight(_ on: Bool) {
        lightTheme = on
        UserDefaults.standard.set(on, forKey: "cc.cull.light")
        withAnimation(.easeInOut(duration: 0.25)) { light = on }
        onTheme?()
    }
    var toastWork: DispatchWorkItem?
    @Published var hovered: String? = nil
    @Published var big = false
    @Published var status = ""
    @Published var small: [String: NSImage] = [:]     // 썸네일 (흐림 층·옆 사진용)
    @Published var large: [String: NSImage] = [:]     // 큰 미리보기
    @Published var aspect: [String: CGFloat] = [:]    // 가로/세로 비율 (썸네일에서)
    var largeTime: [String: Date] = [:]
    var previewIDs: Set<String>? = nil   // 큰 미리보기를 만드는 사진 (작은 사진은 썸네일로)
    var fake = false
    var cacheDir = ""
    var docName = ""
    let ioq = DispatchQueue(label: "cc.cull.io", qos: .userInitiated, attributes: .concurrent)
    var timer: Timer?

    var current: Item? { items.indices.contains(index) ? items[index] : nil }
    func wrap(_ v: Int) -> Int { let n = items.count; return n == 0 ? 0 : ((v % n) + n) % n }

    // 캡쳐원 썸네일 캐시: <사진 폴더>/CaptureOne/Cache/Thumbnails/<파일명>.[...].cot (가장 최근 것)
    func thumbPath(_ it: Item) -> String? {
        if fake { return it.imagePath }
        let url = URL(fileURLWithPath: it.imagePath)
        let dir = url.deletingLastPathComponent().appendingPathComponent("CaptureOne/Cache/Thumbnails")
        let prefix = url.lastPathComponent + "."
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        return files.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".cot") }
            .map { dir.appendingPathComponent($0).path }
            .max { (mtime($0) ?? .distantPast) < (mtime($1) ?? .distantPast) }
    }
    func previewPath(_ it: Item) -> String { fake ? it.imagePath : cacheDir + "/" + it.name + ".jpg" }

    // 처음 불러오기
    func loadFromC1() {
        guard C1.running else { status = "캡쳐원이 꺼져 있어요 · 캡쳐원을 켜고 다시 열어 주세요"; return }
        status = "캡쳐원에서 사진 목록을 불러오는 중…"
        C1.q.async {
            guard let (doc, list) = C1.list() else {
                DispatchQueue.main.async { self.status = "캡쳐원에서 사진 목록을 가져오지 못했어요" }; return
            }
            let safe = doc.replacingOccurrences(of: "/", with: "_")
            let dir = cacheRoot + "/" + safe
            cleanPreviews(keepFolders: true)                                 // 예전에 남은 미리보기 JPG 정리 (폴더는 둠)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            DispatchQueue.main.async {
                self.docName = doc; self.cacheDir = dir; self.items = list
                self.index = 0; self.pos = 0; self.vtarget = 0; self.armed = 0
                self.status = list.isEmpty ? "사진이 없어요" : "보정 반영 미리보기를 만드는 중…"
                self.loadAround(); self.startWatching()
            }
            if !list.isEmpty {
                let ids = C1.makePreviews(into: dir)
                DispatchQueue.main.async { self.previewIDs = ids }
            }
        }
    }
    func loadFake(_ dir: String) {
        fake = true
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { ["jpg", "jpeg", "png"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
        items = files.map { Item(id: dir + "/" + $0, name: ($0 as NSString).deletingPathExtension, rating: 0, tag: 0, imagePath: dir + "/" + $0) }
        docName = "가짜 테스트"; status = "가짜 테스트 모드 · 캡쳐원 연결 없음"
        loadAround(sync: true)
    }

    // 지금 사진 주변만 이미지 불러오기
    func loadAround(sync: Bool = false) {
        guard !items.isEmpty else { return }
        let n = items.count
        var seen = Set<Int>()
        for off in -5...5 {
            let i = wrap(index + off)
            guard seen.insert(i).inserted else { continue }
            let it = items[i]
            let wantLarge = abs(off) <= 1 || n <= 3
            let work = {
                var s: NSImage? = nil, l: NSImage? = nil, lt: Date? = nil
                if self.small[it.id] == nil, let p = self.thumbPath(it) { s = loadImage(p, max: 500) }
                let pp = self.previewPath(it)
                if wantLarge, let t = mtime(pp), t != self.largeTime[it.id] { l = loadImage(pp, max: 1800); lt = t }
                let apply = {
                    if let s = s { self.small[it.id] = s; self.aspect[it.id] = s.size.width / max(1, s.size.height) }
                    if let l = l { self.large[it.id] = l; self.largeTime[it.id] = lt }
                }
                if sync { apply() } else { DispatchQueue.main.async(execute: apply) }
            }
            if sync { work() } else { ioq.async(execute: work) }
        }
    }
    // 큰 미리보기가 새로 생기거나 바뀌면 다시 불러오기
    func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadAround()
            if !self.fake, !self.items.isEmpty {
                let want = self.items.filter { self.previewIDs?.contains($0.id) ?? true }
                let done = want.filter { FileManager.default.fileExists(atPath: self.previewPath($0)) }.count
                self.status = (self.previewIDs != nil && done >= want.count) ? "" : "보정 반영 미리보기 \(done) / \(want.count)"
            }
        }
    }
    // 캡쳐원 쪽 별점·태그 다시 읽기 (창이 앞으로 올 때)
    func refreshMarks() {
        guard !fake, C1.running, !items.isEmpty else { return }
        C1.q.async {
            guard let (_, list) = C1.list() else { return }
            let map = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            DispatchQueue.main.async {
                for i in self.items.indices { if let n = map[self.items[i].id] { self.items[i].rating = n.rating; self.items[i].tag = n.tag } }
            }
        }
    }

    // 조작
    // 키보드·스크롤로 한 칸 이동. 첫/마지막에서 넘어갈 때는 한 번 알리고, 한 번 더 누르면 넘어감
    // held: 키를 꾹 누르고 있는 중(자동 반복)이거나 트랙패드 관성 — 끝에서는 절대 넘어가지 않음
    func step(_ dir: Int, held: Bool = false) {
        let n = items.count
        guard n > 1 else { return }
        let atEdge = (dir < 0 && index == 0) || (dir > 0 && index == n - 1)
        if atEdge && (armed != dir || held) {
            if armed == dir && held { return }                  // 이미 알렸고 아직 누르고 있음 → 그대로 멈춤
            armed = dir
            showToast(dir < 0 ? "First photo" : "Last photo")
            return
        }
        armed = 0
        moveTo(virtual: vtarget + dir, animated: navAnimation)
    }
    // 클릭한 카드(가상 번호)로 바로 이동
    func moveTo(virtual v: Int, animated: Bool = true) {
        guard !items.isEmpty else { return }
        armed = 0
        vtarget = v
        index = wrap(v)
        if animated { withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { pos = Double(v) } }
        else { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { pos = Double(v) } }
        loadAround()
    }
    func showToast(_ t: String) {
        toastWork?.cancel()
        withAnimation(.easeOut(duration: 0.12)) { toast = t }
        let w = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.7)) { self?.toast = nil } }   // 천천히 희미하게
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: w)
    }
    func rate(_ r: Int) {
        guard let it = current else { return }
        let v = (it.rating == r && r != 0) ? 0 : r          // 같은 별점 다시 누르면 지움
        items[index].rating = v
        if !fake { C1.q.async { C1.setRating(it.id, v) } }
    }
    func tag(_ t: Int) {
        guard let it = current else { return }
        let v = it.tag == t ? 0 : t                          // 같은 태그 다시 누르면 지움
        items[index].tag = v
        if !fake { C1.q.async { C1.setTag(it.id, v) } }
    }
    func refreshCurrent() {
        guard !fake, let it = current else { return }
        status = "지금 사진 미리보기 다시 만드는 중…"
        C1.q.async { C1.makePreviews(into: self.cacheDir, ids: [it.id]) }
    }
}

var tiltDeg: Double = 14  // 위에서 내려다보는 각도 (0 = 정면). 옆 4장만 기울고 반사·음영이 들어감
// 3D 회전 한 번에: 옆으로(ry) 돈 사진을 위에서(rx) 내려다본 원근. 두 번 따로 돌리면 면이 평평해져 기울기가 안 생김
struct Turn3D: GeometryEffect {
    var ry: Double, rx: Double, persp: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(ry, rx) } set { ry = newValue.first; rx = newValue.second }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        var m = CATransform3DMakeRotation(CGFloat(ry), 0, 1, 0)
        m = CATransform3DConcat(m, CATransform3DMakeRotation(CGFloat(rx), 1, 0, 0))
        var p = CATransform3DIdentity; p.m34 = -CGFloat(persp) / max(size.width, size.height)
        m = CATransform3DConcat(m, p)
        let pre = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
        let post = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        return ProjectionTransform(CATransform3DConcat(CATransform3DConcat(pre, m), post))
    }
}

// MARK: - 사진 카드 (세로 w×1.5w, 가로 1.5w×w — 여백 없이 꽉 채움)
struct Card: View {
    let img: NSImage?
    let w: CGFloat, h: CGFloat
    let current: Bool
    var shade: Double = 0          // 0 가운데 → 1 옆: 바깥쪽 음영 세기
    var outerLeft = true           // 바깥쪽이 왼쪽인지
    var body: some View {
        ZStack {
            Rectangle().fill(P.card)
            if let i = img { Image(nsImage: i).resizable().interpolation(.high).aspectRatio(contentMode: .fill).frame(width: w, height: h) }
            if shade > 0 {         // 앞에서 빛을 받은 것처럼 바깥쪽이 살짝 어두움
                LinearGradient(colors: [.black.opacity(0.16 * shade), .black.opacity(0)],
                               startPoint: outerLeft ? .leading : .trailing, endPoint: outerLeft ? .trailing : .leading)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(current ? P.accent : P.border, lineWidth: current ? 2.5 : 1))
    }
}

// 원통 위 자리 계산 (화면 그리기와 마우스 위치 계산이 같은 값을 씀)
struct Slot { let v: Int; let it: Item; let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat
              let sc: CGFloat; let rot: Double; let th: Double; let vis: Double; let near: Bool }

func layout(_ s: Store, _ size: CGSize) -> [Slot] {
    let n = s.items.count
    guard n > 0 else { return [] }
    let base = min(size.height * 0.62 / 1.5, size.width * 0.24)       // 세로 사진 너비
    let k = base / 290                                                  // 시안(290px) 기준 비율
    let R = 700 * k, D = 1100 * k
    let step = 29.0 * .pi / 180                                         // 세로-세로 사이 각도
    let cx = size.width / 2, cy = size.height / 2
    let half = n >= 9 ? 4 : max(0, (n - 1) / 2)
    let extra = (n < 9 && n % 2 == 0) ? 1 : 0
    let c = Int(s.pos.rounded(.down)), frac = s.pos - Double(c)
    let lo = c - half - 1, hi = c + half + extra + 1
    func unit(_ v: Int) -> Double { (s.aspect[s.items[s.wrap(v)].id] ?? 0.67) > 1 ? 1.5 : 1 }   // 가로 사진은 1.5칸
    // 이웃 사이 각도를 사진 폭에 맞춰 누적 (가로 사진 옆은 더 벌어짐)
    var A: [Int: Double] = [c: 0]
    // 기울어진 가로 사진은 보이는 폭이 줄어드므로 폭 차이의 68%만 간격에 반영
    func gap(_ a: Int, _ b: Int) -> Double { step * (1 + 0.68 * ((unit(a) + unit(b)) / 2 - 1)) }
    if hi > c { for v in c..<hi { A[v + 1] = A[v]! + gap(v, v + 1) } }
    if lo < c { for v in stride(from: c, to: lo, by: -1) { A[v - 1] = A[v]! - gap(v, v - 1) } }
    let shift = (A[c + 1] ?? 0) * frac                                  // 회전 중간 위치
    var out: [Slot] = []
    for v in (lo + 1)...(hi - 1) {
        let it = s.items[s.wrap(v)]
        let th = A[v]! - shift
        let dist = abs(Double(v) - s.pos)
        let t = min(max(dist - 1, 0), 1)                                // 0: 가운데 세 장 → 1: 가장자리
        let depth = R * (1 - CGFloat(cos(th)))
        let persp = D / (D + depth)
        let sc = persp * (1 + 0.09 * t)
        let push = CGFloat(th < 0 ? -1 : 1) * 47 * k * t * CGFloat(unit(v))
        let u = unit(v)
        let w = u > 1 ? base * 1.5 : base, h = u > 1 ? base : base * 1.5
        let tilt = tiltDeg * .pi / 180
        let lift = depth * CGFloat(sin(tilt)) * persp                  // 뒤로 물러난 사진일수록 위로 (내려다보는 느낌)
        out.append(Slot(v: v, it: it, x: cx + R * CGFloat(sin(th)) * persp + push, y: cy - lift - (tiltDeg > 0 ? 16 * k * CGFloat(t) : 0), w: w, h: h,   // 1·5번은 아주 살짝 더 위로
                        
                        sc: sc, rot: th * (1.35 - 0.25 * t), th: th, vis: cos(th), near: dist < 1.5))
    }
    // 겹침 방지: 화면에 보이는 폭 기준으로 옆 사진과 최소 간격 확보 (가운데에서 바깥으로)
    func hw(_ sl: Slot) -> CGFloat { sl.w * sl.sc * max(0.35, CGFloat(cos(sl.rot))) / 2 }
    let minGap = 14 * k
    guard let mid = out.indices.min(by: { abs(out[$0].th) < abs(out[$1].th) }) else { return out }
    func moved(_ sl: Slot, _ x: CGFloat) -> Slot { Slot(v: sl.v, it: sl.it, x: x, y: sl.y, w: sl.w, h: sl.h, sc: sl.sc, rot: sl.rot, th: sl.th, vis: sl.vis, near: sl.near) }
    if mid + 1 < out.count { for i in (mid + 1)..<out.count {
        let need = out[i - 1].x + hw(out[i - 1]) + hw(out[i]) + minGap
        if out[i].x < need { out[i] = moved(out[i], need) }
    } }
    if mid > 0 { for i in stride(from: mid - 1, through: 0, by: -1) {
        let need = out[i + 1].x - hw(out[i + 1]) - hw(out[i]) - minGap
        if out[i].x > need { out[i] = moved(out[i], need) }
    } }
    return out
}
// 마우스 아래 사진 (앞에 있는 것 우선)
func slotAt(_ p: CGPoint, _ s: Store, _ size: CGSize) -> Slot? {
    layout(s, size).filter { $0.vis >= 0.3 }.sorted { $0.vis > $1.vis }.first { sl in
        let hw = sl.w * sl.sc * max(0.35, CGFloat(cos(sl.rot))) / 2, hh = sl.h * sl.sc / 2
        return abs(p.x - sl.x) <= hw && abs(p.y - sl.y) <= hh
    }
}

// 원통 위 카드들
struct Cards: View {
    @ObservedObject var s: Store
    let size: CGSize
    var blurLayer = false
    var body: some View {
        ZStack {
            ForEach(layout(s, size), id: \.v) { sl in
                let hov = s.hovered == sl.it.id && !blurLayer
                let img = blurLayer ? s.small[sl.it.id] : (sl.near ? (s.large[sl.it.id] ?? s.small[sl.it.id]) : s.small[sl.it.id])
                Card(img: img, w: sl.w, h: sl.h, current: sl.v == s.vtarget && !blurLayer,
                     shade: tiltDeg > 0 ? min(1, abs(sl.th) / 0.5) : 0, outerLeft: sl.th < 0)
                    .overlay(alignment: .bottom) {
                        // 바닥 반사: 사진을 아래로 뒤집어 붙이고 아래로 갈수록 바탕색으로 사라짐
                        if !blurLayer && tiltDeg > 0 {
                            Card(img: img, w: sl.w, h: sl.h, current: false,
                                 shade: min(1, abs(sl.th) / 0.5), outerLeft: sl.th < 0)
                                .scaleEffect(x: 1, y: -1)
                                .mask(LinearGradient(colors: [.white.opacity(lightTheme ? 0.2 : 0.16), .clear],
                                                     startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22)))
                                .offset(y: sl.h + 3)
                                .allowsHitTesting(false)
                        }
                    }
                    .modifier(Turn3D(ry: sl.rot, rx: -tiltDeg * .pi / 180 * min(1, abs(sl.th) / 0.5), persp: tiltDeg > 0 ? 0.11 : 0.12))   // 안쪽 변이 조금 더 길게   // 가운데는 기울지 않음
                    .scaleEffect(sl.sc * (hov ? 1.05 : 1) * (1 - (tiltDeg > 0 ? 0.09 : 0) * min(1, abs(sl.th) / 0.5)))
                    .shadow(color: .black.opacity(blurLayer ? 0 : P.shadow), radius: tiltDeg > 0 ? 16 : 22, x: CGFloat(sin(sl.th)) * 14, y: tiltDeg > 0 ? 10 : 16)
                    .opacity(sl.vis < 0.3 ? 0 : 1)
                    .position(x: sl.x, y: sl.y)
                    .zIndex(sl.vis)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

// 화면 양 끝 → 안쪽 그라데이션
struct EdgeFade: View {
    var edge = 0.14; var invert = false
    var body: some View {
        let a = invert ? 0.0 : 1.0, b = invert ? 1.0 : 0.0
        LinearGradient(stops: [.init(color: .white.opacity(a), location: 0), .init(color: .white.opacity(b), location: edge),
                               .init(color: .white.opacity(b), location: 1 - edge), .init(color: .white.opacity(a), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - 화면
struct RootView: View {
    @ObservedObject var s: Store
    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { g in
                // 가장자리 그라데이션이 가운데 세 장(2·3·4번)에는 닿지 않게: 그 사진들 바깥 끝보다 안쪽으로 번지지 않음
                let fe = fadeEnd(g.size)
                ZStack {
                    P.stage
                    Cards(s: s, size: g.size).mask(EdgeFade(edge: fe, invert: true))
                    Cards(s: s, size: g.size, blurLayer: true).blur(radius: 6).mask(EdgeFade(edge: fe)).allowsHitTesting(false)
                    LinearGradient(stops: [.init(color: P.stage, location: 0), .init(color: P.stage.opacity(0), location: fe),
                                           .init(color: P.stage.opacity(0), location: 1 - fe), .init(color: P.stage, location: 1)],
                                   startPoint: .leading, endPoint: .trailing).allowsHitTesting(false)
                    // 마우스 올림·클릭: 위치로 어느 사진인지 계산 (떼면 확실히 원래대로)
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            let id: String?
                            switch phase {
                            case .active(let p): id = slotAt(p, s, g.size)?.it.id
                            case .ended: id = nil
                            }
                            if id != s.hovered { withAnimation(.easeOut(duration: 0.18)) { s.hovered = id } }
                        }
                        .gesture(SpatialTapGesture().onEnded { e in
                            guard let sl = slotAt(e.location, s, g.size) else { return }
                            if sl.v == s.vtarget { withAnimation(.easeOut(duration: 0.2)) { s.big = true } } else { s.moveTo(virtual: sl.v) }
                        })
                    if s.items.isEmpty {
                        Text(s.status.isEmpty ? "사진이 없어요" : s.status).font(.system(size: 13)).foregroundColor(P.sub)
                    }
                    if let t = s.toast {
                        VStack {
                            Text(t).font(.system(size: 13, weight: .semibold)).foregroundColor(P.strong)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Capsule().fill(P.toastBg.opacity(0.95)))
                                .overlay(Capsule().strokeBorder(P.accent.opacity(0.7), lineWidth: 1))
                                .padding(.top, 22)
                            Spacer()
                        }
                        .transition(.opacity)
                        .allowsHitTesting(false)
                    }
                    if s.big, let it = s.current {
                        ZStack {
                            P.stage.opacity(0.96)
                            if let img = s.large[it.id] ?? s.small[it.id] {
                                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(24)
                            }
                        }
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { s.big = false } }
                        .transition(.opacity)
                    }
                }
            }
            infoBar
        }
        .background(P.stage)
        .preferredColorScheme(lightTheme ? .light : .dark)
    }

    // 그라데이션 폭(화면 비율): 가운데 세 장 중 가장 바깥 끝 - 여유 1%, 최대 16%
    func fadeEnd(_ size: CGSize) -> Double {
        let near = layout(s, size).filter { $0.near }
        guard size.width > 0, !near.isEmpty else { return 0.14 }
        let edge = near.map { sl -> CGFloat in
            let hw = sl.w * sl.sc * max(0.35, CGFloat(cos(sl.rot))) / 2
            return min(sl.x - hw, size.width - (sl.x + hw))                  // 왼쪽·오른쪽 중 화면 끝에 더 가까운 쪽
        }.min() ?? 0
        return max(0.05, min(0.16, Double(edge / size.width) - 0.01))
    }

    var topBar: some View {
        HStack {
            Spacer().frame(width: 78)        // 신호등 버튼 자리
            Text("셀렉 휠").font(.system(size: 12, weight: .semibold)).foregroundColor(P.text)
            if !s.docName.isEmpty { Text("· \(s.docName.replacingOccurrences(of: ".cosessiondb", with: ""))").font(.system(size: 12)).foregroundColor(P.sub) }
            Spacer()
            if !s.status.isEmpty && !s.items.isEmpty { Text(s.status).font(.system(size: 11)).foregroundColor(P.sub) }
            Text("사진 \(s.items.count)장").font(.system(size: 11)).foregroundColor(P.sub)
            animToggle.padding(.leading, 6)
            themeToggle.padding(.leading, 4).padding(.trailing, 10)
        }
        .frame(height: 34).background(P.bar)
    }

    // 방향키·스크롤 넘기기 애니메이션 켜기/끄기
    var animToggle: some View {
        Image(systemName: s.anim ? "rotate.3d" : "rectangle.stack")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(s.anim ? P.accent : P.sub)
            .frame(width: 30, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(s.anim ? P.strong.opacity(0.1) : .clear))
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).strokeBorder(P.sub.opacity(0.35)))
            .contentShape(Rectangle())
            .onTapGesture { s.setAnim(!s.anim) }
            .help(s.anim ? "넘기기 애니메이션 켜짐 (누르면 끔)" : "넘기기 애니메이션 꺼짐 (누르면 켬)")
    }

    // 검정 / 흰색 전환
    var themeToggle: some View {
        HStack(spacing: 2) {
            ForEach([false, true], id: \.self) { on in
                let sel = s.light == on
                Image(systemName: on ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(sel ? P.accent : P.sub)
                    .frame(width: 26, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(sel ? P.strong.opacity(0.1) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { s.setLight(on) }
                    .help(on ? "흰색 화면" : "검정 화면")
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).strokeBorder(P.sub.opacity(0.35)))
    }

    var infoBar: some View {
        HStack(spacing: 18) {
            Text(s.current?.name ?? "").font(.system(size: 13, weight: .semibold)).foregroundColor(P.strong).lineLimit(1)
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { k in
                    let on = (s.current?.rating ?? 0) >= k
                    Image(systemName: on ? "star.fill" : "star").font(.system(size: 13)).foregroundColor(on ? P.accent : P.sub)
                        .onTapGesture { s.rate(k) }
                }
            }
            if let t = s.current?.tag, let info = tagInfo[t] {
                HStack(spacing: 6) { Circle().fill(info.0).frame(width: 10, height: 10); Text(info.1).font(.system(size: 12)).foregroundColor(P.text) }
            }
            Spacer()
            Text("← → 넘기기   1–5 별점   0 지우기   6–9 태그   - 태그 지우기   Space 크게   R 새로고침")
                .font(.system(size: 11)).foregroundColor(P.sub).lineLimit(1)
            Text(s.items.isEmpty ? "0 / 0" : "\(s.index + 1) / \(s.items.count)").font(.system(size: 12, design: .monospaced)).foregroundColor(P.text)
        }
        .padding(.horizontal, 16).frame(height: 44).background(P.bar)
    }
}

// MARK: - 앱
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var window: NSWindow!
    var scrollAcc: CGFloat = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--fake"), args.count > i + 1 { store.loadFake(args[i + 1]) } else { store.loadFromC1() }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        let applyWindowTheme = { [weak self] in
            guard let w = self?.window else { return }
            w.appearance = NSAppearance(named: lightTheme ? .aqua : .darkAqua)
            w.backgroundColor = lightTheme ? .white : .black
        }
        applyWindowTheme()
        store.onTheme = applyWindowTheme
        window.minSize = NSSize(width: 900, height: 600)
        window.contentView = NSHostingView(rootView: RootView(s: store))
        window.center(); window.setFrameAutosaveName("cc.cullwheel")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 키보드
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self else { return e }
            let s = self.store
            if e.modifierFlags.contains(.command) { return e }
            switch e.keyCode {
            case 123: s.step(-1, held: e.isARepeat); return nil         // ←
            case 124: s.step(1, held: e.isARepeat); return nil          // →
            case 49: withAnimation(.easeOut(duration: 0.2)) { s.big.toggle() }; return nil   // Space
            case 53: if s.big { withAnimation(.easeOut(duration: 0.2)) { s.big = false } } else { NSApp.terminate(nil) }; return nil  // Esc
            default: break
            }
            let c = e.charactersIgnoringModifiers ?? ""
            if let r = Int(c), (0...5).contains(r) { s.rate(r); return nil }
            if let t = tagKeys[c] { s.tag(t); return nil }
            if c == "-" { s.tag(0); return nil }
            if c.lowercased() == "r" { s.refreshCurrent(); return nil }
            return e
        }
        // 트랙패드·휠 스크롤 = 넘기기
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self = self else { return e }
            let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? -e.scrollingDeltaX : -e.scrollingDeltaY
            if e.phase == .began || (e.phase == [] && e.momentumPhase == []) && !e.hasPreciseScrollingDeltas { self.scrollAcc = 0 }
            self.scrollAcc += e.hasPreciseScrollingDeltas ? d : d * 12
            let th: CGFloat = 45
            let held = e.momentumPhase != []                               // 관성 스크롤은 끝에서 넘어가지 않음
            if self.scrollAcc > th { self.store.step(1, held: held); self.scrollAcc = 0 }
            if self.scrollAcc < -th { self.store.step(-1, held: held); self.scrollAcc = 0 }
            return nil
        }
    }
    func applicationDidBecomeActive(_ n: Notification) { store.refreshMarks() }
    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) {
        // 창 닫으면 이 세션 미리보기 JPG만 지움. 폴더는 남김 — 캡쳐원이 아직 만드는 중이면 폴더가 없을 때 "파일을 처리할 수 없습니다" 오류가 남
        if !store.fake && !store.cacheDir.isEmpty { cleanPreviews(only: store.cacheDir, keepFolders: true) }
    }
}

// MARK: - 확인용 스냅샷
@MainActor func snapshot(_ out: String, _ dir: String) {
    let s = Store(); s.loadFake(dir); s.index = min(3, max(0, s.items.count - 1)); s.vtarget = s.index; s.pos = Double(s.index); s.loadAround(sync: true)
    if let it = s.current { s.items[s.index].rating = 3; s.items[s.index].tag = 4; _ = it }
    func save(_ name: String) {
        let r = ImageRenderer(content: RootView(s: s).frame(width: 1200, height: 800)); r.scale = 1
        if let cg = r.cgImage { try? NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.9])?.write(to: URL(fileURLWithPath: out + "/" + name)) }
    }
    save("1_기본.jpg")
    s.index = 0; s.vtarget = 0; s.pos = 0; s.loadAround(sync: true); s.toast = "First photo"; save("4_첫장_알림.jpg"); s.toast = nil
    s.index = min(3, max(0, s.items.count - 1)); s.vtarget = s.index; s.pos = Double(s.index)
    if s.items.count > 4 { s.hovered = s.items[s.wrap(s.index + 1)].id; save("2_마우스올림.jpg"); s.hovered = nil }
    s.big = true; save("3_크게보기.jpg"); s.big = false
    let keepTheme = lightTheme
    lightTheme = false; s.light = false
    for t in [14.0] { tiltDeg = t; save("14_반사_검정.jpg"); lightTheme = true; s.light = true; save("14_반사_화이트.jpg"); lightTheme = false; s.light = false }
    tiltDeg = 14
    lightTheme = true; s.light = true
    save("5_하얀화면.jpg")
    s.index = 0; s.vtarget = 0; s.pos = 0; s.loadAround(sync: true); s.toast = "First photo"; save("6_하얀화면_알림.jpg"); s.toast = nil
    lightTheme = keepTheme; s.light = keepTheme
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 {
    MainActor.assumeIsolated { snapshot(args[i + 1], args[i + 2]) }
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
