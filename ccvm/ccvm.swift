// ccvm: 맥 내장 가상화(Virtualization.framework)로 '새 맥'을 띄우는 작은 프로그램 (다른 앱 설치 없이)
//   ccvm download   애플에서 최신 macOS 복원 이미지(ipsw) 받기 → ~/Desktop/cc/작업중/vm/RestoreImage.ipsw
//   ccvm install    가상 맥 만들고 macOS 설치 (20~30분)
//   ccvm run        가상 맥 켜기 (창). ~/Desktop/ylab 폴더가 가상 맥 Finder의 '공유' 위치에 읽기 전용으로 보임
//   ccvm snapshot   (꺼진 상태에서) 지금 상태를 되돌림 지점으로 저장
//   ccvm reset      되돌림 지점으로 되돌리기 — 깨끗한 맥으로 다시 시험. 켜진 채로는 안 됨 (vm/stop 파일을 만들면 정상 종료 요청)
import Cocoa
import Virtualization

let home = NSHomeDirectory(), vmDir = home + "/Desktop/cc/작업중/vm"
let ipswPath = vmDir + "/RestoreImage.ipsw", diskPath = vmDir + "/Disk.img", auxPath = vmDir + "/AuxiliaryStorage", hwPath = vmDir + "/HardwareModel", idPath = vmDir + "/MachineIdentifier", cleanPath = vmDir + "/Disk.clean.img"
let shareDir = vmDir + "/share"   // ~/Desktop/ylab 의 복사본에 '인터넷에서 받은 파일' 표시(quarantine)를 붙여 공유 → 가상 맥에서 진짜 다운로드처럼 경고창이 뜸
func prepareShare() {
    let src = home + "/Desktop/ylab"; guard fm.fileExists(atPath: src) else { return }
    try? fm.removeItem(atPath: shareDir); try? fm.createDirectory(atPath: shareDir, withIntermediateDirectories: true)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); p.arguments = [src, shareDir + "/y"]; try? p.run(); p.waitUntilExit()
    let q = Process(); q.executableURL = URL(fileURLWithPath: "/usr/bin/xattr"); q.arguments = ["-w", "-r", "com.apple.quarantine", "0083;00000000;Safari;", shareDir + "/y"]; try? q.run(); q.waitUntilExit()
    log("공유 폴더 준비: \(shareDir)/y (다운로드 표시 붙임)")
}
func log(_ s: String) { print(s); fflush(stdout) }
func fail(_ s: String) -> Never { log("오류: " + s); exit(1) }
func isRunning() -> Bool {   // 켜져 있는 ccvm run 이 있는지 (pid 파일)
    guard let t = try? String(contentsOfFile: vmDir + "/run.pid", encoding: .utf8), let pid = Int32(t.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return kill(pid, 0) == 0 }
let fm = FileManager.default
try? fm.createDirectory(atPath: vmDir, withIntermediateDirectories: true)

func makeConfig() throws -> VZVirtualMachineConfiguration {
    let c = VZVirtualMachineConfiguration()
    let platform = VZMacPlatformConfiguration()
    guard let hwData = fm.contents(atPath: hwPath), let hw = VZMacHardwareModel(dataRepresentation: hwData), hw.isSupported else { throw NSError(domain: "ccvm", code: 1, userInfo: [NSLocalizedDescriptionKey: "하드웨어 모델 파일이 없거나 지원 안 됨 (install 먼저)"]) }
    platform.hardwareModel = hw
    platform.auxiliaryStorage = VZMacAuxiliaryStorage(url: URL(fileURLWithPath: auxPath))
    guard let idData = fm.contents(atPath: idPath), let mid = VZMacMachineIdentifier(dataRepresentation: idData) else { throw NSError(domain: "ccvm", code: 2, userInfo: [NSLocalizedDescriptionKey: "머신 ID 파일 없음"]) }
    platform.machineIdentifier = mid
    c.platform = platform
    c.bootLoader = VZMacOSBootLoader()
    c.cpuCount = max(4, min(8, ProcessInfo.processInfo.processorCount / 2))
    c.memorySize = max(VZVirtualMachineConfiguration.minimumAllowedMemorySize, 8 * 1024 * 1024 * 1024)
    let gfx = VZMacGraphicsDeviceConfiguration(); gfx.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: 2560, heightInPixels: 1600, pixelsPerInch: 144)]; c.graphicsDevices = [gfx]
    c.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: diskPath), readOnly: false))]
    let net = VZVirtioNetworkDeviceConfiguration(); net.attachment = VZNATNetworkDeviceAttachment(); c.networkDevices = [net]
    c.pointingDevices = [VZMacTrackpadConfiguration()]; c.keyboards = [VZMacKeyboardConfiguration()]
    c.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]; c.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
    let snd = VZVirtioSoundDeviceConfiguration(); let out = VZVirtioSoundDeviceOutputStreamConfiguration(); out.sink = VZHostAudioOutputStreamSink(); snd.streams = [out]; c.audioDevices = [snd]
    if fm.fileExists(atPath: shareDir) {   // ~/Desktop/ylab → 가상 맥 Finder 사이드바 '공유' (읽기 전용, 가상 맥이 망가뜨릴 수 없음)
        let fs = VZVirtioFileSystemDeviceConfiguration(tag: VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag)
        fs.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: URL(fileURLWithPath: shareDir), readOnly: true)); c.directorySharingDevices = [fs] }
    try c.validate()
    return c
}

final class Runner: NSObject, VZVirtualMachineDelegate, NSWindowDelegate {
    var vm: VZVirtualMachine!, win: NSWindow!
    func start() {
        let cfg: VZVirtualMachineConfiguration; do { cfg = try makeConfig() } catch { fail("\(error.localizedDescription)") }
        vm = VZVirtualMachine(configuration: cfg); vm.delegate = self
        let view = VZVirtualMachineView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800)); view.virtualMachine = vm; view.capturesSystemKeys = true; view.autoresizingMask = [.width, .height]
        win = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = "새 맥 (가상) — 닫으면 꺼짐"; win.contentView = view; win.delegate = self; win.center(); win.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        vm.start { r in if case .failure(let e) = r { fail("켜지 못함: \(e.localizedDescription)") } else { log("가상 맥 켜짐") } }
    }
    func guestDidStop(_ vm: VZVirtualMachine) { log("가상 맥 꺼짐"); exit(0) }
    func virtualMachine(_ vm: VZVirtualMachine, didStopWithError e: Error) { fail("멈춤: \(e.localizedDescription)") }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if vm.canRequestStop { try? vm.requestStop(); log("가상 맥에 종료 요청 (몇 초 뒤 꺼짐)"); DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.vm.stop { _ in exit(0) } }; return false }
        vm.stop { _ in exit(0) }; return false
    }
}

let app = NSApplication.shared
let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "download":
    log("최신 macOS 복원 이미지 찾는 중…")
    VZMacOSRestoreImage.fetchLatestSupported { r in
        switch r {
        case .failure(let e): fail("이미지 정보를 못 받음: \(e.localizedDescription)")
        case .success(let img):
            log("받을 이미지: macOS \(img.operatingSystemVersion.majorVersion).\(img.operatingSystemVersion.minorVersion).\(img.operatingSystemVersion.patchVersion) (\(img.buildVersion))")
            final class D: NSObject, URLSessionDownloadDelegate {
                var last = -1
                func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) {
                    let p = t > 0 ? Int(w * 100 / t) : 0; if p / 2 != last / 2 { last = p; log("다운로드 \(p)% (\(w / 1024 / 1024)MB / \(t / 1024 / 1024)MB)") } }
                func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
                    try? fm.removeItem(atPath: ipswPath); do { try fm.moveItem(at: loc, to: URL(fileURLWithPath: ipswPath)); log("다운로드 끝: \(ipswPath)"); exit(0) } catch { fail("옮기지 못함: \(error)") } }
                func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) { if let e { fail("다운로드 실패: \(e.localizedDescription)") } }
            }
            let d = D(); let session = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
            session.downloadTask(with: img.url).resume()
        }
    }
    app.run()
case "install":
    guard fm.fileExists(atPath: ipswPath) else { fail("복원 이미지가 없어요 (download 먼저)") }
    VZMacOSRestoreImage.load(from: URL(fileURLWithPath: ipswPath)) { r in
        guard case .success(let img) = r, let req = img.mostFeaturefulSupportedConfiguration else { fail("이미지를 읽지 못함") }
        guard req.hardwareModel.isSupported else { fail("이 맥에서 지원하지 않는 이미지") }
        do {
            try req.hardwareModel.dataRepresentation.write(to: URL(fileURLWithPath: hwPath))
            try VZMacMachineIdentifier().dataRepresentation.write(to: URL(fileURLWithPath: idPath))
            try? fm.removeItem(atPath: auxPath)
            _ = try VZMacAuxiliaryStorage(creatingStorageAt: URL(fileURLWithPath: auxPath), hardwareModel: req.hardwareModel, options: [])
            try? fm.removeItem(atPath: diskPath); fm.createFile(atPath: diskPath, contents: nil)
            let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: diskPath)); try fh.truncate(atOffset: 80 * 1024 * 1024 * 1024); try fh.close()   // 80GB (실제 쓴 만큼만 차지)
        } catch { fail("가상 맥 파일 준비 실패: \(error)") }
        DispatchQueue.main.async {
            let cfg: VZVirtualMachineConfiguration; do { cfg = try makeConfig() } catch { fail("\(error.localizedDescription)") }
            let vm = VZVirtualMachine(configuration: cfg)
            let inst = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: URL(fileURLWithPath: ipswPath))
            log("macOS 설치 시작 (20~30분)…")
            var last = -1
            let obs = inst.progress.observe(\.fractionCompleted) { p, _ in let k = Int(p.fractionCompleted * 100); if k / 5 != last / 5 { last = k; log("설치 \(k)%") } }
            inst.install { r in
                _ = obs
                switch r { case .failure(let e): fail("설치 실패: \(e.localizedDescription)")
                case .success: log("설치 끝. 깨끗한 디스크 백업본 만드는 중…"); try? fm.removeItem(atPath: cleanPath); try? fm.copyItem(atPath: diskPath, toPath: cleanPath); log("완료: ccvm run 으로 켜세요"); exit(0) }
            }
        }
    }
    app.run()
case "run":
    try? String(getpid()).write(toFile: vmDir + "/run.pid", atomically: true, encoding: .utf8)
    prepareShare()
    let r = Runner(); r.start()
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in if fm.fileExists(atPath: vmDir + "/stop") { try? fm.removeItem(atPath: vmDir + "/stop"); _ = r.windowShouldClose(r.win) } }   // vm/stop 파일 → 정상 종료 요청
    app.run()
case "snapshot":   // 지금 상태(꺼진 상태에서)를 되돌림 지점으로 저장 (디스크 + 보조 저장소)
    guard !isRunning() else { fail("가상 맥이 켜져 있어요. 창을 닫아 끈 뒤 다시 해 주세요") }
    do { try? fm.removeItem(atPath: cleanPath); try fm.copyItem(atPath: diskPath, toPath: cleanPath); try? fm.removeItem(atPath: auxPath + ".clean"); try fm.copyItem(atPath: auxPath, toPath: auxPath + ".clean"); log("되돌림 지점 저장: 지금 상태") } catch { fail("\(error)") }
case "reset":
    guard fm.fileExists(atPath: cleanPath) else { fail("되돌림 지점이 없어요") }
    guard !isRunning() else { fail("가상 맥이 켜져 있어요. 창을 닫아 끈 뒤 다시 해 주세요") }
    try? fm.removeItem(atPath: diskPath); do { try fm.copyItem(atPath: cleanPath, toPath: diskPath); if fm.fileExists(atPath: auxPath + ".clean") { try? fm.removeItem(atPath: auxPath); try fm.copyItem(atPath: auxPath + ".clean", toPath: auxPath) }; log("되돌림 지점 상태로 되돌렸어요") } catch { fail("\(error)") }
default: log("사용: ccvm download | install | run | reset")
}
