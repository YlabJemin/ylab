// cctool: ydot 스크립트들이 쓰는 작은 도구 모음 (파이썬 없이 돌게 스위프트로 옮김, 2026-11-03)
//   cctool instasave [--one] [--again] [--check]   크롬 인스타 게시물 사진을 원본 그대로 데스크톱에 저장 (옛 insta/save.py)
//   cctool websave                                 크롬 웹페이지의 지금 보는 사진 한 장 저장 (옛 insta/websave.py)
//   cctool psexport                                포토샵 레이어 내보내기 (옛 psexport/run.py, 창은 psexportui · jsx는 같은 폴더)
//   cctool fileurl <경로> / cctool unurl <file://…>  경로 ↔ file URL
// 설치 위치: ~/Library/Application Support/cc/cctool (ydot이 켤 때 넣어 줌)
import Foundation
import ImageIO

func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }
func sh(_ args: [String]) -> (Int32, String, String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: args[0]); p.arguments = Array(args.dropFirst())
    let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
    do { try p.run() } catch { return (127, "", "\(error)") }
    let od = o.fileHandleForReading.readDataToEndOfFile(), ed = e.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (p.terminationStatus, String(data: od, encoding: .utf8) ?? "", String(data: ed, encoding: .utf8) ?? "")
}
func asText(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }   // AppleScript 문자열
func chromeJS(_ code: String) -> String {   // 크롬 '보기 > 개발자 > Apple Events의 자바스크립트 허용' 필요
    if let fake = ProcessInfo.processInfo.environment["CCTOOL_FAKE_JS"] { return fake }   // 시험용
    let (rc, out, err) = sh(["/usr/bin/osascript", "-e", "tell application \"Google Chrome\" to execute active tab of front window javascript " + asText(code)])
    if rc != 0 { fail(err.trimmingCharacters(in: .whitespacesAndNewlines)) }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}
func json(_ s: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:] }
func download(_ url: String, headers: [String: String]) -> Data? {
    guard let u = URL(string: url) else { return nil }
    var req = URLRequest(url: u, timeoutInterval: 30); for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    var out: Data?; let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, _, _ in out = d; sem.signal() }.resume(); sem.wait()
    return out
}
func pixelSize(_ path: String) -> String {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return "?" }
    return "\(p["PixelWidth"] ?? "?")×\(p["PixelHeight"] ?? "?")"
}
func sanitize(_ s: String, keepDot: Bool) -> String {   // 파이썬 [^\w.가-힣-] 와 같게
    let re = try! NSRegularExpression(pattern: keepDot ? "[^\\w.가-힣-]" : "[^\\w가-힣-]")
    return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
}
let desktop = NSHomeDirectory() + "/Desktop"
let fm = FileManager.default

// MARK: instasave
let CUR = #"""
(()=>{const d=document.querySelector("div[role=dialog]")||document.querySelector("main")||document;
let vis=[...d.querySelectorAll("img")].filter(i=>{const r=i.getBoundingClientRect();return i.naturalWidth>300&&r.width>200&&r.left>=-5&&r.right<=innerWidth+5&&r.bottom>0&&r.top<innerHeight});
const row=vis.filter(i=>Math.abs(i.getBoundingClientRect().top-vis[0].getBoundingClientRect().top)<5&&Math.abs(i.getBoundingClientRect().width-vis[0].getBoundingClientRect().width)<5);
if(row.length>1)vis=[row.sort((a,b)=>a.getBoundingClientRect().left-b.getBoundingClientRect().left)[0]];
const k=vis.length?(vis[0].src.match(/\/(\d+_\d+_\d+)_n\./)||[])[1]:null;
let best=null;
if(k)for(const i of document.querySelectorAll("img")){if(!i.src.includes(k))continue;
 for(const [u,w] of (i.srcset||"").split(",").map(x=>x.trim().split(" ")).filter(a=>a[0])){const n=parseInt(w||0);if(!best||n>best.w)best={w:n,u:u}}
 if(!best||i.naturalWidth>best.w)best={w:i.naturalWidth,u:i.src}}
const user=(document.querySelector("header a[href^='/'][role=link] span, header h2")||{}).textContent||"";
const nx=!!d.querySelector("button[aria-label='다음'],button[aria-label='Next']");
return JSON.stringify({url:location.href,user:user,key:k,img:best,next:nx})})()
"""#
let NEXT = #"(()=>{const d=document.querySelector("div[role=dialog]")||document;const b=d.querySelector("button[aria-label='다음'],button[aria-label='Next']");if(b){b.click();return "ok"}return "none"})()"#
let PREV = #"(()=>{const d=document.querySelector("div[role=dialog]")||document;const b=d.querySelector("button[aria-label='돌아가기'],button[aria-label='이전'],button[aria-label='Go back'],button[aria-label='Previous']");if(b){b.click();return "ok"}return "none"})()"#

func instasave(_ args: [String]) {
    let ONE = args.contains("--one"), AGAIN = args.contains("--again"), CHECK = args.contains("--check")
    let first = json(chromeJS(CUR))
    let url = first["url"] as? String ?? ""
    guard url.range(of: "/(p|reel)/", options: .regularExpression) != nil else { fail("인스타 게시물을 열어 둔 상태에서 실행해 주세요") }
    guard let firstImg = first["img"] as? [String: Any] else { fail("사진을 못 찾음: " + url) }
    var pid = "post"; if let m = url.range(of: "/(?:p|reel)/([^/?]+)", options: .regularExpression) { let seg = url[m].dropFirst(url[m].hasPrefix("/reel/") ? 6 : 3); pid = String(seg) }
    var user = sanitize(first["user"] as? String ?? "", keepDot: true); if user.isEmpty { user = "insta" }
    if CHECK {
        let n = ((try? fm.contentsOfDirectory(atPath: desktop)) ?? []).filter { $0.hasPrefix("인스타_") && $0.contains("_" + pid) && $0.hasSuffix(".jpg") }.count
        print(n); return
    }
    var imgs: [[String: Any]] = [], moved = 0, idx: Int? = nil
    let hasNext = first["next"] as? Bool ?? false
    if ONE {
        imgs = [firstImg]
        if let m = url.range(of: "img_index=(\\d+)", options: .regularExpression) { idx = Int(url[m].dropFirst(10)) } else if hasNext { idx = 1 }
    } else if hasNext || url.contains("img_index=") {
        for _ in 0..<30 { if chromeJS(PREV) != "ok" { break }; moved -= 1; Thread.sleep(forTimeInterval: 0.6) }
        var seen = Set<String>()
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval: 0.6)
            let c = json(chromeJS(CUR))
            if let k = c["key"] as? String, !seen.contains(k), let im = c["img"] as? [String: Any] { seen.insert(k); imgs.append(im) }
            if !(c["next"] as? Bool ?? false) { break }
            _ = chromeJS(NEXT); moved += 1
        }
        for _ in 0..<moved { _ = chromeJS(PREV); Thread.sleep(forTimeInterval: 0.3) }
    } else { imgs = [firstImg] }
    var saved = 0
    for (n, x) in imgs.enumerated() {
        let num: Int? = idx ?? (imgs.count > 1 ? n + 1 : nil)
        var dst = desktop + "/인스타_\(user)_\(pid)" + (num.map { "_\($0)" } ?? "") + ".jpg"
        if fm.fileExists(atPath: dst) {
            if !AGAIN { print("이미 있음(건너뜀): " + (dst as NSString).lastPathComponent); continue }
            var k = 2; let base = String(dst.dropLast(4)); while fm.fileExists(atPath: base + " (\(k)).jpg") { k += 1 }; dst = base + " (\(k)).jpg"
        }
        guard let u = x["u"] as? String, let d = download(u, headers: ["User-Agent": "Mozilla/5.0"]) else { fail("사진을 받지 못했어요") }
        try? d.write(to: URL(fileURLWithPath: dst))
        print("저장: \((dst as NSString).lastPathComponent) (\(pixelSize(dst)))"); saved += 1
    }
    print(saved > 0 ? "Saved · \(saved) photo" + (saved > 1 ? "s" : "") : "Already saved")
}

// MARK: websave
let WEBJS = #"""
(()=>{
if((document.contentType||"").startsWith("image/"))return JSON.stringify({page:location.href,src:location.href});
const docs=[document];for(const f of document.querySelectorAll("iframe")){try{if(f.contentDocument)docs.push(f.contentDocument)}catch(e){}}
let c=[];
for(const d of docs){const w=d.defaultView,vw=w.innerWidth,vh=w.innerHeight;
 for(const i of d.images){const r=i.getBoundingClientRect();if(i.naturalWidth<150||r.width<120||r.bottom<=0||r.top>=vh||r.right<=0||r.left>=vw)continue;
  const vis=(Math.min(r.right,vw)-Math.max(r.left,0))*(Math.min(r.bottom,vh)-Math.max(r.top,0));
  let best=i.currentSrc||i.src,bw=i.naturalWidth;
  for(const [u,s] of (i.srcset||"").split(",").map(x=>x.trim().split(" ")).filter(a=>a[0])){const n=parseInt(s||0);if(n>bw){bw=n;best=u}}
  c.push({src:new URL(best,d.baseURI).href,vis:vis,dc:Math.abs((r.left+r.right)/2-vw/2)+Math.abs((r.top+r.bottom)/2-vh/2)})}}
if(!c.length)return JSON.stringify({page:location.href,src:null});
const mx=Math.max(...c.map(x=>x.vis));const big=c.filter(x=>x.vis>=mx*0.6);big.sort((a,b)=>a.dc-b.dc);
return JSON.stringify({page:location.href,src:big[0].src})})()
"""#
func websave() {
    let d = json(chromeJS(WEBJS))
    guard let src = d["src"] as? String, !src.isEmpty else { fail("이 페이지에서 사진을 못 찾았어요") }
    let page = d["page"] as? String ?? ""
    var cands: [String] = []
    if src.contains("pstatic.net") { let base = src.components(separatedBy: "?")[0]; cands += [base.replacingOccurrences(of: "postfiles.pstatic.net", with: "blogfiles.pstatic.net"), base + "?type=w3840"] }
    cands.append(src)
    var data: Data? = nil
    for u in cands { if let b = download(u, headers: ["User-Agent": "Mozilla/5.0", "Referer": page]), b.count > 5000 { data = b; break } }
    guard let data else { fail("사진을 받지 못했어요: " + String(src.prefix(100))) }
    var site = (URL(string: page)?.host ?? "web"); site = site.replacingOccurrences(of: "^(www|m)\\.", with: "", options: .regularExpression).components(separatedBy: ".")[0]
    var name = (URL(string: src)?.path as NSString?)?.lastPathComponent ?? "image"; if name.isEmpty || name == "/" { name = "image" }
    name = (name.removingPercentEncoding ?? name); name = try! NSRegularExpression(pattern: "[^\\w.가-힣-]").stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: "_")
    var stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension; if stem.isEmpty { stem = "image" }
    if ext.isEmpty { let b = [UInt8](data.prefix(12)); ext = (b.count >= 4 && b[0] == 0x89 && b[1] == 0x50) ? "png" : (b.count >= 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) ? "webp" : "jpg" }
    var dst = desktop + "/웹_\(site)_\(stem).\(ext)"; var k = 2
    while fm.fileExists(atPath: dst) { dst = desktop + "/웹_\(site)_\(stem) (\(k)).\(ext)"; k += 1 }
    try? data.write(to: URL(fileURLWithPath: dst))
    let sz = pixelSize(dst); print("저장: \((dst as NSString).lastPathComponent) (\(sz))"); print("Saved · \(sz)")
}

// MARK: psexport
func psexport() {
    let here = (CommandLine.arguments[0] as NSString).resolvingSymlinksInPath; let dir = (here as NSString).deletingLastPathComponent   // jsx·psexportui 는 같은 폴더
    let env = ProcessInfo.processInfo.environment
    func ps(_ js: String) -> String {
        let (rc, out, err) = sh(["/usr/bin/osascript", "-e", "with timeout of 7200 seconds", "-e", "tell application id \"com.adobe.Photoshop\" to do javascript " + asText(js), "-e", "end timeout"])
        if rc != 0 { print("error:" + err.trimmingCharacters(in: .whitespacesAndNewlines)); exit(0) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let running = sh(["/usr/bin/osascript", "-e", "application id \"com.adobe.Photoshop\" is running"]).1.trimmingCharacters(in: .whitespacesAndNewlines)
    if running != "true" { print("toast:포토샵이 켜져 있지 않아요"); return }
    guard let infoJS = try? String(contentsOfFile: dir + "/info.jsx", encoding: .utf8), let exportJS = try? String(contentsOfFile: dir + "/export.jsx", encoding: .utf8) else { print("error:jsx 파일이 없어요 (\(dir))"); return }
    let info = json(ps(infoJS)); let docs = info["docs"] as? [[String: Any]] ?? []
    if docs.isEmpty { print("toast:열린 문서가 없어요"); return }
    var sel: [String: Any]
    if let t = env["PSX_TEST_SEL"] { sel = json(t) } else {
        let tmp = NSTemporaryDirectory() + "psx-\(getpid()).json"; try? JSONSerialization.data(withJSONObject: info).write(to: URL(fileURLWithPath: tmp))
        let (rc, out, _) = sh([dir + "/psexportui", tmp]); try? fm.removeItem(atPath: tmp)
        let last = out.split(separator: "\n").last.map(String.init) ?? ""
        if rc != 0 || last.isEmpty { print(""); return }
        sel = json(last)
    }
    let path = sel["path"] as? String ?? desktop, folder = sel["folder"] as? String ?? ""
    let dest = env["PSX_TEST_DEST"] ?? (folder.isEmpty ? path : path + "/" + folder)
    try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
    let before = Set((try? fm.contentsOfDirectory(atPath: dest)) ?? [])
    func clean(_ s: String) -> String { let t = s.replacingOccurrences(of: "[/:\\\\]", with: "_", options: .regularExpression).trimmingCharacters(in: .whitespaces); return t.isEmpty ? "레이어" : t }
    let selDocs = Set((sel["docs"] as? [Int]) ?? []), pick = Set((sel["pick"] as? [String]) ?? [])
    let wantCur = sel["current"] as? Bool ?? false, wantOrig = sel["original"] as? Bool ?? false
    var jobs: [[String: Any]] = []
    for d in docs {
        let i = d["i"] as? Int ?? -1; guard selDocs.contains(i) else { continue }
        let layers = d["layers"] as? [String] ?? [], active = d["active"] as? Int ?? -1
        var want: [Int: String] = [:]
        if wantCur && active >= 0 { want[active] = want[active] ?? "_최종" }
        if wantOrig && !layers.isEmpty { want[layers.count - 1] = want[layers.count - 1] ?? "_원본" }
        for (k, n) in layers.enumerated() where pick.contains(n) { want[k] = want[k] ?? ("_" + clean(n)) }
        if !want.isEmpty { jobs.append(["i": i, "layers": want.keys.sorted().map { ["k": $0, "suffix": want[$0]!] }]) }
    }
    if jobs.isEmpty { print("toast:내보낼 레이어가 없어요"); return }
    let spec: [String: Any] = ["dest": dest, "jobs": jobs, "limit": (sel["kakao"] as? Bool ?? false) ? 19500000 : 0]
    let specJS = String(data: try! JSONSerialization.data(withJSONObject: spec), encoding: .utf8)!
    let out = ps("var SPEC=" + specJS + ";\n" + exportJS)
    let parts = out.components(separatedBy: "|"); let n = parts.first ?? "0", errs = parts.dropFirst().joined(separator: "|")
    func sizes() -> [String: UInt64] { var m: [String: UInt64] = [:]; for f in (try? fm.contentsOfDirectory(atPath: dest)) ?? [] where !before.contains(f) && f.lowercased().hasSuffix(".jpg") { m[f] = (try? fm.attributesOfItem(atPath: dest + "/" + f))?[.size] as? UInt64 ?? 0 }; return m }
    var last = sizes(); let t0 = Date()
    while Date().timeIntervalSince(t0) < 120 { Thread.sleep(forTimeInterval: 1); let cur = sizes(); if cur == last && cur.values.allSatisfy({ $0 > 0 }) { break }; last = cur }
    if !errs.isEmpty { print("error:\(n)개 저장, 실패: \(errs)"); return }
    print("toast:내보내기 완료 · \(n)장")
}

// MARK: main
let argv = Array(CommandLine.arguments.dropFirst())
switch argv.first ?? "" {
case "instasave": instasave(Array(argv.dropFirst()))
case "websave": websave()
case "psexport": psexport()
case "fileurl": guard argv.count > 1 else { fail("경로가 필요해요") }; print(URL(fileURLWithPath: argv[1]).absoluteString)
case "unurl": guard argv.count > 1 else { fail("URL이 필요해요") }; print((URL(string: argv[1])?.path) ?? (argv[1].removingPercentEncoding ?? argv[1]).replacingOccurrences(of: "file://", with: ""))
default: fail("사용: cctool instasave|websave|psexport|fileurl|unurl")
}
