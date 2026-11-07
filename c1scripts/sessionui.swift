// 캡쳐원 스크립트("세션 지우기", "세션 만들기")용 창 — 캡쳐원 패널 스타일(B안)
// 사용:
//   sessionui choose 이름1 이름2 ...  → 세션 체크 → 지우기 → "세션을 지우시겠습니까?" → 확인
//                                      선택한 이름을 한 줄씩 출력 (취소·✕ 누르면 아무것도 출력 안 하고 종료코드 1)
//   sessionui input 기존이름1 ...      → 새 세션 이름 입력 → 만들기 → 이름 출력 (취소·✕ 종료코드 1)
//                                      빈 이름·/·:·. 시작·기존 이름과 같으면 만들기 막힘
//   sessionui msg "문구" [초]         → 알림 한 개 (확인 버튼). 초를 주면 버튼 없이 그 시간 뒤 자동으로 닫힘
//   sessionui snapshot <출력폴더> <배경사진> → 화면 모습을 PNG로 저장 (확인용)
// 창: 제목줄(빨간 ✕ = 실행 전체 취소) + 캡쳐원 도구 패널 모양, 제목줄·빈 곳을 끌면 창 이동
// 파일은 건드리지 않음 (삭제·생성은 AppleScript가 처리)
// 컴파일: swiftc -O sessionui.swift -o ~/Library/Application\ Support/cc/sessionui
import SwiftUI
import AppKit
import CoreImage

// MARK: - 색 (캡쳐원 다크 패널)
enum P {
    static let bg = Color(red: 0.165, green: 0.165, blue: 0.17)       // 창 바탕
    static let bar = Color(red: 0.2, green: 0.2, blue: 0.205)         // 제목줄
    static let section = Color(red: 0.19, green: 0.19, blue: 0.195)   // 패널 머리글
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.135)     // 패널 안
    static let line = Color.white.opacity(0.07)
    static let text = Color(white: 0.86)
    static let sub = Color(white: 0.55)
    static let accent = Color(red: 0.96, green: 0.55, blue: 0.14)   // 캡쳐원 주황
    static let onAccent = Color(red: 0.1, green: 0.07, blue: 0.03)  // 주황 위 글자·체크
    static let red = Color(red: 1.0, green: 0.37, blue: 0.34)
    static let warn = Color(red: 1.0, green: 0.45, blue: 0.42)
}

// MARK: - 상태
enum Stage { case choose, confirm, input, message(String) }

final class Model: ObservableObject {
    let names: [String]
    @Published var checked: Set<String> = []
    @Published var stage: Stage
    @Published var newName = ""
    var onResize: (() -> Void)?
    var finish: ((Bool) -> Void)?
    var autoClose: Double? = nil   // 알림을 몇 초 뒤 자동으로 닫을지 (msg 세 번째 인자)
    init(names: [String], stage: Stage) { self.names = names; self.stage = stage }
    var picked: [String] { names.filter { checked.contains($0) } }
    // 새 세션 이름 검사: 문제 있으면 안내 문구("" = 빈칸), 괜찮으면 nil
    var nameProblem: String? {
        let n = newName.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "" }
        if n.contains("/") || n.contains(":") { return "이름에 / 나 : 는 쓸 수 없어요" }
        if n.hasPrefix(".") { return "이름을 . 으로 시작할 수 없어요" }
        if names.contains(where: { $0.precomposedStringWithCanonicalMapping == n.precomposedStringWithCanonicalMapping }) { return "이미 있는 세션이에요" }
        return nil
    }
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
    var backdrop: NSImage? = nil          // snapshot 때만
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            if let b = backdrop { Image(nsImage: b).resizable().aspectRatio(contentMode: .fill).frame(width: 480, height: 480).clipped() }
            window
                .background(DragArea())
                .background(P.bg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.1)))
                .shadow(color: backdrop == nil ? .clear : .black.opacity(0.4), radius: 20, y: 8)
        }
        .frame(width: backdrop == nil ? nil : 480, height: backdrop == nil ? nil : 480)
    }

    var window: some View {
        VStack(spacing: 0) {
            switch m.stage {
            case .choose: chooseBody
            case .confirm: confirmBody
            case .input: inputBody
            case .message(let s): messageBody(s)
            }
        }
        .frame(width: 380)
    }

    // 제목줄: 신호등(빨간 ✕만 동작) + 제목
    func titleBar(_ title: String) -> some View {
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
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(P.text)
            Spacer()
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(P.bar)
        .overlay(Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1), alignment: .bottom)
    }

    // 캡쳐원 도구 패널 머리글
    func section(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(P.sub)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(P.text)
            Spacer()
        }
        .padding(.horizontal, 12).frame(height: 28)
        .background(P.section)
    }

    func button(_ t: String, primary: Bool, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 12, weight: primary ? .semibold : .regular))
                .foregroundColor(primary ? P.onAccent : P.text)
                .frame(width: 84).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(primary ? P.accent : Color(white: 0.3)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1).disabled(disabled)
    }

    func footer<L: View, B: View>(_ left: L, _ buttons: B) -> some View {
        HStack(spacing: 8) { left; Spacer(); buttons }.padding(.horizontal, 12).padding(.vertical, 8)
    }

    func checkbox(_ on: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(on ? P.accent : Color(white: 0.28)).frame(width: 13, height: 13)
            if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundColor(P.onAccent) }
        }
    }

    // 1) 세션 고르기
    var chooseBody: some View {
        VStack(spacing: 0) {
            titleBar("세션 지우기")
            section("세션")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(m.names, id: \.self) { n in
                        let on = m.checked.contains(n)
                        HStack(spacing: 8) {
                            checkbox(on)
                            Image(systemName: "folder").font(.system(size: 11)).foregroundColor(P.sub)
                            Text(n).font(.system(size: 12)).foregroundColor(on ? .white : P.text).lineLimit(1)
                            Spacer()
                            Text("세션").font(.system(size: 10)).foregroundColor(P.sub)
                        }
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(on ? Color.white.opacity(0.05) : Color.clear)
                        .overlay(Rectangle().fill(P.line).frame(height: 1), alignment: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture { if on { m.checked.remove(n) } else { m.checked.insert(n) } }
                    }
                }
            }
            .frame(maxHeight: 26 * 10).fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
            .background(P.panel)
            footer(Text(m.checked.isEmpty ? "지울 세션을 선택하세요" : "\(m.checked.count)개 선택 · 휴지통으로 이동")
                        .font(.system(size: 11)).foregroundColor(P.sub),
                   HStack(spacing: 8) {
                       button("취소", primary: false) { m.finish?(false) }.keyboardShortcut(.cancelAction)
                       button("지우기", primary: true, disabled: m.checked.isEmpty) { m.stage = .confirm; m.onResize?() }
                           .keyboardShortcut(.defaultAction)
                   })
        }
    }

    // 2) 확인
    var confirmBody: some View {
        VStack(spacing: 0) {
            titleBar("세션 지우기")
            section("세션을 지우시겠습니까?")
            VStack(spacing: 0) {
                ForEach(m.picked, id: \.self) { n in
                    HStack(spacing: 8) {
                        Image(systemName: "folder").font(.system(size: 11)).foregroundColor(P.sub)
                        Text(n).font(.system(size: 12)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12).frame(height: 26)
                    .overlay(Rectangle().fill(P.line).frame(height: 1), alignment: .bottom)
                }
            }
            .padding(.vertical, 6)
            .background(P.panel)
            footer(Text("휴지통으로 이동해요 (복구 가능)").font(.system(size: 11)).foregroundColor(P.sub),
                   HStack(spacing: 8) {
                       button("이전", primary: false) { m.stage = .choose; m.onResize?() }.keyboardShortcut(.cancelAction)
                       button("확인", primary: true) { m.finish?(true) }.keyboardShortcut(.defaultAction)
                   })
        }
    }

    // 3) 새 세션 이름 입력
    var inputBody: some View {
        let problem = m.nameProblem
        let ok = problem == nil
        return VStack(spacing: 0) {
            titleBar("새 세션 만들기")
            section("세션")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("이름").font(.system(size: 12)).foregroundColor(P.sub).frame(width: 52, alignment: .trailing)
                    TextField("", text: $m.newName, prompt: Text("세션 이름").foregroundColor(P.sub))
                        .textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(.white)
                        .padding(.horizontal, 7).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(nameFocused ? P.accent.opacity(0.8) : Color.white.opacity(0.12)))
                        .focused($nameFocused)
                        .onSubmit { if ok { m.finish?(true) } }
                        .onAppear { DispatchQueue.main.async { nameFocused = true } }
                }
                HStack {
                    Text("위치").font(.system(size: 12)).foregroundColor(P.sub).frame(width: 52, alignment: .trailing)
                    HStack(spacing: 5) { Image(systemName: "folder").font(.system(size: 11)); Text("데스크톱 › 세션").font(.system(size: 12)); Spacer() }
                        .foregroundColor(P.text).padding(.horizontal, 7).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.24)))
                }
            }
            .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 22).background(P.panel)
            footer(Text((problem ?? "").isEmpty ? " " : problem!).font(.system(size: 11)).foregroundColor(P.warn),
                   HStack(spacing: 8) {
                       button("취소", primary: false) { m.finish?(false) }.keyboardShortcut(.cancelAction)
                       button("만들기", primary: true, disabled: !ok) { m.finish?(true) }
                   })
        }
    }

    // 4) 알림
    func messageBody(_ s: String) -> some View {
        VStack(spacing: 0) {
            titleBar("캡쳐원")
            HStack { Text(s).font(.system(size: 13)).foregroundColor(.white); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 20).background(P.panel)
            if m.autoClose == nil {
                footer(EmptyView(),
                       button("확인", primary: true) { m.finish?(true) }.keyboardShortcut(.defaultAction))
            }
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
func blurred(_ path: String, _ radius: Double) -> NSImage {
    let ci = CIImage(contentsOf: URL(fileURLWithPath: path))!
    let f = CIFilter(name: "CIGaussianBlur")!
    f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey); f.setValue(radius, forKey: kCIInputRadiusKey)
    let out = f.outputImage!.cropped(to: ci.extent)
    let cg = CIContext().createCGImage(out, from: out.extent)!
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

func snap(_ m: Model, _ bg: NSImage, _ path: String) {
    let h = NSHostingView(rootView: RootView(m: m, backdrop: bg))
    h.appearance = NSAppearance(named: .darkAqua)
    h.setFrameSize(h.fittingSize); h.layoutSubtreeIfNeeded()
    let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!; h.cacheDisplay(in: h.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - 실행
let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "" {
case "choose":
    let m = Model(names: Array(args.dropFirst()), stage: .choose)
    runWindow(m) { ok in
        guard ok else { exit(1) }
        print(m.picked.joined(separator: "\n"))
        exit(0)
    }
case "input":
    let m = Model(names: Array(args.dropFirst()), stage: .input)
    runWindow(m) { ok in
        guard ok else { exit(1) }
        print(m.newName.trimmingCharacters(in: .whitespaces))
        exit(0)
    }
case "msg":   // sessionui msg "문구" [자동으로 닫을 초]
    let m = Model(names: [], stage: .message(args.count > 1 ? args[1] : ""))
    if args.count > 2, let t = Double(args[2]) {
        m.autoClose = t
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { exit(0) }
    }
    runWindow(m) { _ in exit(0) }
case "snapshot":
    let bg = blurred(args[2], 60)
    let demo = ["테스트 세션 A", "테스트 세션 B", "테스트 세션 C"]
    for (i, st) in [Stage.choose, .confirm, .message("세션을 지웠습니다☺️")].enumerated() {
        let m = Model(names: demo, stage: st)
        m.checked = ["테스트 세션 A", "테스트 세션 C"]
        snap(m, bg, "\(args[1])/dark_\(i + 1).png")
    }
    for (i, n) in ["", "0928 프로필 촬영", "테스트 세션 A"].enumerated() {
        let m = Model(names: demo, stage: .input); m.newName = n
        snap(m, bg, "\(args[1])/input_\(i + 1).png")
    }
    exit(0)
default:
    FileHandle.standardError.write("사용: sessionui choose 이름... | input 기존이름... | msg 문구 | snapshot 폴더 배경\n".data(using: .utf8)!)
    exit(2)
}
