// yinsta — 가상 인스타그램 피드 시뮬레이터 (아이폰 모양 창 + 웹 화면 ui/index.html)
// 사진·설정은 ~/Library/Application Support/yinsta/ 에 파일로 저장 (posts/<id>.jpg, posts.json, settings.json)
import Cocoa
import WebKit
import UniformTypeIdentifiers

let BASE_W: CGFloat = 481, STAGE_H: CGFloat = 968, PANEL_H: CGFloat = 924, PC_MIN_W: CGFloat = 760, PC_MIN_H: CGFloat = 480   // ui/index.html 의 무대·패널 크기 (CSS px). PC 창(브라우저) 크기는 pcW×pcH, 무대 = (pcW+6)×(pcH+52)
let LEVELS: [CGFloat] = [0.8, 0.9, 1.0, 1.1, 1.2]   // 창 크기 5단계 (기본 100%)
let MIN_Z: CGFloat = 0.85, MAX_Z: CGFloat = 1.2
func nearestLevel(_ z: CGFloat) -> CGFloat { LEVELS.min { abs($0 - z) < abs($1 - z) } ?? 1 }

final class Win: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.22 }   // 맥 창 확대처럼 빠르게
}

final class Store {
    let dir: URL
    var meta: [[String: Any]] = []
    init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("posts"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("sources"), withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: dir.appendingPathComponent("posts.json")), let a = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] { meta = a }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("sources.json")), let a = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] { sources = a }
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("stories"), withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: dir.appendingPathComponent("stories.json")), let a = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] { stories = a }
    }
    var sources: [[String: Any]] = []
    var stories: [[String: Any]] = []
    func saveStories() { if let d = try? JSONSerialization.data(withJSONObject: stories) { try? d.write(to: dir.appendingPathComponent("stories.json"), options: .atomic) } }
    func storyURL(_ id: String) -> URL { dir.appendingPathComponent("stories").appendingPathComponent(id + ".jpg") }
    func saveMeta() { if let d = try? JSONSerialization.data(withJSONObject: meta) { try? d.write(to: dir.appendingPathComponent("posts.json"), options: .atomic) } }
    func saveSources() { if let d = try? JSONSerialization.data(withJSONObject: sources) { try? d.write(to: dir.appendingPathComponent("sources.json"), options: .atomic) } }
    func imageURL(_ id: String) -> URL { dir.appendingPathComponent("posts").appendingPathComponent(id + ".jpg") }
    func sourceURL(_ id: String) -> URL { dir.appendingPathComponent("sources").appendingPathComponent(id + ".jpg") }
    func settings() -> [String: Any]? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("settings.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    func saveSettings(_ s: [String: Any]) { if let d = try? JSONSerialization.data(withJSONObject: s) { try? d.write(to: dir.appendingPathComponent("settings.json"), options: .atomic) } }
}

func cleanID(_ v: Any?) -> String? {
    guard let s = v as? String, !s.isEmpty, s.count < 64, s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
    return s
}
func dataFromDataURL(_ s: String) -> Data? {
    guard let r = s.range(of: "base64,") else { return nil }
    return Data(base64Encoded: String(s[r.upperBound...]))
}
func jsLiteral(_ obj: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(obj), let d = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
    return String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
}

// yinsta://app/<경로> : ui 폴더의 화면 파일과 저장 폴더의 사진(posts/sources/stories)을 같은 출처로 제공 → 캡처·fetch 가능, 사진은 파일로 바로 불러옴
final class Server: NSObject, WKURLSchemeHandler {
    let ui: URL; let store: Store
    init(ui: URL, store: Store) { self.ui = ui; self.store = store }
    func webView(_ w: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path; if path.isEmpty || path == "/" { path = "/index.html" }
        let parts = path.split(separator: "/").map(String.init)
        var file: URL? = nil
        if parts.count == 2, ["posts", "sources", "stories"].contains(parts[0]), parts[1].hasSuffix(".jpg"), cleanID(String(parts[1].dropLast(4))) != nil {
            file = store.dir.appendingPathComponent(parts[0]).appendingPathComponent(parts[1])
        } else if !parts.contains("..") {
            file = parts.reduce(ui) { $0.appendingPathComponent($1) }
        }
        guard let f = file, let data = try? Data(contentsOf: f) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!); task.didFinish(); return
        }
        let mime: String = ["html": "text/html; charset=utf-8", "js": "application/javascript", "css": "text/css", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "svg": "image/svg+xml", "json": "application/json"][f.pathExtension.lowercased()] ?? "application/octet-stream"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)", "Cache-Control": "no-cache"])!)
        task.didReceive(data); task.didFinish()
    }
    func webView(_ w: WKWebView, stop task: WKURLSchemeTask) {}
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    var window: Win!
    var web: WKWebView!
    var store: Store!
    var level: CGFloat = 1.0   // 슬라이더 단계 (0.8~1.2) — 디스플레이를 옮겨도 그대로
    var df: CGFloat = 1.0      // 디스플레이 계수 = 이 화면 높이 / 기준 화면 높이(refH)
    var z: CGFloat = 1.0       // 휴대폰·PC 실제 배율 = level × df
    var pz: CGFloat = 1.0      // 패널 실제 배율 = df
    var pcW: CGFloat = 1360, pcH: CGFloat = 880   // PC 브라우저 창 크기(CSS px) — 커서로 조절, 배율과 별개
    var testJS: String?

    func applicationDidFinishLaunching(_ n: Notification) {
        let env = ProcessInfo.processInfo.environment
        var dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("yinsta", isDirectory: true)
        if let t = env["YINSTA_STORE"], !t.isEmpty { dir = URL(fileURLWithPath: t, isDirectory: true) }   // 시험용 저장소
        store = Store(dir: dir)
        if let p = env["YINSTA_TESTJS"], env["YINSTA_STORE"] != nil, let s = try? String(contentsOfFile: p, encoding: .utf8) { testJS = s }   // 시험 스크립트는 시험 저장소를 따로 줄 때만 받음
        buildMenu()
        let ud = UserDefaults.standard
        let h0 = screenH(NSScreen.main)
        if ud.double(forKey: "refH") <= 0 { ud.set(Double(h0), forKey: "refH") }   // 기준 화면: 처음 쓴 화면 (여기서 100% = 기본 크기)
        var lv = CGFloat(ud.double(forKey: "level"))
        if lv <= 0 { let frac = CGFloat(ud.double(forKey: "frac")); lv = frac > 0 ? nearestLevel(frac * h0 / STAGE_H) : 1.0; ud.set(Double(lv), forKey: "level") }   // 예전 버전(frac)에서 넘어오기
        level = nearestLevel(lv); df = dfFor(NSScreen.main); z = level * df; pz = df
        if ud.double(forKey: "pcW") >= PC_MIN_W { pcW = CGFloat(ud.double(forKey: "pcW")) }
        if ud.double(forKey: "pcH") >= PC_MIN_H { pcH = CGFloat(ud.double(forKey: "pcH")) }
        if let v = NSScreen.main?.visibleFrame { pcW = min(pcW, (v.width - 16) / z - 52); pcH = min(pcH, (v.height - 16) / z) }   // 화면보다 크게 기억돼 있으면 화면에 맞춤
        window = Win(contentRect: NSRect(x: 0, y: 0, width: BASE_W * z, height: STAGE_H * z), styleMask: [.borderless], backing: .buffered, defer: false)   // 휴대폰 모드는 커서로 크기 조절 불가(버튼·단축키만), 펼침·PC 모드만 .resizable
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false   // 맥 창 그림자는 떠 있는 버튼마다 회색 테두리를 그려서 끔 (그림자는 CSS로)
        window.isReleasedWhenClosed = false; window.delegate = self; window.title = "yinsta"

        let ui = Bundle.main.resourceURL!.appendingPathComponent("ui")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "yinsta")
        cfg.setURLSchemeHandler(Server(ui: ui, store: store), forURLScheme: "yinsta")
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: BASE_W * z, height: STAGE_H * z), configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.uiDelegate = self; web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")          // 창 바깥(아이폰 모서리 밖)은 투명
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }
        web.allowsMagnification = false
        window.contentView = web
        web.load(URLRequest(url: URL(string: "yinsta://app/index.html")!))
        window.center()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    // MARK: 메뉴
    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "yinsta 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "yinsta 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "yinsta 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem); let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let viewItem = NSMenuItem(); main.addItem(viewItem); let view = NSMenu(title: "보기")
        view.addItem(withTitle: "확대", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        view.addItem(withTitle: "축소", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "기본값", action: #selector(zoomReset(_:)), keyEquivalent: "0")
        view.addItem(.separator())
        view.addItem(withTitle: "저장 폴더 보기", action: #selector(showStore(_:)), keyEquivalent: "")
        viewItem.submenu = view
        let winItem = NSMenuItem(); main.addItem(winItem); let win = NSMenu(title: "윈도우")
        win.addItem(withTitle: "닫기", action: #selector(closeWindow(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "최소화", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        NSApp.mainMenu = main
    }

    // MARK: 창 크기
    func screenH(_ scr: NSScreen?) -> CGFloat { (scr?.visibleFrame.height ?? 900) - 24 }
    func dfFor(_ scr: NSScreen?) -> CGFloat {   // 디스플레이 계수: 화면 높이 / 기준 화면 높이 (단계는 그대로, 실제 크기만 화면에 맞춤)
        let ref = CGFloat(UserDefaults.standard.double(forKey: "refH")); if ref <= 0 { return 1.0 }
        return min(1.4, max(0.7, (screenH(scr) / ref * 100).rounded() / 100))
    }
    func windowDidChangeScreen(_ n: Notification) {   // 스튜디오 디스플레이 ↔ 맥북 화면 이동: 단계는 그대로, 휴대폰·패널·PC 모두 화면 높이 비율로
        let ndf = dfFor(window.screen)
        guard abs(ndf - df) > 0.005 else { window.setFrame(clampToScreen(window.frame), display: true); return }
        df = ndf; z = level * df; pz = df; tellZoom()
        guard layoutMode != "expanded" else { window.setFrame(clampToScreen(window.frame), display: true); return }
        var f = window.frame; let top = f.maxY; f.size = sizeFor(level); f.origin.y = top - f.height
        window.setFrame(clampToScreen(f), display: true, animate: false); window.invalidateShadow()
    }
    // MARK: 창 크기 — 패널(왼쪽, 고정 크기) + 휴대폰 무대(배율 z, CSS zoom). 창 = 패널 너비 + 432·z,  높이 = max(932·z, 패널 906)
    var panelsW: CGFloat = 0
    var layoutMode = "normal"      // normal / expanded / pc
    var stageW: CGFloat { layoutMode == "pc" ? pcW + 52 : BASE_W }   // PC: 왼쪽 토글 자리 52 + 크롬 창
    var stageH: CGFloat { layoutMode == "pc" ? pcH : STAGE_H }
    func sizeFor(_ lv: CGFloat) -> NSSize { let nz = lv * df; return NSSize(width: panelsW * df + stageW * nz, height: layoutMode == "pc" ? stageH * nz : max(stageH * nz, panelsW > 0 ? PANEL_H * df : 0)) }   // PC는 패널이 창 높이를 따라감   // 단계 lv 기준. 패널은 df, 무대는 lv·df
    var savedFrame: NSRect?   // PC 창 더블클릭 최대화 전 크기
    var resizeMon: Any?
    func startResize(edge: String) {   // 가장자리 손잡이(웹에서 mousedown)로 창 크기 조절 — 가로·세로·모서리
        guard layoutMode != "normal", resizeMon == nil else { return }
        let start = NSEvent.mouseLocation, f0 = window.frame, minS = window.contentMinSize
        resizeMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] e in
            guard let self = self else { return e }
            let p = NSEvent.mouseLocation; var f = f0
            let dx = p.x - start.x, dy = p.y - start.y
            if edge.contains("r") { f.size.width = max(minS.width, f0.width + dx) }
            if edge.contains("l") { let w = max(minS.width, f0.width - dx); f.origin.x = f0.maxX - w; f.size.width = w }
            if edge.contains("b") { let h = max(minS.height, f0.height - dy); f.origin.y = f0.maxY - h; f.size.height = h }
            self.window.setFrame(f, display: true)
            if e.type == .leftMouseUp { if let m = self.resizeMon { NSEvent.removeMonitor(m) }; self.resizeMon = nil; self.window.invalidateShadow() }
            return nil
        }
    }
    func toggleMax() {   // 크롬 제목줄 더블클릭처럼: 화면 가득 ↔ 원래 크기 (PC 모드)
        guard layoutMode == "pc" else { return }
        if let f = savedFrame { savedFrame = nil; window.setFrame(f, display: true, animate: true) }
        else if let v = window.screen?.visibleFrame { savedFrame = window.frame; window.setFrame(v.insetBy(dx: 8, dy: 8), display: true, animate: true) }   // 맥 '채우기'처럼 가장자리 8pt 여백
        window.invalidateShadow()
    }
    func tellPC() { web.evaluateJavaScript("window.__yinstaPC && __yinstaPC(\(Double(pcW)),\(Double(pcH)))", completionHandler: nil) }
    func tellZoom() { web.evaluateJavaScript("window.__yinstaZoom && __yinstaZoom(\(Double(z)),\(Double(pz)),\(Double(level)))", completionHandler: nil) }
    func windowWillResize(_ sender: NSWindow, to size: NSSize) -> NSSize {
        if layoutMode == "normal" { return sizeFor(nearestLevel((size.width - panelsW * df) / (stageW * df))) }   // 휴대폰: 끌어도 단계 중 가까운 크기로
        return size   // PC(브라우저 창 크기 조절)·펼침: 자유
    }
    func windowDidResize(_ n: Notification) {
        if layoutMode == "pc" {   // 창 크기 → 브라우저 창 크기(CSS px). 배율은 그대로
            let w = ((window.frame.width - panelsW * df) / z - 52).rounded(), h = (window.frame.height / z).rounded()
            let nw = max(PC_MIN_W, w), nh = max(PC_MIN_H, h)
            if nw != pcW || nh != pcH { pcW = nw; pcH = nh; tellPC(); if savedFrame == nil { UserDefaults.standard.set(Double(pcW), forKey: "pcW"); UserDefaults.standard.set(Double(pcH), forKey: "pcH") } }   // 최대화 중 크기는 기억하지 않음
            return
        }
        guard layoutMode == "normal" else { return }
        let lv = nearestLevel((window.frame.width - panelsW * df) / (stageW * df))
        if abs(lv - level) > 0.0005 { level = lv; UserDefaults.standard.set(Double(level), forKey: "level"); z = level * df; tellZoom() }
    }
    func clampToScreen(_ f0: NSRect) -> NSRect {
        var f = f0
        if let v = (window.screen ?? NSScreen.main)?.visibleFrame {
            if f.maxX > v.maxX { f.origin.x = v.maxX - f.width }
            if f.minX < v.minX { f.origin.x = v.minX }
            if f.maxY > v.maxY { f.origin.y = v.maxY - f.height }
            if f.minY < v.minY { f.origin.y = v.minY }
        }
        return f
    }
    func applyLayout(panels: CGFloat, mode: String) {   // 패널 열고 닫기(왼쪽으로 자람) · 펼침 · PC
        let oldPanels = panelsW, wasMode = layoutMode
        panelsW = panels; layoutMode = mode
        if wasMode != mode { savedFrame = nil }   // 모드가 바뀌면 최대화 기억은 버림
        var f = window.frame; let top = f.maxY
        f.origin.x -= (panelsW - oldPanels) * df   // 패널이 왼쪽에 붙으므로 휴대폰 자리는 그대로 (패널 배율 df)
        window.resizeIncrements = NSSize(width: 1, height: 1)
        if mode == "normal" { window.styleMask.remove(.resizable) } else { window.styleMask.insert(.resizable) }   // 휴대폰은 슬라이더로만. PC는 커서로 브라우저 창 크기, 펼침은 자유
        if mode != "expanded" {
            if mode == "pc" { window.contentMinSize = NSSize(width: panelsW * df + (PC_MIN_W + 52) * z, height: PC_MIN_H * z); window.contentMaxSize = NSSize(width: 20000, height: 20000) }
            else { window.contentMinSize = sizeFor(MIN_Z); window.contentMaxSize = sizeFor(MAX_Z) }
            f.size = sizeFor(level); f.origin.y = top - f.height
            if wasMode != mode && mode == "pc" { f.origin.x -= (pcW + 52 - BASE_W) * z / 2 }   // PC로 바뀔 때 가운데가 제자리에
            else if wasMode == "pc" && mode == "normal" { f.origin.x += (pcW + 52 - BASE_W) * z / 2 }
            window.hasShadow = false   // 맥 창 그림자는 떠 있는 버튼·틀 둘레에 회색 선을 만들어 항상 끔 (그림자는 CSS)
        } else {
            window.contentMinSize = NSSize(width: 360, height: 420); window.contentMaxSize = NSSize(width: 20000, height: 20000)
            window.hasShadow = false
            let v = (window.screen ?? NSScreen.main)?.visibleFrame ?? f
            if wasMode == mode { f.size.width += (panelsW - oldPanels) * df }
            else { f.size.width = panelsW * df + BASE_W * z; f.size.height = v.height; f.origin.y = v.minY }
        }
        window.setFrame(clampToScreen(f), display: true, animate: false)
        window.invalidateShadow()
    }
    func setZoom(_ lv: CGFloat) {   // 슬라이더 단계 바꾸기
        level = nearestLevel(lv); UserDefaults.standard.set(Double(level), forKey: "level"); z = level * df
        tellZoom()
        guard layoutMode != "expanded" else { return }
        var f = window.frame; let top = f.maxY
        f.size = sizeFor(level); f.origin.y = top - f.height
        window.setFrame(clampToScreen(f), display: true, animate: false)
        window.invalidateShadow()
    }
    @objc func zoomIn(_ s: Any?) { let i = LEVELS.firstIndex(of: nearestLevel(level)) ?? 2; setZoom(LEVELS[min(LEVELS.count - 1, i + 1)]) }
    @objc func zoomOut(_ s: Any?) { let i = LEVELS.firstIndex(of: nearestLevel(level)) ?? 2; setZoom(LEVELS[max(0, i - 1)]) }
    @objc func zoomReset(_ s: Any?) { setZoom(1.0) }
    @objc func closeWindow(_ s: Any?) { NSApp.terminate(nil) }
    @objc func menuPick(_ s: NSMenuItem) { web.evaluateJavaScript("window.__yinstaMenu && __yinstaMenu('\(s.representedObject as? String ?? "")', \(s.tag))", completionHandler: nil) }
    @objc func showStore(_ s: Any?) { NSWorkspace.shared.activateFileViewerSelecting([store.dir]) }

    // MARK: 웹 → 앱
    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let b = m.body as? [String: Any], let op = b["op"] as? String else { return }
        switch op {
        case "ready":
            tellZoom(); tellPC()   // 게이지·무대 배율, PC 창 크기
            if let js = testJS { web.evaluateJavaScript(js, completionHandler: nil) }
        case "load":
            sendAll()
        case "putImage":   // 사진 파일 저장 후 완료 신호 (화면이 그 주소로 불러옴)
            let kind = b["kind"] as? String ?? ""
            if ["posts", "sources", "stories"].contains(kind), let id = cleanID(b["id"]), let d = dataFromDataURL(b["data"] as? String ?? "") {
                try? d.write(to: store.dir.appendingPathComponent(kind).appendingPathComponent(id + ".jpg"), options: .atomic)
                web.evaluateJavaScript("window.__yinstaSaved && __yinstaSaved('\(kind)/\(id)')", completionHandler: nil)
            }
        case "savePost":
            if let p = b["post"] as? [String: Any], let id = cleanID(p["id"]) {
                if let i = store.meta.firstIndex(where: { $0["id"] as? String == id }) { store.meta[i] = p } else { store.meta.append(p) }
                store.saveMeta()
            }
        case "delPost":
            if let id = cleanID(b["id"]) {
                store.meta.removeAll { $0["id"] as? String == id }; store.saveMeta()
                try? FileManager.default.removeItem(at: store.imageURL(id))
            }
        case "saveSource":
            if let p = b["source"] as? [String: Any], let id = cleanID(p["id"]) {
                if let i = store.sources.firstIndex(where: { $0["id"] as? String == id }) { store.sources[i] = p } else { store.sources.append(p) }
                store.saveSources()
            }
        case "delSource":
            if let id = cleanID(b["id"]) {
                store.sources.removeAll { $0["id"] as? String == id }; store.saveSources()
                try? FileManager.default.removeItem(at: store.sourceURL(id)); try? FileManager.default.removeItem(at: store.sourceURL(id + "_t"))
            }
        case "layout":
            applyLayout(panels: CGFloat((b["panels"] as? NSNumber)?.doubleValue ?? 0), mode: b["mode"] as? String ?? "normal")
        case "saveSettings":
            if let s = b["settings"] as? [String: Any] { store.saveSettings(s) }
        case "copyPNG":
            var ok = false
            if let d = dataFromDataURL(b["data"] as? String ?? ""), let img = NSImage(data: d) {
                let pb = NSPasteboard.general; pb.clearContents(); ok = pb.writeObjects([img]); pb.setData(d, forType: .png)
                ok = ok && pb.data(forType: .png) != nil
            }
            web.evaluateJavaScript("window.__yinstaCopied && __yinstaCopied(\(ok))", completionHandler: nil)
        case "savePNG":
            if let d = dataFromDataURL(b["data"] as? String ?? "") {
                let p = NSSavePanel(); p.allowedContentTypes = [.png]; p.nameFieldStringValue = "yinsta 화면.png"
                p.begin { r in if r == .OK, let u = p.url { try? d.write(to: u) } }
            }
        case "saveStory":
            if let p = b["story"] as? [String: Any], let id = cleanID(p["id"]) {
                if let i = store.stories.firstIndex(where: { $0["id"] as? String == id }) { store.stories[i] = p } else { store.stories.append(p) }
                store.saveStories()
            }
        case "delStory":
            if let id = cleanID(b["id"]) { store.stories.removeAll { $0["id"] as? String == id }; store.saveStories(); try? FileManager.default.removeItem(at: store.storyURL(id)) }
        case "menu":   // 우클릭 맥 메뉴
            let id = (b["id"] as? String ?? "").filter { $0.isLetter || $0.isNumber }
            let menu = NSMenu()
            for (i, t) in (b["items"] as? [String] ?? []).enumerated() { let it = NSMenuItem(title: t, action: #selector(menuPick(_:)), keyEquivalent: ""); it.tag = i; it.target = self; it.representedObject = id; menu.addItem(it) }
            menu.popUp(positioning: nil, at: window.mouseLocationOutsideOfEventStream, in: window.contentView)
        case "confirm":   // 맥 경고창 (지우기·비우기 확인)
            let a = NSAlert(); a.alertStyle = .warning
            a.messageText = b["msg"] as? String ?? "진행할까요?"; a.informativeText = b["info"] as? String ?? ""
            let okBtn = a.addButton(withTitle: b["label"] as? String ?? "확인"); if #available(macOS 11.0, *) { okBtn.hasDestructiveAction = true }
            let cancel = a.addButton(withTitle: "취소"); cancel.keyEquivalent = "\u{1b}"
            let ok = a.runModal() == .alertFirstButtonReturn
            let id = (b["id"] as? String ?? "").filter { $0.isLetter || $0.isNumber }
            web.evaluateJavaScript("window.__yinstaConfirm && __yinstaConfirm('\(id)', \(ok))", completionHandler: nil)
        case "drag":
            if let e = NSApp.currentEvent { window.performDrag(with: e) }
        case "zoom":
            if let v = (b["z"] as? NSNumber)?.doubleValue { setZoom(CGFloat(v)) }
            else { switch b["dir"] as? String { case "in": zoomIn(nil); case "out": zoomOut(nil); default: setZoom(1.0) } }
        case "log":
            print(b["msg"] as? String ?? ""); fflush(stdout)
        case "resize":
            startResize(edge: b["edge"] as? String ?? "br")
        case "frame":   // 시험 전용: 창 위치(화면 왼쪽 위 기준, screencapture용)
            if testJS != nil, let sh = NSScreen.screens.first?.frame.height { let f = window.frame; print("FRAME \(Int(f.minX)),\(Int(sh - f.maxY)),\(Int(f.width)),\(Int(f.height))"); fflush(stdout) }
        case "zoomWindow":
            toggleMax()
        case "snapshot":   // 시험 전용: 창 내용을 PNG로 저장 (시험 저장소일 때만)
            if testJS != nil, let path = b["path"] as? String {
                web.takeSnapshot(with: nil) { img, _ in
                    if let img = img, let t = img.tiffRepresentation, let r = NSBitmapImageRep(data: t), let d = r.representation(using: .png, properties: [:]) { try? d.write(to: URL(fileURLWithPath: path)) }
                    self.web.evaluateJavaScript("window.__yinstaSnapped && __yinstaSnapped()", completionHandler: nil)
                }
            }
        case "quit":
            NSApp.terminate(nil)
        default: break
        }
    }
    func sendAll() {
        let sorted = store.meta.sorted { (($0["order"] as? NSNumber)?.doubleValue ?? 0) < (($1["order"] as? NSNumber)?.doubleValue ?? 0) }
        for p in sorted { guard let id = cleanID(p["id"]), FileManager.default.fileExists(atPath: store.imageURL(id).path), let js = jsLiteral(p) else { continue }; web.evaluateJavaScript("__yinstaPost(\(js))", completionHandler: nil) }
        let ssorted = store.sources.sorted { (($0["order"] as? NSNumber)?.doubleValue ?? 0) < (($1["order"] as? NSNumber)?.doubleValue ?? 0) }
        for p in ssorted { guard let id = cleanID(p["id"]), FileManager.default.fileExists(atPath: store.sourceURL(id).path), let js = jsLiteral(p) else { continue }; web.evaluateJavaScript("__yinstaSource(\(js))", completionHandler: nil) }
        let tsorted = store.stories.sorted { (($0["order"] as? NSNumber)?.doubleValue ?? 0) < (($1["order"] as? NSNumber)?.doubleValue ?? 0) }
        for p in tsorted { guard let id = cleanID(p["id"]), FileManager.default.fileExists(atPath: store.storyURL(id).path), let js = jsLiteral(p) else { continue }; web.evaluateJavaScript("__yinstaStory(\(js))", completionHandler: nil) }
        let s = store.settings().flatMap { jsLiteral($0) } ?? "null"
        web.evaluateJavaScript("__yinstaLoaded(\(s))", completionHandler: nil)
    }

    // MARK: 웹 위임
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(web)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.window.invalidateShadow() }
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = parameters.allowsMultipleSelection; p.canChooseDirectories = false; p.canChooseFiles = true
        p.allowedContentTypes = [.image]; p.message = "피드에 올릴 사진을 고르세요 (여러 장 가능)"; p.prompt = "넣기"
        p.begin { r in completionHandler(r == .OK ? p.urls : nil) }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
