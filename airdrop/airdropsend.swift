// 에어드롭 보내기: 받은 파일들을 맥 기본 에어드롭 창으로 보냄 (공유 버튼 대신)
// 공유 버튼은 선택 창이 닫히며 파일 접근 권한이 끊겨 여러 장이면 "파일 없음"으로 실패 → 이 프로그램이 직접 보내고 끝날 때까지 기다림
// 사용: airdropsend 파일1 파일2 …   (고양이 메뉴 "에어드롭 보내기" / ⌘⇧A 이 Finder 선택 파일로 실행)
// 끝나면 화면 위쪽에 "에어드롭 완료 · N개" 잠깐 표시. 취소하면 조용히 끝
// 컴파일: build.sh
import Cocoa

final class D: NSObject, NSApplicationDelegate, NSSharingServiceDelegate {
    let urls: [URL]
    var toast: NSPanel?
    init(_ u: [URL]) { urls = u }
    func applicationDidFinishLaunching(_ n: Notification) {
        guard let s = NSSharingService(named: .sendViaAirDrop) else { show("에어드롭을 쓸 수 없어요", quit: true); return }
        guard s.canPerform(withItems: urls) else { show("에어드롭으로 보낼 수 없는 파일이에요", quit: true); return }
        s.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        s.perform(withItems: urls)
    }
    func sharingService(_ s: NSSharingService, didShareItems items: [Any]) {
        NSApp.terminate(nil)   // 완료 알림 없음 (사용자 요청 2026-11-03). 실패만 알림
    }
    func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain && e.code == NSUserCancelledError { NSApp.terminate(nil); return }
        show("에어드롭 실패: \(e.localizedDescription)", quit: true, wait: 4)
    }
    // 고양이 앱과 같은 모양의 알림 (화면 위쪽, 잠깐 뜨고 사라짐)
    func show(_ text: String, quit: Bool, wait: Double = 1.5) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold); label.textColor = .white; label.sizeToFit()
        let w = label.frame.width + 44, h: CGFloat = 44
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.level = .statusBar; p.ignoresMouseEvents = true; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.material = .hudWindow; bg.state = .active; bg.appearance = NSAppearance(named: .darkAqua)
        bg.wantsLayer = true; bg.layer?.cornerRadius = h / 2; bg.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: 22, y: (h - label.frame.height) / 2); bg.addSubview(label); p.contentView = bg
        if let sc = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: sc.midX - w / 2, y: sc.maxY - h - 24)) }
        p.orderFrontRegardless(); toast = p
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { if quit { NSApp.terminate(nil) } else { p.close() } }
    }
}

let urls = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let d = D(urls)
app.delegate = d
if urls.isEmpty { DispatchQueue.main.async { d.show("Finder에서 보낼 파일을 골라 주세요", quit: true) } }
app.run()
