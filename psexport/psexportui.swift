// 고양이 메뉴 "포토샵 내보내기" 창
// 사용: psexportui <info.json>  → [내보내기] 누르면 JSON 한 줄 출력 {"path":..,"folder":..,"docs":[i..],"current":bool,"original":bool,"pick":[이름..],"kakao":bool}
//       취소·✕ 누르면 출력 없이 종료코드 1
//       psexportui snapshot <info.json> <출력.png> → 창 모습 PNG (확인용)
// 기본 위치: UserDefaults "cc.psexportui.path" (처음엔 데스크톱). 파일은 건드리지 않음
// 컴파일: swiftc -O psexportui.swift -o ~/Library/Application\ Support/cc/psexportui
import SwiftUI
import AppKit

enum P {
    static let bg = Color(red: 0.165, green: 0.165, blue: 0.17)
    static let bar = Color(red: 0.2, green: 0.2, blue: 0.205)
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.135)
    static let text = Color(white: 0.86)
    static let sub = Color(white: 0.55)
    static let accent = Color(red: 0.19, green: 0.66, blue: 1.0)   // 포토샵 파랑
    static let onAccent = Color(red: 0.02, green: 0.08, blue: 0.16)
    static let red = Color(red: 1.0, green: 0.37, blue: 0.34)
    static let warn = Color(red: 1.0, green: 0.62, blue: 0.3)
}
let defaultsKey = "cc.psexportui.path"
let home = FileManager.default.homeDirectoryForCurrentUser.path
func pretty(_ path: String) -> String {
    var p = path; var head = ""
    for (full, name) in [(home + "/Desktop", "데스크톱"), (home + "/Documents", "문서"), (home + "/Downloads", "다운로드"), (home + "/Pictures", "사진"), (home, "홈")]
        where p == full || p.hasPrefix(full + "/") { head = name; p = String(p.dropFirst(full.count)); break }
    return ([head].filter { !$0.isEmpty } + p.split(separator: "/").map(String.init)).joined(separator: " › ")
}

struct Doc: Decodable { let i: Int; let name: String; let current: Bool; let active: Int; let layers: [String] }
struct Info: Decodable { let docs: [Doc] }

final class Model: ObservableObject {
    let docs: [Doc]
    let defaultPath: String
    @Published var selDocs: Set<Int>
    @Published var useCurrent = true
    @Published var useOriginal = false
    @Published var usePick = false
    @Published var kakao = false
    @Published var pick: Set<String> = []
    @Published var path: String
    @Published var saveDefault = false
    @Published var makeFolder = false
    @Published var folderName: String
    var finish: ((Bool) -> Void)?
    var onResize: (() -> Void)?
    init(_ info: Info) {
        docs = info.docs
        selDocs = Set(info.docs.filter { $0.current }.map { $0.i })
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        let d = (saved != nil && FileManager.default.fileExists(atPath: saved!)) ? saved! : home + "/Desktop"
        defaultPath = d; path = d
        let f = DateFormatter(); f.dateFormat = "MMdd"; folderName = f.string(from: Date()) + " 보정"
    }
    var isDefault: Bool { path == defaultPath }
    var cleanName: String { folderName.trimmingCharacters(in: .whitespaces) }
    // 고른 문서들의 레이어 이름 (위에서부터, 겹치지 않게)
    var layerNames: [String] {
        var seen = Set<String>(), out: [String] = []
        for d in docs where selDocs.contains(d.i) { for n in d.layers where !seen.contains(n) { seen.insert(n); out.append(n) } }
        return out
    }
    // 문서마다 내보낼 레이어 번호 수
    var fileCount: Int {
        docs.filter { selDocs.contains($0.i) }.reduce(0) { s, d in
            var ks = Set<Int>()
            if useCurrent && d.active >= 0 { ks.insert(d.active) }
            if useOriginal && !d.layers.isEmpty { ks.insert(d.layers.count - 1) }
            if usePick { for (k, n) in d.layers.enumerated() where pick.contains(n) { ks.insert(k) } }
            return s + ks.count
        }
    }
    var nameProblem: String? {
        guard makeFolder else { return nil }
        let n = cleanName
        if n.isEmpty { return "폴더 이름을 입력해 주세요" }
        if n.contains("/") || n.contains(":") { return "폴더 이름에 / 나 : 는 쓸 수 없어요" }
        if n.hasPrefix(".") { return "폴더 이름을 . 으로 시작할 수 없어요" }
        return nil
    }
    var footerText: String {
        if let p = nameProblem { return p }
        if fileCount == 0 { return "내보낼 문서와 레이어를 골라 주세요" }
        return "JPG \(fileCount)개 · " + (makeFolder ? "[\(pretty(path))] 하위폴더" : "[\(pretty(path))]")
    }
    var canExport: Bool { nameProblem == nil && fileCount > 0 }
}

struct DragArea: NSViewRepresentable {
    final class V: NSView { override func mouseDown(with e: NSEvent) { window?.performDrag(with: e) } }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) {}
}

struct RootView: View {
    @ObservedObject var m: Model
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(spacing: 0) { titleBar; setupBody }
            .frame(width: 460)
            .background(DragArea()).background(P.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.1)))
    }
    var titleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { m.finish?(false) } label: {
                    Circle().fill(P.red).frame(width: 12, height: 12)
                        .overlay(Image(systemName: "xmark").font(.system(size: 6.5, weight: .heavy)).foregroundColor(Color(red: 0.45, green: 0.05, blue: 0.03)))
                }.buttonStyle(.plain)
                Circle().fill(Color.white.opacity(0.18)).frame(width: 12, height: 12)
                Circle().fill(Color.white.opacity(0.18)).frame(width: 12, height: 12)
            }
            Text("Photoshop Export").font(.system(size: 12, weight: .semibold)).foregroundColor(P.text)
            Spacer()
        }
        .padding(.horizontal, 12).frame(height: 34).background(P.bar)
        .overlay(Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1), alignment: .bottom)
    }
    func box(_ on: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(on ? P.accent : Color(white: 0.28)).frame(width: 13, height: 13)
            if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundColor(P.onAccent) }
        }
    }
    func check(_ on: Bool, _ title: String, note: String? = nil, _ toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            box(on)
            Text(title).font(.system(size: 12)).foregroundColor(P.text).lineLimit(1).truncationMode(.middle)
            if let n = note { Text(n).font(.system(size: 11)).foregroundColor(P.sub).lineLimit(1) }
            Spacer(minLength: 0)
        }.contentShape(Rectangle()).onTapGesture(perform: toggle)
    }
    func label(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundColor(P.sub).frame(width: 52, alignment: .trailing)
    }
    func small(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(.system(size: 11)).foregroundColor(P.sub).underline() }.buttonStyle(.plain)
    }
    func button(_ t: String, primary: Bool, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 12, weight: primary ? .semibold : .regular))
                .foregroundColor(primary ? P.onAccent : P.text).frame(width: 84).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(primary ? P.accent : Color(white: 0.3))).contentShape(Rectangle())
        }.buttonStyle(.plain).opacity(disabled ? 0.4 : 1).disabled(disabled)
    }
    func list<C: View>(_ h: CGFloat, @ViewBuilder _ c: () -> C) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 6) { c() }.padding(8) }
            .frame(height: h).background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.25)))
    }
    var curDoc: Doc? { m.docs.first { $0.current } }

    var setupBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // 문서
                HStack(alignment: .top) {
                    label("문서").padding(.top, 8)
                    VStack(alignment: .leading, spacing: 4) {
                        list(min(CGFloat(m.docs.count) * 21 + 14, 160)) {
                            ForEach(m.docs, id: \.i) { d in
                                check(m.selDocs.contains(d.i), d.name, note: d.current ? "· 지금 문서" : nil) {
                                    if m.selDocs.contains(d.i) { m.selDocs.remove(d.i) } else { m.selDocs.insert(d.i) }
                                    m.onResize?()
                                }
                            }
                        }
                        HStack(spacing: 10) {
                            small("전체 선택") { m.selDocs = Set(m.docs.map { $0.i }); m.onResize?() }
                            small("지금 문서만") { m.selDocs = Set(m.docs.filter { $0.current }.map { $0.i }); m.onResize?() }
                            Spacer()
                            Text("\(m.selDocs.count) / \(m.docs.count)").font(.system(size: 11)).foregroundColor(P.sub)
                        }
                    }
                }
                // 레이어
                HStack(alignment: .top) {
                    label("레이어").padding(.top, 1)
                    VStack(alignment: .leading, spacing: 7) {
                        check(m.useCurrent, "현재 레이어", note: "· 선택된 레이어, 이름 뒤 _최종" + ((curDoc?.active ?? -1) >= 0 && m.selDocs.count == 1 ? " (\(curDoc!.layers[curDoc!.active]))" : "")) { m.useCurrent.toggle() }
                        check(m.useOriginal, "원본", note: "· 맨 아래 레이어, 이름 뒤 _원본") { m.useOriginal.toggle() }
                        check(m.usePick, "레이어 직접 고르기", note: "· 이름 뒤 _레이어이름") { m.usePick.toggle(); m.onResize?() }
                        if m.usePick {
                            list(min(CGFloat(m.layerNames.count) * 21 + 14, 150)) {
                                ForEach(m.layerNames, id: \.self) { n in
                                    check(m.pick.contains(n), n) { if m.pick.contains(n) { m.pick.remove(n) } else { m.pick.insert(n) } }
                                }
                            }.padding(.leading, 21)
                        }
                    }
                }
                HStack { label("형식"); Text("JPG · 품질 최고 · 문서 크기 그대로 · 색 프로필 포함").font(.system(size: 12)).foregroundColor(P.text); Spacer() }
                HStack { Color.clear.frame(width: 52, height: 1)
                    check(m.kakao, "카톡용 (20MB 이하)", note: "· 넘으면 해상도는 그대로, 화질만 낮춤") { m.kakao.toggle() } }
                // 위치
                HStack {
                    label("위치")
                    HStack(spacing: 5) {
                        Image(systemName: "folder").font(.system(size: 11))
                        Text(pretty(m.path)).font(.system(size: 12)).lineLimit(1).truncationMode(.head); Spacer()
                    }
                    .foregroundColor(P.text).padding(.horizontal, 7).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.24))).help(m.path)
                    Button { choose() } label: {
                        Text("선택…").font(.system(size: 12)).foregroundColor(P.text).padding(.horizontal, 10).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.3))).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                HStack { Color.clear.frame(width: 52, height: 1)
                    check(m.saveDefault && !m.isDefault, "이 위치를 기본값으로 저장", note: m.isDefault ? "· 지금 기본 위치예요" : nil) { if !m.isDefault { m.saveDefault.toggle() } }
                        .opacity(m.isDefault ? 0.4 : 1) }
                HStack { Color.clear.frame(width: 52, height: 1)
                    check(m.makeFolder, "새 폴더 만들어서 넣기") {
                        m.makeFolder.toggle(); m.onResize?()
                        if m.makeFolder { DispatchQueue.main.async { nameFocused = true } }
                    } }
                if m.makeFolder {
                    HStack {
                        label("폴더 이름")
                        TextField("", text: $m.folderName).textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(.white)
                            .padding(.horizontal, 7).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35)))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(nameFocused ? P.accent.opacity(0.8) : Color.white.opacity(0.12)))
                            .focused($nameFocused).onSubmit { if m.canExport { m.finish?(true) } }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 18).background(P.panel)
            HStack(spacing: 8) {
                Text(m.footerText).font(.system(size: 11)).foregroundColor(m.nameProblem != nil || m.fileCount == 0 ? P.warn : P.sub)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                button("취소", primary: false) { m.finish?(false) }.keyboardShortcut(.cancelAction)
                button("내보내기", primary: true, disabled: !m.canExport) { m.finish?(true) }.keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
    func choose() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: m.path); p.prompt = "선택"; p.message = "내보낼 위치를 선택하세요"; p.level = .floating + 1
        if p.runModal() == .OK, let u = p.url { m.path = u.path; if m.isDefault { m.saveDefault = false } }
    }
}

final class PanelWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 1 else { FileHandle.standardError.write("사용: psexportui info.json | snapshot info.json out.png\n".data(using: .utf8)!); exit(2) }
let snapMode = args[0] == "snapshot"
guard let info = try? JSONDecoder().decode(Info.self, from: Data(contentsOf: URL(fileURLWithPath: snapMode ? args[1] : args[0]))) else { FileHandle.standardError.write("정보 파일을 읽지 못했어요\n".data(using: .utf8)!); exit(1) }
let m = Model(info)
if snapMode {
    _ = NSApplication.shared
    if args.count > 3 { m.useOriginal = true; m.usePick = true; m.pick = [m.layerNames.first ?? ""]; m.makeFolder = true; m.selDocs = Set(m.docs.prefix(3).map { $0.i }) }
    let h = NSHostingView(rootView: RootView(m: m)); h.appearance = NSAppearance(named: .darkAqua)
    h.setFrameSize(h.fittingSize); h.layoutSubtreeIfNeeded()
    let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!; h.cacheDisplay(in: h.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = PanelWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = true; win.level = .floating
win.appearance = NSAppearance(named: .darkAqua)
let host = NSHostingView(rootView: RootView(m: m))
win.contentView = host
m.onResize = {
    DispatchQueue.main.async {
        let s = host.fittingSize; var f = win.frame
        f.origin.y += f.height - s.height; f.size = s
        win.setFrame(f, display: true, animate: false); win.invalidateShadow()
    }
}
m.finish = { ok in
    guard ok else { exit(1) }
    if m.saveDefault && !m.isDefault { UserDefaults.standard.set(m.path, forKey: defaultsKey) }
    let o: [String: Any] = ["path": m.path, "folder": m.makeFolder ? m.cleanName : "", "docs": m.selDocs.sorted(),
                            "current": m.useCurrent, "original": m.useOriginal, "pick": m.usePick ? Array(m.pick) : [], "kakao": m.kakao]
    print(String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!)
    exit(0)
}
win.setContentSize(host.fittingSize); win.center()
app.activate(ignoringOtherApps: true); win.makeKeyAndOrderFront(nil)
app.run()
