// 캡쳐원 "셀렉 내보내기" 스크립트 전용 창 (세션 스크립트용 sessionui와 별개)
// 사용:
//   exportui <사진 수>                  → 내보내기 설정 창 → [내보내기] 누르면 세 줄 출력: 경로 / 새 폴더 이름(없으면 빈 줄) / 종류(raw,orig,edit 중 고른 것) / 카톡용이면 kakao
//                                        취소·✕ 누르면 아무것도 출력 안 하고 종료코드 1
//   exportui msg "문구"                 → 알림 (확인)
//   exportui done "문구" <폴더 경로>     → 완료 알림 ([폴더 열기] [확인])
//   exportui snapshot <출력폴더> <배경사진> → 화면 모습을 PNG로 저장 (확인용)
// 기본 위치: UserDefaults "cc.exportui.path" (처음엔 데스크톱). "이 위치를 기본값으로 저장" 체크 후 내보내면 바뀜
// 파일은 건드리지 않음 (폴더 만들기·내보내기는 AppleScript가 처리)
// 컴파일: swiftc -O exportui.swift -o ~/Library/Application\ Support/cc/exportui
import SwiftUI
import AppKit
import CoreImage

// MARK: - 색 (캡쳐원 다크 패널 + 주황)
enum P {
    static let bg = Color(red: 0.165, green: 0.165, blue: 0.17)
    static let bar = Color(red: 0.2, green: 0.2, blue: 0.205)
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.135)
    static let text = Color(white: 0.86)
    static let sub = Color(white: 0.55)
    static let accent = Color(red: 0.96, green: 0.55, blue: 0.14)
    static let onAccent = Color(red: 0.1, green: 0.07, blue: 0.03)
    static let red = Color(red: 1.0, green: 0.37, blue: 0.34)
    static let warn = Color(red: 1.0, green: 0.62, blue: 0.3)
}

let defaultsKey = "cc.exportui.path"
let kindsKey = "cc.exportui.kinds"   // 마지막에 고른 종류 (raw,orig,edit)
let kakaoKey = "cc.exportui.kakao"   // 마지막 카톡용 체크
let allKinds: [(id: String, title: String)] = [("raw", "RAW"), ("orig", "원본"), ("edit", "보정본")]
let home = FileManager.default.homeDirectoryForCurrentUser.path

// 경로를 보기 좋게: ~/Desktop/납품 → "데스크톱 › 납품"
func pretty(_ path: String) -> String {
    var p = path
    let named: [(String, String)] = [(home + "/Desktop", "데스크톱"), (home + "/Documents", "문서"),
                                     (home + "/Downloads", "다운로드"), (home + "/Pictures", "사진"), (home, "홈")]
    var head = ""
    for (full, name) in named where p == full || p.hasPrefix(full + "/") {
        head = name; p = String(p.dropFirst(full.count)); break
    }
    if head.isEmpty && p.hasPrefix("/Volumes/") { p = String(p.dropFirst("/Volumes/".count)) }
    let parts = p.split(separator: "/").map(String.init)
    return ([head].filter { !$0.isEmpty } + parts).joined(separator: " › ")
}

// MARK: - 상태
enum Stage { case setup, message(String), done(String, String) }

final class Model: ObservableObject {
    let count: Int
    let defaultPath: String
    @Published var stage: Stage
    @Published var path: String
    @Published var saveDefault = false
    @Published var makeFolder = false
    @Published var folderName: String
    @Published var kinds: Set<String>
    @Published var kakao = UserDefaults.standard.bool(forKey: kakaoKey)
    var hasJpg: Bool { kinds.contains("orig") || kinds.contains("edit") }
    var finish: ((Bool) -> Void)?
    var onResize: (() -> Void)?

    init(count: Int, stage: Stage) {
        self.count = count; self.stage = stage
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        let d = (saved != nil && FileManager.default.fileExists(atPath: saved!)) ? saved! : home + "/Desktop"
        defaultPath = d; path = d
        let f = DateFormatter(); f.dateFormat = "MMdd"
        folderName = f.string(from: Date()) + " 셀렉"
        let k = (UserDefaults.standard.string(forKey: kindsKey) ?? "edit").split(separator: ",").map(String.init)
        kinds = Set(k.filter { id in allKinds.contains { $0.id == id } })
    }
    var kindsText: String { allKinds.map(\.id).filter { kinds.contains($0) }.joined(separator: ",") }
    var isDefault: Bool { path == defaultPath }
    var cleanName: String { folderName.trimmingCharacters(in: .whitespaces) }
    // 폴더 이름 문제: 있으면 안내 문구, 없으면 nil
    var nameProblem: String? {
        guard makeFolder else { return nil }
        let n = cleanName
        if n.isEmpty { return "폴더 이름을 입력해 주세요" }
        if n.contains("/") || n.contains(":") { return "폴더 이름에 / 나 : 는 쓸 수 없어요" }
        if n.hasPrefix(".") { return "폴더 이름을 . 으로 시작할 수 없어요" }
        return nil
    }
    var folderExists: Bool {
        var dir: ObjCBool = false
        return makeFolder && FileManager.default.fileExists(atPath: path + "/" + cleanName, isDirectory: &dir) && dir.boolValue
    }
    var footerText: String {
        if kinds.isEmpty { return "내보낼 종류를 하나 이상 골라 주세요" }
        if let p = nameProblem { return p }
        if folderExists { return "이미 있는 폴더예요 · 하위폴더로 저장" }
        return makeFolder ? "[\(pretty(path))] 하위폴더로 저장" : "[\(pretty(path))]에 바로 저장"
    }
    var footerWarn: Bool { kinds.isEmpty || nameProblem != nil || folderExists }
    var canExport: Bool { !kinds.isEmpty && nameProblem == nil }
}

// MARK: - 창 끌기 영역
struct DragArea: NSViewRepresentable {
    final class V: NSView {
        override func mouseDown(with e: NSEvent) { window?.performDrag(with: e) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: - 화면
struct RootView: View {
    @ObservedObject var m: Model
    var backdrop: NSImage? = nil
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            if let b = backdrop { Image(nsImage: b).resizable().aspectRatio(contentMode: .fill).frame(width: 560, height: 520).clipped() }
            content
                .background(DragArea())
                .background(P.bg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.1)))
                .shadow(color: backdrop == nil ? .clear : .black.opacity(0.4), radius: 20, y: 8)
        }
        .frame(width: backdrop == nil ? nil : 560, height: backdrop == nil ? nil : 520)
    }

    var content: some View {
        VStack(spacing: 0) {
            titleBar
            switch m.stage {
            case .setup: setupBody
            case .message(let s): messageBody(s, folder: nil)
            case .done(let s, let f): messageBody(s, folder: f)
            }
        }
        .frame(width: 440)
    }

    var titleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { m.finish?(false) } label: {
                    Circle().fill(P.red).frame(width: 12, height: 12)
                        .overlay(Image(systemName: "xmark").font(.system(size: 6.5, weight: .heavy))
                                    .foregroundColor(Color(red: 0.45, green: 0.05, blue: 0.03)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help("닫기 (실행 취소)")
                Circle().fill(Color.white.opacity(0.18)).frame(width: 12, height: 12)
                Circle().fill(Color.white.opacity(0.18)).frame(width: 12, height: 12)
            }
            Text("셀렉 내보내기").font(.system(size: 12, weight: .semibold)).foregroundColor(P.text)
            Spacer()
        }
        .padding(.horizontal, 12).frame(height: 34).background(P.bar)
        .overlay(Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1), alignment: .bottom)
    }

    func button(_ t: String, primary: Bool, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 12, weight: primary ? .semibold : .regular))
                .foregroundColor(primary ? P.onAccent : P.text)
                .frame(width: 84).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(primary ? P.accent : Color(white: 0.3)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(disabled ? 0.4 : 1).disabled(disabled)
    }

    func checkRow(_ on: Bool, _ title: String, note: String? = nil, enabled: Bool = true, _ toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 62, height: 1)
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(on ? P.accent : Color(white: 0.28)).frame(width: 13, height: 13)
                    if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundColor(P.onAccent) }
                }
                Text(title).font(.system(size: 12)).foregroundColor(P.text)
                if let n = note { Text(n).font(.system(size: 11)).foregroundColor(P.sub) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if enabled { toggle() } }
            Spacer()
        }
        .opacity(enabled ? 1 : 0.4)
    }

    // 형식 줄의 작은 체크 (RAW / 원본 / 보정본)
    func kindCheck(_ id: String, _ title: String) -> some View {
        let on = m.kinds.contains(id)
        return HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(on ? P.accent : Color(white: 0.28)).frame(width: 13, height: 13)
                if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundColor(P.onAccent) }
            }
            Text(title).font(.system(size: 12)).foregroundColor(P.text)
        }
        .contentShape(Rectangle())
        .onTapGesture { if on { m.kinds.remove(id) } else { m.kinds.insert(id) } }
    }

    func label(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundColor(P.sub).frame(width: 62, alignment: .trailing)
    }

    var setupBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { label("사진"); Text("선택한 사진 \(m.count)장").font(.system(size: 12)).foregroundColor(.white); Spacer() }
                HStack(spacing: 8) {
                    label("형식")
                    HStack(spacing: 16) { ForEach(allKinds, id: \.id) { kindCheck($0.id, $0.title) } }
                    Spacer()
                }
                HStack(alignment: .top, spacing: 8) {
                    Color.clear.frame(width: 62, height: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RAW · 원래 파일 그대로 복사")
                        Text("원본 · 보정 없는 JPG (이름_원본.jpg)")
                        Text("보정본 · 캡쳐원 보정 JPG (원본 크기 · sRGB · 품질 100)")
                    }.font(.system(size: 11)).foregroundColor(P.sub)
                    Spacer()
                }
                checkRow(m.kakao && m.hasJpg, "카톡용 (20MB 이하)", note: m.hasJpg ? "· JPG 화질만 낮춤, 크기 그대로" : "· 원본·보정본 JPG에만", enabled: m.hasJpg) { m.kakao.toggle() }
                HStack {
                    label("위치")
                    HStack(spacing: 5) {
                        Image(systemName: "folder").font(.system(size: 11))
                        Text(pretty(m.path)).font(.system(size: 12)).lineLimit(1).truncationMode(.head)
                        Spacer()
                    }
                    .foregroundColor(P.text).padding(.horizontal, 7).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.24)))
                    .help(m.path)
                    Button { choose() } label: {
                        Text("선택…").font(.system(size: 12)).foregroundColor(P.text)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.3)))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .padding(.top, 5)   // 사진·형식 ↔ 위치 구분 여백
                checkRow(m.saveDefault && !m.isDefault, "이 위치를 기본값으로 저장",
                         note: m.isDefault ? "· 지금 기본 위치예요" : nil, enabled: !m.isDefault) { m.saveDefault.toggle() }
                checkRow(m.makeFolder, "새 폴더 만들어서 넣기") {
                    m.makeFolder.toggle(); m.onResize?()
                    if m.makeFolder { DispatchQueue.main.async { nameFocused = true } }
                }
                if m.makeFolder {
                    HStack {
                        label("폴더 이름")
                        TextField("", text: $m.folderName, prompt: Text("폴더 이름").foregroundColor(P.sub))
                            .textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(.white)
                            .padding(.horizontal, 7).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35)))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(nameFocused ? P.accent.opacity(0.8) : Color.white.opacity(0.12)))
                            .focused($nameFocused)
                            .onSubmit { if m.canExport { m.finish?(true) } }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 22).background(P.panel)
            HStack(spacing: 8) {
                Text(m.footerText).font(.system(size: 11)).foregroundColor(m.footerWarn ? P.warn : P.sub)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                button("취소", primary: false) { m.finish?(false) }.keyboardShortcut(.cancelAction)
                button("내보내기", primary: true, disabled: !m.canExport) { m.finish?(true) }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    func messageBody(_ s: String, folder: String?) -> some View {
        VStack(spacing: 0) {
            HStack { Text(s).font(.system(size: 13)).foregroundColor(.white); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 16).background(P.panel)
            HStack(spacing: 8) {
                Spacer()
                if let f = folder {
                    button("폴더 열기", primary: false) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: f)); m.finish?(true)
                    }
                }
                button("확인", primary: true) { m.finish?(true) }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    // 맥 폴더 선택 창
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: m.path)
        panel.prompt = "선택"
        panel.message = "내보낼 위치를 선택하세요"
        panel.level = .floating + 1
        if panel.runModal() == .OK, let u = panel.url {
            m.path = u.path
            if m.isDefault { m.saveDefault = false }
        }
    }
}

// MARK: - 창
final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

func runWindow(_ m: Model, onFinish: @escaping (Bool) -> Void) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let win = PanelWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = true
    win.level = .floating; win.isMovableByWindowBackground = true
    win.appearance = NSAppearance(named: .darkAqua)
    let host = NSHostingView(rootView: RootView(m: m))
    win.contentView = host
    m.onResize = {
        DispatchQueue.main.async {
            let s = host.fittingSize
            var f = win.frame
            f.origin.y += f.height - s.height        // 위쪽 고정
            f.size = s
            win.setFrame(f, display: true, animate: false)
            win.invalidateShadow()
        }
    }
    m.finish = onFinish
    win.setContentSize(host.fittingSize)
    win.center()
    app.activate(ignoringOtherApps: true)
    win.makeKeyAndOrderFront(nil)
    win.invalidateShadow()
    app.run()
    exit(0)
}

// MARK: - 확인용 스냅샷
func blurred(_ path: String, _ r: Double) -> NSImage {
    let ci = CIImage(contentsOf: URL(fileURLWithPath: path))!
    let f = CIFilter(name: "CIGaussianBlur")!; f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey); f.setValue(r, forKey: kCIInputRadiusKey)
    let out = f.outputImage!.cropped(to: ci.extent); let cg = CIContext().createCGImage(out, from: out.extent)!
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
func snap(_ m: Model, _ bg: NSImage, _ path: String) {
    let h = NSHostingView(rootView: RootView(m: m, backdrop: bg)); h.appearance = NSAppearance(named: .darkAqua)
    h.setFrameSize(h.fittingSize); h.layoutSubtreeIfNeeded()
    let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!; h.cacheDisplay(in: h.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - 실행
let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "" {
case "msg":
    let m = Model(count: 0, stage: .message(args.count > 1 ? args[1] : ""))
    runWindow(m) { _ in exit(0) }
case "done":
    let m = Model(count: 0, stage: .done(args.count > 1 ? args[1] : "", args.count > 2 ? args[2] : home))
    runWindow(m) { _ in exit(0) }
case "snapshot":
    let bg = blurred(args[2], 60)
    let a = Model(count: 12, stage: .setup); a.kinds = ["edit"]; a.kakao = false; snap(a, bg, args[1] + "/1_기본.png")
    let b = Model(count: 12, stage: .setup); b.path = home + "/Desktop/납품"; b.saveDefault = true; b.makeFolder = true; b.kinds = ["raw", "orig", "edit"]; b.kakao = true
    snap(b, bg, args[1] + "/2_위치바꿈_새폴더.png")
    let c = Model(count: 12, stage: .setup); c.makeFolder = true; c.folderName = "a/b"; c.kinds = []
    snap(c, bg, args[1] + "/3_잘못된이름.png")
    let d = Model(count: 0, stage: .done("내보내기 완료 · RAW 12 · 원본 12 · 보정본 12 (카톡용)", home)); snap(d, bg, args[1] + "/4_완료.png")
    exit(0)
default:
    guard let n = Int(args.first ?? "") else {
        FileHandle.standardError.write("사용: exportui <사진 수> | msg 문구 | done 문구 폴더 | snapshot 폴더 배경\n".data(using: .utf8)!)
        exit(2)
    }
    let m = Model(count: n, stage: .setup)
    runWindow(m) { ok in
        guard ok else { exit(1) }
        if m.saveDefault && !m.isDefault { UserDefaults.standard.set(m.path, forKey: defaultsKey) }
        print(m.path)
        print(m.makeFolder ? m.cleanName : "")
        print(m.kindsText)
        print(m.kakao && m.hasJpg ? "kakao" : "")
        UserDefaults.standard.set(m.kindsText, forKey: kindsKey)
        UserDefaults.standard.set(m.kakao, forKey: kakaoKey)
        exit(0)
    }
}
