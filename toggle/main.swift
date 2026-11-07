// 앱 토글: 누를 때마다 대상 앱을  맨 앞에 있으면 → 숨김 / 숨겨졌거나 뒤에 있으면 → 앞으로 / 꺼져 있으면 → 켬
// 대상은 이 앱 Info.plist 의 CCToggleBundleID (앱마다 껍데기 .app을 따로 만들어 씀, build.sh)
// Stream Deck '앱 열기'로 이 껍데기 앱을 지정. 화면 맨 앞 앱을 빼앗지 않도록 LSBackgroundOnly
// --dry : 실제로 하지 않고 무엇을 할지만 출력 (시험용)
import Cocoa
let dry = CommandLine.arguments.contains("--dry")
guard let bid = Bundle.main.object(forInfoDictionaryKey: "CCToggleBundleID") as? String
        ?? CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { exit(1) }
let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first
let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
// 화면에 그 앱 창이 실제로 보이는지 (창을 닫아 둔 카톡처럼 '켜져 있지만 안 보임'도 구분)
func hasVisibleWindow(_ pid: pid_t) -> Bool {
    let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return l.contains { ($0["kCGWindowOwnerPID"] as? Int).map { pid_t($0) } == pid && ($0["kCGWindowLayer"] as? Int ?? 1) == 0 }
}
if let app = running, front == bid, !app.isHidden, hasVisibleWindow(app.processIdentifier) {
    if dry { print("숨김:", bid) } else { app.hide() }                       // 맨 앞에 보이고 있으면 → 숨김
} else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
    // 꺼짐·숨김·뒤에 있음·창 닫힘 → Dock 아이콘 누른 것처럼 열기 (닫힌 창도 다시 나옴)
    if dry { print("앞으로/켜기:", bid, "(지금 맨 앞:", front ?? "-", ")") } else {
        running?.unhide()
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
        let sem = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
    }
}
