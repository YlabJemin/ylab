// yap (2026-11-05 앱 나누기, 예전 ydot의 스크립트 메뉴): 메뉴 막대 'yap.' 아이콘에서 스크립트 실행. Shift Convert는 ydot 앱으로 따로
//   위: ~/Library/Scripts/cc 스크립트 (인스타 저장 등 cc 전용) / 가운데: cc 스크립트/Photoshop (회색 제목 Photoshop) / 아래: Capture One Scripts 폴더 최상위
import Cocoa
import Carbon

let scriptsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Scripts/Capture One Scripts")
let ccScriptsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Scripts/yap_scripts")   // 영어 이름만 (예전 "ydot_scripts"·"cc 스크립트"는 syncBundleFiles가 옮김, 2026-11-05)
let psScriptsDir = ccScriptsDir.appendingPathComponent("Photoshop")

// 전역 단축키 (⌘⇧6 사진 저장) → cc 스크립트 폴더의 스크립트
// (⌘⇧A 에어드롭 보내기는 포토샵 카메라 로우 필터 ⇧⌘A를 가로채서 뺌, 2026-10-26. 에어드롭은 메뉴에서 실행)
let hotKeys: [(url: URL, code: UInt32, key: String)] = [
    (ccScriptsDir.appendingPathComponent("Save Instagram Photos.applescript"), UInt32(kVK_ANSI_6), "6"),
]
let hotKeyMods = UInt32(cmdKey | shiftKey)

func scripts(in dir: URL) -> [URL] {
    let files = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    return files
        .filter { scriptExts.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}
let scriptExts: Set<String> = ["scpt", "scptd", "applescript"]
func ordered(_ list: [URL], first: [String]) -> [URL] {   // 정해진 이름은 그 순서대로 앞에, 나머지는 이름순 뒤에
    let name = { (u: URL) in u.deletingPathExtension().lastPathComponent }
    return first.compactMap { f in list.first { name($0) == f } } + list.filter { !first.contains(name($0)) }
}

// 메뉴바 로고 'y.' (템플릿 이미지라 라이트/다크 모드에 맞춰 색이 자동으로 바뀜)
func yLogoImage() -> NSImage {   // 메뉴 막대 'yap.' 검정 알약 (글자 부분은 비움 → 라이트·다크에 맞춰 색이 바뀌는 템플릿) (2026-11-05 사용자 선택 B)
    let img = NSImage(size: NSSize(width: 30, height: 18), flipped: false) { r in
        NSColor.black.setFill(); NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 28, height: 12), xRadius: 3.2, yRadius: 3.2).fill()
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .heavy), .foregroundColor: NSColor.black, .kern: -0.2]
        let t = "yap." as NSString, sz = t.size(withAttributes: a)
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        t.draw(at: NSPoint(x: (30 - sz.width) / 2, y: (18 - sz.height) / 2 + 1), withAttributes: a)
        return true
    }
    img.isTemplate = true; img.accessibilityDescription = "yap"
    return img
}
// (예전) 단색 선 그림 고양이 얼굴
func catFaceImage() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.set()

        // 머리 + 귀를 하나의 윤곽선으로
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 3.2, y: 9.5))
        head.line(to: NSPoint(x: 3.6, y: 16))
        head.line(to: NSPoint(x: 7.3, y: 13.2))
        head.curve(to: NSPoint(x: 10.7, y: 13.2),
                   controlPoint1: NSPoint(x: 8.4, y: 13.6), controlPoint2: NSPoint(x: 9.6, y: 13.6))
        head.line(to: NSPoint(x: 14.4, y: 16))
        head.line(to: NSPoint(x: 14.8, y: 9.5))
        head.curve(to: NSPoint(x: 9, y: 2.3),
                   controlPoint1: NSPoint(x: 15.6, y: 5), controlPoint2: NSPoint(x: 12.8, y: 2.3))
        head.curve(to: NSPoint(x: 3.2, y: 9.5),
                   controlPoint1: NSPoint(x: 5.2, y: 2.3), controlPoint2: NSPoint(x: 2.4, y: 5))
        head.close()
        head.lineWidth = 1.3
        head.lineJoinStyle = .round
        head.stroke()

        // 눈
        NSBezierPath(ovalIn: NSRect(x: 5.4, y: 7.4, width: 1.9, height: 1.9)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.7, y: 7.4, width: 1.9, height: 1.9)).fill()

        // 코
        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: 8.1, y: 6.1))
        nose.line(to: NSPoint(x: 9.9, y: 6.1))
        nose.line(to: NSPoint(x: 9, y: 5.1))
        nose.close()
        nose.fill()

        // 수염
        let whiskers = NSBezierPath()
        for (y1, y2) in [(6.2, 5.6), (4.2, 4.8)] {
            whiskers.move(to: NSPoint(x: 0.6, y: y1)); whiskers.line(to: NSPoint(x: 5, y: y2))
            whiskers.move(to: NSPoint(x: 17.4, y: y1)); whiskers.line(to: NSPoint(x: 13, y: y2))
        }
        whiskers.lineWidth = 0.8
        whiskers.lineCapStyle = .round
        whiskers.stroke()
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "cc 스크립트"
    return img
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!

    // 앱 안에 담긴 도우미(Helpers/) → ~/Library/Application Support/cc/, 스크립트(Resources/scripts/) → ~/Library/Scripts/… 로 복사
    // 빌드 시각(CFBundleVersion)이 지난번과 다를 때만 (다른 맥에 처음 깔거나 업데이트했을 때). 같은 이름만 덮어쓰고 사용자가 넣은 다른 스크립트는 그대로
    func syncBundleFiles() {
        let fm = FileManager.default, ver = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let cc = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/cc"), stamp = cc.appendingPathComponent("yap-version")
        if (try? String(contentsOf: stamp, encoding: .utf8)) == ver { return }
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers"), scripts = Bundle.main.resourceURL!.appendingPathComponent("scripts")
        try? fm.createDirectory(at: cc, withIntermediateDirectories: true)
        for dir in [helpers, Bundle.main.resourceURL!.appendingPathComponent("helpers")] {   // 실행 파일(Helpers) + 스크립트(Resources/helpers)
            for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !n.hasSuffix(".app") {
                let dst = cc.appendingPathComponent(n); try? fm.removeItem(at: dst); try? fm.copyItem(at: dir.appendingPathComponent(n), to: dst) } }
        for n in ["ydot 가이드.jsx", "ydot 인화.jsx", "ydot_guide.jsx", "ydot_print.jsx"] { try? fm.removeItem(at: cc.appendingPathComponent(n)) }   // 포토샵 스크립트는 이제 ydot 몫 → 예전 사본 정리 (2026-11-05)
        // 예전에 사용자 Presets/Scripts에 깔던 포토샵 스크립트 정리 (포토샵 2026은 그 폴더를 메뉴에 안 띄움 → 설치 앱이 앱 폴더 Presets/Scripts에 관리자 권한으로 넣음, 2026-11-04)
        let adobe = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Adobe")
        for v in (try? fm.contentsOfDirectory(atPath: adobe.path)) ?? [] where v.hasPrefix("Adobe Photoshop") {
            for n in ["ydot 가이드.jsx", "ydot 인화.jsx", "ydot 원래대로.jsx"] { try? fm.removeItem(at: adobe.appendingPathComponent(v + "/Presets/Scripts/" + n)) } }
        try? fm.removeItem(at: cc.appendingPathComponent("ydot 원래대로.jsx"))
        for old in ["ydot_scripts", "cc 스크립트"] {   // 예전 폴더 → yap_scripts로 통째로 옮김 (사용자가 넣은 스크립트도 같이)
            let oldDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Scripts/" + old)
            if fm.fileExists(atPath: oldDir.path), !fm.fileExists(atPath: ccScriptsDir.path) { try? fm.moveItem(at: oldDir, to: ccScriptsDir) } }
        for (sub, dstSub, ext) in [("ccscripts", "yap_scripts", "applescript"), ("ccscripts/Photoshop", "yap_scripts/Photoshop", "applescript"), ("Capture One Scripts", "Capture One Scripts", "scpt")] {
            let from = scripts.appendingPathComponent(sub), to = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Scripts/" + dstSub)
            try? fm.createDirectory(at: to, withIntermediateDirectories: true)
            for n in (try? fm.contentsOfDirectory(atPath: from.path)) ?? [] where n.hasSuffix("." + ext) {
                let dst = to.appendingPathComponent(n); try? fm.removeItem(at: dst); try? fm.copyItem(at: from.appendingPathComponent(n), to: dst) }
        }
        try? ver.write(to: stamp, atomically: true, encoding: .utf8)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        syncBundleFiles()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = yLogoImage()
            button.toolTip = "yap"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        registerHotKey()
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let i = Int(hk.id) - 1
            if i >= 0 && i < hotKeys.count {
                DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.run(hotKeys[i].url, activate: false) }
            }
            return noErr
        }, 1, &spec, nil, nil)
        for (i, h) in hotKeys.enumerated() {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(h.code, hotKeyMods, EventHotKeyID(signature: OSType(0x63636B31), id: UInt32(i + 1)),
                                GetApplicationEventTarget(), 0, &ref)
        }
    }

    // 메뉴를 열 때마다 폴더를 다시 읽어서, 스크립트를 추가/제거하면 바로 반영됨
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let cc = scripts(in: ccScriptsDir), ps = scripts(in: psScriptsDir), c1 = ordered(scripts(in: scriptsDir).filter { $0.deletingPathExtension().lastPathComponent != "Pick" }, first: ["New Session", "Delete Session", "Export"])   // Pick 항목은 Pick 앱 것 → yap 메뉴엔 안 보임 (2026-11-05)   // 캡쳐원 묶음 순서 (사용자 지정 2026-11-03)
        if cc.isEmpty && ps.isEmpty && c1.isEmpty {
            let empty = NSMenuItem(title: "No scripts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for url in cc { menu.addItem(scriptItem(url)) }
        // 회색 제목 묶음(클릭 안 됨): Photoshop → Capture One
        for (title, list) in [("Photoshop", ps), ("Capture One", c1)] where !list.isEmpty {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            if #available(macOS 14, *) { menu.addItem(NSMenuItem.sectionHeader(title: title)) }
            else { let h = NSMenuItem(title: title, action: nil, keyEquivalent: ""); h.isEnabled = false; menu.addItem(h) }   // macOS 13: 회색 비활성 항목
            for url in list { menu.addItem(scriptItem(url)) }
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Scripts Folder", action: #selector(openFolder), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(NSMenuItem(title: "Quit yap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    func scriptItem(_ url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: url.deletingPathExtension().lastPathComponent,
                              action: #selector(runScript(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        if let h = hotKeys.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {   // 단축키 표시 (⌘⇧숫자)
            item.keyEquivalent = h.key; item.keyEquivalentModifierMask = [.command, .shift]
        }
        return item
    }

    @objc func runScript(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        // 메뉴가 닫힌 뒤 실행해야 대화상자가 앞에 뜸
        DispatchQueue.main.async { self.run(url, activate: true) }
    }

    // activate: 메뉴에서 실행하면 앱을 앞으로(대화상자용). 단축키로 실행하면 지금 앱(크롬)을 그대로 둠
    func run(_ url: URL, activate: Bool) {
        if activate { NSApp.activate(ignoringOtherApps: true) }
        var loadError: NSDictionary?
        guard let script = NSAppleScript(contentsOf: url, error: &loadError) else {
            showError(url, loadError)
            return
        }
        var runError: NSDictionary?
        let result = script.executeAndReturnError(&runError)
        // 스크립트가 "toast:문구"를 돌려주면 화면 위쪽에 잠깐 띄웠다가 사라짐, "error:문구"면 오류 창
        if runError == nil, let text = result.stringValue {
            if text.hasPrefix("toast:") { showToast(String(text.dropFirst(6))) }
            if text.hasPrefix("error:") { showError(url, [NSAppleScript.errorMessage: String(text.dropFirst(6))]) }
        }
        // -128 = 사용자가 취소함 → 오류 아님
        if let err = runError, (err[NSAppleScript.errorNumber] as? Int) != -128 {
            showError(url, err)
        }
    }

    var toast: NSPanel?
    func showToast(_ text: String) {
        toast?.close()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.sizeToFit()
        let w = label.frame.width + 44, h: CGFloat = 44
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .statusBar
        panel.ignoresMouseEvents = true; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.material = .hudWindow; bg.state = .active; bg.appearance = NSAppearance(named: .darkAqua)
        bg.wantsLayer = true; bg.layer?.cornerRadius = h / 2; bg.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: 22, y: (h - label.frame.height) / 2)
        bg.addSubview(label)
        panel.contentView = bg
        if let sc = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: sc.midX - w / 2, y: sc.maxY - h - 24))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        toast = panel
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak panel] in
            guard let panel = panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.close() })
        }
    }

    func showError(_ url: URL, _ err: NSDictionary?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "스크립트 실행 오류: \(url.deletingPathExtension().lastPathComponent)"
        alert.informativeText = (err?[NSAppleScript.errorMessage] as? String) ?? "알 수 없는 오류"
        alert.runModal()
    }

    @objc func openFolder() {
        NSWorkspace.shared.open(scriptsDir)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
