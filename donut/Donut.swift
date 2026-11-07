// Donut: 사진을 집고 쉬프트를 누르면 도넛 메뉴가 펼쳐지고, 칸 위에 놓으면 그 자리에 변환 파일을 만든다
import AppKit
import ApplicationServices
import ImageIO
import UniformTypeIdentifiers
import Vision

// MARK: - 변환

enum Action: Int, CaseIterable {   // 5칸 균등(72°), 12시부터 시계방향: 위 AirDrop · 오른쪽 위 For Web(온라인 제출용 증명사진) · 오른쪽 아래 20MB · 왼쪽 아래 PNG · 왼쪽 위 JPG (2026-11-03 사용자 배치)
    case airdrop, web, under20, png, jpg
    static let step: CGFloat = 360 / CGFloat(Action.allCases.count)
    var title: String {
        switch self {
        case .airdrop: return "AirDrop"
        case .web: return "Product"
        case .under20: return "20MB↓"   // 카톡 전송 한도 (사용자 표기)
        case .png: return "PNG"
        case .jpg: return "JPG"
        }
    }
    var angle: CGFloat { CGFloat(rawValue) * Action.step }
}

enum Outcome {
    case made(URL, URL)   // 임시 폴더에 만든 파일, 복사해 넣을 폴더
    case failed(URL, String)
}

enum Converter {
    static let limit = 20_000_000      // 파인더가 보여 주는 20MB
    static let target = 19_500_000
    static let webEdge = 2048
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static func run(_ action: Action, source: URL, destFolder: URL?, staging: URL, webSpec: WebSpec? = nil, webHigh: Bool = false, webName: String? = nil) -> Outcome {

        let folder = destFolder ?? source.deletingLastPathComponent()
        let put = { (data: Data, name: String, ext: String) throws -> Outcome in
            .made(try save(data, folder, staging, name, ext), folder)
        }
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return .failed(source, "사진을 읽지 못함")
        }
        let meta = metadata(from: props)
        let base = source.deletingPathExtension().lastPathComponent
        do {
            switch action {
            case .airdrop: return .failed(source, "에어드롭은 변환이 아님")   // 놓기 단계에서 따로 처리됨
            case .png:
                guard let img = fullImage(src, props) else { return .failed(source, "사진을 읽지 못함") }
                let data = try encode(img, .png, nil, meta)
                return try put(data, base, "png")
            case .jpg:
                guard let img = fullImage(src, props), let flat = flatten(img) else { return .failed(source, "사진을 읽지 못함") }
                let data = try encode(flat, .jpeg, 0.92, meta)
                return try put(data, base, "jpg")
            case .web:   // Product: 규격(cm)에 맞춰 얼굴 기준으로 자름. 저화질 = 300ppi 픽셀 크기(이름_규격_web.jpg) / 고화질 = 원본 해상도 그대로(이름_규격.jpg, 실제 cm에 맞는 ppi)
                guard let img = fullImage(src, props), let flat = flatten(img) else { return .failed(source, "사진을 읽지 못함") }
                let (spec, out, dpi) = webSized(flat, want: webSpec, high: webHigh, key: source)
                var m = meta; m[kCGImagePropertyDPIWidth] = dpi; m[kCGImagePropertyDPIHeight] = dpi
                let data = try encode(out, .jpeg, webHigh ? 0.96 : 0.92, m)
                lastWebSpec = "\(spec.name) \(out.width)×\(out.height)"
                let tag = spec.name.replacingOccurrences(of: "&", with: "")
                _ = tag; return try put(data, (webName ?? (webHigh ? FileNames.current().high : FileNames.current().low)).precomposedStringWithCanonicalMapping, "jpg")   // Product: N_고화질 / N_저화질 (2026-11-05)   // 이름은 "고화질"/"저화질"만. 겹치면 save()가 "고화질 2.jpg"처럼 번호를 붙여 따로 저장 (사용자 2026-11-04)
            case .under20:
                let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
                // 이미 20MB 미만인 JPG는 다시 압축하지 않고 그대로 복사
                if size < limit, CGImageSourceGetType(src) as String? == UTType.jpeg.identifier {
                    return try put(Data(contentsOf: source), base + "_under20mb", "jpg")
                }
                guard let img = fullImage(src, props) else { return .failed(source, "사진을 읽지 못함") }
                if isTransparent(img) {
                    let data = try shrinkPNG(img, meta)
                    return try put(data, base + "_under20mb", "png")
                }
                guard let flat = flatten(img) else { return .failed(source, "사진을 읽지 못함") }
                let data = try shrinkJPEG(flat, meta)
                return try put(data, base + "_under20mb", "jpg")
            }
        } catch {
            return .failed(source, error.localizedDescription)
        }
    }

    static func shrinkJPEG(_ img: CGImage, _ meta: [CFString: Any]) throws -> Data {
        for q in [0.92, 0.85, 0.78, 0.7, 0.6] {
            let data = try encode(img, .jpeg, q, meta)
            if data.count <= target { return data }
        }
        var current = img
        for _ in 0..<8 {
            let data = try encode(current, .jpeg, 0.8, meta)
            if data.count <= target { return data }
            let k = (Double(target) / Double(data.count)).squareRoot() * 0.95
            guard let next = scaled(current, k) else { break }
            current = next
        }
        throw err("20MB 미만으로 줄이지 못함")
    }

    static func shrinkPNG(_ img: CGImage, _ meta: [CFString: Any]) throws -> Data {
        var current = img
        for _ in 0..<8 {
            let data = try encode(current, .png, nil, meta)
            if data.count <= target { return data }
            let k = (Double(target) / Double(data.count)).squareRoot() * 0.95
            guard let next = scaled(current, k) else { break }
            current = next
        }
        throw err("20MB 미만으로 줄이지 못함")
    }

    static func err(_ m: String) -> NSError {
        NSError(domain: "Donut", code: 1, userInfo: [NSLocalizedDescriptionKey: m])
    }

    static func orientation(_ props: [CFString: Any]) -> Int {
        (props[kCGImagePropertyOrientation] as? Int) ?? 1
    }

    static func pixelEdge(_ props: [CFString: Any]) -> Int {
        max((props[kCGImagePropertyPixelWidth] as? Int) ?? 0, (props[kCGImagePropertyPixelHeight] as? Int) ?? 0)
    }

    // 16비트 등 원본 깊이를 지키려고 회전이 없으면 원본 그대로 읽음
    static func fullImage(_ src: CGImageSource, _ props: [CFString: Any]) -> CGImage? {
        if orientation(props) == 1, let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        return sized(src, props, pixelEdge(props))
    }

    static func sized(_ src: CGImageSource, _ props: [CFString: Any], _ edge: Int) -> CGImage? {
        let full = pixelEdge(props)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: full > 0 ? min(edge, full) : edge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func hasAlpha(_ img: CGImage) -> Bool {
        switch img.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    static func isTransparent(_ img: CGImage) -> Bool {
        guard hasAlpha(img),
              let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        guard let p = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        for y in 0..<img.height {
            let row = p + y * ctx.bytesPerRow
            for x in 0..<img.width where row[x * 4 + 3] < 255 { return true }
        }
        return false
    }

    // sRGB 8비트로 바꾸고 투명한 곳은 흰색으로 채움
    static func flatten(_ img: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(r)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: r)
        return ctx.makeImage()
    }

    // 증명사진 규격 (cm) → 300ppi 픽셀. 세로형 기준이고 가로 사진은 뒤집어 맞춤
    struct WebSpec { let name: String; let w: Double; let h: Double; var headCm: Double = 0; var topCm: Double = 0   // headCm>0 이면 얼굴 인식으로 정수리~턱 길이를 맞춰 자름
        var px: (Int, Int) { (Int((w / 2.54 * 300).rounded()), Int((h / 2.54 * 300).rounded())) }
        var size: String { "\(fmt(w))×\(fmt(h))cm" }
        var detail: String { headCm > 0 ? "\(size)  |  여백 \(fmt(topCm))cm  얼굴크기 \(fmt(headCm))cm" : size }   // 목록에 표시 (2026-11-04)
        func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) } }
    static func cmPx(_ cm: Double) -> Double { cm / 2.54 * 300 }
    static var webSpecs: [WebSpec] { let o = ySettings.specs(specSide); return baseSpecs.map { var w = $0; if let v = o[w.name], v.count == 2 { w.headCm = v[0]; w.topCm = v[1] }; return w } }   // 설정 › 규격 기본값 (데스크톱·포토샵 따로)
    static let baseSpecs: [WebSpec] = [   // 기본값. 사용자 지정 2026-11-03: 규격 / 위 여백 / 정수리~턱
        WebSpec(name: "증명", w: 3.5, h: 4.5, headCm: 2.6, topCm: 0.25),   // 얼굴 2.5→2.6 (사용자 2026-11-04 두 번째)   // 얼굴 2.6→2.5 (사용자 2026-11-04)
        WebSpec(name: "반명함", w: 3, h: 4, headCm: 2.4, topCm: 0.25),   // 얼굴 2.0→2.3 (11-06) → 2.4 (사용자 2026-11-07)   // 여권과 순서 바꿈 (사용자 2026-11-04)
        WebSpec(name: "여권", w: 3.5, h: 4.5, headCm: 3.3, topCm: 0.2),
        WebSpec(name: "미국비자", w: 5, h: 5, headCm: 3.0, topCm: 0.35),
        WebSpec(name: "중국비자", w: 3.3, h: 4.8, headCm: 3.0, topCm: 0.4),
        WebSpec(name: "명함", w: 5, h: 7, headCm: 3.3, topCm: 0.5)]   // 이름 명함&캐나다여권 → 명함 (사용자 2026-11-05)
    static let customBase = WebSpec(name: "Custom", w: 3.5, h: 4.5, headCm: 2.6, topCm: 0.25)   // Custom 처음 값 (설정 › 기본 › 규격에서 바꿈: deskSpecs["Custom"] = [얼굴, 여백, 가로, 세로])
    static func baseOf(_ n: String) -> WebSpec { n == "Custom" ? customBase : (baseSpecs.first { $0.name == n } ?? baseSpecs[0]) }
    static func customStart(_ s: YSettings) -> WebSpec { let o = s.deskSpecs["Custom"] ?? [], b = customBase
        guard o.count == 4 else { return b }; return WebSpec(name: "Custom", w: min(7, max(2, o[2])), h: min(9, max(2.5, o[3])), headCm: o[0], topCm: o[1]) }
    static var lastWebSpec = ""
    // 얼굴 인식: 정수리(사람 영역 맨 위)와 턱(얼굴 윤곽 맨 아래)의 픽셀 y (위에서부터), 얼굴 가운데 x. 못 찾으면 nil
    static let visionLock = NSLock()   // Vision은 한 번에 하나만: 고화질+저화질 두 작업이 동시에 돌리다 Vision 안에서 충돌(2026-11-03 SIGSEGV, VNGeneratePersonSegmentation)
    static var headCache: [String: (crown: Double, chin: Double, cx: Double)?] = [:]   // 같은 사진(경로+수정시각)은 한 번만 인식 → 고화질·저화질·미리보기가 같은 결과를 씀. 값은 0~1 비율(어느 크기의 그림에도 맞음)
    static let testFace: String = FileManager.default.temporaryDirectory.appendingPathComponent("ydot_test_sample.jpg").path   // 테스트 'sample' 회색 인물 그림 경로 (고정 · 여러 줄에서 읽어도 안전) → 얼굴 인식 없이 아래 자리 (0~1)
    static let testFaceVal = (crown: 0.19, chin: 0.52, cx: 0.5)
    static func headLine(_ img: CGImage, key: URL? = nil) -> (crown: Double, chin: Double, cx: Double)? {
        visionLock.lock(); defer { visionLock.unlock() }
        let W = Double(img.width), H = Double(img.height)
        if key?.path == testFace { return (testFaceVal.crown * H, testFaceVal.chin * H, testFaceVal.cx * W) }   // 테스트 '샘플 없음' 그림: 정해 둔 자리
        let k = key.map { $0.path + "|" + String(describing: (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date) ?? .distantPast) }
        if let k = k, let c = headCache[k] { return c.map { ($0.crown * H, $0.chin * H, $0.cx * W) } }
        let r = headLine0(img); if let k = k { if headCache.count > 200 { headCache.removeAll() }; headCache[k] = r.map { ($0.crown / H, $0.chin / H, $0.cx / W) } }
        return r
    }
    static func faceCount(_ img: CGImage) -> Int {   // Product 시작 전 확인: 얼굴 수 (정확히 1개일 때만 진행)
        visionLock.lock(); defer { visionLock.unlock() }
        let r = VNDetectFaceRectanglesRequest(); try? VNImageRequestHandler(cgImage: img, options: [:]).perform([r])
        return r.results?.count ?? 0
    }
    static func cropRect(_ img: CGImage, _ spec: WebSpec) -> CGRect? {   // 포토샵 가이드용: 변환(webSized)과 같은 식으로 자를 자리 (원본 픽셀, 위 기준). 얼굴 못 찾으면 nil
        guard img.height >= img.width, let hl = headLine(img) else { return nil }
        let (tw, th) = spec.px, k = cmPx(spec.headCm) / (hl.chin - hl.crown), cw = Double(tw) / k, ch = Double(th) / k
        var x = hl.cx - cw / 2, y = hl.crown - cmPx(spec.topCm) / k
        x = min(max(0, x), Double(img.width) - cw); y = min(max(0, y), Double(img.height) - ch)
        return CGRect(x: x, y: y, width: cw, height: ch)
    }
    static func psCheck(_ u: URL) -> (CGImage?, String?) {   // 포토샵 연동 공통 확인: 세로 · 얼굴 1개 · 정수리·턱
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any], let b = fullImage(src, props) else { return (nil, "사진을 읽지 못했어요.") }   // 사진 방향(EXIF) 반영
        if b.width > b.height { return (b, "가로 사진이에요. 세로 사진만 쓸 수 있어요.") }
        let n = faceCount(b); if n == 0 { return (b, "얼굴을 찾지 못했어요.") }; if n > 1 { return (b, "얼굴이 \(n)개 있어요. 한 사람만 나온 사진이어야 해요.") }
        if headLine(b) == nil { return (b, "정수리와 턱 위치를 찾지 못했어요.") }
        return (b, nil)
    }
    static func writeResult(_ path: String, _ kv: [(String, String)]) {   // 포토샵 스크립트가 읽는 결과 (한 줄에 키=값, UTF-8)
        let ys = ySettings, st = Sheet.style(ys), kv = kv + [("psFile", ys.psFile ? "1" : "0"), ("psPS", ys.psPS ? "1" : "0"),
            ("logoFile", st.logo), ("nOriginal", ys.fileName("original")), ("nCrop", ys.fileName("crop")), ("nHigh", ys.fileName("high")), ("nLow", ys.fileName("low")), ("nSheet", ys.fileName("sheet")), ("polStrip", String(st.strip)), ("logoH", String(st.logoH)), ("logoMargin", String(st.margin)), ("logoAlign", st.align)]   // 설정 › 시그니처 → YDOT.customSheet   // 설정 › 인화지 출력 (포토샵) → 인화 스크립트가 따름
        let text = kv.map { $0.0 + "=" + $0.1.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n") + "\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }
    static func warmUp() {   // 켤 때 뒤에서 한 번: 비전 모델을 미리 불러 둬 첫 변환·미리보기가 0.5~1초 늦지 않게
        guard let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let img = ctx.makeImage() else { return }
        _ = headLine(img)
    }
    static func headLine0(_ img0: CGImage) -> (crown: Double, chin: Double, cx: Double)? {
        var img = img0   // 인식은 긴 변 1600px로 줄여서 (비전 결과는 0~1 좌표라 정확도 차이 없이 몇 배 빠름, 메모리도 적게)
        let long = max(img0.width, img0.height)
        if long > 1600 { let k = 1600.0 / Double(long), w = Int(Double(img0.width) * k), h = Int(Double(img0.height) * k)
            if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) { ctx.interpolationQuality = .medium; ctx.draw(img0, in: CGRect(x: 0, y: 0, width: w, height: h)); img = ctx.makeImage() ?? img0 } }
        let lm = VNDetectFaceLandmarksRequest(); let seg = VNGeneratePersonSegmentationRequest(); seg.qualityLevel = .accurate; seg.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let h = VNImageRequestHandler(cgImage: img, options: [:])
        try? h.perform([lm, seg])
        guard let face = lm.results?.first else { return nil }
        let W = Double(img0.width), H = Double(img0.height), b = face.boundingBox   // 비전 좌표: 왼쪽 아래 원점, 0~1 → 원본 픽셀로
        var chinY = (1 - b.minY) * H   // 기본: 얼굴 상자 아래
        if let pts = face.landmarks?.faceContour?.normalizedPoints, let low = pts.min(by: { $0.y < $1.y }) { chinY = (1 - (b.minY + Double(low.y) * b.height)) * H }
        let cx = (b.midX) * W
        var crownY = (1 - b.maxY) * H - b.height * H * 0.45   // 기본 추정: 얼굴 상자 위 + 45%
        if let mask = seg.results?.first?.pixelBuffer {   // 사람 영역 맨 위 = 머리 꼭대기 (얼굴 가운데 좌우 ±얼굴폭 0.6 안에서)
            CVPixelBufferLockBaseAddress(mask, .readOnly); defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
            let mw = CVPixelBufferGetWidth(mask), mh = CVPixelBufferGetHeight(mask), bpr = CVPixelBufferGetBytesPerRow(mask), base = CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: UInt8.self)
            let x0 = max(0, Int((b.midX - b.width * 0.6) * Double(mw))), x1 = min(mw - 1, Int((b.midX + b.width * 0.6) * Double(mw)))
            outer: for y in 0..<mh { for x in stride(from: x0, through: x1, by: 2) where base[y * bpr + x] > 128 { crownY = Double(y) / Double(mh) * H; break outer } }
        }
        guard chinY > crownY + 10 else { return nil }
        return (crownY, chinY, cx)
    }
    static func webSized(_ img: CGImage, want: WebSpec? = nil, high: Bool = false, key: URL? = nil) -> (WebSpec, CGImage, Int) {
        let landscape = img.width > img.height
        let r = Double(min(img.width, img.height)) / Double(max(img.width, img.height))   // 짧은 변/긴 변
        let spec = want ?? webSpecs.min { abs($0.w / $0.h - r) < abs($1.w / $1.h - r) }!   // 목록에서 고른 규격, 아니면 비율이 가장 가까운 규격 (같은 비율이면 앞 것 = 증명)
        var (tw, th) = spec.px; if landscape { swap(&tw, &th) }
        var crop: CGRect
        if spec.headCm > 0, !landscape, let hl = headLine(img, key: key) {   // 얼굴 기준: 정수리~턱 = headCm, 위 여백 = topCm, 얼굴 가운데 정렬
            let k = cmPx(spec.headCm) / (hl.chin - hl.crown)   // 300ppi 결과 px / 원본 px
            let cw = Double(tw) / k, ch = Double(th) / k
            var x = hl.cx - cw / 2, y = hl.crown - cmPx(spec.topCm) / k
            x = min(max(0, x), Double(img.width) - cw); y = min(max(0, y), Double(img.height) - ch)   // 사진 밖으로 나가면 안쪽으로
            crop = CGRect(x: x, y: y, width: cw, height: ch)
            if cw > Double(img.width) || ch > Double(img.height) { crop = ratioCrop(img, tw, th) }   // 사진이 작아 규격이 안 나오면 비율로
        } else { crop = ratioCrop(img, tw, th) }
        guard let c = img.cropping(to: crop) else { return (spec, img, 300) }
        if high {   // 고화질: 자른 영역을 원본 해상도 그대로 (실제 cm에 맞는 ppi 정보)
            let dpi = Int((Double(c.width) / ((landscape ? spec.h : spec.w) / 2.54)).rounded())
            return (spec, c, max(72, dpi))
        }
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return (spec, c, 300) }
        ctx.interpolationQuality = .high; ctx.draw(c, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return (spec, ctx.makeImage() ?? c, 300)
    }
    // 조절 화면 미리보기: 원본 밖으로 나가도 그대로 자르고 밖은 검정 (끄는 동안 보여 주기용, 저장엔 안 씀) (2026-11-05)
    static func faceCropRect(_ img: CGImage, _ sp: WebSpec, key: URL?) -> CGRect? {   // faceCropAny와 같은 자리 (원본 px, 위 기준) — 규격 탭 큰 사진이 같은 사진에서 '창'만 옮기게
        guard let hl = headLine(img, key: key) else { return nil }
        let k = cmPx(sp.headCm) / (hl.chin - hl.crown), cw = cmPx(sp.w) / k, ch = cmPx(sp.h) / k
        return CGRect(x: hl.cx - cw / 2, y: hl.crown - cmPx(sp.topCm) / k, width: cw, height: ch) }
    static func faceCropAny(_ img: CGImage, _ sp: WebSpec, key: URL?, outH: Int) -> CGImage? {
        guard let hl = headLine(img, key: key) else { return nil }
        let k = cmPx(sp.headCm) / (hl.chin - hl.crown), cw = cmPx(sp.w) / k, ch = cmPx(sp.h) / k
        let x = hl.cx - cw / 2, y = hl.crown - cmPx(sp.topCm) / k
        let oh = outH, ow = max(1, Int((Double(oh) * sp.w / sp.h).rounded())), sc = Double(oh) / ch
        guard let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: ow, height: oh)); ctx.interpolationQuality = .high
        let W = Double(img.width), H = Double(img.height)
        ctx.draw(img, in: CGRect(x: -x * sc, y: Double(oh) + y * sc - H * sc, width: W * sc, height: H * sc))
        return ctx.makeImage()
    }
    // 원본 사진 한계: 얼굴 최소(좌우 폭·아래 끝·위 여백) · 위 여백 최소~최대. 얼굴과 여백은 서로 엮임
    static func faceLimits(_ W: Double, _ H: Double, _ hl: (crown: Double, chin: Double, cx: Double), _ sp: WebSpec, _ f: Double, _ m: Double) -> (fLo: Double, mLo: Double, mHi: Double) {
        let face = hl.chin - hl.crown, half = max(1, min(hl.cx, W - hl.cx))
        let fLo = max(sp.w * face / (2 * half), face * (sp.h - m) / max(1, H - hl.crown), hl.crown > 0 ? face * m / hl.crown : 0)
        let mLo = max(-0.5, sp.h - (H - hl.crown) * f / face), mHi = hl.crown * f / face   // 위 여백은 -0.5까지 (정수리가 조금 잘림, 사용자 2026-11-05)
        return ((fLo * 100).rounded(.up) / 100, (mLo * 100).rounded(.up) / 100, (mHi * 100).rounded(.down) / 100)
    }
    static func ratioCrop(_ img: CGImage, _ tw: Int, _ th: Int) -> CGRect {   // 비율만 맞춰 가운데 자르기 (늘리지 않음)
        let sx = Double(tw) / Double(img.width), sy = Double(th) / Double(img.height), k = max(sx, sy)
        let cw = Double(tw) / k, ch = Double(th) / k
        return CGRect(x: (Double(img.width) - cw) / 2, y: (Double(img.height) - ch) / 2, width: cw, height: ch)
    }
    static func scaled(_ img: CGImage, _ k: Double) -> CGImage? {
        let w = max(1, Int(Double(img.width) * k)), h = max(1, Int(Double(img.height) * k))
        let alpha = hasAlpha(img)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                  bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // 촬영 정보는 유지하고, 회전은 이미 적용했으므로 정방향으로 표시
    static func metadata(from p: [CFString: Any]) -> [CFString: Any] {
        var out: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if var tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            out[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            out[kCGImagePropertyExifDictionary] = exif
        }
        for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            if let d = p[key] { out[key] = d }
        }
        return out
    }

    // 다시 압축하지 않고 해상도(ppi) 정보만 바꿔 저장 (CGImageDestinationCopyImageSource: 화질 손실 없음)
    static func rewriteDPI(_ src: CGImageSource, _ type: UTType, _ dpi: Int) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw err("저장 형식을 만들지 못함") }
        let md = CGImageMetadataCreateMutable()
        for (ns, prefix, tag, v) in [(kCGImageMetadataNamespaceTIFF, kCGImageMetadataPrefixTIFF, "XResolution", "\(dpi)/1"), (kCGImageMetadataNamespaceTIFF, kCGImageMetadataPrefixTIFF, "YResolution", "\(dpi)/1"), (kCGImageMetadataNamespaceTIFF, kCGImageMetadataPrefixTIFF, "ResolutionUnit", "2")] {
            if let t = CGImageMetadataTagCreate(ns, prefix, tag as CFString, .string, v as CFString) { CGImageMetadataSetTagWithPath(md, nil, (String(prefix) + ":" + tag) as CFString, t) }
        }
        let opts: [CFString: Any] = [kCGImageDestinationMetadata: md, kCGImageDestinationMergeMetadata: true]   // DPI 키를 여기 넣으면 다시 압축함 → 메타데이터만
        var e: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, &e) else { throw err("해상도 정보를 쓰지 못함") }
        return data as Data
    }
    static func encode(_ img: CGImage, _ type: UTType, _ quality: Double?, _ meta: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw err("저장 형식을 만들지 못함") }
        var props = meta
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw err("저장하지 못함") }
        return data as Data
    }

    // 놓을 폴더에 같은 이름이 있으면 '이름 2.jpg'처럼 번호를 붙이고, 덮어쓰지 않음
    static func save(_ data: Data, _ folder: URL, _ staging: URL, _ base: String, _ ext: String) throws -> URL {
        var n = 1
        while true {
            let name = n == 1 ? "\(base).\(ext)" : "\(base) \(n).\(ext)"
            let url = staging.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
                n += 1
                continue
            }
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                n += 1
            }
        }
    }
}

// MARK: - 놓을 자리 찾기

struct DropTarget {
    var folder: URL?             // nil = 원본 옆
    var desktopPoint: CGPoint?   // 데스크톱이면 그 자리
    var note: String?
}

struct Spot {
    enum Kind {
        case unknown
        case otherApp(String)
        case desktop(pid_t)
        case finderWindow(pid_t, CGRect, Int)
    }
    var point: CGPoint
    var kind: Kind
}

enum Locator {
    static func cgPoint(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - p.y)
    }

    // 파인더는 끌기 중에 질문을 받으면 끌기가 끝날 때까지 답하지 않음.
    // 그래서 도넛을 열 때는 창 정보만 기억하고, 폴더는 놓은 뒤에 물어봄
    static func snapshot(at screenPoint: NSPoint) -> Spot {
        let pt = cgPoint(screenPoint)
        let me = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return Spot(point: pt, kind: .unknown)
        }
        for w in list {
            let pid = (w[kCGWindowOwnerPID as String] as? pid_t) ?? 0
            let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1
            if pid == me || layer > 0 || alpha == 0 { continue }
            guard let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bd), rect.contains(pt) else { continue }
            let isFinder = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
            if !isFinder {
                if layer < 0 { continue }
                return Spot(point: pt, kind: .otherApp((w[kCGWindowOwnerName as String] as? String) ?? ""))
            }
            if layer < 0 { return Spot(point: pt, kind: .desktop(pid)) }
            return Spot(point: pt, kind: .finderWindow(pid, rect, (w[kCGWindowNumber as String] as? Int) ?? 0))
        }
        return Spot(point: pt, kind: .unknown)
    }

    static func resolve(_ spot: Spot) -> DropTarget {
        switch spot.kind {
        case .unknown:
            return DropTarget(note: "원본 옆에 저장")
        case .otherApp(let owner):
            return DropTarget(note: "\(owner)에는 바로 못 넣어 원본 옆에 저장")
        case .desktop(let pid):
            // 자동 시험 때는 실제 데스크톱 대신 시험 폴더에 저장
            if let test = ProcessInfo.processInfo.environment["DONUT_TEST_DESKTOP"] {
                return DropTarget(folder: URL(fileURLWithPath: test))
            }
            if let icon = folderIcon(at: spot.point, pid: pid) { return DropTarget(folder: icon) }
            let desk = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            return DropTarget(folder: desk, desktopPoint: spot.point)
        case .finderWindow(let pid, let rect, let id):
            if let icon = folderIcon(at: spot.point, pid: pid) { return DropTarget(folder: icon) }
            if let f = finderFolder(pid: pid, rect: rect, windowID: id) { return DropTarget(folder: f) }
            return DropTarget(note: "파인더 창 폴더를 못 찾아 원본 옆에 저장")
        }
    }

    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        AXUIElementSetMessagingTimeout(el, 2)
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    static func url(from v: AnyObject?) -> URL? {
        if let u = v as? URL { return u }
        if let s = v as? String { return s.hasPrefix("/") ? URL(fileURLWithPath: s) : URL(string: s) }
        return nil
    }

    static func isFolder(_ u: URL) -> Bool {
        let r = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return r?.isDirectory == true && r?.isPackage != true
    }

    // 커서 아래 항목이 폴더 아이콘이면 그 폴더
    static func folderIcon(at pt: CGPoint, pid: pid_t) -> URL? {
        var el: AXUIElement?
        let finder = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(finder, 2)
        guard AXUIElementCopyElementAtPosition(finder, Float(pt.x), Float(pt.y), &el) == .success, var cur = el else { return nil }
        for _ in 0..<3 {
            let role = attr(cur, kAXRoleAttribute) as? String
            if role == kAXWindowRole || role == kAXScrollAreaRole { return nil }
            if let u = url(from: attr(cur, kAXURLAttribute) ?? attr(cur, kAXFilenameAttribute)) {
                return isFolder(u) ? u : nil
            }
            guard let parent = attr(cur, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            cur = parent as! AXUIElement
        }
        return nil
    }

    static func finderFolder(pid: pid_t, rect: CGRect, windowID: Int) -> URL? {
        let app = AXUIElementCreateApplication(pid)
        if let wins = attr(app, kAXWindowsAttribute) as? [AXUIElement] {
            for w in wins {
                var pos = CGPoint.zero, size = CGSize.zero
                guard let pv = attr(w, kAXPositionAttribute), let sv = attr(w, kAXSizeAttribute) else { continue }
                AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
                AXValueGetValue(sv as! AXValue, .cgSize, &size)
                if abs(pos.x - rect.minX) < 2, abs(pos.y - rect.minY) < 2, abs(size.width - rect.width) < 2,
                   let u = url(from: attr(w, kAXDocumentAttribute)), isFolder(u) { return u }
            }
        }
        let script = "tell application \"Finder\" to get POSIX path of (target of window id \(windowID) as alias)"
        return DispatchQueue.main.sync {
            var error: NSDictionary?
            if let path = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
    }

    static func placeOnDesktop(_ urls: [URL], at pt: CGPoint) {
        for (i, u) in urls.enumerated() {
            let path = u.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let x = Int(pt.x) + i * 24, y = Int(pt.y) + i * 24
            let script = "tell application \"Finder\" to set desktop position of (POSIX file \"\(path)\" as alias) to {\(x), \(y)}"
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }
}

// MARK: - 파인더로 복사

enum FinderCopy {
    static let script = """
    on run argv
        set dest to POSIX file (item 1 of argv) as alias
        set theFiles to {}
        repeat with i from 2 to count of argv
            set end of theFiles to POSIX file (item i of argv) as alias
        end repeat
        tell application "Finder" to duplicate theFiles to dest
    end run
    """

    // 파인더에게 복사를 맡겨야 파인더의 복사 소리가 그대로 남.
    // 파인더는 끌기 중에 답하지 않으므로 osascript로 따로 띄워 앱이 멈추지 않게 함
    static func run(_ files: [URL], to folder: URL, retries: Int = 1, done: @escaping ([URL], [String]) -> Void) {
        let settle = { settleCopies(files, folder, retries, done) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script, folder.path] + files.map(\.path)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { debugLog("파인더 복사 끝 \($0.terminationStatus)"); settle() }
        do { try p.run() } catch {
            DispatchQueue.global(qos: .userInitiated).async(execute: settle)
        }
    }

    // 파인더는 이름이 겹치면 그 파일만 빼고 복사하므로 내용까지 비교해서 실제로 복사됐는지 확인함.
    // 남은 파일은 다음 번호로 파인더에게 한 번 더 맡기고, 그래도 안 되면 소리 없이 직접 복사
    static func settleCopies(_ files: [URL], _ folder: URL, _ retries: Int, _ done: @escaping ([URL], [String]) -> Void) {
        let fm = FileManager.default
        var made: [URL] = [], left: [URL] = []
        for f in files {
            let to = folder.appendingPathComponent(f.lastPathComponent)
            if fm.contentsEqual(atPath: f.path, andPath: to.path) { made.append(to) } else { left.append(f) }
        }
        guard !left.isEmpty else { return done(made, []) }
        var renamed: [URL] = [], failed: [String] = []
        for f in left {
            do { renamed.append(try freeName(f, in: folder)) } catch {
                failed.append("\(f.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if retries > 0, !renamed.isEmpty {
            debugLog("다시 복사 \(renamed.map(\.lastPathComponent))")
            run(renamed, to: folder, retries: retries - 1) { m, f in done(made + m, failed + f) }
            return
        }
        for f in renamed {
            let to = folder.appendingPathComponent(f.lastPathComponent)
            debugLog("직접 복사 \(f.lastPathComponent)")
            do {
                try fm.copyItem(at: f, to: to)
                made.append(to)
            } catch {
                failed.append("\(f.lastPathComponent): \(error.localizedDescription)")
            }
        }
        done(made, failed)
    }

    // 놓을 폴더에 같은 이름이 있으면 임시 파일 이름을 다음 번호로 바꿈
    static func freeName(_ file: URL, in folder: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent(file.lastPathComponent).path) else { return file }
        let ext = file.pathExtension
        var stem = file.deletingPathExtension().lastPathComponent, n = 2
        if let r = stem.range(of: " [0-9]+$", options: .regularExpression), let old = Int(stem[r].dropFirst()) {
            n = old + 1
            stem.removeSubrange(r)
        }
        while true {
            let name = "\(stem) \(n).\(ext)"
            let to = file.deletingLastPathComponent().appendingPathComponent(name)
            if !fm.fileExists(atPath: folder.appendingPathComponent(name).path), !fm.fileExists(atPath: to.path) {
                try fm.moveItem(at: file, to: to)
                return to
            }
            n += 1
        }
    }
}

// MARK: - 도넛 그림

let donutSize: CGFloat = 380   // 웹 시연(ring8.html)과 같은 크기
let outerR: CGFloat = 182, innerR: CGFloat = 60, holeR: CGFloat = 60   // 웹 시연 수치. 구멍 = 안쪽 반지름 → 빈 띠 없음
let gapDeg: CGFloat = 0, cornerR: CGFloat = 0.01, popOut: CGFloat = 0   // 웹 시연(ring8.html, 크롬 화면) 그대로: 칸 사이 선 없는 매끈한 원판 (2026-11-03)
// 맥 네이티브 모양 (2026-11-03 시안 A): 밝은 팝오버 유리 + SF 심볼 + 선택 칸은 시스템 강조색
let coral = NSColor(srgbRed: 0.37, green: 0.62, blue: 1.0, alpha: 1)   // 선택색: 맥 느낌의 파랑 (#5e9eff, 2026-11-04 조금 더 진하게). 이름은 예전 그대로 coral
let selectedFill = coral.withAlphaComponent(0.85).cgColor   // 선택 칸: 옆 칸까지 부드럽게 번짐
let bladeFill = NSColor.clear.cgColor   // 칸은 투명 (원판 한 장으로 칠해 칸 경계선이 안 생김)
let discFill = NSColor(white: 1, alpha: CGFloat(Double(ProcessInfo.processInfo.environment["DONUT_BLADE"] ?? "0.20")!)).cgColor
let ringMaterial: NSVisualEffectView.Material = { switch ProcessInfo.processInfo.environment["DONUT_MATERIAL"] ?? "popover" { case "hud": return .hudWindow; case "menu": return .menu; case "selection": return .selection; case "sheet": return .sheet; case "fullscreen": return .fullScreenUI; case "tooltip": return .toolTip; case "underwin": return .underWindowBackground; case "sidebar": return .sidebar; case "titlebar": return .titlebar; default: return .popover } }()
let rimColor = NSColor(white: 0, alpha: 0.13).cgColor
let textDark = NSColor(white: 0.12, alpha: 1)
func discMaskImage() -> NSImage {   // 가운데 불투명 → 가장자리 14px 서서히 투명 (선 없는 원판)
    NSImage(size: NSSize(width: donutSize, height: donutSize), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillEllipse(in: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2)); return true } }   // 또렷한 원 (바깥 경계선 없음, 그라데이션 없음 — 웹 시연처럼)
var symbolCache: [String: CGImage] = [:]   // 칸을 오갈 때마다 심볼을 다시 그리지 않게
func symbolImage(_ name: String, _ pt: CGFloat, _ color: NSColor) -> CGImage? {   // SF 심볼을 색 입혀 CALayer contents로
    let key = "\(name)|\(pt)|\(color.description)"; if let c = symbolCache[key] { return c }
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: pt, weight: .regular)) else { return nil }
    let img = NSImage(size: base.size, flipped: false) { r in base.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
    let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil); if let cg { symbolCache[key] = cg }; return cg }
extension Action { var symbol: String { switch self { case .airdrop: return "dot.radiowaves.left.and.right"; case .png: return "photo"; case .web: return "globe"; case .jpg: return "doc.richtext"; case .under20: return "bubble.fill" } } }   // 20MB↓ = 카톡 말풍선
let center = CGPoint(x: donutSize / 2, y: donutSize / 2)

func polar(_ radius: CGFloat, _ deg: CGFloat) -> CGPoint {   // 0도 = 위, 시계방향
    let t = deg * .pi / 180
    return CGPoint(x: center.x + radius * sin(t), y: center.y + radius * cos(t))
}

func bladePath() -> CGPath {
    let a0 = -Action.step / 2 + gapDeg, a1 = Action.step / 2 - gapDeg
    let dO = cornerR / outerR * 180 / .pi, dI = cornerR / innerR * 180 / .pi
    let math = { (deg: CGFloat) in (90 - deg) * .pi / 180 }
    let p = CGMutablePath()
    p.move(to: polar(outerR - cornerR, a0))
    p.addQuadCurve(to: polar(outerR, a0 + dO), control: polar(outerR, a0))
    p.addArc(center: center, radius: outerR, startAngle: math(a0 + dO), endAngle: math(a1 - dO), clockwise: true)
    p.addQuadCurve(to: polar(outerR - cornerR, a1), control: polar(outerR, a1))
    p.addLine(to: polar(innerR + cornerR, a1))
    p.addQuadCurve(to: polar(innerR, a1 - dI), control: polar(innerR, a1))
    p.addArc(center: center, radius: innerR, startAngle: math(a1 - dI), endAngle: math(a0 + dI), clockwise: false)
    p.addQuadCurve(to: polar(innerR + cornerR, a0), control: polar(innerR, a0))
    p.closeSubpath()
    return p
}

// 선택 칸 번짐 그림: 한 번만 미리 그려 두고(칸 모양을 파랑으로 칠해 20px·60px 블러를 겹침) 칸마다 투명도만 바꿈
// → 매 프레임 CIFilter 블러를 돌리던 것보다 훨씬 가볍고, 색이 clear(검정 투명)로 보간되며 생기던 검은 그림자도 없음 (2026-11-04)
let glowPad: CGFloat = 150   // 60px 블러가 칸 밖으로 번지는 여유
let glowImage: CGImage? = {
    let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2, size = donutSize + 2 * glowPad, W = Int(size * scale)
    guard let ctx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: glowPad, y: glowPad)
    ctx.addPath(bladePath()); ctx.setFillColor(coral.cgColor); ctx.fillPath()
    guard let shape = ctx.makeImage() else { return nil }
    let ci = CIImage(cgImage: shape)
    func blur(_ r: CGFloat, _ alpha: CGFloat) -> CIImage {
        ci.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)]).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: r * scale]).cropped(to: ci.extent) }
    let out = blur(20, 0.95).composited(over: blur(60, 0.8))   // 안쪽 또렷한 번짐 + 바깥 넓은 번짐 (전과 같은 구성)
    return CIContext(options: [.cacheIntermediates: false]).createCGImage(out, from: ci.extent)
}()
final class BladeLayer: CALayer {
    let fill = CAShapeLayer(), glow = CALayer()
    override init() {
        super.init()
        let path = bladePath(), box = CGRect(x: 0, y: 0, width: donutSize, height: donutSize)
        bounds = box; position = center
        fill.frame = box; fill.path = path; fill.fillColor = bladeFill
        glow.frame = box.insetBy(dx: -glowPad, dy: -glowPad); glow.contents = glowImage; glow.contentsScale = NSScreen.main?.backingScaleFactor ?? 2; glow.opacity = 0
        addSublayer(fill); addSublayer(glow)
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }
    func setOn(_ on: Bool) {
        zPosition = on ? 10 : 0   // 선택 칸을 맨 위로 → 번짐이 옆 칸 위로 퍼짐
        CATransaction.begin(); CATransaction.setAnimationDuration(0.12); CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1))   // 웹 시연(.wedge transition .12s)과 같게
        glow.opacity = on ? 1 : 0
        CATransaction.commit()
    }
}

final class DonutView: NSView {
    weak var controller: Controller?
    let effect = NSVisualEffectView()
    let content = CALayer()
    var blades: [BladeLayer] = []
    var labels: [CATextLayer] = [], icons: [CALayer] = []
    var shadeLayer: CAGradientLayer?
    let hole = CAShapeLayer(), holeText = CATextLayer(), holeLogo = CATextLayer(), catcher = CAShapeLayer()   // 가운데: 로고 층과 칸 이름 층을 따로 두고 투명도만 바꿈 (크기를 바꾸면 옛 글자가 한 프레임 튀어 보임, 2026-11-04)
    var selected: Action?
    var s: CGFloat = 0
    let bladeShape = bladePath()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        effect.frame = bounds
        effect.material = ringMaterial
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .aqua)
        addSubview(effect)
        let host = NSView(frame: bounds)
        host.wantsLayer = true
        addSubview(host)
        host.layer?.addSublayer(content)
        content.frame = bounds
        let clip = CALayer(); clip.frame = bounds; clip.contents = discMaskImage(); clip.contentsScale = NSScreen.main?.backingScaleFactor ?? 2; content.mask = clip   // 가장자리로 갈수록 서서히 사라짐 (선 없음)

        // 칸 사이 틈에 놓아도 파인더로 빠지지 않게 원판 전체를 아주 옅게 채움
        catcher.frame = bounds
        catcher.path = CGPath(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2), transform: nil)
        catcher.fillColor = NSColor(white: 1, alpha: 0.004).cgColor
        content.addSublayer(catcher)
        let disc = CAShapeLayer(); disc.frame = bounds; disc.path = CGPath(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2), transform: nil); disc.fillColor = discFill
        content.addSublayer(disc)   // 유리 위 옅은 흰 한 장 (웹 시연의 흰 35%)

        for _ in Action.allCases { blades.append(BladeLayer()) }
        for b in blades.reversed() { content.addSublayer(b) }   // PNG 칸이 맨 위로

        let holeRect = CGRect(x: center.x - holeR, y: center.y - holeR, width: holeR * 2, height: holeR * 2)
        hole.frame = bounds; hole.zPosition = 20   // 구멍·글자·아이콘은 번지는 선택 칸보다 위
        hole.path = CGPath(ellipseIn: holeRect, transform: nil)
        hole.fillColor = NSColor(white: 1, alpha: 0.55).cgColor   // 웹 시연: 흰 55% + 회색 경계선
        hole.strokeColor = NSColor(white: 0, alpha: 0.13).cgColor
        hole.lineWidth = 1
        content.addSublayer(hole)

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for l in [holeText, holeLogo] { l.contentsScale = scale; l.zPosition = 21; l.alignmentMode = .center; l.isWrapped = false; l.truncationMode = .end }
        holeText.bounds = CGRect(x: 0, y: 0, width: holeR * 2 - 8, height: 20); holeText.position = center   // 크기 고정 → 글자만 바뀜
        holeLogo.bounds = CGRect(x: 0, y: 0, width: holeR * 2 - 8, height: 38); holeLogo.position = CGPoint(x: center.x, y: center.y + 2)
        holeLogo.string = NSAttributedString(string: "y.", attributes: [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor(white: 0.07, alpha: 1)])
        setHole(nil)   // 가운데 = ydot 로고, 칸을 고르면 그 이름
        content.addSublayer(holeText); content.addSublayer(holeLogo)
        for a in Action.allCases {
            let t = CATextLayer()
            t.contentsScale = scale; t.zPosition = 21
            t.alignmentMode = .center
            t.string = attributed(a.title, 13, textDark)
            let size = (t.string as! NSAttributedString).size()
            t.bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 4, height: ceil(size.height))
            content.addSublayer(t)
            labels.append(t)
            let ic = CALayer(); ic.contentsScale = scale; ic.zPosition = 21; ic.bounds = CGRect(x: 0, y: 0, width: 28, height: 24); ic.contentsGravity = .resizeAspect
            ic.contents = symbolImage(a.symbol, 21, textDark); content.addSublayer(ic); icons.append(ic)
        }
        registerForDraggedTypes([.fileURL])
        render(0)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setHole(_ a: Action?) {   // 선택 없음 → y. 로고 / 칸 위 → 칸 이름 (2026-11-03 사용자 요청). 층 크기는 고정, 보이는 층만 바꿈
        if let a { holeText.string = NSAttributedString(string: a.title, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: textDark]) }
        holeText.opacity = a == nil ? 0 : Float(min(1, max(0, s))); holeLogo.opacity = a == nil ? Float(min(1, max(0, s))) : 0
    }
    func attributed(_ s: String, _ size: CGFloat, _ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
    }

    func quiet(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    func render(_ value: CGFloat) {
        s = value
        let fade = min(1, max(0, s)), show = fade   // 페이드 인·아웃만 (회전·확대 없음, 2026-11-03)
        let scale: CGFloat = 1
        var frames: [CGAffineTransform] = []
        quiet {
            for a in Action.allCases {
                let i = a.rawValue, phi = a.angle, on = selected == a, pop = on ? popOut : 0
                var t = CGAffineTransform(rotationAngle: -phi * .pi / 180)
                t = t.translatedBy(x: 0, y: pop).scaledBy(x: scale, y: scale)
                blades[i].setAffineTransform(t)
                blades[i].opacity = Float(fade)
                let mid = polar((outerR + innerR) / 2 + pop, phi)   // 칸 가운데. 아이콘은 그 위, 글자는 그 아래 (화면 기준)
                labels[i].position = CGPoint(x: mid.x, y: mid.y - 11)
                labels[i].opacity = Float(show)
                icons[i].position = CGPoint(x: mid.x, y: mid.y + 15)
                icons[i].opacity = Float(show)
                frames.append(t)
            }
            let hs: CGFloat = 1
            hole.bounds = bounds; hole.position = center
            hole.setAffineTransform(CGAffineTransform(scaleX: hs, y: hs))
            hole.opacity = Float(fade)
            holeText.opacity = selected == nil ? 0 : Float(fade); holeLogo.opacity = selected == nil ? Float(fade) : 0
            catcher.opacity = s > 0.5 ? 1 : 0
        }
        effect.alphaValue = 1
        if !maskReady { updateMask(frames); maskReady = true }   // 마스크는 고정(또렷한 원) → 한 번만
    }
    var maskReady = false

    func updateMask(_ frames: [CGAffineTransform]) {
        let shape = bladeShape, hs = 0.7 + 0.3 * min(1, s), holeSize = holeR * hs
        effect.maskImage = NSImage(size: NSSize(width: donutSize, height: donutSize), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.draw(discMaskImage().cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: CGRect(x: 0, y: 0, width: donutSize, height: donutSize))   // 원판 전체, 가장자리는 서서히 (선 없음)
            for t in frames where false {
                ctx.saveGState()
                ctx.translateBy(x: center.x, y: center.y)
                ctx.concatenate(t)
                ctx.translateBy(x: -center.x, y: -center.y)
                ctx.addPath(shape)
                ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.fillEllipse(in: CGRect(x: center.x - holeSize, y: center.y - holeSize, width: holeSize * 2, height: holeSize * 2))
            return true
        }
    }

    func select(_ a: Action?) {
        guard a != selected else { return }
        selected = a
        controller?.webHover(a == .web)
        for action in Action.allCases { blades[action.rawValue].setOn(action == a) }   // 애니메이션되게 quiet 밖에서
        quiet {
            for action in Action.allCases {
                let on = action == a
                labels[action.rawValue].string = attributed(action.title, 13, on ? .white : textDark)
                icons[action.rawValue].contents = symbolImage(action.symbol, 21, on ? .white : textDark)
            }
            setHole(a)
        }
        render(s)
    }

    func action(at p: NSPoint) -> Action? {
        let dx = p.x - center.x, dy = p.y - center.y, d = hypot(dx, dy)
        guard d >= innerR, d <= outerR else { return nil }
        let a = (atan2(dx, dy) * 180 / .pi + 360 + Action.step / 2).truncatingRemainder(dividingBy: 360)
        return Action(rawValue: Int(a / Action.step))
    }

    // 끌기 받기
    func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard controller?.accepting == true else { select(nil); return [] }
        select(action(at: convert(sender.draggingLocation, from: nil)))
        return selected == nil ? [] : .copy
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { select(nil) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { selected != nil && controller?.accepting == true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let a = selected, let c = controller, c.accepting else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if a == .web { return c.beginPick(urls) }   // Product 칸에 놓으면: 도넛 사라지고 규격 목록이 떠서 클릭으로 고름 (2026-11-04)
        return c.drop(urls, a, spec: nil, both: true)
    }
}

// MARK: - For Web 규격 목록 (For Web 칸에 올리면 오른쪽에 뜸. 규격 위에 놓으면 그 규격으로, 칸에 놓으면 비율로 자동)
// MARK: - 고르기 패널 (2026-11-05 새 디자인: 카드 B 배치 · 조절 화면 아래 도구 막대 · Custom)
// 바탕 3가지 = y. 버튼으로 그레이 → 다크 → 글래스 (cardTheme: sidebar · dark · glass, 기억)
var uiK: CGFloat = 1   // 화면 배율 (Panel Size). 버튼·y.는 늘 같은 크기 (2026-11-05)
var uiP: CGFloat { pow(uiK, 0.5) }   // 버튼 아닌 막대·글자·게이지 = 배율을 반쯤만 따라감 (Large에서 살짝 큼)
final class PassView: NSView { override func hitTest(_ p: NSPoint) -> NSView? { let v = super.hitTest(p); return v === self ? nil : v } }   // 버튼 틀: 빈 곳 클릭은 아래로 통과
func screenBox(_ c: NSView, top: Bool, h: CGFloat, W: CGFloat, H: CGFloat) {   // 화면 1:1 틀 (버튼용). h = 화면 높이 pt
    c.frame = NSRect(x: 0, y: top ? H - h / uiK : 0, width: W, height: h / uiK); c.bounds = NSRect(x: 0, y: 0, width: W * uiK, height: h) }
let btnM: CGFloat = 84   // 패널 창 사방 여백: y. 버튼 바깥 반쪽 + 그림자 + 젤리 튕김(최대 약 9%)이 창 끝에 잘리지 않을 자리 (2026-11-05, 예전 30)
let themeOrder = ["sidebar", "dark"]   // 글래스 뺌 (사용자 2026-11-05). 예전에 글래스였던 맥은 그레이로
var cardTheme: String { get { let t = UserDefaults.standard.string(forKey: "cardTheme") ?? "sidebar"; return themeOrder.contains(t) ? t : "sidebar" } set { UserDefaults.standard.set(newValue, forKey: "cardTheme") } }
struct PanelColors { let bg, tx, sub, ln, well, btn: NSColor; let dark, glass: Bool }
// MARK: 상단바 (2026-11-05): 흰 제목 막대 + 신호등(Finder처럼) · 가운데 y. · ◐(아이폰 다크 모드처럼) · [ − Medium + ]. 화면에서 늘 같은 크기(높이 30)
let titleBarH: CGFloat = 30
func tbFill(_ c: PanelColors, _ k: CGFloat = 1) -> NSColor { c.dark ? NSColor(white: 1, alpha: 0.075 * k) : NSColor(white: 0, alpha: 0.065 * k) }
final class TrafficLights: NSView {   // 빨강 닫기 하나만 (사용자 2026-11-05: 노랑·초록 뺌). 올리면 × 표시
    var onClose: (() -> Void)?, onZoom: (() -> Void)?
    var hover = false { didSet { if oldValue != hover { needsDisplay = true } } }
    var pressed = -1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 14, height: 14)) }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() { trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)); super.updateTrackingAreas() }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    func rect(_ i: Int) -> NSRect { NSRect(x: 1 + CGFloat(i) * 20, y: 1, width: 12, height: 12) }
    func idx(_ p: NSPoint) -> Int { rect(0).insetBy(dx: -3, dy: -3).contains(p) ? 0 : -1 }
    override func draw(_ r: NSRect) {
        let cols = [NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1), NSColor(white: 0.78, alpha: 1), NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)]
        for i in 0..<1 {
            var c = cols[i]; if pressed == i { c = c.blended(withFraction: 0.2, of: .black) ?? c }
            c.setFill(); let o = NSBezierPath(ovalIn: rect(i)); o.fill(); NSColor(white: 0, alpha: 0.12).setStroke(); o.lineWidth = 0.5; o.stroke()
            guard hover, i != 1 else { continue }
            let q = rect(i).insetBy(dx: 3.4, dy: 3.4), g = NSBezierPath(); g.lineWidth = 1.2; g.lineCapStyle = .round
            if i == 0 { NSColor(srgbRed: 0.3, green: 0.02, blue: 0, alpha: 0.75).set(); g.move(to: NSPoint(x: q.minX, y: q.minY)); g.line(to: NSPoint(x: q.maxX, y: q.maxY)); g.move(to: NSPoint(x: q.maxX, y: q.minY)); g.line(to: NSPoint(x: q.minX, y: q.maxY)); g.stroke() }
            else { NSColor(srgbRed: 0, green: 0.3, blue: 0.05, alpha: 0.75).setFill(); let t1 = NSBezierPath(); t1.move(to: NSPoint(x: q.minX, y: q.maxY)); t1.line(to: NSPoint(x: q.minX, y: q.minY + 1.5)); t1.line(to: NSPoint(x: q.maxX - 1.5, y: q.maxY)); t1.close(); t1.fill()
                let t2 = NSBezierPath(); t2.move(to: NSPoint(x: q.maxX, y: q.minY)); t2.line(to: NSPoint(x: q.maxX, y: q.maxY - 1.5)); t2.line(to: NSPoint(x: q.minX + 1.5, y: q.minY)); t2.close(); t2.fill() } }
    }
    override func mouseDown(with e: NSEvent) {
        let i = idx(convert(e.locationInWindow, from: nil)); guard i == 0 else { return }
        pressed = i; var inside = true
        while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) { inside = idx(convert(ev.locationInWindow, from: nil)) == i; pressed = inside ? i : -1; if ev.type == .leftMouseUp { break } }
        pressed = -1; if inside { (i == 0 ? onClose : onZoom)?() }
    }
}
final class ThemeToggle: NSView {   // 아이폰 다크 모드 버튼처럼: 누르면 반쪽 무늬가 반 바퀴 돌며 튕기고 둘레가 '톡' 퍼짐
    var onClick: (() -> Void)?
    let disc = CALayer(), ring = CAShapeLayer(), half = CAShapeLayer(), ripple = CAShapeLayer()
    var col = panelColors(), hovering = false, isDark = false
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 24)); wantsLayer = true; layer?.cornerRadius = 7
        for l in [ring, half] { disc.addSublayer(l) }; layer?.addSublayer(disc); layer?.addSublayer(ripple)
        ring.fillColor = nil; ring.lineWidth = 1.5; ripple.fillColor = nil; ripple.lineWidth = 1.5; ripple.opacity = 0 }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true)
        let d: CGFloat = 13; disc.bounds = CGRect(x: 0, y: 0, width: d, height: d); disc.position = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.path = CGPath(ellipseIn: CGRect(x: 0.75, y: 0.75, width: d - 1.5, height: d - 1.5), transform: nil)
        let hp = CGMutablePath(); hp.addArc(center: CGPoint(x: d / 2, y: d / 2), radius: d / 2 - 0.75, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false); hp.closeSubpath(); half.path = hp
        ripple.frame = bounds; ripple.path = CGPath(ellipseIn: CGRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18), transform: nil)
        CATransaction.commit(); paint() }
    func paint() { let c = hovering ? col.tx : col.sub
        CATransaction.begin(); CATransaction.setDisableActions(true); ring.strokeColor = c.cgColor; half.fillColor = c.cgColor; ripple.strokeColor = col.tx.cgColor; layer?.backgroundColor = hovering ? tbFill(col, 1.6).cgColor : NSColor.clear.cgColor; CATransaction.commit() }
    func setDark(_ d: Bool, animated: Bool) {
        guard d != isDark || !animated else { return }; isDark = d; let to = d ? CGFloat.pi : 0
        disc.setValue(to, forKeyPath: "transform.rotation.z")
        guard animated else { return }
        let s = CASpringAnimation(keyPath: "transform.rotation.z"); s.fromValue = d ? 0 : CGFloat.pi; s.toValue = to; s.damping = 11; s.stiffness = 180; s.mass = 1; s.duration = s.settlingDuration; disc.add(s, forKey: "spin")
        let g = CAAnimationGroup(); let sc = CABasicAnimation(keyPath: "transform.scale"); sc.fromValue = 0.6; sc.toValue = 1.5; let op = CABasicAnimation(keyPath: "opacity"); op.fromValue = 0.4; op.toValue = 0
        g.animations = [sc, op]; g.duration = 0.45; g.timingFunction = CAMediaTimingFunction(name: .easeOut); ripple.bounds = bounds; ripple.position = CGPoint(x: bounds.midX, y: bounds.midY); ripple.add(g, forKey: "pop") }
    override func updateTrackingAreas() { trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)); super.updateTrackingAreas() }
    override func mouseEntered(with e: NSEvent) { hovering = true; paint() }
    override func mouseExited(with e: NSEvent) { hovering = false; paint() }
    override func mouseDown(with e: NSEvent) { layer?.backgroundColor = tbFill(col, 2.4).cgColor
        var inside = true; while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) { inside = bounds.contains(convert(ev.locationInWindow, from: nil)); if ev.type == .leftMouseUp { break } }
        paint(); if inside { onClick?() } }
}
final class SizeStepper: NSView {   // [ − Medium + ] 패널 크기 (Small · Medium · Large)
    var onStep: ((Int) -> Void)?
    var col = panelColors(), hot = -1, down = -1, title = "Medium"
    static let W: CGFloat = 96, H: CGFloat = 22   // 덜 꽉 차게 (사용자 2026-11-05)
    init() { super.init(frame: NSRect(x: 0, y: 0, width: SizeStepper.W, height: SizeStepper.H)) }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func part(_ p: NSPoint) -> Int { p.x < 26 ? 0 : p.x > bounds.width - 26 ? 1 : -1 }
    override func draw(_ r: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2); tbFill(col).setFill(); pill.fill()
        for k in [0, 1] where hot == k || down == k { NSGraphicsContext.saveGraphicsState(); pill.addClip(); tbFill(col, down == k ? 2.4 : 1.4).setFill(); NSRect(x: k == 0 ? 0 : bounds.width - 26, y: 0, width: 26, height: bounds.height).fill(); NSGraphicsContext.restoreGraphicsState() }
        let g = NSBezierPath(); g.lineWidth = 1.5; g.lineCapStyle = .round; let cy = bounds.midY
        g.move(to: NSPoint(x: 9, y: cy)); g.line(to: NSPoint(x: 17, y: cy)); let px = bounds.width - 13; g.move(to: NSPoint(x: px - 4, y: cy)); g.line(to: NSPoint(x: px + 4, y: cy)); g.move(to: NSPoint(x: px, y: cy - 4)); g.line(to: NSPoint(x: px, y: cy + 4))
        col.sub.setStroke(); g.stroke()
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: col.tx]; let sz = (title as NSString).size(withAttributes: a)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2), withAttributes: a)
    }
    override func updateTrackingAreas() { trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)); super.updateTrackingAreas() }
    override func mouseMoved(with e: NSEvent) { let h = part(convert(e.locationInWindow, from: nil)); if h != hot { hot = h; needsDisplay = true } }
    override func mouseExited(with e: NSEvent) { hot = -1; needsDisplay = true }
    override func mouseDown(with e: NSEvent) { let k = part(convert(e.locationInWindow, from: nil)); guard k >= 0 else { return }; down = k; needsDisplay = true
        var inside = true; while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) { inside = part(convert(ev.locationInWindow, from: nil)) == k; if ev.type == .leftMouseUp { break } }
        down = -1; needsDisplay = true; if inside { onStep?(k == 0 ? -1 : 1) } }
}
final class TitleBar: NSView {   // 상단바 부품 묶음 (화면 1:1 틀 안에). 빈 곳 = 끌면 패널 옮기기 (우클릭 메뉴는 빼기로, 사용자 2026-11-05)
    let lights = TrafficLights(), logo = NSTextField(labelWithString: "y."), toggle = ThemeToggle(), stepper = SizeStepper()
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 300, height: titleBarH)); logo.font = .systemFont(ofSize: 15, weight: .heavy); logo.sizeToFit()
        for v in [lights, logo, toggle, stepper] as [NSView] { addSubview(v) }
        lights.onClose = { controller.endPick() }
        toggle.onClick = { controller.cycleTheme() }
        stepper.onStep = { d in let sizes = [220.0, 300.0, 400.0], i = sizes.firstIndex(of: Double(previewThumbH())) ?? 1, n = max(0, min(2, i + d)); guard n != i else { NSSound.beep(); return }; let it = NSMenuItem(); it.representedObject = sizes[n]; controller.setPanelSize(it) } }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func place(width W: CGFloat) {
        let cy = titleBarH / 2
        lights.setFrameOrigin(NSPoint(x: 12, y: (cy - lights.frame.height / 2).rounded()))
        logo.setFrameOrigin(NSPoint(x: ((W - logo.frame.width) / 2).rounded(), y: (cy - logo.frame.height / 2).rounded()))
        stepper.setFrameOrigin(NSPoint(x: W - 14 - SizeStepper.W, y: (cy - SizeStepper.H / 2).rounded()))
        toggle.setFrameOrigin(NSPoint(x: stepper.frame.minX - 4 - toggle.frame.width, y: (cy - toggle.frame.height / 2).rounded()))
        let t = ["Small", "Medium", "Large"][[220, 300, 400].firstIndex(of: Int(previewThumbH())) ?? 1]; if stepper.title != t { stepper.title = t; stepper.needsDisplay = true } }
    func style(_ c: PanelColors) { logo.textColor = c.tx; toggle.col = c; toggle.paint(); toggle.setDark(c.dark, animated: window != nil && toggle.isDark != c.dark); stepper.col = c; stepper.needsDisplay = true; lights.needsDisplay = true }
    override func mouseDown(with e: NSEvent) {   // 빈 곳을 끌면 패널 옮기기 (맥 창 제목 막대처럼)
        guard let w = window else { return }; let start = NSEvent.mouseLocation, o = w.frame.origin; var moved = false
        while let ev = w.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) { let p = NSEvent.mouseLocation
            if !moved, hypot(p.x - start.x, p.y - start.y) > 2 { moved = true }
            if moved { w.setFrameOrigin(NSPoint(x: o.x + p.x - start.x, y: o.y + p.y - start.y)) }
            if ev.type == .leftMouseUp { break } } }
}
func applyTitleBG(_ v: ThemedPanel, _ l: CALayer) {   // 흰 상단바 바탕 + 아래 구분선 (패널 바탕 판 위 → 둥근 모서리 따라 잘림)
    if l.superlayer == nil { v.tint.layer?.addSublayer(l) }
    let c = panelColors(), W = v.frame.width, H = v.frame.height, h = titleBarH / uiK
    CATransaction.begin(); CATransaction.setDisableActions(true); l.sublayers?.forEach { $0.removeFromSuperlayer() }
    l.frame = CGRect(x: 0, y: H - h, width: W, height: h); l.backgroundColor = c.btn.cgColor
    let shv: String? = "2"   // 상단바 = 그림자만 (구분선 없음, 사용자 2026-11-05)
    if let shv { l.shadowColor = NSColor.black.cgColor; l.shadowOpacity = c.dark ? 0.5 : 0.1; l.shadowRadius = 6 / uiK; l.shadowOffset = CGSize(width: 0, height: -2 / uiK); l.shadowPath = CGPath(rect: l.bounds, transform: nil); if shv == "2" { CATransaction.commit(); return } } else { l.shadowOpacity = 0 }
    let ln = CALayer(); ln.frame = CGRect(x: 0, y: 0, width: W, height: 0.5 / uiK); ln.backgroundColor = (c.dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.12)).cgColor; l.addSublayer(ln)
    CATransaction.commit()
}

enum DimStyle { static let v = Int(ProcessInfo.processInfo.environment["DONUT_DIM"] ?? "") ?? 2;   // 2 = 알약 (사용자 2026-11-05)
    static let gray = ProcessInfo.processInfo.environment["DONUT_DIMGRAY"] != nil; static let cap = true }   // 끝 = I자 (사용자 2026-11-05)   // 치수 라벨 시안 1 숫자만 · 2 파란 알약 · 3 테두리 알약 · 4 세로 글자 (0 = 지금)
func adjWell(_ c: PanelColors) -> NSColor { c.dark ? c.btn : wellColor(c) }   // 조절 화면 사진 칸: 다크에선 아래 막대와 같은 색 (사용자 2026-11-05)
func wellColor(_ c: PanelColors) -> NSColor {   // 패널 안 칸 색 (Custom 자르기 칸과 같게). DONUT_WELL=gray = 그레이에서 살짝 진한 회색 (시안)
    if !c.dark, ProcessInfo.processInfo.environment["DONUT_WELL"] == "gray" { return NSColor(srgbRed: 0.878, green: 0.878, blue: 0.89, alpha: 1) }
    return c.well }
func panelColors(_ t: String = cardTheme) -> PanelColors {
    switch t {
    case "dark": return PanelColors(bg: NSColor(srgbRed: 0.165, green: 0.165, blue: 0.173, alpha: 1), tx: NSColor(white: 0.95, alpha: 1), sub: NSColor(white: 0.72, alpha: 1), ln: NSColor(white: 1, alpha: 0.12), well: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.125, alpha: 1), btn: NSColor(white: 0.27, alpha: 1), dark: true, glass: false)   // 다크 한 단계 밝게 (사용자 2026-11-05, 예전 bg .118 · well .078 · btn .23)
    case "glass": return PanelColors(bg: NSColor(white: 1, alpha: 0.72), tx: NSColor(white: 0.11, alpha: 1), sub: NSColor(white: 0.37, alpha: 1), ln: NSColor(white: 0, alpha: 0.08), well: NSColor(white: 1, alpha: 0.45), btn: NSColor(white: 1, alpha: 0.85), dark: false, glass: true)
    default: return PanelColors(bg: NSColor(srgbRed: 0.925, green: 0.925, blue: 0.933, alpha: 1), tx: NSColor(white: 0.11, alpha: 1), sub: NSColor(white: 0.53, alpha: 1), ln: NSColor(srgbRed: 0.863, green: 0.863, blue: 0.878, alpha: 1), well: NSColor.white, btn: NSColor.white, dark: false, glass: false)
    }
}
let displayFPS: Double = Double(max(60, NSScreen.screens.map { $0.maximumFramesPerSecond }.max() ?? 60))   // 120Hz 화면이면 1초 120번 (2026-11-05)
let sysBlue = NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1), limitOrange = NSColor(srgbRed: 1, green: 0.58, blue: 0, alpha: 1)
let panelWhite: CGFloat = 0.5
// 미리보기 패널 (Shift 끌기 중 규격 목록 아래 별도 창) — 그대로
let previewPad: CGFloat = 10, previewGap: CGFloat = 10, previewMax = 12
let sharedDefaults = UserDefaults(suiteName: "com.cc.ydot-shared")!
var testPanelH: Double?   // 시험 중 바꾼 크기 (사용자 설정에 안 씀)
func previewThumbH() -> CGFloat { let v = testPanelH ?? Double(ProcessInfo.processInfo.environment["DONUT_PANELH"] ?? "") ?? sharedDefaults.double(forKey: "previewH");   // DONUT_PANELH = 시험용 (사용자 설정 안 건드림)
    guard v > 0 else { return 300 }; return [220, 300, 400].min { abs($0 - v) < abs($1 - v) }! }   // 패널 크기 Small 220 · Medium 300(기본) · Large 400 (2026-11-05)
func previewH() -> CGFloat { previewPad * 2 + previewThumbH() + 20 }
func listRaise() -> CGFloat { (previewH() + 10) / 2 }
final class PreviewStripView: NSView {
    let effect = NSVisualEffectView(), white = NSView(), cap = NSTextField(labelWithString: "")
    var slots: [NSImageView] = []
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: previewH()))
        wantsLayer = true; layer?.cornerRadius = 12; layer?.masksToBounds = true; layer?.borderWidth = 1; layer?.borderColor = NSColor(white: 0, alpha: 0.08).cgColor
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active; effect.appearance = NSAppearance(named: .aqua); addSubview(effect)
        white.wantsLayer = true; white.layer?.backgroundColor = NSColor(white: 1, alpha: panelWhite).cgColor; addSubview(white)
        cap.alignment = .center; cap.font = .systemFont(ofSize: 10.5, weight: .regular); cap.textColor = NSColor(white: 0.45, alpha: 1); addSubview(cap)
    }
    required init?(coder: NSCoder) { fatalError() }
    func layout(sizes: [CGSize], cap text: String) -> CGSize {
        slots.forEach { $0.removeFromSuperview() }; slots = []
        var x = previewPad
        for sz in sizes.prefix(previewMax) {
            let w = ceil(previewThumbH() * sz.width / max(1, sz.height))
            let iv = NSImageView(frame: NSRect(x: x, y: previewPad + 20, width: w, height: previewThumbH())); iv.imageScaling = .scaleProportionallyUpOrDown; iv.wantsLayer = true; iv.layer?.cornerRadius = 4; iv.layer?.backgroundColor = NSColor(white: 0, alpha: 0.05).cgColor
            addSubview(iv); slots.append(iv); x += w + previewGap
        }
        let W = max(x - previewGap + previewPad, 140)
        frame = NSRect(x: 0, y: 0, width: W, height: previewH()); effect.frame = bounds; white.frame = bounds
        cap.frame = NSRect(x: 0, y: previewPad - 4, width: W, height: 16); cap.stringValue = text
        return CGSize(width: W, height: previewH())
    }
    func set(_ i: Int, _ im: NSImage) { if i < slots.count { slots[i].image = im } }
}
final class HolderView: NSView {   // 패널 창의 그릇: 투명 여유를 누르면 = 밖 클릭 (닫기)
    var onOutside: (() -> Void)?
    override func mouseDown(with e: NSEvent) { onOutside?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }
final class FirstMouseButton: NSButton { override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true } }

// 패널 바탕 (세 화면 공통): 흐림 + 색 + 테두리 + 레이어 그림자 (맥 창 그림자는 안 씀)
class ThemedPanel: NSView {
    let effect = NSVisualEffectView(), tint = NSView()
    let R: CGFloat
    init(frame: NSRect, radius: CGFloat = 18) {
        R = radius; super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = R; layer?.masksToBounds = false; layer?.borderWidth = 0.5
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOffset = CGSize(width: 0, height: -16); layer?.shadowRadius = 20   // 맥 창처럼 아래로 길게, 위는 거의 없게 (2026-11-05)
        effect.blendingMode = .behindWindow; effect.state = .active; effect.material = .popover; effect.wantsLayer = true; effect.layer?.cornerRadius = R; effect.layer?.masksToBounds = true; effect.autoresizingMask = [.width, .height]; effect.frame = bounds; addSubview(effect)
        tint.wantsLayer = true; tint.layer?.cornerRadius = R; tint.layer?.masksToBounds = true; tint.autoresizingMask = [.width, .height]; tint.frame = bounds; addSubview(tint)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: R, cornerHeight: R, transform: nil) }
    var dragBand: CGFloat = 56   // 위쪽 이만큼을 잡고 끌면 패널 이동 (버튼은 버튼이 먼저 받음, 2026-11-05)
    func inDragBand(_ e: NSEvent) -> Bool { convert(e.locationInWindow, from: nil).y >= bounds.height - dragBand }
    func applyPanelTheme() {
        let c = panelColors()
        appearance = NSAppearance(named: c.dark ? .darkAqua : .aqua); effect.appearance = appearance
        effect.material = c.glass ? .hudWindow : .popover
        effect.isHidden = !c.glass   // 그레이·다크는 불투명 색, 글래스만 뒤가 비침
        tint.layer?.backgroundColor = c.bg.cgColor
        layer?.borderColor = c.glass ? NSColor(white: 1, alpha: 0.65).cgColor : (c.dark ? NSColor(white: 1, alpha: 0.14).cgColor : NSColor(white: 0, alpha: 0.08).cgColor)
        layer?.shadowOpacity = c.dark ? 0.45 : 0.2
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: R, cornerHeight: R, transform: nil)
    }
    func label(_ t: String, _ size: CGFloat, _ col: NSColor, mono: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: t); l.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: .regular) : .systemFont(ofSize: size, weight: .regular); l.textColor = col; l.lineBreakMode = .byTruncatingTail; return l }
}

// 둥근 알약 버튼 (← 뒤로 · Default ⌘0 · Save) — 바탕색에 맞춤
final class PillButton: NSButton {   // 둥근 알약 버튼: 옅은 그림자·위 하이라이트(입체) + 올리면 밝아짐 · 누르면 어두워지며 쏙 (맥 기본 버튼처럼, 2026-11-05)
    var fill: NSColor = .white { didSet { paint() } }
    var textColor: NSColor = .black { didSet { refresh() } }
    var hint = ""   // 옅은 단축키 글자 (⌘0)
    var text = "" { didSet { refresh() } }
    var primary = false, dark = false, hovering = false, pressing = false
    var nativeBlue = true   // Save = 진짜 맥 기본 버튼과 같게: 시스템 강조 색 한 가지 · 테두리 없음 (2026-11-05 실측 비교) · 그림자만 아주 옅게
    let hi = CAGradientLayer()
    let edge = CAGradientLayer(), edgeMask = CAShapeLayer()   // 테두리 그라데이션: 위 옅게 → 아래 진하게 (맥 기본 버튼)
    init(_ title: String, hint: String = "", target: AnyObject?, action: Selector) {
        super.init(frame: .zero); self.text = title; self.hint = hint; self.target = target; self.action = action
        isBordered = false; wantsLayer = true; layer?.cornerRadius = 14; layer?.masksToBounds = false; focusRingType = .none
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOffset = CGSize(width: 0, height: -1)
        edgeMask.fillColor = nil; edgeMask.strokeColor = NSColor.black.cgColor; edgeMask.lineWidth = 1; edge.mask = edgeMask; edge.startPoint = CGPoint(x: 0.5, y: isFlipped ? 0 : 1); edge.endPoint = CGPoint(x: 0.5, y: isFlipped ? 1 : 0)   // 버튼은 위아래 뒤집힌 좌표 → 위 옅게·아래 진하게가 되도록
        layer?.addSublayer(edge); refresh()   // 광(위 하이라이트) 없음 (2026-11-05)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); paint() }
    func refresh() {
        let s = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: textColor])
        if !hint.isEmpty { s.append(NSAttributedString(string: "  " + hint, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: textColor.withAlphaComponent(0.5)])) }
        attributedTitle = s }
    func fitWidth(_ minW: CGFloat = 0) -> CGFloat { max(minW, ceil(attributedTitle.size().width) + 26) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func style(_ c: PanelColors, primary: Bool = false) {
        self.primary = primary; dark = c.dark
        layer?.borderWidth = 0
        if primary { textColor = .white
            if nativeBlue { var acc = NSColor.controlAccentColor; effectiveAppearance.performAsCurrentDrawingAppearance { acc = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? sysBlue }; fill = acc
                hi.isHidden = true; edge.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor] }
            else { fill = sysBlue; hi.isHidden = true   // Save = 파랑 (2026-11-05)
                edge.colors = [NSColor(white: 1, alpha: 0.18).cgColor, NSColor(white: 0, alpha: 0.12).cgColor] } }
        else { textColor = c.tx; fill = c.dark ? NSColor(white: 1, alpha: 0.075) : NSColor(white: 0, alpha: 0.065)   // 진짜 맥 일반 버튼과 같게: 바탕에 비치는 옅은 칸 · 테두리·그림자 없음 (2026-11-05 실측)
            edge.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor] }
    }
    func paint() {   // 상태별 색·그림자 (짧게 움직임)
        guard let l = layer else { return }
        var col = fill
        if !primary { col = fill.withAlphaComponent(fill.alphaComponent * (pressing ? 2.0 : hovering ? 1.45 : 1)) }   // 일반 버튼: 올리면·누르면 조금 더 진하게
        else if pressing { col = (primary ? fill.blended(withFraction: 0.18, of: .black) : (dark ? fill.blended(withFraction: 0.25, of: .white) : fill.blended(withFraction: 0.12, of: .black))) ?? fill }
        else if hovering { col = (primary ? fill.blended(withFraction: 0.1, of: .white) : (dark ? fill.blended(withFraction: 0.12, of: .white) : fill.blended(withFraction: 0.04, of: .black))) ?? fill }
        CATransaction.begin(); CATransaction.setAnimationDuration(pressing ? 0.06 : 0.14)
        l.backgroundColor = col.cgColor
        // 맥 기본 버튼처럼: 테두리 아래쪽이 진하고 + 바로 밑에 짧은 그림자 (위·옆으로 안 퍼짐) (2026-11-05)
        let r = l.cornerRadius
        // 그림자 = 버튼 아래로만: 양옆을 줄인 모양을 2pt 내려 흐리게 → 위·옆엔 없고 바닥 밑에 옅게 (2026-11-05)
        // 2026-11-05: 경계가 보이던 것 → 더 넓게 흐리고 옅게 (부드러운 번짐)
        l.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: 4, dy: 2).offsetBy(dx: 0, dy: isFlipped ? 3 : -3), cornerWidth: max(0, r - 4), cornerHeight: max(0, r - 4), transform: nil); l.shadowOffset = .zero
        l.shadowColor = (primary ? (nativeBlue ? fill.blended(withFraction: 0.45, of: .black) ?? .black : NSColor(srgbRed: 0, green: 0.25, blue: 0.6, alpha: 1)) : NSColor.black).cgColor
        l.shadowOpacity = !primary ? 0 : pressing ? 0.05 : (nativeBlue ? 0.16 : 0.32); l.shadowRadius = pressing ? 2 : 4.5
        hi.frame = bounds; hi.cornerRadius = r
        edge.frame = bounds; edgeMask.frame = bounds; edgeMask.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: max(0, r - 0.5), cornerHeight: max(0, r - 0.5), transform: nil)
        let w = bounds.width / 2, h = bounds.height / 2, k: CGFloat = pressing ? 0.97 : 1
        l.transform = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(w, h, 0), k, k, 1), -w, -h, 0)
        CATransaction.commit()
    }
    override func updateTrackingAreas() { trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)); super.updateTrackingAreas() }
    override func mouseEntered(with e: NSEvent) { hovering = true; paint() }
    override func mouseExited(with e: NSEvent) { hovering = false; paint() }
    override func mouseDown(with e: NSEvent) {   // 누르는 동안 어둡게·쏙. 버튼 밖에서 놓으면 실행 안 함 (맥 기본과 같음)
        pressing = true; paint()
        var inside = true
        while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = bounds.contains(convert(ev.locationInWindow, from: nil))
            if ev.type == .leftMouseUp { break }
            if pressing != inside { pressing = inside; paint() } }
        pressing = false; hovering = inside; paint()
        if inside, let a = action { NSApp.sendAction(a, to: target, from: self) }
    }
}

// 비율 고르기: 파란 표시가 미끄러지듯 옮겨 감 (2026-11-05). 바탕은 맥 일반 버튼처럼 옅은 칸
final class SlideSeg: NSView {
    var labels: [String] = [] { didSet { rebuild() } }
    var selectedSegment = 0 { didSet { if oldValue != selectedSegment { moveHi(animated: window != nil) } } }
    weak var target: AnyObject?; var action: Selector?
    let track = CALayer(), hi = CALayer(); var texts: [CATextLayer] = [], widths: [CGFloat] = []
    var col = panelColors()
    static let H: CGFloat = 24
    override var isFlipped: Bool { true }
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 100, height: SlideSeg.H)); wantsLayer = true; layer?.addSublayer(track); track.addSublayer(hi); hi.backgroundColor = sysBlue.cgColor }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func str(_ t: String, _ on: Bool) -> NSAttributedString { NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: on ? .medium : .regular), .foregroundColor: on ? NSColor.white : col.tx]) }
    func rebuild() { texts.forEach { $0.removeFromSuperlayer() }
        texts = labels.enumerated().map { i, t in let l = CATextLayer(); l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2; l.alignmentMode = .center; l.string = str(t, i == selectedSegment); track.addSublayer(l); return l }
        widths = labels.map { ceil(str($0, true).size().width) + 26 }; sizeToFit() }
    func sizeToFit() { setFrameSize(NSSize(width: widths.reduce(0, +) + 4, height: SlideSeg.H)); needsLayout = true }
    func rect(_ i: Int) -> CGRect { let x = 2 + widths.prefix(i).reduce(0, +); return CGRect(x: x, y: 2, width: widths.indices.contains(i) ? widths[i] : 0, height: SlideSeg.H - 4) }
    override func layout() { super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = bounds; track.cornerRadius = bounds.height / 2; hi.cornerRadius = (SlideSeg.H - 4) / 2; hi.frame = rect(selectedSegment)
        for (i, l) in texts.enumerated() { let r = rect(i), h = str(labels[i], true).size().height; l.frame = CGRect(x: r.minX, y: (bounds.height - h) / 2, width: r.width, height: h + 1) }
        CATransaction.commit() }
    func moveHi(animated: Bool) {   // 파란 표시 미끄러지기 + 글자 색 바꾸기
        CATransaction.begin(); CATransaction.setAnimationDuration(animated ? 0.28 : 0); CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)); if !animated { CATransaction.setDisableActions(true) }
        hi.frame = rect(selectedSegment); for (i, l) in texts.enumerated() { l.string = str(labels[i], i == selectedSegment) }
        CATransaction.commit() }
    func style(_ c: PanelColors) { col = c; track.backgroundColor = (c.dark ? NSColor(white: 1, alpha: 0.075) : NSColor(white: 0, alpha: 0.065)).cgColor; for (i, l) in texts.enumerated() { l.string = str(labels[i], i == selectedSegment) } }
    override func mouseDown(with e: NSEvent) {
        let x = convert(e.locationInWindow, from: nil).x; guard let i = widths.indices.first(where: { rect($0).minX - 2 <= x && x <= rect($0).maxX + 2 }), i != selectedSegment else { return }
        selectedSegment = i; if let a = action { NSApp.sendAction(a, to: target, from: self) } }
}

// 제목 칸 (조절·Custom 위 가운데): 버튼과 같은 알약 모양, 조금 크게(높이 30). 누르는 칸 아님(클릭은 패널 끌기로 통과). 글자가 바뀌면 위로 밀며 바뀜 (2026-11-05 시안 A)
final class TitlePill: NSView {
    static let H: CGFloat = 32
    let mainL = NSTextField(labelWithString: ""), subL = NSTextField(labelWithString: "")
    var main = "", sub = "", blue = false, animating = false, col: PanelColors = panelColors()
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 100, height: TitlePill.H)); wantsLayer = true; layer?.masksToBounds = true; addSubview(mainL); addSubview(subL) }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }   // 누르는 칸 아님 (패널 끌기로 통과)
    override func layout() { super.layout(); layer?.cornerRadius = bounds.height / 2 }
    var accent: NSColor { var a = sysBlue; effectiveAppearance.performAsCurrentDrawingAppearance { a = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? sysBlue }; return a }
    func paintText() {
        mainL.attributedStringValue = NSAttributedString(string: main, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: blue ? NSColor.white : col.tx])
        subL.attributedStringValue = NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: blue ? NSColor(white: 1, alpha: 0.85) : col.sub])
        mainL.sizeToFit(); subL.sizeToFit() }
    var fitW: CGFloat { ceil(mainL.frame.width) + (sub.isEmpty ? 0 : 8 + ceil(subL.frame.width)) + 32 }
    func placeLabels(_ W: CGFloat) { let content = mainL.frame.width + (sub.isEmpty ? 0 : 8 + subL.frame.width), x0 = ((W - content) / 2).rounded()
        mainL.frame.origin = NSPoint(x: x0, y: ((TitlePill.H - mainL.frame.height) / 2).rounded()); subL.frame.origin = NSPoint(x: x0 + mainL.frame.width + 8, y: ((TitlePill.H - subL.frame.height) / 2).rounded()); subL.alphaValue = sub.isEmpty ? 0 : 1 }
    func paintBG() { layer?.backgroundColor = (blue ? accent : (col.dark ? NSColor(white: 1, alpha: 0.075) : NSColor(white: 0, alpha: 0.065))).cgColor }
    func set(_ m: String, _ s: String, blue b: Bool = false, animated: Bool) {   // animated = 좌우로 늘어나며 '프로필'은 왼쪽으로, 설명이 생김 (2026-11-05 사용자)
        guard m != main || s != sub || b != blue else { return }
        let oldSubEmpty = sub.isEmpty; main = m; sub = s; blue = b; paintText()
        let w = fitW, mid = frame.midX, target = NSRect(x: (mid - w / 2).rounded(), y: frame.minY, width: w, height: TitlePill.H)
        guard animated, window != nil else { frame = target; placeLabels(w); paintBG(); return }
        if oldSubEmpty && !sub.isEmpty { subL.frame.origin = NSPoint(x: mainL.frame.maxX + 8, y: ((TitlePill.H - subL.frame.height) / 2).rounded()); subL.alphaValue = 0 }   // 설명은 '프로필' 바로 옆에서 생겨 남
        animating = true
        CATransaction.begin(); CATransaction.setAnimationDuration(0.38); CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)); paintBG(); CATransaction.commit()
        let content = mainL.frame.width + (sub.isEmpty ? 0 : 8 + subL.frame.width), x0 = ((w - content) / 2).rounded()
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.38; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1); c.allowsImplicitAnimation = true
            self.animator().frame = target
            self.mainL.animator().frame.origin.x = x0; self.subL.animator().frame.origin.x = x0 + self.mainL.frame.width + 8; self.subL.animator().alphaValue = self.sub.isEmpty ? 0 : 1
        }, completionHandler: { self.animating = false; self.placeLabels(self.frame.width) })
    }
    func style(_ c: PanelColors) { col = c; paintText(); paintBG(); placeLabels(frame.width) }
}

// y. 버튼 (바탕별 모양: 그레이 = 흰 동그라미, 다크 = 짙은 동그라미, 글래스 = 테두리 없는 유리 구슬)
final class YButton: NSButton {
    let glassGrad = CAGradientLayer()
    init(target: AnyObject?, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30)); self.target = target; self.action = action
        isBordered = false; title = ""; wantsLayer = true; layer?.cornerRadius = 15; layer?.masksToBounds = false; focusRingType = .none
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOffset = CGSize(width: 0, height: -1.5)
        glassGrad.type = .radial; glassGrad.frame = bounds; glassGrad.cornerRadius = 15; glassGrad.masksToBounds = true
        glassGrad.startPoint = CGPoint(x: 0.35, y: 0.75); glassGrad.endPoint = CGPoint(x: 1.15, y: -0.05)
        glassGrad.colors = [NSColor(white: 1, alpha: 0.98).cgColor, NSColor(white: 1, alpha: 0.55).cgColor, NSColor(srgbRed: 0.9, green: 0.92, blue: 0.96, alpha: 0.35).cgColor, NSColor(white: 1, alpha: 0.6).cgColor]
        glassGrad.locations = [0.0, 0.3, 0.7, 1.0]
        layer?.addSublayer(glassGrad); toolTip = "누르면 바탕 바꾸기 (그레이 ↔ 다크) · 끌면 패널 옮기기"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var k: CGFloat { max(0.3, bounds.width / 30) }   // 그릇 좌표의 크기 비율 (화면에선 늘 30pt)
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); layer?.cornerRadius = s.width / 2; glassGrad.frame = bounds; glassGrad.cornerRadius = s.width / 2; applyTheme() }   // 2026-11-05: bounds 배율 꼼수는 패널 크기·열기 애니메이션에서 모양이 틀어짐 → 비례로 다시 그림
    var menuMaker: (() -> NSMenu)?
    override func rightMouseDown(with e: NSEvent) { if let m = menuMaker?() { NSMenu.popUpContextMenu(m, with: e, for: self) } }   // 우클릭 = Panel Size · Settings
    func applyTheme() {
        let t = cardTheme
        glassGrad.isHidden = t != "glass"
        let bg: NSColor = t == "dark" ? NSColor(srgbRed: 0.173, green: 0.173, blue: 0.18, alpha: 1) : (t == "glass" ? NSColor(white: 1, alpha: 0.35) : .white)
        layer?.backgroundColor = bg.cgColor
        layer?.borderWidth = t == "dark" ? 0.5 : (t == "glass" ? 0 : 0.5)
        layer?.borderColor = (t == "dark" ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.08)).cgColor
        // 그림자 = 아래로만: 조금 작은 원을 아래로 내려 흐리게 (2026-11-05)
        let w = bounds.width; layer?.shadowPath = CGPath(ellipseIn: CGRect(x: w * 0.08, y: (isFlipped ? 0.23 : -0.07) * w, width: w * 0.84, height: w * 0.84), transform: nil); layer?.shadowOffset = .zero
        layer?.shadowOpacity = t == "dark" ? 0.55 : 0.22; layer?.shadowRadius = 2.2 * k; layer?.borderWidth = (t == "dark" ? 0.5 : 0.5) * k
        let col: NSColor = t == "dark" ? .white : NSColor(white: 0.07, alpha: 1)
        let ps = NSMutableParagraphStyle(); ps.alignment = .center
        attributedTitle = NSAttributedString(string: "y.", attributes: [.font: NSFont.systemFont(ofSize: 14 * k, weight: .heavy), .foregroundColor: col, .paragraphStyle: ps, .baselineOffset: 1 * k])
        glassGrad.zPosition = -1
    }
    override func mouseDown(with e: NSEvent) {   // 끌면 패널 옮기기 · 안 움직이고 놓으면 바탕 바꾸기 (2026-11-05)
        if e.modifierFlags.contains(.control) { rightMouseDown(with: e); return }   // ⌃클릭 = 우클릭
        bump(0.92); let start = NSEvent.mouseLocation; var moved = false
        let origin = window?.frame.origin ?? .zero
        while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = NSEvent.mouseLocation
            if !moved, hypot(p.x - start.x, p.y - start.y) > 3 { moved = true; bump(1.0); NSCursor.closedHand.push() }
            if moved { window?.setFrameOrigin(NSPoint(x: origin.x + p.x - start.x, y: origin.y + p.y - start.y)) }
            if ev.type == .leftMouseUp { break } }
        if moved { NSCursor.pop() } else { bump(1.0); if let a = action { NSApp.sendAction(a, to: target, from: self) } }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    func bump(_ s: CGFloat) { guard let l = layer else { return }; let w = bounds.width / 2, h = bounds.height / 2
        let t = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(w, h, 0), s, s, 1), -w, -h, 0)
        let a = CABasicAnimation(keyPath: "transform"); a.fromValue = NSValue(caTransform3D: l.presentation()?.transform ?? l.transform); a.toValue = NSValue(caTransform3D: t); a.duration = 0.12; l.transform = t; l.add(a, forKey: "bump") }
}

// MARK: 1. 카드 패널 (B 배치: 증명·반명함·여권·Custom / 중국비자·미국비자·명함 · 실제 비율 1cm = 26pt · 흰 테두리 2pt)
let customCell = 100, directCell = 101   // 카드 칸 번호: 100 = 프로필 (흰 카드 PROFILE) · 101 = Custom (크기 직접, 점선 칸) (사용자 2026-11-07)
let cardK: CGFloat = 26, cardBW: CGFloat = 2.2
let cardRows: [[Int]] = [[0, 1, 2, directCell], [5, 3, 4, customCell]]   // 위 = 증명 · 반명함 · 여권 · Custom / 아래 = 명함 · 미국비자 · 중국비자 · 프로필 (소형 뺌, 사용자 2026-11-07)   // 아래 = 명함 · 미국비자 · 중국비자 · 소형 (사용자 2026-11-07)   // webSpecs 번호 · 소형(2) 다시 넣음 (사용자 2026-11-07)
let cardPadX: CGFloat = 24, cardPadTop: CGFloat = 22 + 30 /* + 상단바 */, cardPadBottom: CGFloat = (Int(ProcessInfo.processInfo.environment["DONUT_CARDBOX"] ?? "") ?? 1) > 0 ? 24 : 16, cardGapX: CGFloat = (Int(ProcessInfo.processInfo.environment["DONUT_CARDBOX"] ?? "") ?? 1) > 0 ? 25 : 24, cardTextH: CGFloat = 40, cardSepH: CGFloat = (Int(ProcessInfo.processInfo.environment["DONUT_CARDBOX"] ?? "") ?? 1) > 0 ? 25 : 27, customW: CGFloat = 96, customH: CGFloat = 100
func cardItemW(_ i: Int) -> CGFloat { i >= customCell ? (3.5 * cardK + cardBW * 2).rounded() : (CGFloat(Converter.webSpecs[i].w) * cardK + cardBW * 2).rounded() }   // 프로필·Custom = 증명 크기 칸
func cardItemPhotoH(_ i: Int) -> CGFloat { i >= customCell ? (4.5 * cardK + cardBW * 2).rounded() : (CGFloat(Converter.webSpecs[i].h) * cardK + cardBW * 2).rounded() }
func cardRowW(_ r: [Int]) -> CGFloat { r.map(cardItemW).reduce(0, +) + cardGapX * CGFloat(r.count - 1) }
func cardRowPhotoH(_ r: [Int]) -> CGFloat { r.map(cardItemPhotoH).max() ?? 0 }
let cardsSize = NSSize(width: (cardRows.map(cardRowW).max() ?? 400) + cardPadX * 2, height: cardPadTop + cardRows.map { cardRowPhotoH($0) + cardTextH }.reduce(0, +) + cardSepH + cardPadBottom)

let cardAlignBottom = false   // 칸 안 사진·글씨를 줄마다 아래로 맞춤 (false = 칸마다 가운데)
let hoverBezel: NSButton.BezelStyle? = Int(ProcessInfo.processInfo.environment["DONUT_HOVER"] ?? "").flatMap { NSButton.BezelStyle(rawValue: UInt($0)) }
final class RolloverBtn: NSButton { override func hitTest(_ p: NSPoint) -> NSView? { nil } }   // 커서 효과만 · 클릭은 칸이 받음
let cardBoxStyle = Int(ProcessInfo.processInfo.environment["DONUT_CARDBOX"] ?? "") ?? 1, cardBoxes = cardBoxStyle > 0, cardNoFrame = cardBoxes || ProcessInfo.processInfo.environment["DONUT_FRAME"] == nil   // 사진 흰 프레임 없음 (사용자 2026-11-07) · DONUT_FRAME = 예전   // 시안: 첫 패널 규격마다 칸 + 사진 흰 테두리 없음
final class SizeListView: ThemedPanel {
    weak var controller: Controller?
    let wellL = CALayer(), topBarL = CALayer(), tbar = TitleBar(), tbBox = PassView()
    var boxes: [NSView] = [], boxOf: [Int: NSView] = [:], pressed = -1
    var macHover: Bool { cardBoxStyle == 1 }   // 칸 1번: 커서 올리면 칸이 살짝 진해짐 · 누르면 한 단계 더 (맥 버튼처럼, 사용자 2026-11-07)
    var items: [Int: (cell: NSView, frame: NSView, thumb: NSImageView, name: NSTextField, size: NSTextField)] = [:]
    var thumbs: [NSImageView] = []   // webSpecs 번호 → 썸네일 (패널에 없는 규격은 숨은 뷰)
    let customBox = NSView(), customPlus = NSTextField(labelWithString: "+"), customName = NSTextField(labelWithString: "프로필"), customDash = CAShapeLayer(), sep = NSView()
    var hover = -1
    var showCustom = true { didSet { items[customCell]?.cell.isHidden = !showCustom } }   // 프로필 (포토샵 가이드에선 숨김)
    init(frame: NSRect) {
        super.init(frame: frame, radius: 18); dragBand = cardPadTop + 8
        thumbs = Converter.webSpecs.map { _ in NSImageView() }
        var y = frame.height - cardPadTop
        for (ri, row) in cardRows.enumerated() {
            let ph = cardRowPhotoH(row), maxW = cardRows.map(cardRowW).max() ?? cardRowW(row), extra = row.count > 1 ? (maxW - cardRowW(row)) / CGFloat(row.count - 1) : 0; var x = (frame.width - maxW) / 2   // 짧은 줄은 간격을 넓혀 양끝을 긴 줄과 맞춤 (사용자 2026-11-07)
            for i in row {
                let w = cardItemW(i), h = cardItemPhotoH(i)
                let cell = NSView(frame: NSRect(x: x, y: y - ph - cardTextH, width: w, height: ph + cardTextH)); cell.wantsLayer = true
                if i == customCell {   // 프로필: 증명처럼 카드 · 흰 바탕에 PROFILE (Didot 대문자, 사용자 2026-11-07)
                    let fr = NSView(frame: NSRect(x: 0, y: cardTextH, width: w, height: h)); fr.wantsLayer = true; fr.layer?.backgroundColor = NSColor.white.cgColor
                    fr.layer?.shadowColor = NSColor(srgbRed: 0.31, green: 0.24, blue: 0.12, alpha: 1).cgColor; fr.layer?.shadowOpacity = 0.16; fr.layer?.shadowRadius = 3; fr.layer?.shadowOffset = CGSize(width: 0, height: -2)
                    let pt = NSTextField(labelWithString: ""); let ps = NSMutableParagraphStyle(); ps.alignment = .center
                    pt.attributedStringValue = NSAttributedString(string: "PROFILE", attributes: [.font: NSFont(name: "Didot", size: 12.5) ?? .systemFont(ofSize: 12), .kern: 1.6, .foregroundColor: NSColor(white: 0.11, alpha: 1), .paragraphStyle: ps])
                    pt.frame = NSRect(x: 0, y: (h - 18) / 2, width: w, height: 18); fr.addSubview(pt); cell.addSubview(fr)
                    let n = label("프로필", 10, .black); n.font = .systemFont(ofSize: 10, weight: .light); n.alignment = .center; n.frame = NSRect(x: -20, y: 14, width: w + 40, height: 17); cell.addSubview(n)
                    let s = label("5×7 · 4×6 in", 8.5, .gray); s.alignment = .center; s.frame = NSRect(x: -20, y: 3, width: w + 40, height: 14); cell.addSubview(s)
                    addBox(cell, extra, row.firstIndex(of: i) ?? 0, row.count, h); if cardBoxes { boxOf[i] = boxes.last }; addSubview(cell); items[i] = (cell, fr, NSImageView(), n, s); x += w + cardGapX + extra; continue }
                if i == directCell {   // Custom: 예전 '+ 프로필' 점선 칸 모양 그대로
                    customName.stringValue = "Custom"
                    customBox.frame = NSRect(x: 0, y: cardTextH, width: w, height: h)   // 사진들과 아래를 맞춤
                    customBox.wantsLayer = true; customDash.path = CGPath(roundedRect: customBox.bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 6, cornerHeight: 6, transform: nil)
                    customDash.fillColor = nil; customDash.lineWidth = 1.5; customDash.lineDashPattern = [4, 3]; customBox.layer?.addSublayer(customDash); cell.addSubview(customBox)
                    customPlus.font = .systemFont(ofSize: 28, weight: .ultraLight); customPlus.alignment = .center; customPlus.frame = NSRect(x: 0, y: h / 2 - 4, width: w, height: 34); customBox.addSubview(customPlus)
                    customName.font = .systemFont(ofSize: 10.5, weight: .regular); customName.alignment = .center; customName.frame = NSRect(x: 0, y: h / 2 - 24, width: w, height: 16); customBox.addSubview(customName)
                    addBox(cell, extra, row.firstIndex(of: i) ?? 0, row.count, h); if cardBoxes { boxOf[i] = boxes.last; cell.frame.origin.y -= (cardTextH / 2).rounded() - 4 }; addSubview(cell); items[i] = (cell, customBox, NSImageView(), customName, customName); x += w + cardGapX + extra; continue
                }
                let fr = NSView(frame: NSRect(x: 0, y: cardTextH, width: w, height: h)); fr.wantsLayer = true; fr.layer?.backgroundColor = NSColor.white.cgColor
                fr.layer?.shadowColor = NSColor(srgbRed: 0.31, green: 0.24, blue: 0.12, alpha: 1).cgColor; fr.layer?.shadowOpacity = 0.16; fr.layer?.shadowRadius = 3; fr.layer?.shadowOffset = CGSize(width: 0, height: -2)
                let iv = thumbs[i]; let bw = cardNoFrame ? 0 : cardBW; iv.frame = NSRect(x: bw, y: bw, width: w - bw * 2, height: h - bw * 2); iv.imageScaling = .scaleAxesIndependently; iv.wantsLayer = true; iv.layer?.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
                fr.addSubview(iv); cell.addSubview(fr)
                let sp = Converter.webSpecs[i]
                let n = label(sp.name, 10, .black); n.font = .systemFont(ofSize: 10, weight: .light); n.alignment = .center; n.frame = NSRect(x: -20, y: 14, width: w + 40, height: 17); cell.addSubview(n)
                let s = label(sp.size.replacingOccurrences(of: "cm", with: " cm"), 8.5, .gray); s.alignment = .center; s.frame = NSRect(x: -20, y: 3, width: w + 40, height: 14); cell.addSubview(s)
                addBox(cell, extra, row.firstIndex(of: i) ?? 0, row.count, h); if cardBoxes { boxOf[i] = boxes.last }; addSubview(cell); items[i] = (cell, fr, iv, n, s); x += w + cardGapX + extra
            }
            y -= ph + cardTextH
            if ri == 0 { sep.frame = NSRect(x: cardPadX - 6, y: y - 13, width: frame.width - (cardPadX - 6) * 2, height: 1); sep.wantsLayer = true; addSubview(sep); y -= cardSepH }
        }
        applyTheme()
    }
    func addBox(_ cell: NSView, _ ex: CGFloat = 0, _ k: Int = 0, _ n: Int = 1, _ h: CGFloat = 0) { guard cardBoxes else { return }; let pad: CGFloat = cardBoxStyle == 4 ? -13 : -10; var bf = cell.frame.insetBy(dx: pad, dy: pad); bf.origin.x -= ex * CGFloat(k) / CGFloat(n); bf.size.width += ex * CGFloat(n - 1) / CGFloat(n); cell.frame.origin.x = (bf.midX - cell.frame.width / 2).rounded(); cell.frame.origin.y += (cardAlignBottom ? 0 : ((cell.frame.height - cardTextH - h) / 2).rounded()) - 7; let b = NSView(frame: bf); b.wantsLayer = true; b.layer?.cornerRadius = cardBoxStyle == 4 ? 14 : 10; addSubview(b); boxes.append(b)
        if let st = hoverBezel { let r = RolloverBtn(frame: b.bounds); r.title = ""; r.bezelStyle = st; r.showsBorderOnlyWhileMouseInside = true; r.autoresizingMask = [.width, .height]; b.addSubview(r) } }   // 시험: 커서 효과를 맥이 직접 그림 (DONUT_HOVER = 버튼 모양 번호)   // 판 위 · 칸(사진·글자)보다 먼저 = 아래   // 시안: 규격마다 칸 (1 흰 칸·회색 바탕 · 2 흰 판 위 옅은 회색 칸 · 3 흰 판 위 테두리 칸 · 4 떠 있는 큰 칸)
    required init?(coder: NSCoder) { fatalError() }
    func setUI() {   // 상단바·칸 (상단바는 화면 크기 그대로)
        if tbBox.superview == nil { addSubview(tbBox); tbBox.addSubview(tbar) }
        screenBox(tbBox, top: true, h: titleBarH, W: frame.width, H: frame.height); let S = frame.width * uiK
        tbar.frame = NSRect(x: 0, y: 0, width: S, height: titleBarH); tbar.place(width: S); applyTitleBG(self, topBarL)
        CATransaction.begin(); CATransaction.setDisableActions(true); var w = bounds.insetBy(dx: 6, dy: 6); w.size.height -= titleBarH / uiK; wellL.frame = w; CATransaction.commit() }
    func applyTheme() {
        applyPanelTheme(); let c = panelColors()
        if wellL.superlayer == nil { wellL.cornerRadius = 10; tint.layer?.addSublayer(wellL) }   // 바탕 판(tint) 위   // 카드 뒤 칸 (Custom 자르기 칸처럼, 2026-11-05)
        wellL.backgroundColor = adjWell(c).cgColor; tbar.style(c); setUI()   // 시안: 첫 화면도 신호등 상단바
        let st = cardBoxStyle; wellL.isHidden = st == 1 || st == 4; sep.isHidden = cardBoxes
        for b in boxes { let l = b.layer!; l.shadowColor = NSColor.black.cgColor; l.borderWidth = 0; l.shadowOpacity = 0
            switch st {
            case 1: l.backgroundColor = adjWell(c).cgColor; l.shadowOpacity = c.dark ? 0.3 : 0.06; l.shadowRadius = 2; l.shadowOffset = CGSize(width: 0, height: -1)
            case 2: l.backgroundColor = (c.dark ? NSColor(white: 0.33, alpha: 1) : NSColor(white: 0.955, alpha: 1)).cgColor
            case 3: l.backgroundColor = nil; l.borderWidth = 1; l.borderColor = (c.dark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.09)).cgColor
            default: l.backgroundColor = adjWell(c).cgColor; l.shadowOpacity = c.dark ? 0.4 : 0.12; l.shadowRadius = 7; l.shadowOffset = CGSize(width: 0, height: -3) } }
        if macHover { for i in boxOf.keys { paintBox(i, 0) } }
        sep.layer?.backgroundColor = c.ln.cgColor
        for (i, it) in items where i != directCell { it.name.textColor = c.tx.withAlphaComponent(c.dark ? 1 : 0.8); it.size.textColor = c.sub.withAlphaComponent(c.dark ? 1 : 0.8)
            it.frame.layer?.shadowColor = (c.dark ? NSColor.black : NSColor(srgbRed: 0.31, green: 0.24, blue: 0.12, alpha: 1)).cgColor; it.frame.layer?.shadowOpacity = c.dark ? 0.5 : 0.16 }
        hover = -2; setHover(-1)
    }
    func setThumb(_ i: Int, _ im: NSImage?) { guard i >= 0, i < thumbs.count else { return }; if im != nil, let l = thumbs[i].layer { let t = CATransition(); t.type = .fade; t.duration = 0.18; l.add(t, forKey: "thumbFade") }; thumbs[i].image = im }   // 썸네일은 살짝 페이드로 (갑자기 바뀌지 않게)
    override func updateTrackingAreas() { trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)); super.updateTrackingAreas() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53, controller?.picking == true { debugLog("Esc 받음 (카드)"); controller?.endPick() } else { super.keyDown(with: e) } }
    override func cancelOperation(_ sender: Any?) { if controller?.picking == true { controller?.endPick() } }
    override func mouseMoved(with e: NSEvent) { guard controller?.picking == true else { return }; setHover(cell(at: convert(e.locationInWindow, from: nil))) }
    override func mouseExited(with e: NSEvent) { setHover(-1) }
    override func scrollWheel(with e: NSEvent) {}   // 스크롤로 패널 크기 바꾸기 뺌 (사용자 2026-11-05: 늘어났다 줄어들어 이상함). 크기는 ydot 메뉴 Preview Size
    override func mouseDown(with e: NSEvent) { guard controller?.picking == true else { return }; let i = cell(at: convert(e.locationInWindow, from: nil))
        if macHover { pressed = i; if i >= 0 { paintBox(i, 0.06) }; return }
        activate(i) }
    override func mouseDragged(with e: NSEvent) { guard macHover, pressed >= 0 else { return }; let inside = cell(at: convert(e.locationInWindow, from: nil)) == pressed
        if inside != (hover == pressed) { hover = inside ? pressed : -1; paintBox(pressed, 0.1) } }
    override func mouseUp(with e: NSEvent) { guard macHover, pressed >= 0 else { return }; let i = pressed, j = cell(at: convert(e.locationInWindow, from: nil)); pressed = -1; hover = j; paintBox(i, 0.15)
        if j == i && controller?.picking == true { activate(i) } }
    func activate(_ i: Int) { if i == customCell { controller?.beginCustom() } else if i == directCell { controller?.pickDirect() } else if i >= 0 { if !macHover { pressAnim(i) }; controller?.pick(i) } }
    func boxFill(_ i: Int) -> NSColor { let c = panelColors(), st = pressed == i ? 2 : hover == i ? 1 : 0
        return c.dark ? adjWell(c).blended(withFraction: [0, 0.07, 0.13][st], of: .white)! : adjWell(c).blended(withFraction: [0, 0.045, 0.09][st], of: .black)! }
    func paintBox(_ i: Int, _ dur: CFTimeInterval) { guard let l = boxOf[i]?.layer else { return }; let to = boxFill(i).cgColor
        if dur > 0 { let a = CABasicAnimation(keyPath: "backgroundColor"); a.fromValue = l.presentation()?.backgroundColor ?? l.backgroundColor; a.toValue = to; a.duration = dur; a.timingFunction = CAMediaTimingFunction(name: .easeOut); l.add(a, forKey: "fill") }
        CATransaction.begin(); CATransaction.setDisableActions(true); l.backgroundColor = to; CATransaction.commit() }
    func pressAnim(_ i: Int) { guard let l = items[i]?.frame.layer else { return }; let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 0.7; a.toValue = 1; a.duration = 0.15; l.add(a, forKey: "press") }
    func setHover(_ i: Int) {   // 올린 사진만 또렷하고 위로 4pt · 나머지는 옅게 (흑백 없음)
        guard i != hover else { return }; hover = i
        if macHover && hoverBezel == nil { let c = panelColors(); for k in boxOf.keys { paintBox(k, 0.2) }
            customDash.strokeColor = (i == directCell ? sysBlue : c.sub.withAlphaComponent(0.45)).cgColor; customPlus.textColor = i == directCell ? sysBlue : c.sub; customName.textColor = i == directCell ? sysBlue : c.sub; return }
        if hoverBezel != nil { let c = panelColors(); customDash.strokeColor = c.sub.withAlphaComponent(0.45).cgColor; customPlus.textColor = c.sub; customName.textColor = c.sub; return }
        let c = panelColors()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.3; ctx.allowsImplicitAnimation = true
            for (k, it) in items {
                let on = k == i, dim = i >= 0 && !on
                it.cell.animator().alphaValue = dim ? 0.4 : 1
                if k == directCell {
                    customDash.strokeColor = (on ? sysBlue : c.sub.withAlphaComponent(0.45)).cgColor
                    customPlus.textColor = on ? sysBlue : c.sub; customName.textColor = on ? sysBlue : c.sub
                    continue }
                it.frame.animator().setFrameOrigin(NSPoint(x: 0, y: cardTextH + (on ? 4 : 0)))
                it.frame.layer?.shadowRadius = on ? 11 : 3; it.frame.layer?.shadowOffset = CGSize(width: 0, height: on ? -10 : -2); it.frame.layer?.shadowOpacity = on ? (c.dark ? 0.6 : 0.25) : (c.dark ? 0.5 : 0.16)
            }
        }
    }
    func cell(at p: NSPoint) -> Int { for (k, it) in items where it.cell.frame.insetBy(dx: -cardGapX / 2, dy: -14).contains(p) && !(k == customCell && !showCustom) { return k }; return -1 }   // 사진 사이 빈틈도 가까운 칸으로 → 옮겨 갈 때 깜빡이지 않음 (2026-11-05)
}

// 게이지 (맥 기본 가로 슬라이더) — 놓을 때 알림 (한계값으로 스냅)
final class SnapSlider: NSSlider {
    var onRelease: (() -> Void)?
    var dragging = false
    override func mouseDown(with e: NSEvent) { dragging = true; super.mouseDown(with: e); dragging = false; onRelease?() }   // super가 끌기 동안 붙잡고 있다가 놓으면 돌아옴
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
// 게이지 아래: 양 끝 숫자 + 기본값 자리 세로 눈금
final class GaugeTicks: NSView {
    var lo = "", hi = "", def: CGFloat = 0.5, col = NSColor.gray
    override func draw(_ r: NSRect) {
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular), .foregroundColor: col]
        let inset: CGFloat = 10, w = bounds.width - inset * 2
        let ls = NSAttributedString(string: lo, attributes: a), hs = NSAttributedString(string: hi, attributes: a)
        ls.draw(at: NSPoint(x: inset - ls.size().width / 2, y: 0)); hs.draw(at: NSPoint(x: inset + w - hs.size().width / 2, y: 0))
        col.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect: NSRect(x: inset + w * def - 0.75, y: bounds.height - 7, width: 1.5, height: 7), xRadius: 0.75, yRadius: 0.75).fill()
    }
}

// MARK: 2. 얼굴·여백 조절 화면 (아래 도구 막대 · 원본 한계 넘으면 검은 부분, 놓으면 한계로 스냅)
let adjustSize = NSSize(width: 620, height: 560)
let faceRange: ClosedRange<Double> = 1.5...4.5, topRange: ClosedRange<Double> = -0.5...1
final class AdjustView: ThemedPanel {
    weak var controller: Controller?
    let photo = NSImageView(), over = LayerHost(), bar = NSView()   // over = 치수선 그림 전용(마우스 안 받음 — 예전엔 위 버튼을 가려 뒤로·Default가 안 눌렸음, 2026-11-05)
    let dash = CAShapeLayer(), dimLine = CAShapeLayer(), labelBox = CALayer(), labelText = CATextLayer()
    let title = NSTextField(labelWithString: ""), sizeL = NSTextField(labelWithString: "")
    let faceT = NSTextField(labelWithString: "얼굴"), faceV = NSTextField(labelWithString: ""), topT = NSTextField(labelWithString: "여백"), topV = NSTextField(labelWithString: "")
    let slider = SnapSlider(value: 2.6, minValue: faceRange.lowerBound, maxValue: faceRange.upperBound, target: nil, action: nil)
    let topSlider = SnapSlider(value: 0.25, minValue: topRange.lowerBound, maxValue: topRange.upperBound, target: nil, action: nil)
    let faceTicks = GaugeTicks(), topTicks = GaugeTicks()
    // Custom(이번만 크기): 가로·세로 게이지 한 줄 더 (얼굴·여백과 같은 모양, 0.1 cm씩, 사용자 2026-11-07)
    let wT = NSTextField(labelWithString: "가로"), wV = NSTextField(labelWithString: ""), hT = NSTextField(labelWithString: "세로"), hV = NSTextField(labelWithString: "")
    let wSl = SnapSlider(value: 3.5, minValue: 2, maxValue: 7, target: nil, action: nil), hSl = SnapSlider(value: 4.5, minValue: 2.5, maxValue: 9, target: nil, action: nil), wTicks = GaugeTicks(), hTicks = GaugeTicks()
    var dirViews: [NSView] { [wT, wV, hT, hV, wSl, hSl, wTicks, hTicks] }
    var direct = false { didSet { guard oldValue != direct else { return }; dirViews.forEach { $0.isHidden = !direct }; setUI() } }
    @objc func sizeChanged() {   // 가로·세로 → 틀 크기·제목·사진을 바로 (끄는 동안 계속)
        let w = (wSl.doubleValue * 10).rounded() / 10, h = (hSl.doubleValue * 10).rounded() / 10
        spec = Converter.WebSpec(name: "Custom", w: w, h: h, headCm: head, topCm: topM)
        wV.stringValue = String(format: "%.1f cm", w); hV.stringValue = String(format: "%.1f cm", h)
        titlePill.set("Custom", "\(trimNum(w))×\(trimNum(h)) cm", animated: false); layoutTitle(); layoutPhoto(); fitToLimits(); changed() }
    var back: PillButton!, reset: PillButton!, save: PillButton!
    var spec = Converter.webSpecs[0]
    var limits: (fLo: Double, mLo: Double, mHi: Double) = (faceRange.lowerBound, topRange.lowerBound, topRange.upperBound)
    init(frame: NSRect) {
        super.init(frame: frame, radius: 18)
        back = PillButton("← 뒤로", target: self, action: #selector(goBack)); reset = PillButton("Default", hint: "⌘0", target: self, action: #selector(doReset)); save = PillButton("Save", target: self, action: #selector(doSave))
        back.frame = NSRect(x: 18, y: frame.height - 44, width: back.fitWidth(70), height: 28); reset.frame = NSRect(x: frame.width - 18 - reset.fitWidth(), y: frame.height - 44, width: reset.fitWidth(), height: 28)
        topB.addSubview(back); topB.addSubview(titlePill); botB.addSubview(reset)   // Default = 아래 Save 옆 (2026-11-05)
        title.font = .systemFont(ofSize: 13.5, weight: .medium); sizeL.font = .systemFont(ofSize: 10.5)
        topC.addSubview(title); topC.addSubview(sizeL)
        photo.imageScaling = .scaleAxesIndependently; photo.wantsLayer = true; photo.layer?.backgroundColor = NSColor.black.cgColor
        photo.layer?.shadowColor = NSColor.black.cgColor; photo.layer?.shadowOpacity = 0.18; photo.layer?.shadowRadius = 9; photo.layer?.shadowOffset = CGSize(width: 0, height: -6)   // 테두리 없이 그림자만
        addSubview(photo)
        over.frame = bounds; over.wantsLayer = true; addSubview(over)
        dash.strokeColor = NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 0.75).cgColor; dash.lineWidth = 1; dash.lineDashPattern = [3, 3]; dash.fillColor = nil
        dimLine.strokeColor = sysBlue.cgColor; dimLine.lineWidth = 1   // 얇게 (사용자 2026-11-05); dimLine.fillColor = sysBlue.cgColor
        labelBox.cornerRadius = 6; labelBox.borderWidth = 1; labelBox.borderColor = sysBlue.cgColor
        labelText.contentsScale = NSScreen.main?.backingScaleFactor ?? 2; labelText.alignmentMode = .center
        for l in [dash, dimLine, labelBox] as [CALayer] { over.layer?.addSublayer(l) }; labelBox.addSublayer(labelText)
        // 아래 도구 막대
        bar.frame = NSRect(x: 16, y: 14, width: frame.width - 32, height: 70); bar.wantsLayer = true; bar.layer?.cornerRadius = 16; bar.layer?.borderWidth = 0.5
        bar.layer?.shadowColor = NSColor.black.cgColor; bar.layer?.shadowOpacity = 0.08; bar.layer?.shadowRadius = 5; bar.layer?.shadowOffset = CGSize(width: 0, height: -2); botC.addSubview(bar); addSubview(topC); addSubview(botC)
        let saveW: CGFloat = 76, gw = (bar.frame.width - 14 * 2 - saveW - 18 * 2) / 2
        for (k, (t, v, sl, tk)) in [(faceT, faceV, slider, faceTicks), (topT, topV, topSlider, topTicks)].enumerated() {
            let x = 14 + CGFloat(k) * (gw + 18)
            t.font = .systemFont(ofSize: 11); t.frame = NSRect(x: x, y: 46, width: 60, height: 15); bar.addSubview(t)
            v.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); v.alignment = .right; v.frame = NSRect(x: x + gw - 80, y: 46, width: 80, height: 15); bar.addSubview(v)
            sl.isContinuous = true; sl.controlSize = .small; sl.trackFillColor = sysBlue; sl.target = self; sl.action = #selector(changed); sl.frame = NSRect(x: x - 2, y: 22, width: gw + 4, height: 22)
            sl.onRelease = { [weak self] in self?.released() }; bar.addSubview(sl)
            tk.frame = NSRect(x: x, y: 6, width: gw, height: 16); bar.addSubview(tk)
        }
        for (t, v, sl, tk) in [(wT, wV, wSl, wTicks), (hT, hV, hSl, hTicks)] {
            t.font = .systemFont(ofSize: 11); bar.addSubview(t); v.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); v.alignment = .right; bar.addSubview(v)
            sl.isContinuous = true; sl.controlSize = .small; sl.trackFillColor = sysBlue; sl.target = self; sl.action = #selector(sizeChanged); bar.addSubview(sl); bar.addSubview(tk) }
        wTicks.lo = "2"; wTicks.hi = "7"; wTicks.def = CGFloat((3.5 - 2) / 5); hTicks.lo = "2.5"; hTicks.hi = "9"; hTicks.def = CGFloat((4.5 - 2.5) / 6.5); dirViews.forEach { $0.isHidden = true }
        save.frame = NSRect(x: bar.frame.width - 14 - saveW, y: 17, width: saveW, height: 36); save.layer?.cornerRadius = 18; save.keyEquivalent = "\r"; botB.addSubview(save); addSubview(topB); addSubview(botB)
        setUI()
    }
    required init?(coder: NSCoder) { fatalError() }
    let topB = PassView(), botB = PassView()   // 버튼만 담는 화면 1:1 틀
    // 위 막대(뒤로·제목·Default) 58pt · 아래 막대(게이지·Save) 96pt는 화면에서 늘 같은 크기. 사진 자리만 Panel Size 따라 커지고 작아짐 (2026-11-05)
    let tbar = TitleBar()
    let topC = NSView(), botC = NSView(); let topH: CGFloat = 68 + titleBarH; var botH: CGFloat { direct ? 156 : 96 }   // Custom = 아래 막대 한 줄 더   // 위 = 상단바 30 + 버튼 줄 + 제목 칸   // 68 = 버튼 줄 + 그 아래 제목 칸 (2026-11-05)
    let topBarL = CALayer()
    let wellL = CALayer()   // 사진 뒤 칸 (Custom 자르기 칸과 같은 자리·모양, 2026-11-05)
    var shownImage: NSImage?
    func setUI() {
        let p = uiP, inv = p / uiK, f = 1 / p, W = frame.width, H = frame.height, w = W * uiK / p
        topC.frame = NSRect(x: 0, y: H - topH * inv, width: W, height: topH * inv); topC.bounds = NSRect(x: 0, y: 0, width: w, height: topH)
        botC.frame = NSRect(x: 0, y: 0, width: W, height: botH * inv); botC.bounds = NSRect(x: 0, y: 0, width: w, height: botH)
        let S = W * uiK; screenBox(topB, top: true, h: topH * p, W: W, H: H); screenBox(botB, top: false, h: botH * p, W: W, H: H)
        let bw = back.fitWidth(66), rw = reset.fitWidth()
        back.frame = NSRect(x: 18 * p, y: 38 * p - 14, width: bw, height: 28)
        if tbar.superview == nil { topB.addSubview(tbar) }; tbar.frame = NSRect(x: 0, y: topH * p - titleBarH, width: S, height: titleBarH); tbar.place(width: S)
        let barH: CGFloat = direct ? 130 : 70; bar.frame = NSRect(x: 10, y: 14, width: w - 20, height: barH)
        let saveW = save.fitWidth(56), gw = (bar.frame.width - 14 * 2 - (saveW + 8 + rw) * f - 18 * 2) / 2
        var rows: [[(NSTextField, NSTextField, NSSlider, GaugeTicks)]] = [[(faceT, faceV, slider, faceTicks), (topT, topV, topSlider, topTicks)]]
        if direct { rows.insert([(wT, wV, wSl, wTicks), (hT, hV, hSl, hTicks)], at: 0) }   // 위 줄 = 가로·세로, 아래 줄 = 얼굴·여백
        for (ri, row) in rows.enumerated() { let dy = CGFloat(rows.count - 1 - ri) * 60   // 줄 사이 = 눈금 글자와 이름이 안 겹치게
            for (k, (t, v, sl, tk)) in row.enumerated() {
                let x = 14 + CGFloat(k) * (gw + 18)
                t.frame = NSRect(x: x, y: 46 + dy, width: 60, height: 15); v.frame = NSRect(x: x + gw - 80, y: 46 + dy, width: 80, height: 15)
                sl.frame = NSRect(x: x - 2, y: 22 + dy, width: gw + 4, height: 22); tk.frame = NSRect(x: x, y: 6 + dy, width: gw, height: 16); tk.needsDisplay = true } }
        let by = (14 + barH / 2) * p - 14   // Save·Default = 막대 세로 가운데
        save.frame = NSRect(x: S - 24 * p - saveW, y: by, width: saveW, height: 28); save.layer?.cornerRadius = 14
        reset.frame = NSRect(x: save.frame.minX - 8 - rw, y: by, width: rw, height: 28)
        layoutTitle(); layoutPhoto(); applyTitleBG(self, topBarL)
    }
    let titlePill = TitlePill()
    func layoutTitle() { if titlePill.animating { return }; let w = titlePill.fitW; titlePill.frame = NSRect(x: ((frame.width * uiK - w) / 2).rounded(), y: (38 * uiP - 10 - TitlePill.H / 2).rounded(), width: w, height: TitlePill.H); title.isHidden = true; sizeL.isHidden = true }   // 버튼보다 10 아래   // 제목 칸 (화면 크기 그대로, 버튼 줄 가운데)
    func layoutPhoto() {
        let inv = uiP / uiK, areaTop = frame.height - topH * inv, areaBottom = botH * inv, h: CGFloat = max(60, min(370, areaTop - areaBottom - 24 * inv))
        if wellL.superlayer == nil { wellL.cornerRadius = 10; tint.layer?.addSublayer(wellL) }   // 바탕 판(tint) 위
        CATransaction.begin(); CATransaction.setDisableActions(true); wellL.frame = CGRect(x: 10 * inv, y: areaBottom, width: frame.width - 20 * inv, height: areaTop - areaBottom); wellL.backgroundColor = adjWell(panelColors()).cgColor; CATransaction.commit()
        K = h / CGFloat(spec.h)
        let pw = (CGFloat(spec.w) * K).rounded(), ph = (CGFloat(spec.h) * K).rounded()
        photo.frame = NSRect(x: ((frame.width - pw) / 2).rounded(), y: (areaBottom + (areaTop - areaBottom - ph) / 2).rounded(), width: pw, height: ph)
        update()
    }
    func applyTheme(_ glass: Bool = false) {
        applyPanelTheme(); let c = panelColors()
        for b in [back!, reset!] { b.style(c) }; save.style(c, primary: true)
        title.textColor = c.tx; sizeL.textColor = c.sub; titlePill.style(c); tbar.style(c); applyTitleBG(self, topBarL)
        // 사진 둘레 사방 그림자: 흰 배경 증명사진이 밝은 바탕에서도 가장자리가 보이게 (2026-11-05)
        photo.layer?.shadowOffset = CGSize(width: 0, height: c.dark ? -6 : -1); photo.layer?.shadowRadius = c.dark ? 9 : 7; photo.layer?.shadowOpacity = c.dark ? 0.45 : 0.3
        photo.layer?.borderWidth = c.dark ? 0 : 0.5; photo.layer?.borderColor = NSColor(white: 0, alpha: 0.1).cgColor; wellL.backgroundColor = adjWell(c).cgColor
        bar.layer?.backgroundColor = c.btn.cgColor; bar.layer?.borderColor = (c.dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.1)).cgColor
        for t in [faceT, topT, wT, hT] { t.textColor = c.sub }; for v in [wV, hV] { v.textColor = c.tx }
        for t in [faceTicks, topTicks, wTicks, hTicks] { t.col = c.sub; t.needsDisplay = true }; wSl.appearance = appearance; hSl.appearance = appearance
        labelBox.backgroundColor = c.btn.cgColor
        slider.appearance = appearance; topSlider.appearance = appearance
        update()
    }
    var K: CGFloat = 80
    func show(_ sp: Converter.WebSpec, image: NSImage?) {
        spec = sp
        let t = NSMutableAttributedString(string: sp.name, attributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: .medium)])
        title.attributedStringValue = t; title.sizeToFit()
        sizeL.stringValue = sp.size.replacingOccurrences(of: "×", with: "×").replacingOccurrences(of: "cm", with: " cm"); sizeL.sizeToFit()
        titlePill.set(sp.name, sp.size.replacingOccurrences(of: "cm", with: " cm"), animated: false); layoutTitle(); shownImage = image; photo.image = image; layoutPhoto()
        faceTicks.lo = trimNum(faceRange.lowerBound); faceTicks.hi = trimNum(faceRange.upperBound); faceTicks.def = CGFloat((sp.headCm - faceRange.lowerBound) / (faceRange.upperBound - faceRange.lowerBound))
        topTicks.lo = trimNum(topRange.lowerBound); topTicks.hi = trimNum(topRange.upperBound); topTicks.def = CGFloat((sp.topCm - topRange.lowerBound) / (topRange.upperBound - topRange.lowerBound))
        faceTicks.needsDisplay = true; topTicks.needsDisplay = true
        slider.doubleValue = sp.headCm; topSlider.doubleValue = sp.topCm
        if direct { wSl.doubleValue = sp.w; hSl.doubleValue = sp.h; wV.stringValue = String(format: "%.1f cm", sp.w); hV.stringValue = String(format: "%.1f cm", sp.h); wTicks.needsDisplay = true; hTicks.needsDisplay = true }
        fitToLimits(); update()
    }
    func trimNum(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
    var head: Double { (slider.doubleValue * 100).rounded() / 100 }
    var topM: Double { (topSlider.doubleValue * 100).rounded() / 100 }
    func limitsFor(_ f: Double, _ m: Double) -> (fLo: Double, mLo: Double, mHi: Double) { controller?.adjustLimits(spec, f, m) ?? (faceRange.lowerBound, topRange.lowerBound, topRange.upperBound) }
    func clampFace(_ f: Double, _ m: Double) -> Double { let L = limitsFor(f, m); return min(faceRange.upperBound, max(L.fLo, f)) }
    func clampTop(_ f: Double, _ m: Double) -> Double { let L = limitsFor(f, m); return min(max(L.mLo, L.mHi), max(L.mLo, m)) }
    func fitToLimits() { var f = head, m = topM; for _ in 0..<3 { f = clampFace(f, m); m = clampTop(f, m) }; slider.doubleValue = f; topSlider.doubleValue = m }
    func overLimit() -> (Bool, Bool) { let f = head, m = topM; return (abs(clampFace(f, m) - f) > 0.004, abs(clampTop(f, m) - m) > 0.004) }
    func update() {
        let c = panelColors(), (fo, mo) = overLimit()
        faceV.stringValue = String(format: "%.2f cm", head); faceV.textColor = fo ? limitOrange : c.tx
        topV.stringValue = String(format: "%.2f cm", topM); topV.textColor = mo ? limitOrange : c.tx
        // 치수선: 정수리·턱 회색 점선(사진 가운데 → 치수선까지), 파란 치수선 + 값 라벨
        let pillHalf = DimStyle.v == 2 ? (ceil(NSAttributedString(string: String(format: "%.2f cm", head), attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11 * uiP / uiK, weight: .medium)]).size().width) + 14 * uiP / uiK) / 2 : 0
        func snap(_ p: NSPoint) -> NSPoint { let b = convertToBacking(p); return convertFromBacking(NSPoint(x: floor(b.x), y: floor(b.y))) }   // 화면 픽셀 정가운데 (패널 그릇 좌표가 반 픽셀 어긋나 있어 +0.5 없이가 맞음, 실측) → 1픽셀이 또렷하게 (두 픽셀에 번지지 않게)
        let f = photo.frame, raw1 = f.maxY - CGFloat(topM) * K, raw2 = raw1 - CGFloat(head) * K, rdx = f.maxX + max(18, pillHalf + 10 * uiP / uiK)   // 알약이 사진과 안 겹치게
        let p1 = snap(NSPoint(x: f.maxX + 12 * uiP / uiK, y: raw1)), p2 = snap(NSPoint(x: f.maxX + 12 * uiP / uiK, y: raw2)), dx = p1.x, y1 = p1.y, y2 = p2.y, mid = (y1 + y2) / 2   // 선 = 사진 가까이
        let pillX = rdx   // 알약 = 예전 자리 그대로 (선 오른쪽)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let d = CGMutablePath(); for y in [y1, y2] { d.move(to: CGPoint(x: f.midX, y: y)); d.addLine(to: CGPoint(x: dx, y: y)) }; dash.path = d
        let inv = uiP / uiK, st = DimStyle.v   // 값 라벨 = 막대와 같이 반쯤만 따라감
        let blue = DimStyle.gray ? (c.dark ? NSColor(white: 0.8, alpha: 1) : NSColor(white: 0.27, alpha: 1)) : (c.dark ? NSColor(srgbRed: 0.2, green: 0.5, blue: 0.98, alpha: 1) : NSColor(srgbRed: 0.0, green: 0.38, blue: 0.86, alpha: 1))   // 원래 파랑보다 조금 진하게 (사용자 2026-11-05)
        dimLine.strokeColor = blue.cgColor; dimLine.fillColor = blue.cgColor
        let hair = 1 / ((window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) * uiK); dimLine.lineWidth = hair; dash.lineWidth = hair   // 포토샵 안내선처럼 화면 1픽셀 (사용자 2026-11-05)
        let txt = st == 4 || st == 2 ? String(format: "%.2f cm", head) : String(format: "%.2f", head)
        let fg: NSColor = st == 2 ? (DimStyle.gray && c.dark ? NSColor(white: 0.1, alpha: 1) : .white) : blue, wt: NSFont.Weight = st == 1 || st == 4 ? .semibold : .medium
        let s = NSAttributedString(string: txt, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: (st == 0 ? 11 : 11) * inv, weight: st == 0 ? .regular : wt), .foregroundColor: fg])
        let tw = ceil(s.size().width), th = ceil(s.size().height)
        let lw = st == 1 || st == 4 ? tw : tw + 14 * inv, lh = st == 1 || st == 4 ? th : 20 * inv
        let gap: CGFloat = st == 2 ? 0 : st == 0 ? 0 : (st == 4 ? lw : lh) + 8 * inv   // 선이 끊기는 길이 (알약은 선 밖이라 안 끊음)
        let b = CGMutablePath()
        let e = DimStyle.cap ? CGFloat(0) : 5
        if gap > 0 { b.move(to: CGPoint(x: dx, y: y1 - e)); b.addLine(to: CGPoint(x: dx, y: max(y2 + e, mid + gap / 2))); b.move(to: CGPoint(x: dx, y: min(y1 - e, mid - gap / 2))); b.addLine(to: CGPoint(x: dx, y: y2 + e)) }
        else { b.move(to: CGPoint(x: dx, y: y1 - 5)); b.addLine(to: CGPoint(x: dx, y: y2 + 5)) }
        if DimStyle.cap {   // 끝 = 짧은 가로줄 (H를 눕힌 I자, 시안)
            let w = 5 * uiP / uiK; for y in [y1, y2] { b.move(to: CGPoint(x: dx - w, y: y)); b.addLine(to: CGPoint(x: dx + w, y: y)) }
            dimLine.fillColor = nil
        } else {
        b.move(to: CGPoint(x: dx, y: y1)); b.addLine(to: CGPoint(x: dx - 3.5, y: y1 - 5)); b.addLine(to: CGPoint(x: dx + 3.5, y: y1 - 5)); b.closeSubpath()
        b.move(to: CGPoint(x: dx, y: y2)); b.addLine(to: CGPoint(x: dx - 3.5, y: y2 + 5)); b.addLine(to: CGPoint(x: dx + 3.5, y: y2 + 5)); b.closeSubpath() }
        dimLine.path = b
        labelText.string = s; labelText.contentsScale = (NSScreen.main?.backingScaleFactor ?? 2) * uiK / uiP; labelBox.transform = CATransform3DIdentity
        switch st {
        case 0: labelBox.cornerRadius = 6 * inv; labelBox.borderWidth = 1; labelBox.borderColor = blue.cgColor; labelBox.backgroundColor = c.btn.cgColor; labelBox.frame = CGRect(x: dx + 8, y: mid - 10 * inv, width: lw, height: 20 * inv)
        case 1: labelBox.borderWidth = 0; labelBox.backgroundColor = nil; labelBox.frame = CGRect(x: dx - lw / 2, y: mid - lh / 2, width: lw, height: lh)   // 숫자만 (선 사이)
        case 2: labelBox.cornerRadius = lh / 2; labelBox.borderWidth = 0; labelBox.backgroundColor = blue.cgColor; labelBox.frame = CGRect(x: max(dx + 6 * inv, pillX - lw / 2), y: mid - lh / 2, width: lw, height: lh)   // 파란 알약 (선 오른쪽, 예전 자리)
        case 3: labelBox.cornerRadius = lh / 2; labelBox.borderWidth = 1.2; labelBox.borderColor = blue.cgColor; labelBox.backgroundColor = wellColor(c).cgColor; labelBox.frame = CGRect(x: dx - lw / 2, y: mid - lh / 2, width: lw, height: lh)   // 테두리 알약
        default: labelBox.borderWidth = 0; labelBox.backgroundColor = nil; labelBox.bounds = CGRect(x: 0, y: 0, width: lw, height: lh); labelBox.position = CGPoint(x: dx, y: mid); labelBox.transform = CATransform3DMakeRotation(.pi / 2, 0, 0, 1)   // 세로 글자
        }
        labelText.frame = CGRect(x: 0, y: (labelBox.bounds.height - th) / 2 - (st == 0 || st == 2 || st == 3 ? 0 : 0), width: labelBox.bounds.width, height: th + 1)
        CATransaction.commit()
    }
    @objc func changed() { update(); controller?.adjustChanged(head, topM) }
    func released() {   // 놓으면: 한계를 넘었으면 한계값으로 톡 (스프링)
        let f0 = head, m0 = topM; var f = f0, m = m0; for _ in 0..<3 { f = clampFace(f, m); m = clampTop(f, m) }
        guard abs(f - f0) > 0.004 || abs(m - m0) > 0.004 else { return }
        animateTo(f, m)
    }
    var snapTimer: Timer?
    func animateTo(_ f1: Double, _ m1: Double) {
        snapTimer?.invalidate(); let f0 = slider.doubleValue, m0 = topSlider.doubleValue, t0 = CACurrentMediaTime(), dur = 0.42
        snapTimer = Timer.scheduledTimer(withTimeInterval: 1 / displayFPS, repeats: true) { [weak self] tm in guard let self else { tm.invalidate(); return }
            let t = min(1, (CACurrentMediaTime() - t0) / dur), c1 = 1.56, c3 = c1 + 1, e = 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)   // 살짝 넘었다 돌아오는 곡선
            self.slider.doubleValue = f0 + (f1 - f0) * (t >= 1 ? 1 : e); self.topSlider.doubleValue = m0 + (m1 - m0) * (t >= 1 ? 1 : e); self.changed()
            if t >= 1 { tm.invalidate(); self.slider.doubleValue = f1; self.topSlider.doubleValue = m1; self.changed() } }
    }
    @objc func goBack() { snapTimer?.invalidate(); controller?.adjustBack() }
    @objc func doReset() { snapTimer?.invalidate()
        if direct { let b = Converter.customStart(ySnap()); wSl.doubleValue = b.w; hSl.doubleValue = b.h; slider.doubleValue = b.headCm; topSlider.doubleValue = b.topCm; sizeChanged(); return }   // Custom: 증명 크기로
        slider.doubleValue = spec.headCm; topSlider.doubleValue = spec.topCm; fitToLimits(); changed() }
    @objc func doSave() { snapTimer?.invalidate(); fitToLimits(); update(); controller?.adjustSave(head, topM) }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func keyDown(with e: NSEvent) {
        if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "0" { doReset(); return }
        switch e.keyCode {
        case 53: controller?.endPick()   // Esc = 어느 화면에서든 닫기
        case 51: goBack()   // 백스페이스 = 뒤로
        case 36, 76: doSave()
        case 126, 125: let st = e.modifierFlags.contains(.shift) ? 0.1 : 0.01; slider.doubleValue = clampFace(head + (e.keyCode == 126 ? st : -st), topM); changed()
        default: super.keyDown(with: e) }
    }
    override func performKeyEquivalent(with e: NSEvent) -> Bool { if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "0" { doReset(); return true }; return super.performKeyEquivalent(with: e) }
    override func cancelOperation(_ sender: Any?) { controller?.endPick() }   // Esc = 닫기 (뒤로는 백스페이스)
}

// MARK: 3. Custom (5×7 세로 패널 · 1차 5×7in/4×6in/3.5×4.5cm → 2차 3.5×4.5cm → 포토샵 시트)
let customSize = NSSize(width: 560, height: 784)
let panelW = cardsSize.width, listH = cardsSize.height   // 옛 목록 코드·시험 그리기용
struct CustomRatio { let key: String; let label: String; let w: Double; let h: Double }   // w·h = 결과 크기(cm)
let customRatios = [CustomRatio(key: "5x7", label: "5×7 in", w: 12.7, h: 17.78), CustomRatio(key: "4x6", label: "4×6 in", w: 10.16, h: 15.24), CustomRatio(key: "orig", label: "원본 비율", w: 0, h: 0)]   // 원본 비율 = 사진 그대로 (w·h는 사진에서, 2026-11-05: 3.5×4.5 빼고 원본)
let secondRatio = CustomRatio(key: "id", label: "3.5×4.5 cm", w: 3.5, h: 4.5)

// 작업 영역: 사진을 끌고(손바닥) · 스크롤·⌘±·Z+끌기로 확대 · 틀은 가운데 고정 · 틀 아래·오른쪽 스크롤바
final class LayerHost: NSView { override func hitTest(_ p: NSPoint) -> NSView? { nil } }   // 그림 전용 (마우스는 아래 작업 영역이 받음)
final class CropStage: NSView {
    weak var owner: CustomView?
    var image: CGImage?
    var IW: CGFloat = 1, IH: CGFloat = 1
    var B = CGRect(x: 0, y: 0, width: 1, height: 1)   // 움직일 수 있는 범위 (사진 px, 위 기준)
    var ratio: CGFloat = 5 / 7, z: CGFloat = 1, zMax: CGFloat = 4, ix: CGFloat = 0, iy: CGFloat = 0   // ix·iy = 사진 왼쪽 위 (작업 영역 좌표, 위 기준)
    var FW: CGFloat = 0, FH: CGFloat = 0
    var zKey = false, snapping = false
    var c: PanelColors = panelColors()
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var SW: CGFloat { bounds.width }
    var SH: CGFloat { bounds.height }
    func frameSize() -> (CGFloat, CGFloat) { let mh = SH - 44, mw = SW - 44; var fh = mh, fw = fh * ratio; if fw > mw { fw = mw; fh = fw / ratio }; return (fw.rounded(), fh.rounded()) }
    var base: CGFloat { max(FW / B.width, FH / B.height) }
    var s: CGFloat { base * z }
    var fx: CGFloat { (SW - FW) / 2 }
    var fy: CGFloat { (SH - FH) / 2 }
    func rng() -> (x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat) { (fx - (B.maxX) * s + FW, fx - B.minX * s, fy - B.maxY * s + FH, fy - B.minY * s) }
    func clampPos() { let r = rng(); ix = min(r.x1, max(r.x0, ix)); iy = min(r.y1, max(r.y0, iy)) }
    func relayoutFrame() { (FW, FH) = frameSize() }
    func center(on r: CGRect) { ix = SW / 2 - r.midX * s; iy = SH / 2 - r.midY * s; clampPos() }
    func cropRect() -> CGRect { CGRect(x: (fx - ix) / s, y: (fy - iy) / s, width: FW / s, height: FH / s) }   // 사진 px (위 기준)
    func zoom(to z1: CGFloat, anchor: CGPoint? = nil) {
        let a = anchor ?? CGPoint(x: SW / 2, y: SH / 2), s0 = s, px = (a.x - ix) / s0, py = (a.y - iy) / s0
        z = min(zMax, max(1, z1)); ix = a.x - px * s; iy = a.y - py * s; clampPos(); syncLayers(); owner?.refreshBar() }
    // 부드러운 확대 (⌘± · 스크롤): 목표 배율까지 프레임마다 22%씩
    var zTarget: CGFloat = 1, zAnchor: CGPoint?, zTimer: Timer?
    func zoomSmooth(_ z1: CGFloat, anchor: CGPoint? = nil) {
        zTarget = min(zMax, max(1, z1)); zAnchor = anchor
        guard zTimer == nil else { return }
        zTimer = Timer.scheduledTimer(withTimeInterval: 1 / displayFPS, repeats: true) { [weak self] t in guard let self else { t.invalidate(); return }
            let d = self.zTarget - self.z
            if abs(d) < 0.002 { self.zoom(to: self.zTarget, anchor: self.zAnchor); t.invalidate(); self.zTimer = nil; return }
            self.zoom(to: self.z + d * 0.22, anchor: self.zAnchor) }
    }
    func stopSmooth() { zTimer?.invalidate(); zTimer = nil }
    var goalZ: CGFloat { zTimer != nil ? zTarget : z }
    // 놓았을 때 틀에 빈 곳이 있으면 톡 돌아감
    func snapBack() {
        let a0 = (ix, iy); clampPos(); let a1 = (ix, iy); guard abs(a1.0 - a0.0) + abs(a1.1 - a0.1) > 0.5 else { return }
        ix = a0.0; iy = a0.1; let t0 = CACurrentMediaTime(), dur = 0.42; snapping = true
        Timer.scheduledTimer(withTimeInterval: 1 / displayFPS, repeats: true) { [weak self] tm in guard let self else { tm.invalidate(); return }
            let t = min(1, (CACurrentMediaTime() - t0) / dur), c1 = 1.56, c3 = c1 + 1, e = t >= 1 ? 1 : 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
            self.ix = a0.0 + (a1.0 - a0.0) * e; self.iy = a0.1 + (a1.1 - a0.1) * e; self.syncLayers(); self.owner?.refreshBar()
            if t >= 1 { tm.invalidate(); self.snapping = false; self.ix = a1.0; self.iy = a1.1 } }
    }
    // 스크롤바 (틀 아래·오른쪽): 막대 길이 = 보이는 비율
    var sbX: NSRect { NSRect(x: fx, y: fy + FH + 5, width: FW, height: 11) }
    var sbY: NSRect { NSRect(x: fx + FW + 5, y: fy, width: 11, height: FH) }
    func thumb(_ ax: Int) -> (NSRect, Bool) {
        let r = rng(), iw = B.width * s, ih = B.height * s
        if ax == 0 { let frac = min(1, FW / iw), t = r.x1 - r.x0 > 0.5 ? (r.x1 - ix) / (r.x1 - r.x0) : 0.5, w = max(8, sbX.width * frac); return (NSRect(x: sbX.minX + (sbX.width - w) * t, y: sbX.minY + 3, width: w, height: 5), frac < 0.999) }
        let frac = min(1, FH / ih), t = r.y1 - r.y0 > 0.5 ? (r.y1 - iy) / (r.y1 - r.y0) : 0.5, h = max(8, sbY.height * frac); return (NSRect(x: sbY.minX + 3, y: sbY.minY + (sbY.height - h) * t, width: 5, height: h), frac < 0.999)
    }
    var sbHover = -1, sbDrag = -1
    // 그리기 = GPU 레이어 (2026-11-05 최적화): 끌기·확대 때 사진을 다시 그리지 않고 레이어 위치·크기만 바꿈 → 화면 주사율대로 부드럽게
    let host = LayerHost(), clip = CALayer(), well = CALayer(), black = CALayer(), photo = CALayer(), dim = CAShapeLayer(), outline = CALayer()
    let sbTrack = [CALayer(), CALayer()], sbThumb = [CALayer(), CALayer()]
    var layersReady = false
    func setupLayers() {
        guard !layersReady else { return }; layersReady = true
        host.frame = bounds; host.autoresizingMask = [.width, .height]; host.wantsLayer = true; addSubview(host)
        guard let root = host.layer else { return }
        clip.masksToBounds = true; clip.cornerRadius = 10; root.addSublayer(clip)
        for l in [well, black, photo] as [CALayer] { clip.addSublayer(l) }
        photo.contentsGravity = .resize; photo.minificationFilter = .trilinear; photo.magnificationFilter = .linear
        dim.fillRule = .evenOdd; clip.addSublayer(dim)
        outline.borderWidth = 1; clip.addSublayer(outline)
        for k in 0..<2 { sbTrack[k].cornerRadius = 5.5; root.addSublayer(sbTrack[k]); root.addSublayer(sbThumb[k]) }
    }
    func L(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height) }   // 위 기준 → 레이어(아래 기준)
    func pulseFrame() {   // 2차로 넘어간 뒤 새 틀 둘레로 파란 테두리가 두 번 퍼짐 ('여기를 다시 잘라요', 2026-11-05 시안 C)
        guard let root = layer else { return }
        var acc = sysBlue; effectiveAppearance.performAsCurrentDrawingAppearance { acc = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? sysBlue }
        let fr = L(NSRect(x: fx, y: fy, width: FW, height: FH))
        for i in 0..<2 {
            let ring = CALayer(); ring.frame = fr; ring.borderColor = acc.cgColor; ring.borderWidth = 2.5; ring.cornerRadius = 2; ring.opacity = 0; root.addSublayer(ring)
            let g = CAAnimationGroup(); g.duration = 0.9; g.beginTime = CACurrentMediaTime() + Double(i) * 0.45; g.fillMode = .backwards
            let b = CABasicAnimation(keyPath: "bounds.size"); b.fromValue = NSValue(size: fr.size); b.toValue = NSValue(size: NSSize(width: fr.width + 26, height: fr.height + 26))
            let o = CABasicAnimation(keyPath: "opacity"); o.fromValue = 1; o.toValue = 0
            g.animations = [b, o]; g.timingFunction = CAMediaTimingFunction(name: .easeOut); ring.add(g, forKey: "pulse")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95 + Double(i) * 0.45) { ring.removeFromSuperlayer() } }
    }
    func syncLayers() {
        setupLayers(); guard FW > 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        host.frame = bounds; clip.frame = host.bounds; well.frame = clip.bounds; well.backgroundColor = adjWell(c).cgColor
        let fr = NSRect(x: fx, y: fy, width: FW, height: FH)
        black.frame = L(fr); black.backgroundColor = NSColor.black.cgColor
        if photo.contents == nil || (photo.contents as! CGImage?) !== image { photo.contents = image }
        photo.frame = L(NSRect(x: ix, y: iy, width: IW * s, height: IH * s))
        let pth = CGMutablePath(); pth.addRect(clip.bounds); pth.addRect(L(fr)); dim.path = pth; dim.fillColor = adjWell(c).withAlphaComponent(c.dark ? 0.78 : 0.8).cgColor
        outline.frame = L(fr).insetBy(dx: -0.5, dy: -0.5); outline.borderColor = (c.dark ? NSColor(white: 1, alpha: 0.3) : NSColor(white: 0, alpha: 0.18)).cgColor
        for ax in 0..<2 { let (t, on) = thumb(ax), track = ax == 0 ? sbX : sbY, hot = sbHover == ax || sbDrag == ax
            sbTrack[ax].frame = L(track); sbTrack[ax].backgroundColor = (hot ? (c.dark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.05)) : NSColor.clear).cgColor
            let tt = hot ? (ax == 0 ? t.insetBy(dx: 0, dy: -1) : t.insetBy(dx: -1, dy: 0)) : t
            let a: CGFloat = (c.dark ? (hot ? 0.55 : 0.35) : (hot ? 0.5 : 0.32)) * (on ? 1 : 0.25)
            sbThumb[ax].frame = L(tt); sbThumb[ax].cornerRadius = min(tt.width, tt.height) / 2; sbThumb[ax].backgroundColor = (c.dark ? NSColor(white: 1, alpha: a) : NSColor(white: 0, alpha: a)).cgColor }
        CATransaction.commit()
    }
    override func layout() { super.layout(); if FW > 0 { syncLayers() } }
    override func updateTrackingAreas() { trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .cursorUpdate], owner: self, userInfo: nil)); super.updateTrackingAreas() }
    func sbAt(_ p: NSPoint) -> Int { sbX.insetBy(dx: 0, dy: -3).contains(p) ? 0 : (sbY.insetBy(dx: -3, dy: 0).contains(p) ? 1 : -1) }
    override func mouseMoved(with e: NSEvent) { let h = sbAt(convert(e.locationInWindow, from: nil)); if h != sbHover { sbHover = h; syncLayers() }; cursorUpdate(with: e) }
    override func mouseExited(with e: NSEvent) { if sbHover != -1 { sbHover = -1; syncLayers() } }
    override func cursorUpdate(with e: NSEvent) {
        if zKey { if #available(macOS 15.0, *) { NSCursor.zoomIn.set() } else { NSCursor.crosshair.set() }; return }
        if sbAt(convert(e.locationInWindow, from: nil)) >= 0 { NSCursor.arrow.set() } else { NSCursor.openHand.set() } }
    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(owner); let p0 = convert(e.locationInWindow, from: nil)
        let sb = sbAt(p0)
        if sb >= 0 {   // 스크롤바: 막대 끌기 · 빈 곳 누르면 그 자리로
            stopSmooth(); sbDrag = sb; let (t, _) = thumb(sb), track = sb == 0 ? sbX : sbY, L = sb == 0 ? track.width : track.height, tl = sb == 0 ? t.width : t.height
            func pos(_ p: NSPoint) -> CGFloat { sb == 0 ? p.x - track.minX : p.y - track.minY }
            let grab = t.contains(p0) ? pos(p0) - (sb == 0 ? t.minX - track.minX : t.minY - track.minY) : tl / 2
            func set(_ p: NSPoint) { let r = rng(), tt = min(1, max(0, (pos(p) - grab) / max(1, L - tl))); if sb == 0 { ix = r.x1 - tt * (r.x1 - r.x0) } else { iy = r.y1 - tt * (r.y1 - r.y0) }; syncLayers(); owner?.refreshBar() }
            set(p0)
            while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) { if ev.type == .leftMouseUp { break }; set(convert(ev.locationInWindow, from: nil)) }
            sbDrag = -1; syncLayers(); return }
        stopSmooth()
        if zKey {   // Z + 끌기: 오른쪽 = 확대, 왼쪽 = 축소 (누른 자리 기준)
            let z0 = z
            while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) { if ev.type == .leftMouseUp { break }; let p = convert(ev.locationInWindow, from: nil); zoom(to: z0 * exp((p.x - p0.x) * 0.006), anchor: p0) }
            return }
        NSCursor.closedHand.set(); let a = ix, b = iy
        while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }; let p = convert(ev.locationInWindow, from: nil); ix = a + p.x - p0.x; iy = b + p.y - p0.y; syncLayers(); owner?.refreshBar() }
        NSCursor.openHand.set(); snapBack()
    }
    override func scrollWheel(with e: NSEvent) {   // 트랙패드 두 손가락 쓸기 = 손바닥(사진 옮기기) · 마우스 휠 = 부드러운 확대·축소 (2026-11-05, 맥 사진·미리보기와 같게)
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) {
            stopSmooth(); ix += e.scrollingDeltaX; iy += e.scrollingDeltaY; clampPos(); syncLayers(); owner?.refreshBar(); return }
        let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 12   // ⌘+두 손가락 = 확대 (예전 방식)
        guard d != 0 else { return }
        zoomSmooth(goalZ * exp(d * 0.0045), anchor: convert(e.locationInWindow, from: nil)) }
    override func magnify(with e: NSEvent) {   // 트랙패드 두 손가락 벌리기·오므리기 = 손가락 따라 바로 확대·축소, 손가락 자리 기준 (2026-11-05)
        stopSmooth(); zoom(to: z * (1 + e.magnification), anchor: convert(e.locationInWindow, from: nil))
        if e.phase == .ended || e.phase == .cancelled { snapBack() } }
    override func smartMagnify(with e: NSEvent) {   // 두 손가락 두 번 톡 = 처음 크기 ↔ 2배
        zoomSmooth(goalZ > 1.05 ? 1 : 2, anchor: convert(e.locationInWindow, from: nil)) }
}
extension CGFloat { func min2(_ o: CGFloat) -> CGFloat { Swift.min(self, o) } }

final class CustomView: ThemedPanel {
    weak var controller: Controller?
    let stage = CropStage(), seg = SlideSeg(), sub = NSTextField(labelWithString: ""), title = NSTextField(labelWithString: "Custom"), stepL = NSTextField(labelWithString: "")
    let bar = NSView(), zoomT = NSTextField(labelWithString: "확대"), zoomHint = NSTextField(labelWithString: "⌘− ⌘+ · Z+끌기"), zoomV = NSTextField(labelWithString: "100%"), zoomS = NSSlider(value: 1, minValue: 1, maxValue: 4, target: nil, action: nil)
    var back: PillButton!, reset: PillButton!, save: PillButton!, done: PillButton!
    var step = 1, ratioIdx = 0
    var c1: CGRect = .zero, z1: CGFloat = 1, z2: CGFloat = 1
    init(frame: NSRect) {
        super.init(frame: frame, radius: 18)
        back = PillButton("← 뒤로", target: self, action: #selector(goBack)); reset = PillButton("Default", hint: "⌘0", target: self, action: #selector(doReset)); save = PillButton("Save · 다음", target: self, action: #selector(doSave)); done = PillButton("Done", target: self, action: #selector(doDone)); done.toolTip = "1차 크롭만 저장하고 끝내기 (인화지 없이)"
        back.frame = NSRect(x: 16, y: frame.height - 42, width: 74, height: 28); reset.frame = NSRect(x: frame.width - 16 - reset.fitWidth(), y: frame.height - 42, width: reset.fitWidth(), height: 28)
        topB.addSubview(back); topB.addSubview(titlePill); botB.addSubview(reset); botB.addSubview(done)   // Default · Done = 아래 Save 옆
        title.font = .systemFont(ofSize: 13.5, weight: .medium); stepL.font = .systemFont(ofSize: 10.5); topC.addSubview(title); topC.addSubview(stepL)
        seg.labels = customRatios.map(\.label); seg.target = self; seg.action = #selector(ratioChanged)
        topC.addSubview(seg)
        sub.font = .systemFont(ofSize: 10.5); sub.alignment = .center; sub.stringValue = "1차 크롭에서 시작 · 축소하면 원본 전체까지"; topC.addSubview(sub)
        stage.owner = self; addSubview(stage)
        bar.frame = NSRect(x: 16, y: 14, width: frame.width - 32, height: 66); bar.wantsLayer = true; bar.layer?.cornerRadius = 16; bar.layer?.borderWidth = 0.5
        bar.layer?.shadowColor = NSColor.black.cgColor; bar.layer?.shadowOpacity = 0.08; bar.layer?.shadowRadius = 5; bar.layer?.shadowOffset = CGSize(width: 0, height: -2); botC.addSubview(bar); addSubview(topC); addSubview(botC)
        let saveW: CGFloat = 104, gw = bar.frame.width - 14 * 2 - saveW - 18
        zoomT.font = .systemFont(ofSize: 11); zoomT.sizeToFit(); zoomT.setFrameOrigin(NSPoint(x: 14, y: 40)); bar.addSubview(zoomT)
        zoomHint.font = .systemFont(ofSize: 10); zoomHint.sizeToFit(); zoomHint.setFrameOrigin(NSPoint(x: 14 + zoomT.frame.width + 6, y: 40.5)); bar.addSubview(zoomHint)
        zoomV.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); zoomV.alignment = .right; zoomV.frame = NSRect(x: 14 + gw - 60, y: 40, width: 60, height: 15); bar.addSubview(zoomV)
        zoomS.isContinuous = true; zoomS.controlSize = .small; zoomS.trackFillColor = sysBlue; zoomS.target = self; zoomS.action = #selector(zoomSlid); zoomS.frame = NSRect(x: 12, y: 14, width: gw + 4, height: 22); bar.addSubview(zoomS)
        save.frame = NSRect(x: bar.frame.width - 14 - saveW, y: 15, width: saveW, height: 36); save.layer?.cornerRadius = 18; save.keyEquivalent = "\r"; botB.addSubview(save); addSubview(topB); addSubview(botB)
        setUI()
    }
    required init?(coder: NSCoder) { fatalError() }
    let topB = PassView(), botB = PassView()   // 버튼만 담는 화면 1:1 틀
    let topBarL = CALayer()
    // 위 막대 90pt(뒤로·제목·비율) · 아래 막대 96pt(확대·Save)는 화면에서 늘 같은 크기. 자르기 화면만 Panel Size 따라 (2026-11-05)
    let tbar = TitleBar()
    let topC = NSView(), botC = NSView(); let topH: CGFloat = 100 + titleBarH, botH: CGFloat = 96
    func setUI() {
        let p = uiP, inv = p / uiK, f = 1 / p, W = frame.width, H = frame.height, w = W * uiK / p
        topC.frame = NSRect(x: 0, y: H - topH * inv, width: W, height: topH * inv); topC.bounds = NSRect(x: 0, y: 0, width: w, height: topH)
        botC.frame = NSRect(x: 0, y: 0, width: W, height: botH * inv); botC.bounds = NSRect(x: 0, y: 0, width: w, height: botH)
        let S = W * uiK; screenBox(topB, top: true, h: topH * p, W: W, H: H); screenBox(botB, top: false, h: botH * p, W: W, H: H)
        let rw = reset.fitWidth(); back.frame = NSRect(x: 16 * p, y: 72 * p - 14, width: back.fitWidth(80), height: 28)
        if tbar.superview == nil { topB.addSubview(tbar) }; tbar.frame = NSRect(x: 0, y: topH * p - titleBarH, width: S, height: titleBarH); tbar.place(width: S)
        seg.setFrameOrigin(NSPoint(x: ((w - seg.frame.width) / 2).rounded(), y: 14)); sub.frame = NSRect(x: 0, y: 14, width: w, height: 15)
        bar.frame = NSRect(x: 10, y: 14, width: w - 20, height: 66)
        let saveW = save.fitWidth(56), dw = step == 1 ? done.fitWidth(56) + 8 : 0, gw = bar.frame.width - 14 * 2 - (saveW + 8 + rw + dw) * f - 18
        zoomV.frame = NSRect(x: 14 + gw - 60, y: 40, width: 60, height: 15); zoomS.frame = NSRect(x: 12, y: 14, width: gw + 4, height: 22)
        save.frame = NSRect(x: S - 24 * p - saveW, y: 47 * p - 14, width: saveW, height: 28); save.layer?.cornerRadius = 14
        done.isHidden = step != 1; done.frame = NSRect(x: save.frame.minX - dw, y: 47 * p - 14, width: max(0, dw - 8), height: 28)
        reset.frame = NSRect(x: save.frame.minX - dw - 8 - rw, y: 47 * p - 14, width: rw, height: 28)
        layoutTitle(); applyTitleBG(self, topBarL)
        let had = stage.FW > 0, cen = had ? stage.cropRect() : .zero
        stage.frame = NSRect(x: 10 * inv, y: botH * inv, width: W - 20 * inv, height: H - (botH + topH) * inv)
        if had { stage.relayoutFrame(); stage.center(on: cen); stage.syncLayers(); refreshBar() }
    }
    let titlePill = TitlePill()
    var curRatio: CustomRatio { let r = customRatios[ratioIdx]; return r.key == "orig" ? CustomRatio(key: "orig", label: r.label, w: Double(stage.IW) / 300 * 2.54, h: Double(stage.IH) / 300 * 2.54) : r }   // 원본 비율 = 사진 그대로 (300ppi 기준 cm)
    func pillSub() -> String { step == 1 ? "" : "2차 크롭 · 3.5×4.5 cm" }   // 1차엔 설명 없음 (2026-11-05)
    func layoutTitle() { if titlePill.animating { return }; let w = titlePill.fitW; titlePill.frame = NSRect(x: ((frame.width * uiK - w) / 2).rounded(), y: (72 * uiP - 10 - TitlePill.H / 2).rounded(), width: w, height: TitlePill.H); title.isHidden = true; stepL.isHidden = true }   // 버튼보다 10 아래
    func applyTheme() {
        applyPanelTheme(); let c = panelColors(); stage.c = c
        for b in [back!, reset!, done!] { b.style(c) }; save.style(c, primary: true)
        title.textColor = c.tx; stepL.textColor = c.sub; sub.textColor = c.sub; titlePill.style(c); tbar.style(c); applyTitleBG(self, topBarL)
        bar.layer?.backgroundColor = c.btn.cgColor; bar.layer?.borderColor = (c.dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.1)).cgColor
        zoomT.textColor = c.sub; zoomHint.textColor = c.sub.withAlphaComponent(0.7); zoomV.textColor = c.tx
        seg.style(c); zoomS.appearance = appearance; stage.syncLayers()
    }
    func start(_ img: CGImage) {   // 1단계부터
        stage.image = img; stage.IW = CGFloat(img.width); stage.IH = CGFloat(img.height); hideThumb()
        step = 1; ratioIdx = 0; seg.selectedSegment = 0; setStep()
    }
    func setStep() {
        let r = step == 1 ? curRatio : secondRatio
        stage.ratio = CGFloat(r.w / r.h); stage.B = CGRect(x: 0, y: 0, width: stage.IW, height: stage.IH); stage.stopSmooth()
        seg.isHidden = step != 1; sub.isHidden = true   // 2차 안내는 제목 칸이 함 (예전 문구 뺌)
        defer { setUI() }   // 버튼 글자가 바뀌면 폭도 다시 (Save · 다음 ↔ Save)
        back.text = step == 1 ? "← 뒤로" : "← 1단계"; save.text = step == 1 ? "Save · 다음" : "Save"
        title.sizeToFit(); stepL.stringValue = step == 1 ? "1 / 2 · 크롭" : "2 / 2 · 3.5×4.5 cm"; stepL.sizeToFit()
        let animate = titlePill.window != nil && !titlePill.main.isEmpty && !isHidden; titlePill.set("프로필", pillSub(), blue: step == 2, animated: animate)   // 1차 → 2차: 글자가 위로 밀며 바뀜
        layoutTitle()
        stage.relayoutFrame()
        if step == 2 {   // 1차 크롭 높이에 맞춰 시작 (위아래 그대로, 양옆은 원본으로 넓힘) · 원본 전체까지 축소 가능
            let sc = max(stage.FH / c1.height, stage.base); stage.z = sc / stage.base; stage.zMax = max(4, stage.z * 3); z2 = stage.z; stage.center(on: c1)
        } else { stage.zMax = 4; stage.z = 1; stage.center(on: stage.B) }
        refreshBar(); stage.syncLayers()
    }
    func glide(_ change: () -> Void) {   // 바꾸기 전·후 상태 사이를 부드럽게 (틀 크기·확대·위치)
        let a = (stage.FW, stage.FH, stage.z, stage.ix, stage.iy, stage.ratio); change(); let b = (stage.FW, stage.FH, stage.z, stage.ix, stage.iy, stage.ratio)
        guard abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.3 - b.3) + abs(a.4 - b.4) > 0.5 || abs(a.2 - b.2) > 0.001 else { return }
        stage.stopSmooth(); glideGen += 1; let g = glideGen, t0 = CACurrentMediaTime(), dur = 0.34
        stage.FW = a.0; stage.FH = a.1; stage.z = a.2; stage.ix = a.3; stage.iy = a.4; stage.syncLayers()   // 시작 모습으로 되돌려 놓고 출발 (도착 모습이 한 번 비치지 않게)
        Timer.scheduledTimer(withTimeInterval: 1 / displayFPS, repeats: true) { [weak self] tm in guard let self, self.glideGen == g else { tm.invalidate(); return }
            let t = min(1, (CACurrentMediaTime() - t0) / dur), e = CGFloat(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
            let st = self.stage; st.FW = a.0 + (b.0 - a.0) * e; st.FH = a.1 + (b.1 - a.1) * e; st.z = a.2 * pow(b.2 / a.2, e); st.ix = a.3 + (b.3 - a.3) * e; st.iy = a.4 + (b.4 - a.4) * e
            if t >= 1 { tm.invalidate(); st.FW = b.0; st.FH = b.1; st.z = b.2; st.ix = b.3; st.iy = b.4 }
            st.syncLayers(); self.refreshBar() }
    }
    var glideGen = 0
    func refreshBar() { zoomS.maxValue = Double(stage.zMax); zoomS.doubleValue = Double(stage.z); zoomV.stringValue = "\(Int((stage.z * 100).rounded()))%" }
    @objc func ratioChanged() { ratioIdx = max(0, seg.selectedSegment); let cen = stage.cropRect(), r = curRatio   // 자르기 틀도 부드럽게 바뀜
        glide { stage.ratio = CGFloat(r.w / r.h); stage.relayoutFrame(); stage.center(on: cen) }; stage.syncLayers(); refreshBar() }
    @objc func zoomSlid() { stage.stopSmooth(); stage.zoom(to: CGFloat(zoomS.doubleValue)) }
    @objc func goBack() { if step == 2 { hideThumb(); glide { step = 1; setStep(); stage.z = z1; stage.center(on: c1) } } else { glideGen += 1; controller?.customBack() } }
    @objc func doReset() { stage.stopSmooth(); if step == 2 { stage.z = z2; stage.center(on: c1) } else { stage.z = 1; stage.center(on: stage.B) }; stage.syncLayers(); refreshBar() }
    let thumbL = CALayer(), badgeL = CALayer(), badgeT = CATextLayer()   // 그림 전용 레이어 (보기 부품은 움직이는 동안 끝 크기로 먼저 그려져서 작은 그림이 엉뚱한 데서 출발했음)
    func flyThumb(_ r: CGRect) {   // 1차로 자른 사진이 틀 크기에서 작아지며 왼쪽 위로 날아가 ✓ 붙은 작은 그림으로 남음 (2026-11-05 시안 C)
        guard let img = stage.image?.cropping(to: r.integral), let root = layer else { return }
        let inv = uiP / uiK, start = stage.convert(NSRect(x: stage.fx, y: stage.fy, width: stage.FW, height: stage.FH), to: self)
        let h = 46 * inv, w = h * r.width / max(1, r.height), end = NSRect(x: 16 * inv, y: frame.height - topH * inv + 10 * inv, width: w, height: h)
        if thumbL.superlayer == nil { root.addSublayer(thumbL); root.addSublayer(badgeL); badgeL.addSublayer(badgeT) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        thumbL.zPosition = 50; badgeL.zPosition = 51; thumbL.isHidden = false; badgeL.isHidden = false
        thumbL.contents = img; thumbL.contentsGravity = .resizeAspectFill; thumbL.masksToBounds = true; thumbL.cornerRadius = 3 * inv; thumbL.borderColor = NSColor.white.cgColor; thumbL.borderWidth = 1.2 * inv; thumbL.frame = end
        let bs = 15 * inv; badgeL.frame = CGRect(x: end.maxX - bs * 0.6, y: end.minY - bs * 0.35, width: bs, height: bs); badgeL.cornerRadius = bs / 2; badgeL.backgroundColor = NSColor.systemGreen.cgColor; badgeL.opacity = 1
        badgeT.string = NSAttributedString(string: "✓", attributes: [.font: NSFont.systemFont(ofSize: 10 * inv, weight: .bold), .foregroundColor: NSColor.white]); badgeT.alignmentMode = .center; badgeT.contentsScale = (window?.backingScaleFactor ?? 2) * uiK; badgeT.frame = CGRect(x: 0, y: bs * 0.12, width: bs, height: bs)
        CATransaction.commit()
        let tf = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
        let pos = CABasicAnimation(keyPath: "position"); pos.fromValue = NSValue(point: NSPoint(x: start.midX, y: start.midY)); pos.toValue = NSValue(point: NSPoint(x: end.midX, y: end.midY))
        let bnd = CABasicAnimation(keyPath: "bounds"); bnd.fromValue = NSValue(rect: NSRect(origin: .zero, size: start.size)); bnd.toValue = NSValue(rect: NSRect(origin: .zero, size: end.size))
        let g = CAAnimationGroup(); g.animations = [pos, bnd]; g.duration = 0.55; g.timingFunction = tf; thumbL.add(g, forKey: "fly")
        let o = CABasicAnimation(keyPath: "opacity"); o.fromValue = 0; o.toValue = 1; o.beginTime = CACurrentMediaTime() + 0.5; o.duration = 0.2; o.fillMode = .backwards; badgeL.add(o, forKey: "in")
    }
    func hideThumb() { CATransaction.begin(); CATransaction.setDisableActions(true); thumbL.isHidden = true; badgeL.isHidden = true; CATransaction.commit() }

    @objc func doDone() {   // Done = 1차 크롭만 저장하고 끝 (2차·인화지 없음, 2026-11-05)
        stage.stopSmooth(); stage.clampPos(); controller?.customDone(stage.cropRect(), curRatio) }
    @objc func doSave() {
        stage.stopSmooth(); stage.clampPos()
        let r = stage.cropRect()
        if step == 1 { c1 = r; z1 = stage.z; controller?.customSaveFirst(r, curRatio); flyThumb(r)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in guard let self else { return }; self.glide { self.step = 2; self.setStep() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in if self?.step == 2 { self?.stage.pulseFrame() } } } }
        else { controller?.customSaveSecond(c1, curRatio, r) }
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard e.modifierFlags.contains(.command), let ch = e.charactersIgnoringModifiers else { return super.performKeyEquivalent(with: e) }
        switch ch { case "=", "+": stage.zoomSmooth(stage.goalZ * 1.25); return true
        case "-", "_": stage.zoomSmooth(stage.goalZ / 1.25); return true
        case "0": doReset(); return true
        default: return super.performKeyEquivalent(with: e) }
    }
    override func keyDown(with e: NSEvent) {
        if e.charactersIgnoringModifiers?.lowercased() == "z", !e.modifierFlags.contains(.command) { stage.zKey = true; NSCursor.crosshair.set(); if #available(macOS 15.0, *) { NSCursor.zoomIn.set() }; return }
        switch e.keyCode { case 53: debugLog("Esc 받음 (Custom)"); glideGen += 1; controller?.endPick(); case 51: goBack(); case 36, 76: doSave(); default: super.keyDown(with: e) }
    }
    override func keyUp(with e: NSEvent) { if e.charactersIgnoringModifiers?.lowercased() == "z" { stage.zKey = false; NSCursor.openHand.set() } else { super.keyUp(with: e) } }
    override func cancelOperation(_ sender: Any?) { controller?.endPick() }   // Esc = 닫기 (뒤로는 백스페이스)
}

// MARK: - Custom 인화지 (5×7in · 300ppi, 2026-11-05)
// 기존 ydot 인화(YDOT.sheet)와 같은 규칙: 작은 사진 = 사진 3.5×4.5cm + 사방 10px 흰 여백, 칸 둘레 1px 회색(204) 선, 칸끼리 맞붙임.
// 위 줄 = 폴라로이드 2장(90° 돌림): 짧은 변 = 사진 폭(흰 틀 없음), 긴 변 = 아래 3칸 폭의 절반, 사진 4.5cm + 남는 곳 = 로고 띠(오른쪽에 로고). 선만.
enum Sheet {
    static let W = 1500, H = 2100, px = { (cm: Double) in Int((cm / 2.54 * 300).rounded()) }
    // 폴라로이드 모양 (300ppi px) — 설정 › 시그니처. 포토샵 YDOT.customSheet도 같은 값을 받아 같게 그림
    struct FrameDef: Equatable { var path = ""; var w = 531, h = 708, x = 59, y = 59, pw = 413, ph = 531 }   // 프레임 사진 (px · 위 기준)
    struct PolStyle: Equatable { var strip = 63, logoH = 35, margin = 24; var align = "right"; var logo = ""   // strip = 로고 사진 아래 여백
        var mt = 0, ml = 0, mr = 0, pw = 413, ph = 531; var lx: Int? = nil, ly: Int? = nil; var frames: [String: FrameDef] = [:]
        var sigW: Int { ml + pw + mr }; var sigH: Int { mt + ph + strip } }   // logo: "" = 샘플 로고 (번들 logo.ai = y. 로고 · 2026-11-06 스튜디오 로고는 배포에서 뺌) · "none" = 없음 · 그 밖 = 로고 파일 경로
    static func style(_ s: YSettings) -> PolStyle {
        var st = PolStyle(strip: max(0, min(400, s.polStrip)), logoH: max(4, min(300, s.logoH)), margin: max(0, min(200, s.logoMargin)), align: ["left", "center", "right"].contains(s.logoAlign) ? s.logoAlign : "right", logo: "")
        if s.logoID == "none" { st.logo = "none" } else if let l = s.logos.first(where: { $0.id == s.logoID }) { st.logo = YSettings.logoDir.appendingPathComponent(l.file).path }
        st.mt = max(0, min(1200, s.sigMT)); st.ml = max(0, min(1200, s.sigML)); st.mr = max(0, min(1200, s.sigMR)); st.lx = s.logoX; st.ly = s.logoY
        st.pw = max(60, min(1800, s.design.w)); st.ph = max(60, min(1800, s.design.h))
        for f in s.frames { let path = YSettings.frameDir.appendingPathComponent(f.file).path, a = frameAspect(path), w = max(60, min(3000, f.w)), pw = max(30, min(3000, f.pw))
            st.frames[f.id] = FrameDef(path: path, w: w, h: max(1, Int((CGFloat(w) / a).rounded())), x: f.x, y: f.y, pw: pw, ph: max(1, Int((CGFloat(pw) * CGFloat(st.ph) / CGFloat(st.pw)).rounded()))) }
        return st }
    // ── 로고 사진 · 프레임 사진 · 로고만 (인화지 칸) — 설정 › 로고 · 프레임 탭 (사용자 2026-11-07)
    static func logoSize(_ a: LogoArt, _ h: CGFloat) -> CGSize { let lw0 = a.box.width * a.size.width, lh0 = a.box.height * a.size.height; return CGSize(width: lw0 * h / max(0.001, lh0), height: h) }
    static func logoRect(_ st: PolStyle) -> CGRect? {   // 로고 사진 안 로고 자리 (위 기준 px) · 로고 없음 = nil
        guard let a = logoArt(st.logo) else { return nil }; let sz = logoSize(a, CGFloat(max(4, st.logoH)))
        let W = CGFloat(st.sigW), x = st.lx.map { CGFloat($0) } ?? (st.align == "left" ? CGFloat(st.margin) : st.align == "center" ? (W - sz.width) / 2 : W - CGFloat(st.margin) - sz.width)
        let y = st.ly.map { CGFloat($0) } ?? CGFloat(st.mt + st.ph) + (CGFloat(st.strip) - sz.height) / 2
        return CGRect(x: x.rounded(), y: y.rounded(), width: sz.width, height: sz.height) }
    static func drawLogo(_ ctx: CGContext, _ a: LogoArt, in r: CGRect) {   // r = CG 좌표 (아래 기준)
        let lh0 = a.box.height * a.size.height, k = r.height / max(0.001, lh0)
        ctx.saveGState(); ctx.clip(to: r)
        if let page = a.page { let mb = page.getBoxRect(.cropBox); ctx.translateBy(x: r.minX, y: r.minY); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -(mb.minX + a.box.minX * mb.width), y: -(mb.minY + a.box.minY * mb.height)); ctx.drawPDFPage(page) }
        else if let im = a.img { ctx.interpolationQuality = .high; ctx.draw(im, in: CGRect(x: r.minX - a.box.minX * a.size.width * k, y: r.minY - a.box.minY * a.size.height * k, width: a.size.width * k, height: a.size.height * k)) }
        ctx.restoreGState() }
    static func logoCell(_ st: PolStyle, _ h: Int) -> CGImage? {   // 로고만 칸 (흰 바탕 · 높이 h px)
        guard let a = logoArt(st.logo == "none" ? "" : st.logo) else { return nil }; let sz = logoSize(a, CGFloat(max(8, h))), w = max(1, Int(sz.width.rounded())), hh = max(1, Int(sz.height.rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: hh, bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: hh)); drawLogo(ctx, a, in: CGRect(x: 0, y: 0, width: w, height: hh)); return ctx.makeImage() }
    static func logoCellSize(_ st: PolStyle, _ h: Int) -> (Int, Int) { guard let a = logoArt(st.logo == "none" ? "" : st.logo) else { return (h * 3, h) }; let sz = logoSize(a, CGFloat(max(8, h))); return (max(1, Int(sz.width.rounded())), max(1, Int(sz.height.rounded()))) }
    // 프레임 그림: ai·pdf = 벡터 · 그 밖 = 맥이 여는 그림이면 다 (png jpg tiff heic psd gif bmp webp svg …) · 여백 그대로
    static let frameLock = NSLock(); static var frameSrc: [String: (page: CGPDFPage?, img: CGImage?, size: CGSize)] = [:]
    static func frameSource(_ path: String) -> (page: CGPDFPage?, img: CGImage?, size: CGSize)? {
        frameLock.lock(); defer { frameLock.unlock() }; if let f = frameSrc[path] { return f.page == nil && f.img == nil ? nil : f }
        let u = URL(fileURLWithPath: path); var r: (page: CGPDFPage?, img: CGImage?, size: CGSize) = (nil, nil, .zero)
        if ["pdf", "ai"].contains(u.pathExtension.lowercased()), let page = CGPDFDocument(u as CFURL)?.page(at: 1) { r = (page, nil, page.getBoxRect(.cropBox).size) }
        else if let src = CGImageSourceCreateWithURL(u as CFURL, nil), let im = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary) { r = (nil, im, CGSize(width: im.width, height: im.height)) }
        else if let ns = NSImage(contentsOf: u), ns.size.width > 0 { let k = max(1, 2400 / max(ns.size.width, ns.size.height)); var rr = NSRect(x: 0, y: 0, width: ns.size.width * k, height: ns.size.height * k)
            if let im = ns.cgImage(forProposedRect: &rr, context: nil, hints: nil) { r = (nil, im, CGSize(width: im.width, height: im.height)) } }
        frameSrc[path] = r; return r.page == nil && r.img == nil ? nil : r }
    static func frameThumb(_ path: String) -> NSImage? { guard frameSource(path) != nil else { return nil }; let a = frameAspect(path), h: CGFloat = 268, w = max(1, (h * a).rounded())
        guard let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        drawFrameArt(ctx, path, in: CGRect(x: 0, y: 0, width: w, height: h)); return ctx.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: w / 2, height: h / 2)) } }
    static func frameAspect(_ path: String) -> CGFloat { guard let f = frameSource(path), f.size.height > 0 else { return 0.75 }; return f.size.width / f.size.height }
    static func drawFrameArt(_ ctx: CGContext, _ path: String, in r: CGRect) {
        guard let f = frameSource(path) else { return }; ctx.saveGState(); ctx.clip(to: r); ctx.interpolationQuality = .high
        if let page = f.page { let mb = page.getBoxRect(.cropBox); ctx.translateBy(x: r.minX, y: r.minY); ctx.scaleBy(x: r.width / mb.width, y: r.height / mb.height); ctx.translateBy(x: -mb.minX, y: -mb.minY); ctx.drawPDFPage(page) }
        else if let im = f.img { ctx.draw(im, in: r) }
        ctx.restoreGState() }
    static func framePhoto(_ photo: CGImage, _ fd: FrameDef) -> CGImage? {   // 프레임 위에 사진 (흰 바탕)
        guard let ctx = CGContext(data: nil, width: fd.w, height: fd.h, bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: fd.w, height: fd.h))
        drawFrameArt(ctx, fd.path, in: CGRect(x: 0, y: 0, width: fd.w, height: fd.h))
        fill(ctx, photo, CGRect(x: fd.x, y: fd.h - fd.y - fd.ph, width: fd.pw, height: fd.ph)); return ctx.makeImage() }
    static func itemSize(_ c: YCell, _ st: PolStyle) -> (Int, Int)? {   // 특별 칸 크기 (안 돌림) · 보통 사진 = nil
        if c.sig == true { return (st.sigW, st.sigH) }
        if c.kind == "logo" { return logoCellSize(st, c.lh ?? 71) }
        if c.kind == "frame" { let f = st.frames[c.fid ?? ""] ?? FrameDef(); return (f.w, f.h) }
        return nil }
    static func itemImage(_ c: YCell, _ photo: CGImage, _ st: PolStyle) -> CGImage? {
        if c.sig == true { return polaroid(photo, st) }
        if c.kind == "logo" { return logoCell(st, c.lh ?? 71) }
        if c.kind == "frame" { guard let f = st.frames[c.fid ?? ""] else { return nil }; return framePhoto(photo, f) }
        return nil }
    final class LogoArt { var page: CGPDFPage?; var img: CGImage?; var box = CGRect(x: 0, y: 0, width: 1, height: 1); var size = CGSize(width: 1, height: 1) }   // box = 그림 있는 자리 (0~1, 아래 기준)
    static let logoLock = NSLock(); static var logoCache: [String: LogoArt] = [:]
    static func logoArt(_ key: String) -> LogoArt? {   // 기본(번들 logo.ai) · pdf/ai = 벡터 · 그 밖 = 그림. 여백은 빼고 그림 있는 자리만
        if key == "none" { return nil }
        logoLock.lock(); defer { logoLock.unlock() }
        if let a = logoCache[key] { return a.page == nil && a.img == nil ? nil : a }
        let a = LogoArt()
        let url: URL? = key.isEmpty ? (Bundle.main.url(forResource: "logo", withExtension: "ai") ?? ProcessInfo.processInfo.environment["DONUT_LOGO"].map { URL(fileURLWithPath: $0) }) : URL(fileURLWithPath: key)
        if let url {
            if ["pdf", "ai"].contains(url.pathExtension.lowercased()), let page = CGPDFDocument(url as CFURL)?.page(at: 1) { a.page = page; a.size = page.getBoxRect(.cropBox).size }
            else if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let im = CGImageSourceCreateImageAtIndex(src, 0, nil) { a.img = im; a.size = CGSize(width: im.width, height: im.height) } }
        if a.page != nil || a.img != nil {   // 흰 바탕에 그려 보고 그림 있는 자리 찾기
            let w = 1200, h = max(1, Int(CGFloat(w) * a.size.height / max(1, a.size.width)))
            if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                if let page = a.page { let mb = page.getBoxRect(.cropBox), sc = CGFloat(w) / mb.width; ctx.scaleBy(x: sc, y: sc); ctx.translateBy(x: -mb.minX, y: -mb.minY); ctx.drawPDFPage(page) }
                else if let im = a.img { ctx.draw(im, in: CGRect(x: 0, y: 0, width: w, height: h)) }
                if let d = ctx.data?.assumingMemoryBound(to: UInt8.self) {
                    var x0 = w, x1 = -1, y0 = h, y1 = -1
                    for y in 0..<h { for x in 0..<w { let i = y * w * 4 + x * 4; if Int(d[i]) + Int(d[i + 1]) + Int(d[i + 2]) < 700 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } } }
                    if x1 > x0, y1 > y0 { a.box = CGRect(x: Double(x0) / Double(w), y: Double(h - 1 - y1) / Double(h), width: Double(x1 - x0 + 1) / Double(w), height: Double(y1 - y0 + 1) / Double(h)) } } } }
        logoCache[key] = a
        return a.page == nil && a.img == nil ? nil : a
    }
    static func drawLogo(_ ctx: CGContext, _ a: LogoArt, height lh: CGFloat, centerY: CGFloat, width W: CGFloat, margin: CGFloat, align: String) {   // 높이 lh로, 띠 안 왼쪽·가운데·오른쪽
        let lw0 = a.box.width * a.size.width, lh0 = a.box.height * a.size.height, k = lh / max(0.001, lh0), dw = lw0 * k
        let x = align == "left" ? margin : align == "center" ? (W - dw) / 2 : W - margin - dw, r = CGRect(x: x, y: centerY - lh / 2, width: dw, height: lh)
        ctx.saveGState(); ctx.clip(to: r)
        if let page = a.page { let mb = page.getBoxRect(.cropBox); ctx.translateBy(x: r.minX, y: r.minY); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -(mb.minX + a.box.minX * mb.width), y: -(mb.minY + a.box.minY * mb.height)); ctx.drawPDFPage(page) }
        else if let im = a.img { ctx.interpolationQuality = .high; let full = CGRect(x: r.minX - a.box.minX * a.size.width * k, y: r.minY - a.box.minY * a.size.height * k, width: a.size.width * k, height: a.size.height * k); ctx.draw(im, in: full) }
        ctx.restoreGState()
    }
    static func logoThumb(_ key: String) -> NSImage? {   // 설정창 로고 칸 (흰 바탕, 높이 40에 맞춤)
        guard let a = logoArt(key) else { return nil }
        let W: CGFloat = 300, H: CGFloat = 128
        guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let lw = a.box.width * a.size.width, lh = a.box.height * a.size.height, h = min(56, (W - 40) * lh / max(1, lw))
        drawLogo(ctx, a, height: h, centerY: H / 2, width: W, margin: 0, align: "center")
        return ctx.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: W / 2, height: H / 2)) } }
    static func polaroid(_ photo: CGImage, _ st: PolStyle) -> CGImage? {   // 세운 폴라로이드 한 장 (폭 413 · 사진 531 + 아래 띠)
        let W = st.sigW, H = st.sigH   // 로고 사진 = 위·왼·오른·아래 여백 + 사진(자른 규격) + 로고 (로고 탭)
        guard let pc = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        pc.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); pc.fill(CGRect(x: 0, y: 0, width: W, height: H))
        fill(pc, photo, CGRect(x: st.ml, y: H - st.mt - st.ph, width: st.pw, height: st.ph))
        if let a = logoArt(st.logo), let r = logoRect(st) { drawLogo(pc, a, in: CGRect(x: r.minX, y: CGFloat(H) - r.maxY, width: r.width, height: r.height)) }
        return pc.makeImage()
    }
    static func fill(_ ctx: CGContext, _ img: CGImage, _ r: CGRect) {   // r을 꽉 채우게 가운데 맞춰 (넘치는 곳 자름)
        let k = max(r.width / CGFloat(img.width), r.height / CGFloat(img.height)), w = CGFloat(img.width) * k, h = CGFloat(img.height) * k
        ctx.saveGState(); ctx.clip(to: r); ctx.interpolationQuality = .high; ctx.draw(img, in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)); ctx.restoreGState()
    }
    static func line(_ ctx: CGContext, _ r: CGRect) { ctx.setStrokeColor(CGColor(srgbRed: 204 / 255, green: 204 / 255, blue: 204 / 255, alpha: 1)); ctx.setLineWidth(1); ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5)) }
    static func make(polaroid: CGImage, small: CGImage, style: PolStyle? = nil) -> CGImage? {   // 프로필 인화지 = 인화지 탭 '프로필' 배치 (작은 칸 = 2차 크롭 · 로고 사진·프레임 사진 = 1차 크롭)
        let ys = ySnap(); return render(small, layout("프로필", ys), "프로필", style: style ?? Sheet.style(ys), sigPhoto: polaroid) }
    static let layouts: [String: (c: Int, r: Int, rot: Bool)] = ["증명": (3, 3, false), "여권": (3, 3, false), "반명함": (2, 5, true), "중국비자": (2, 4, true), "소형": (3, 4, false), "미국비자": (2, 3, false), "명함": (2, 2, false)]   // 포토샵 YDOT.layouts와 같게
    static func grid(_ photo: CGImage, _ spec: String) -> CGImage? { let ys = ySnap(); return render(photo, layout(spec, ys), spec, style: style(ys)) }   // 규격 인화지 (설정 › 인화지 배치)
    static var customDims: (Double, Double)?   // Custom(이번만 크기)일 때 가로·세로 cm (조절 화면이 정함)
    static func specPx(_ spec: String) -> (Int, Int) { if spec == "Custom", let d = customDims { return (Int((d.0 / 2.54 * 300).rounded()), Int((d.1 / 2.54 * 300).rounded())) }; return (Converter.baseSpecs.first { $0.name == spec } ?? Converter.baseSpecs[0]).px }
    static func cellWH(_ spec: String, _ q: Int) -> (Int, Int) { let (w, h) = specPx(spec); return q % 2 == 0 ? (w, h) : (h, w) }
    static func sheetWH(_ L: YLayout) -> (Int, Int) { L.land ? (H, W) : (W, H) }
    static func size(_ spec: String, _ c: YCell, _ st: PolStyle) -> (Int, Int) { let (w, h) = itemSize(c, st) ?? specPx(spec); return c.q % 2 == 0 ? (w, h) : (h, w) }   // 칸 크기 (회전 반영)
    static func defaultLayout(_ spec: String) -> YLayout {   // 예전 포토샵 배치와 같음 (가운데 c×r, 칸 = 사진 + 사방 10px)
        var L = YLayout()
        if spec == "프로필" {   // 프로필 인화지: 위 로고 사진 2장 (눕힘 · 사진 위 = 왼쪽) + 아래 사진 3×2 — 예전 고정 배치와 같은 자리 (사용자 2026-11-07: 인화지 탭에서 같이 편집)
            let st = Sheet.style(ySnap()), pw = px(3.5), ph = px(4.5), cw = pw + 20, ch = ph + 20, gw = cw * 3, polW = st.sigH, polH = st.sigW, gap = 20, totalH = polH + 20 + gh(ch)
            let left = (W - gw) / 2, top = (H - totalH) / 2 + 10, px0 = (W - (polW * 2 + gap)) / 2
            for i in 0..<2 { L.cells.append(YCell(x: px0 + i * (polW + gap), y: top, q: 3, sig: true)) }
            for r in 0..<2 { for c in 0..<3 { L.cells.append(YCell(x: left + c * cw + 10, y: top + polH + 20 + r * ch, q: 0)) } }
            return L }
        guard let t = layouts[spec] ?? autoGrid(spec) else { return L }
        let q = t.rot ? 1 : 0, (pw, ph) = cellWH(spec, q), tw = pw + L.pad * 2, th = ph + L.pad * 2
        let x0 = Int((Double(W - t.c * tw) / 2).rounded()) + L.pad, y0 = Int((Double(H - t.r * th) / 2).rounded()) + L.pad
        for r in 0..<t.r { for c in 0..<t.c { L.cells.append(YCell(x: x0 + c * tw, y: y0 + r * th, q: q)) } }
        return L }
    static func gh(_ ch: Int) -> Int { ch * 2 }
    static func autoGrid(_ spec: String) -> (c: Int, r: Int, rot: Bool)? {   // 배치 표가 없는 크기(Custom): 5×7에 가장 많이 들어가게 (눕히기 포함)
        let (w, h) = specPx(spec); guard w > 0, h > 0 else { return nil }
        func fit(_ a: Int, _ b: Int) -> (Int, Int) { (W / (a + 20), H / (b + 20)) }
        let (c0, r0) = fit(w, h), (c1, r1) = fit(h, w); guard max(c0 * r0, c1 * r1) > 0 else { return nil }
        return c1 * r1 > c0 * r0 ? (c1, r1, true) : (c0, r0, false) }
    static func layout(_ spec: String, _ s: YSettings) -> YLayout { if let l = s.layouts[spec], !l.cells.isEmpty, l.cells.count <= 200, (0...120).contains(l.pad), (0...30).contains(l.stroke) { return l }; return defaultLayout(spec) }   // 비었거나 이상한 값이면 기본 (파일이 깨져도 인화는 됨)
    static func render(_ photo: CGImage, _ L: YLayout, _ spec: String, scale: CGFloat = 1, style: PolStyle? = nil, board: CGRect? = nil, dim: CGColor? = nil, sigPhoto: CGImage? = nil) -> CGImage? {   // sigPhoto = 로고 사진·프레임 사진에 넣을 사진 (프로필 = 1차 크롭)   // 배치대로 그리기 (포토샵 YDOT.sheetLay와 같게: 사진 · 여백만큼 넓힌 칸 안쪽 선) · board = 편집 창에서 인화지 밖까지 (밖은 dim으로 흐리게)
        let (SW, SH) = sheetWH(L), (sw, sh) = specPx(spec), st = style ?? Sheet.style(ySnap()), area = board ?? CGRect(x: 0, y: 0, width: SW, height: SH)
        guard let ctx = CGContext(data: nil, width: max(1, Int((area.width * scale).rounded())), height: max(1, Int((area.height * scale).rounded())), bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: (board == nil ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -area.minX, y: area.maxY - CGFloat(SH))   // 위 기준 area → CG (인화지 왼쪽 아래 = 0,0)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: SW, height: SH)); ctx.interpolationQuality = .high
        let g = CGFloat(max(0, min(255, L.gray))) / 255; var items: [String: CGImage] = [:]
        for c in L.cells {
            let (w, h) = size(spec, c, st), r = CGRect(x: c.x, y: SH - c.y - h, width: w, height: h), q = ((c.q % 4) + 4) % 4
            var im = photo, iw = CGFloat(sw), ih = CGFloat(sh)
            if !c.key.isEmpty { if items[c.key] == nil { items[c.key] = itemImage(c, sigPhoto ?? photo, st) }; guard let p = items[c.key] else { continue }; im = p; iw = CGFloat(p.width); ih = CGFloat(p.height) }
            ctx.saveGState(); ctx.translateBy(x: r.midX, y: r.midY); ctx.rotate(by: -CGFloat(q) * .pi / 2); ctx.draw(im, in: CGRect(x: -iw / 2, y: -ih / 2, width: iw, height: ih)); ctx.restoreGState()
            if L.stroke > 0 && c.kind != "logo" { let o = r.insetBy(dx: -CGFloat(L.pad), dy: -CGFloat(L.pad)), lw = CGFloat(L.stroke)
                ctx.setStrokeColor(CGColor(srgbRed: g, green: g, blue: g, alpha: 1)); ctx.setLineWidth(lw); ctx.stroke(o.insetBy(dx: lw / 2, dy: lw / 2)) } }
        if board != nil, let dim { let all = CGRect(x: area.minX, y: CGFloat(SH) - area.maxY, width: area.width, height: area.height); ctx.addRect(all); ctx.addRect(CGRect(x: 0, y: 0, width: SW, height: SH)); ctx.setFillColor(dim); ctx.fillPath(using: .evenOdd) }   // 인화지 밖 = 흐리게 (인화 안 됨)
        return ctx.makeImage() }
    static func layString(_ L: YLayout, _ spec: String = "", style st: PolStyle) -> String {   // 포토샵 인화 스크립트로 · 인화지 밖에 있는 칸은 뺌 · 특별 칸 = 끝에 ,키 (s 로고 사진 · l높이 로고만 · f아이디 프레임 사진 → 그림 = layItems/키.png)
        let (a, b) = sheetWH(L), sheet = CGRect(x: 0, y: 0, width: a, height: b)
        let cs = L.cells.filter { c in let (w, h) = size(spec, c, st); return CGRect(x: c.x - L.pad, y: c.y - L.pad, width: w + 2 * L.pad, height: h + 2 * L.pad).intersects(sheet) }
        return "\(a),\(b),\(L.pad),\(L.stroke),\(L.gray);" + cs.map { "\($0.x),\($0.y),\((($0.q % 4) + 4) % 4)" + ($0.key.isEmpty ? "" : "," + $0.key) }.joined(separator: ";") }
    static func writeItems(_ L: YLayout, _ photo: CGImage, _ st: PolStyle) -> URL? {   // 포토샵용: 특별 칸 그림을 임시 폴더에 (키.png) · 스크립트가 다 쓰면 지움
        let keys = Dictionary(L.cells.filter { !$0.key.isEmpty }.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }); guard !keys.isEmpty else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ydot_items_\(getpid())_\(Int(Date().timeIntervalSince1970 * 1000))", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        for (k, c) in keys { if let im = itemImage(c, photo, st) { try? writePNG(im, dir.appendingPathComponent(k + ".png")) } }
        return dir }
    static func writePNG(_ img: CGImage, _ url: URL) throws {
        let data = try Converter.encode(img, .png, nil, [kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300])
        try data.write(to: url, options: .atomic)
    }
    // 포토샵에 저장 안 된 새 문서(Untitled)로 열기. 포토샵 제어 권한이 없거나 실패하면 → 파일 그대로 포토샵으로, 포토샵이 없으면 데스크톱에 저장
    static func openInPhotoshop(_ file: URL, fallbackName: String, dest: URL) {
        let ws = NSWorkspace.shared
        guard let ps = ws.urlForApplication(withBundleIdentifier: "com.adobe.Photoshop") else {
            let to = dest.appendingPathComponent(fallbackName.precomposedStringWithCanonicalMapping); try? FileManager.default.copyItem(at: file, to: to); ws.activateFileViewerSelecting([to]); return }
        let path = file.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = "(function(){var d=app.open(new File('\(path)'));var n=app.documents.add(d.width,d.height,300,undefined,NewDocumentMode.RGB,DocumentFill.WHITE,1,BitsPerChannelType.EIGHT,'sRGB IEC61966-2.1');app.activeDocument=d;d.artLayers[0].duplicate(n,ElementPlacement.PLACEATBEGINNING);d.close(SaveOptions.DONOTSAVECHANGES);app.activeDocument=n;n.flatten();})();"
        let script = "tell application id \"com.adobe.Photoshop\"\nactivate\ndo javascript \"\(js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\nend tell"
        DispatchQueue.global(qos: .userInitiated).async {   // 포토샵이 켜지는 동안 앱이 멈추지 않게
            var err: NSDictionary?; _ = NSAppleScript(source: script)?.executeAndReturnError(&err)
            if let err { debugLog("포토샵 열기 실패 \(err)"); DispatchQueue.main.async { let cfg = NSWorkspace.OpenConfiguration(); ws.open([file], withApplicationAt: ps, configuration: cfg) } }
        }
    }
}

// MARK: - 알림 (실패·원본 옆 저장만)

final class Toast {
    let panel: NSPanel
    let label = NSTextField(labelWithString: "")
    var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let v = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        v.material = .hudWindow; v.state = .active; v.blendingMode = .behindWindow
        v.appearance = NSAppearance(named: .darkAqua)
        v.wantsLayer = true; v.layer?.cornerRadius = 12; v.layer?.masksToBounds = true
        v.autoresizingMask = [.width, .height]
        panel.contentView = v
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        v.addSubview(label)
    }

    func show(_ text: String) {
        debugLog("알림(안 띄움): " + text); return   // 사용자 요청 2026-11-03: 알림 창 없음. 기록만
        label.stringValue = text
        label.sizeToFit()
        let textW = min(ceil(label.frame.width), 460)
        let w = 32 + textW, h: CGFloat = 44
        label.frame = NSRect(x: 16, y: (h - label.frame.height) / 2, width: textW, height: label.frame.height)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - w / 2, y: screen.visibleFrame.maxY - h - 14, width: w, height: h), display: true)
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func hide() { panel.orderOut(nil) }
}

// MARK: - 끌기 감지와 도넛 열고 닫기

enum DebugLog { static let path = ProcessInfo.processInfo.environment["DONUT_LOG"] }   // 시험 때만 (평소엔 nil → 글자도 안 만듦) · static = 순서와 상관없이 안전
func debugLog(_ m: @autoclosure () -> String) {
    guard let path = DebugLog.path else { return }
    let line = "\(String(format: "%.3f", CACurrentMediaTime())) \(m())\n"
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8)) }
}

final class Controller: NSObject, NSMenuDelegate {
    let panel: NSPanel
    let view: DonutView
    let toast = Toast()
    var status: NSStatusItem?
    var mouseTimer: Timer?
    var dragCount = 0
    var dragging = false
    var shiftWas = false
    let sizePanel: NSPanel, sizeView: SizeListView, adjustView: AdjustView, customView: CustomView
    var yBtn: YButton!
    var mode = "cards"   // cards · adjust · custom (패널 크기가 화면마다 다름)
    var baseSize: NSSize { mode == "adjust" ? adjustSize : (mode == "custom" ? customSize : cardsSize) }
    var pickHead: (crown: Double, chin: Double, cx: Double, W: Double, H: Double)?   // 고른 사진의 얼굴 인식 (미리보기 크기 기준)
    @objc func cycleTheme() {   // y. = 그레이 → 다크 → 글래스
        let i = themeOrder.firstIndex(of: cardTheme) ?? 0; cardTheme = themeOrder[(i + 1) % themeOrder.count]
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.2; c.allowsImplicitAnimation = true; applyThemeAll() } }
    func applyThemeAll() { sizeView.applyTheme(); adjustView.applyTheme(); customView.applyTheme(); yBtn.applyTheme() }
    func layoutHolder() {   // 그릇 = 지금 화면 크기 + 사방 btnM. y. 버튼 가운데 = 패널 오른쪽 위 모서리
        guard let holder = sizePanel.contentView else { return }
        let b = baseSize; holder.bounds = NSRect(x: 0, y: 0, width: b.width + btnM * 2, height: b.height + btnM * 2)
        for (v, m) in [(sizeView as NSView, "cards"), (adjustView, "adjust"), (customView, "custom")] { v.isHidden = m != mode; v.setFrameOrigin(NSPoint(x: btnM, y: btnM)) }
        yBtn.frame = yRect(btnM + b.width, btnM + b.height)
    }
    var switchGen = 0
    // 화면 전환 (2026-11-05): 바탕(같은 색 패널)만 크기가 부드럽게 변하고, 내용은 늘이지 않고 페이드 (예전 내용 사라짐 → 새 내용 나타남)
    let morph = ThemedPanel(frame: .zero)
    func switchMode(_ m: String, animated: Bool = true) {
        // 2026-11-05 F11 시험 뒤: 매 프레임 창 크기를 바꾸면 맥이 바쁠 때(창들이 돌아오는 중 등) 밀려서 버벅·잘림 →
        // 창은 두 크기를 다 담게 한 번만 키우고, 그 안에서 바탕·y.·내용만 Core Animation으로 움직임 → 끝나면 창을 한 번만 맞춤
        let f = sizePanel.frame, c = NSPoint(x: f.midX, y: f.midY), gen = { switchGen += 1; return switchGen }()
        let old = activeView(), oldBase = baseSize
        let v: NSView = m == "adjust" ? adjustView : (m == "custom" ? customView : sizeView)
        guard animated, sizePanel.isVisible, old !== v, let holder = sizePanel.contentView else {
            mode = m; layoutHolder(); let r = pickRect(center: c); sizePanel.setFrame(r, display: true); fitHolder(r.size); sizePanel.alphaValue = 1; old.alphaValue = 1; v.alphaValue = 1; morph.isHidden = true; sizePanel.makeFirstResponder(v); return }
        let k = f.width / (oldBase.width + btnM * 2)   // 화면 배율 (세 화면 같음)
        mode = m; let newBase = baseSize, r1 = pickRect(center: c); mode = old === adjustView ? "adjust" : (old === customView ? "custom" : "cards")
        let U = f.union(r1)   // 창 = 지금 자리와 갈 자리를 다 담는 크기 (한 번만 바꿈)
        let W = U.width / k - btnM * 2, H = U.height / k - btnM * 2
        func rectFor(_ r: NSRect, _ b: NSSize) -> NSRect { NSRect(x: (r.minX - U.minX) / k + btnM, y: (r.minY - U.minY) / k + btnM, width: b.width, height: b.height) }   // 화면 자리 → 그릇 좌표
        let o0 = rectFor(f, oldBase), o1 = rectFor(r1, newBase)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sizePanel.setFrame(U, display: false); holder.frame = NSRect(origin: .zero, size: U.size); holder.bounds = NSRect(x: 0, y: 0, width: W + btnM * 2, height: H + btnM * 2)
        morph.applyPanelTheme(); morph.layer?.shadowOpacity = 0
        if morph.superview == nil { holder.addSubview(morph, positioned: .below, relativeTo: nil) }
        morph.isHidden = false; morph.frame = o0
        old.setFrameOrigin(o0.origin); v.setFrameOrigin(o1.origin); v.isHidden = false; v.alphaValue = 0
        yBtn.frame = yRect(o0.maxX, o0.maxY)
        CATransaction.commit(); sizePanel.display()
        NSAnimationContext.runAnimationGroup({ ctx in   // 바탕·y. = 부드럽게 크기·자리 (화면 그래픽 엔진이 그림)
            ctx.duration = 0.32; ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1); ctx.allowsImplicitAnimation = true
            morph.animator().frame = o1; yBtn.animator().frame = yRect(o1.maxX, o1.maxY)
            old.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, gen == self.switchGen else { return }
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.16; v.animator().alphaValue = 1 }, completionHandler: { [weak self] in
                guard let self, gen == self.switchGen else { return }
                let before = self.morph.convert(self.morph.bounds, to: nil), wb = self.sizePanel.convertToScreen(before)
                CATransaction.begin(); CATransaction.setDisableActions(true)
                self.mode = m; self.layoutHolder(); self.sizePanel.setFrame(r1, display: false); self.fitHolder(r1.size); old.alphaValue = 1; self.morph.isHidden = true
                let vv = self.activeView(), after = self.sizePanel.convertToScreen(vv.convert(vv.bounds, to: nil)); debugLog("전환 끝 \(m): 바탕 \(wb) → 새 화면 \(after)")
                CATransaction.commit(); self.sizePanel.display() })
            self.sizePanel.makeFirstResponder(v) })
    }
    let previewPanel: NSPanel, previewView = PreviewStripView()
    var listHovering = false, listHideWork: DispatchWorkItem?
    func webHover(_ on: Bool) {}   // 끌다가 Product 칸에 올려도 목록은 안 뜸 — 놓은 뒤 고르기 패널(beginPick)로 (2026-11-04)
    var listGen = 0, listSlide: CGFloat = 8   // 규격 목록: 웹 시연(ring8.html #sizes)과 같게 8px 슬라이드 + 0.15s 페이드, 커서를 떼면 바로 같은 속도로 (2026-11-04 녹화로 확인)
    func showList() {
        listHideWork?.cancel(); listGen += 1
        let f = panel.frame; let screen = NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.screens[0]
        var x = f.maxX + 14; listSlide = 8; if x + panelW > screen.frame.maxX { x = f.minX - 14 - panelW; listSlide = -8 }   // 오른쪽에 자리가 없으면 왼쪽(그땐 오른쪽에서 나옴)
        let y = min(max(f.midY - listH / 2 + listRaise(), screen.frame.minY), screen.frame.maxY - listH)   // 아래 미리보기 패널 자리만큼 위로
        sizePanel.ignoresMouseEvents = false
        if !sizePanel.isVisible { sizePanel.setFrameOrigin(NSPoint(x: x - listSlide, y: y)); sizePanel.alphaValue = 0; sizePanel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.15; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1); sizePanel.animator().setFrame(NSRect(x: x, y: y, width: panelW, height: listH), display: true); sizePanel.animator().alphaValue = 1 }   // CSS ease와 같은 곡선. 창 이동은 setFrame(_:display:)만 애니메이션됨(setFrameOrigin은 바로 튐)
    }
    func scheduleListHide() {
        listHideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in guard let self, !self.listHovering, self.view.selected != .web else { return }
            if self.view.selected == nil, self.sizePanel.isVisible, self.betweenRingAndList(NSEvent.mouseLocation) { self.scheduleListHide(); return }   // Product 칸 → 목록으로 건너가는 틈에 있으면 닫지 않고 기다림
            self.hideList() }
        listHideWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: w)   // 커서를 떼면 바로 (목록으로 건너가면 draggingEntered가 다시 띄움)
    }
    func betweenRingAndList(_ p: NSPoint) -> Bool {   // 목록·미리보기 위, 또는 고리 원 바깥에서 목록까지의 틈 (고리 안쪽·구멍은 해당 없음 → 바로 닫힘)
        let f = panel.frame; var l = sizePanel.frame; if previewPanel.isVisible { l = l.union(previewPanel.frame) }
        if l.insetBy(dx: -6, dy: -6).contains(p) { return true }
        let c = NSPoint(x: f.midX, y: f.midY)
        guard hypot(p.x - c.x, p.y - c.y) > outerR - 4 else { return false }
        let inX = l.minX >= c.x ? (p.x >= c.x && p.x <= l.minX + 6) : (p.x <= c.x && p.x >= l.maxX - 6)   // 목록이 왼쪽에 뜬 경우도
        return inX && p.y >= l.minY - 10 && p.y <= l.maxY + 10
    }
    // 미리보기: 끌고 있는 사진들(최대 6장)을 1400px로 줄여 두고(previewBases, previewQ 전용), 올린 규격으로 얼굴 기준 자른 모습을 목록 아래 패널에
    var previewURLs: [URL] = [], previewInfo: [URL: CGSize] = [:], previewCache: [String: NSImage] = [:], previewGen = 0, previewHideWork: DispatchWorkItem?, previewSpec = -1
    var previewBases: [String: CGImage] = [:]   // previewQ에서만 씀
    let previewQ = DispatchQueue(label: "donut.preview", qos: .userInteractive)
    func previewReset() { previewURLs = []; previewInfo = [:]; previewCache = [:]; previewGen += 1; previewSpec = -1; previewQ.async { self.previewBases = [:] } }
    func previewScroll(_ e: NSEvent) {   // 미리보기가 떠 있을 때 스크롤(휠·트랙패드) = 크기 조절. 위로 = 크게
        guard previewPanel.isVisible, previewSpec >= 0 else { return }
        let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 12
        guard stepPanelSize(-d) else { return }; showPreview(previewSpec)
    }
    var scrollAcc: CGFloat = 0
    func stepPanelSize(_ d: CGFloat) -> Bool {   // 스크롤을 모아 40pt마다 한 단계 (Small 220 · Medium 300 · Large 400). 예전엔 매 스크롤마다 저장·다시 그리기만 하고 크기는 그대로였음 (2026-11-05)
        scrollAcc += d; guard abs(scrollAcc) >= 40 else { return false }
        let sizes: [CGFloat] = [220, 300, 400], i = sizes.firstIndex(of: previewThumbH()) ?? 1, n = min(2, max(0, i + (scrollAcc > 0 ? 1 : -1))); scrollAcc = 0
        guard n != i else { return false }; sharedDefaults.set(Double(sizes[n]), forKey: "previewH"); return true }
    func orientedSize(_ u: URL) -> CGSize {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let pr = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any], let w = pr[kCGImagePropertyPixelWidth] as? Double, let h = pr[kCGImagePropertyPixelHeight] as? Double else { return CGSize(width: 2, height: 3) }
        return (pr[kCGImagePropertyOrientation] as? Int ?? 1) >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }
    func showPreview(_ idx: Int) {
        guard idx >= 0, idx < Converter.webSpecs.count else { schedulePreviewHide(); return }
        previewHideWork?.cancel()
        if previewURLs.isEmpty { previewURLs = (NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).filter { isImage($0) }; for u in previewURLs.prefix(previewMax) { previewInfo[u] = orientedSize(u) } }
        guard !previewURLs.isEmpty else { return }
        let spec = Converter.webSpecs[idx]; previewSpec = idx
        let l = sizePanel.frame, screen = NSScreen.screens.first { $0.frame.intersects(l) } ?? NSScreen.screens[0]
        var sizes: [CGSize] = [], wsum = previewPad * 2   // 화면 폭 안에 들어가는 만큼만 (최대 12장)
        for u in previewURLs.prefix(previewMax) { let s = previewInfo[u] ?? CGSize(width: 2, height: 3); var (tw, th) = spec.px; if s.width > s.height { swap(&tw, &th) }
            let w = ceil(previewThumbH() * CGFloat(tw) / CGFloat(th)); if !sizes.isEmpty, wsum + w > screen.frame.width - 40 { break }; wsum += w + previewGap; sizes.append(CGSize(width: tw, height: th)) }
        let shown = Array(previewURLs.prefix(sizes.count))
        let cap = spec.name + " " + spec.size + (previewURLs.count > 1 ? " · \(previewURLs.count)장" : "") + (previewURLs.count > shown.count ? " (앞 \(shown.count)장만)" : "")
        let size = previewView.layout(sizes: sizes, cap: cap)
        var x = l.minX, y = l.minY - 10 - size.height; if x + size.width > screen.frame.maxX { x = max(screen.frame.minX, screen.frame.maxX - size.width) }; y = max(y, screen.frame.minY)
        let target = NSRect(x: x, y: y, width: size.width, height: size.height)
        if !previewPanel.isVisible { previewPanel.setFrame(target.offsetBy(dx: -listSlide, dy: 0), display: false); previewPanel.alphaValue = 0; previewPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { c in c.duration = 0.15; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1); previewPanel.animator().setFrame(target, display: true); previewPanel.animator().alphaValue = 1 }
        } else { NSAnimationContext.runAnimationGroup { c in c.duration = 0; previewPanel.animator().setFrame(target, display: true); previewPanel.animator().alphaValue = 1 } }   // 보이는 중: 0초 애니메이션 = 즉시 확정 + 진행 중이던(나타남·사라짐) 애니메이션 취소 (2026-11-04 실측). 크기를 애니메이션하면 모서리가 어색하고, 그냥 setFrame하면 진행 중 애니메이션이 옛 폭으로 덮어 잘림
        previewHiding = false
        previewGen += 1; let gen = previewGen
        for (i, u) in shown.enumerated() {
            let key = u.path + "|" + spec.name
            if let im = previewCache[key] { previewView.set(i, im); continue }
            previewQ.async { [weak self] in
                guard let self else { return }
                var base = self.previewBases[u.path]
                if base == nil, let src = CGImageSourceCreateWithURL(u as CFURL, nil) { base = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary); self.previewBases[u.path] = base }
                guard let b = base else { return }
                let (_, out, _) = Converter.webSized(b, want: spec, high: false, key: u)
                let im = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
                DispatchQueue.main.async { self.previewCache[key] = im; if self.previewGen == gen { self.previewView.set(i, im) } }
            }
        }
    }
    func schedulePreviewHide() {   // 줄에서 나감: 미리보기·틈 위에 있으면 유지, 아니면 숨김
        previewHideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in guard let self, self.previewPanel.isVisible else { return }
            if self.sizeView.hover >= 0 { return }
            if self.view.selected == nil, self.betweenRingAndList(NSEvent.mouseLocation) { self.schedulePreviewHide(); return }
            self.hidePreviewPanel() }
        previewHideWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: w)
    }
    var previewHideGen = 0, previewHiding = false
    func hidePreviewPanel(animated: Bool = true) {
        previewHideWork?.cancel(); previewGen += 1; previewHideGen += 1; let my = previewHideGen
        guard animated, previewPanel.isVisible else { previewPanel.orderOut(nil); previewHiding = false; return }
        previewHiding = true
        let o = NSPoint(x: previewPanel.frame.origin.x - listSlide, y: previewPanel.frame.origin.y)
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.15; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1); self.previewPanel.animator().setFrame(NSRect(origin: o, size: self.previewPanel.frame.size), display: true); self.previewPanel.animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in guard let self, self.previewHideGen == my else { return }; self.previewPanel.orderOut(nil); self.previewHiding = false })
    }
    func hideList(animated: Bool = true) {
        listHideWork?.cancel(); sizeView.setHover(-1); listHovering = false; listGen += 1; let my = listGen; hidePreviewPanel(animated: animated)
        guard animated, sizePanel.isVisible else { sizePanel.orderOut(nil); if !picking { mode = "cards"; layoutHolder() }; resetAnim(); return }
        sizePanel.ignoresMouseEvents = true
        playClose { [weak self] in guard let self, self.listGen == my else { return }; self.sizePanel.orderOut(nil); if !self.picking { self.mode = "cards"; self.layoutHolder() }; self.resetAnim() }   // 그 사이 다시 띄웠으면 그대로 둠
    }
    var isOpen = false
    // 고르기 모드: Product 칸에 놓은 뒤 도넛은 사라지고 규격 목록이 그 자리에 떠서 클릭으로 고름. 밖을 클릭하면 변환 없이 닫힘 (2026-11-04)
    var picking = false, pickURLs: [URL] = []
    var psPreset: (Int, Double, Double)?   // 포토샵: 지난번 값이 있으면 그 규격 조절 화면으로 바로
    var psOut: String?   // 포토샵 가이드 모드: 결과 파일 경로 (Save·취소·사용불가 때 써 두고 끝남)
    // 테스트 (ydot 창 › 오른쪽 '테스트', 사용자 2026-11-06): 샘플 사진으로 패널을 그대로 돌려 봄 · Save 때 파일·포토샵 문서는 안 만들고 결과 창만 (그림은 실제 저장과 같은 함수로 메모리에서)
    var testMode: String?   // "desk" = 데스크톱(Shift Convert) · "ps" = 포토샵 인화
    var testFirst: CGImage?, testFull: CGImage?   // 프로필 1차 (customQ에서만 씀)
    func startTest(_ side: String, _ photo: URL?) {   // photo nil = '샘플 없음' 회색 인물 그림
        if picking { endPick() }
        guard let u = photo ?? Controller.testSilhouette() else { unusable("테스트 그림을 만들지 못했어요."); return }
        testMode = side; customQ.async { [weak self] in self?.testFirst = nil; self?.testFull = nil }
        if !beginPick([u]) { testMode = nil; unusable("사진을 읽지 못했어요.") }
    }
    static var silURL: URL?
    static func testSilhouette() -> URL? {   // 회색 인물 그림 (임시 폴더 · 얼굴 자리는 Converter.testFaceVal과 같게 그림) · 한 번만 만듦
        if let u = silURL, FileManager.default.fileExists(atPath: u.path) { return u }
        let W = 1200, H = 1600, f = Converter.testFaceVal
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        func y(_ top: Double) -> CGFloat { CGFloat(Double(H) * (1 - top)) }   // 위 기준 비율 → CG
        ctx.setFillColor(CGColor(srgbRed: 0.88, green: 0.88, blue: 0.89, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(CGColor(srgbRed: 0.70, green: 0.70, blue: 0.72, alpha: 1))
        let hw = CGFloat(Double(H) * (f.chin - f.crown) * 0.78), cx = CGFloat(Double(W) * f.cx)
        ctx.fillEllipse(in: CGRect(x: cx - hw / 2, y: y(f.chin), width: hw, height: y(f.crown) - y(f.chin)))
        ctx.fill(CGRect(x: cx - hw * 0.22, y: y(f.chin + 0.07), width: hw * 0.44, height: y(f.chin - 0.02) - y(f.chin + 0.07)))
        let b = CGMutablePath(); b.move(to: CGPoint(x: 60, y: 0)); b.addCurve(to: CGPoint(x: cx, y: y(f.chin + 0.06)), control1: CGPoint(x: 80, y: y(f.chin + 0.2)), control2: CGPoint(x: cx - 330, y: y(f.chin + 0.06)))
        b.addCurve(to: CGPoint(x: CGFloat(W - 60), y: 0), control1: CGPoint(x: cx + 330, y: y(f.chin + 0.06)), control2: CGPoint(x: CGFloat(W - 80), y: y(f.chin + 0.2))); b.closeSubpath(); ctx.addPath(b); ctx.fillPath()
        guard let img = ctx.makeImage() else { return nil }
        let u = URL(fileURLWithPath: Converter.testFace)
        guard let d = try? Converter.encode(img, .jpeg, 0.9, [:]), (try? d.write(to: u, options: .atomic)) != nil else { return nil }
        silURL = u; return u }
    func testDest(_ side: String) -> (URL, String) {   // 실제라면 저장될 곳 (데스크톱은 끌어 놓은 폴더라 테스트에선 데스크톱 기준)
        let desk = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        if side == "ps" { return (desk, "데스크톱") }
        if let f = ySnap().fixedFolder { return (f, f == desk ? "데스크톱" : f.lastPathComponent) }
        return (desk, "끌어 놓은 폴더 (여기선 데스크톱 기준)") }
    func testRun(_ side: String, _ spec: String, _ work: @escaping () -> [(String, CGImage?, String)]) {   // 뒤에서 그림 만들고 결과 창
        customQ.async { [weak self] in let items = autoreleasepool { work() }; DispatchQueue.main.async { self?.showTestResult(side, spec, items) } } }
    func showTestResult(_ side: String, _ spec: String, _ items: [(String, CGImage?, String)]) {
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.environment["DONUT_TESTRUN"] != nil { print("TR 결과 " + items.map { "\($0.0) [\($0.1.map { "\($0.width)×\($0.height)" } ?? "없음")] \($0.2.replacingOccurrences(of: "\n", with: " / "))" }.joined(separator: " | ")) }
        let a = NSAlert(); a.messageText = "테스트 완료 · 파일은 만들지 않았어요"
        a.informativeText = (side == "ps" ? "포토샵 인화" : "데스크톱 (Shift Convert)") + " · \(spec)\n실제로는 \(testDest(side).1)에 이렇게 만들어져요"
        let row = NSStackView(); row.alignment = .top; row.spacing = 14
        for (name, img, detail) in items {
            let iv = NSImageView(); iv.imageScaling = .scaleProportionallyUpOrDown; iv.translatesAutoresizingMaskIntoConstraints = false
            let H: CGFloat = 150; var w: CGFloat = 96
            if let img { iv.image = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)); w = min(130, H * CGFloat(img.width) / CGFloat(max(1, img.height)))
                iv.wantsLayer = true; iv.layer?.shadowColor = NSColor.black.cgColor; iv.layer?.shadowOpacity = 0.2; iv.layer?.shadowRadius = 3; iv.layer?.shadowOffset = CGSize(width: 0, height: -1) }
            else { iv.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil); iv.contentTintColor = .tertiaryLabelColor; iv.imageScaling = .scaleNone }
            iv.widthAnchor.constraint(equalToConstant: w).isActive = true; iv.heightAnchor.constraint(equalToConstant: H).isActive = true
            let n = NSTextField(labelWithString: name); n.font = .systemFont(ofSize: 11.5, weight: .medium); n.alignment = .center
            let d = NSTextField(wrappingLabelWithString: detail); d.font = .systemFont(ofSize: 10); d.textColor = .secondaryLabelColor; d.alignment = .center; d.preferredMaxLayoutWidth = 120
            d.widthAnchor.constraint(equalToConstant: 120).isActive = true
            let col = NSStackView(views: [iv, n, d]); col.orientation = .vertical; col.spacing = 5; row.addArrangedSubview(col) }
        row.layoutSubtreeIfNeeded(); row.frame = NSRect(origin: .zero, size: row.fittingSize); a.accessoryView = row
        a.addButton(withTitle: "확인")
        if let w = settings.win, w.isVisible { a.beginSheetModal(for: w, completionHandler: nil) } else { a.runModal() }
    }
    func beginPick(_ urls: [URL]) -> Bool {
        var images = urls.filter(isImage); guard !images.isEmpty else { return false }
        if images.count > 1 { images = [images[0]]; toast.show("Product는 한 장씩 해요 · 첫 사진만 열었어요") }   // 여러 장은 안 받음 (사용자 2026-11-04)
        previewReset(); hidePreviewPanel(animated: false)   // 먼저 비움 (아래 썸네일 작업과 순서 보장)
        pickURLs = images; picking = true; pickSpot = spot
        for i in 0..<Converter.webSpecs.count { sizeView.setThumb(i, nil) }; previewGen += 1; let gen = previewGen, u = images[0]
        close(keepTarget: true); accepting = false; panel.ignoresMouseEvents = true; view.select(nil)   // 도넛은 바로 사라짐
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        previewQ.async { [weak self] in guard let self else { return }   // 먼저 확인: 얼굴이 정확히 하나인 세로 사진만 (아니면 '사용불가' 경고창, 사용자 2026-11-04)
            var base = self.previewBases[u.path]
            if base == nil, let src = CGImageSourceCreateWithURL(u as CFURL, nil) { base = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary); self.previewBases[u.path] = base }
            let why: String? = { guard let b = base else { return "사진을 읽지 못했어요." }
                if b.width > b.height { return "가로 사진이에요. 세로 사진만 쓸 수 있어요." }
                let n = u.path == Converter.testFace ? 1 : Converter.faceCount(b); if n == 0 { return "얼굴을 찾지 못했어요." }; if n > 1 { return "얼굴이 \(n)개 있어요. 한 사람만 나온 사진이어야 해요." }
                guard let hl = Converter.headLine(b, key: u) else { return "정수리와 턱 위치를 찾지 못했어요." }
                let ph = (hl.crown, hl.chin, hl.cx, Double(b.width), Double(b.height)); DispatchQueue.main.async { self.pickHead = ph }
                return nil }()
            DispatchQueue.main.async { guard self.previewGen == gen, self.picking else { return }
                if let why { self.picking = false; self.pickURLs = []; self.previewGen += 1; self.unusable(why) } else { self.presentPick(center) } } }
        for (i, spec) in Converter.webSpecs.enumerated() {   // 카드 썸네일: 첫 사진을 각 규격으로 얼굴 기준 자르기 (변환과 같은 함수)
            previewQ.async { [weak self] in guard let self else { return }
                var base = self.previewBases[u.path]
                if base == nil, let src = CGImageSourceCreateWithURL(u as CFURL, nil) { base = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary); self.previewBases[u.path] = base }
                guard let b = base else { return }
                let (_, out, _) = Converter.webSized(b, want: spec, high: false, key: u)
                let im = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
                DispatchQueue.main.async { if self.previewGen == gen, self.picking { self.sizeView.setThumb(i, im) } } } }
        return true
    }
    func unusable(_ why: String) {   // 사용불가 경고창
        testMode = nil
        if let o = psOut { Converter.writeResult(o, [("ok", "0"), ("reason", why)]); exit(0) }   // 포토샵: 스크립트가 경고창을 띄움
        if let out = ProcessInfo.processInfo.environment["DONUT_PICKSHOT"] { print("ALERT 사용불가: \(why)"); fflush(stdout); _ = out; exit(0) }   // 시험
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.alertStyle = .warning; a.messageText = "사용불가"; a.informativeText = why + "\n얼굴이 하나만 또렷하게 나온 세로 사진으로 다시 해 주세요."; a.addButton(withTitle: "확인"); a.runModal()
    }
    func presentPick(_ center: NSPoint) {
        mode = "cards"; layoutHolder(); sizeView.showCustom = psOut == nil || ProcessInfo.processInfo.environment["DONUT_PS_CUSTOM"] != nil; applyThemeAll()
        let m = NSEvent.mouseLocation, scr = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        let target = pickRect(center: NSPoint(x: scr.visibleFrame.midX, y: scr.visibleFrame.midY))   // 항상 화면 가운데 (마우스가 있는 모니터, 2026-11-05)
        debugLog("패널 위치 \(target) 화면 \(scr.visibleFrame)")
        listHideWork?.cancel(); listGen += 1; listSlide = 0
        sizePanel.ignoresMouseEvents = false; sizePanel.acceptsMouseMovedEvents = true; sizeView.updateTrackingAreas()
        sizePanel.setFrame(target, display: false); fitHolder(target.size)
        if let p = psPreset { psPreset = nil; pick(p.0); adjustView.slider.doubleValue = p.1; adjustView.topSlider.doubleValue = p.2; adjustView.changed() }   // 포토샵: 지난 규격 조절 화면으로 바로 (띄우기 전에)
        let r = pickRect(center: NSPoint(x: target.midX, y: target.midY)); sizePanel.setFrame(r, display: false); fitHolder(r.size)
        playOpen()
        sizePanel.makeKey(); sizePanel.makeFirstResponder(activeView())   // Esc 받기
    }
    // MARK: 등장·퇴장 (2026-11-05 사용자 선택 A): y. 가 나타나며 딱 한 번 통 → 패널이 y. 모서리(오른쪽 위)에서 젤리처럼 / 닫을 땐 짧게 역순
    var panelAnimGen = 0
    func activeView() -> NSView { mode == "adjust" ? adjustView : (mode == "custom" ? customView : sizeView) }
    func resetAnim() { CATransaction.begin(); CATransaction.setDisableActions(true); for v in [sizeView as NSView, adjustView, customView, yBtn as NSView] { v.layer?.removeAnimation(forKey: "panelAnim"); v.layer?.transform = CATransform3DIdentity; v.layer?.opacity = 1 }; CATransaction.commit() }
    // Core Animation에 맡김 (2026-11-05 최적화): 화면 주사율(120Hz)대로 그려지고 앱이 바빠도 끊기지 않음. 곡선은 미리 뽑은 값(키프레임)
    func scaleT(_ v: NSView, _ k: CGFloat, corner: Bool) -> CATransform3D {
        let w = corner ? v.bounds.width : v.bounds.width / 2, h = corner ? v.bounds.height : v.bounds.height / 2
        return CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(w, h, 0), k, k, 1), -w, -h, 0) }
    func keyframes(_ v: NSView, dur: Double, delay: Double, n: Int = 48, corner: Bool, scale: (Double) -> Double, opacity: (Double) -> Double) {
        guard let l = v.layer else { return }
        let ts = (0...n).map { Double($0) / Double(n) }
        let tr = CAKeyframeAnimation(keyPath: "transform"); tr.values = ts.map { NSValue(caTransform3D: scaleT(v, CGFloat(scale($0)), corner: corner)) }
        let op = CAKeyframeAnimation(keyPath: "opacity"); op.values = ts.map { NSNumber(value: opacity($0)) }
        let g = CAAnimationGroup(); g.animations = [tr, op]; g.duration = dur; g.beginTime = CACurrentMediaTime() + delay; g.fillMode = .backwards; g.isRemovedOnCompletion = true
        for a in [tr, op] { a.duration = dur; a.calculationMode = .linear }
        l.add(g, forKey: "panelAnim")
    }
    func playOpen() {
        panelAnimGen += 1; let v = activeView()
        CATransaction.begin(); CATransaction.setDisableActions(true); resetAnim(); CATransaction.commit()   // 끝 모습 = 원래 크기 (애니메이션은 그 위에)
        sizePanel.alphaValue = 1; sizePanel.orderFrontRegardless()
        keyframes(yBtn, dur: 0.38, delay: 0, corner: false, scale: { t in t < 0.6 ? 0.4 + 0.78 * sin(t / 0.6 * .pi / 2) : 1.18 - 0.18 * sin((t - 0.6) / 0.4 * .pi / 2) }, opacity: { min(1, $0 * 3) })   // y.: 통 한 번
        keyframes(v, dur: 0.62, delay: 0.38, n: 60, corner: true, scale: { t in 0.2 + 0.8 * (1 - exp(-7 * t) * cos(t * .pi * 3.2)) }, opacity: { min(1, $0 * 3) })   // 패널: 모서리에서 젤리
    }
    func playClose(_ done: @escaping () -> Void) {   // 역순, 짧게: 패널 0.18초 → y. 0.1초
        panelAnimGen += 1; let g = panelAnimGen, v = activeView()
        keyframes(v, dur: 0.18, delay: 0, n: 12, corner: true, scale: { 1 - 0.85 * $0 * $0 }, opacity: { 1 - $0 * $0 })
        keyframes(yBtn, dur: 0.1, delay: 0.18, n: 8, corner: false, scale: { 1 - 0.6 * $0 }, opacity: { 1 - $0 })
        CATransaction.begin(); CATransaction.setDisableActions(true); v.layer?.opacity = 0; yBtn.layer?.opacity = 0; CATransaction.commit()   // 끝 모습 = 안 보임
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in guard let self, self.panelAnimGen == g else { return }; done() }
    }
    func resetAnimLater() { DispatchQueue.main.async { [weak self] in guard let self, !self.sizePanel.isVisible else { return }; self.resetAnim() } }
    // 패널 크기 = ydot의 Preview Size(Small 150 · Medium 220 · Large 300 · Extra Large 400)와 같은 설정(previewH). 패널 위 스크롤로도 조절 (2026-11-04)
    func pickScale() -> CGFloat {
        let h = previewThumbH(), pts: [(CGFloat, CGFloat)] = [(120, 0.72), (150, 0.8), (220, 1.0), (300, 1.2), (400, 1.4), (480, 1.55)]
        for k in 1..<pts.count where h <= pts[k].0 { let (a, sa) = pts[k - 1], (b, sb) = pts[k]; return sa + (sb - sa) * (h - a) / (b - a) }
        return 1.55
    }
    func pickRect(center c: NSPoint, base b: NSSize? = nil) -> NSRect {   // 보이는 패널이 화면 안에 들어가게. 배율은 세 화면 공통(가장 큰 화면 기준) → 전환 끝에 "뚝" 없음, 어떤 화면에서도 같은 규칙 (2026-11-05)
        let screen = NSScreen.screens.first { $0.frame.contains(c) } ?? NSScreen.main ?? NSScreen.screens[0]; let v = screen.visibleFrame
        let base = b ?? baseSize
        let maxW = max(cardsSize.width, adjustSize.width, customSize.width), maxH = max(cardsSize.height, adjustSize.height, customSize.height)
        let k = max(0.4, min(pickScale(), (v.width - 24) / maxW, (v.height - 24) / maxH))   // 보이는 패널만 + 위아래 12씩 (투명 여유는 화면 밖으로 나가도 됨)
        let pw = base.width * k, ph = base.height * k
        let cx = min(max(c.x, v.minX + 12 + pw / 2), v.maxX - 12 - pw / 2), cy = min(max(c.y, v.minY + 12 + ph / 2), v.maxY - 12 - ph / 2)
        let w = ((base.width + btnM * 2) * k).rounded(), h = ((base.height + btnM * 2) * k).rounded()
        return NSRect(x: (cx - w / 2).rounded(), y: (cy - h / 2).rounded(), width: w, height: h)
    }
    func yRect(_ x: CGFloat, _ y: CGFloat) -> NSRect { let d = 30 / uiK; return NSRect(x: x - d / 2, y: y - d / 2, width: d, height: d) }   // y. = 모서리 가운데, 화면에서 늘 30pt
    func fitHolder(_ size: NSSize) {   // 그릇 뷰를 창 크기로, 내용은 원래 좌표 그대로 확대·축소 (버튼 막대·y.만 되돌려 같은 크기)
        guard let holder = sizePanel.contentView else { return }
        let k = size.width / (baseSize.width + btnM * 2)
        if abs(k - uiK) > 0.01 { uiK = k; adjustView.setUI(); customView.setUI(); sizeView.setUI(); let b = baseSize; yBtn.frame = yRect(btnM + b.width, btnM + b.height) }
        holder.frame = NSRect(origin: .zero, size: size); holder.bounds = NSRect(x: 0, y: 0, width: baseSize.width + btnM * 2, height: baseSize.height + btnM * 2)
    }
    // 카드 클릭 → 2단계(얼굴 크기 조절). Save = 그 크기로 고화질+저화질
    var adjustIdx = -1, adjustGen = 0
    func pickDirect() {   // Custom: 증명 크기로 조절 화면 시작 · 가로·세로 슬라이더로 이번만 크기 바꿈 (저장 안 함, 사용자 2026-11-07)
        guard picking else { return }; adjustIdx = 0; let sp = Converter.customStart(ySnap())   // 설정 › 기본 › 규격 › Custom 처음 값
        adjustView.direct = true; adjustView.applyTheme(); adjustView.show(sp, image: sizeView.thumbs[0].image)
        switchMode("adjust"); adjustChanged(adjustView.head, adjustView.topM) }
    func pick(_ i: Int) {
        guard picking, i >= 0, i < Converter.webSpecs.count else { return }
        adjustIdx = i; let sp = Converter.webSpecs[i]
        adjustView.direct = false; adjustView.applyTheme(); adjustView.show(sp, image: sizeView.thumbs[i].image)
        switchMode("adjust")
        adjustChanged(adjustView.head, adjustView.topM)
    }
    func adjustChanged(_ head: Double, _ top: Double) {   // 게이지 → 같은 얼굴 인식 결과로 다시 자름 (최신 값만)
        guard picking, adjustIdx >= 0, let u = pickURLs.first else { return }
        var sp = adjustView.spec; sp.headCm = head; sp.topCm = top   // Custom이면 조절 화면의 가로·세로
        adjustGen += 1; let gen = adjustGen
        previewQ.async { [weak self] in guard let self, self.adjustGen == gen else { return }
            var base = self.previewBases[u.path]
            if base == nil, let src = CGImageSourceCreateWithURL(u as CFURL, nil) { base = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary); self.previewBases[u.path] = base }
            guard let b = base else { return }
            guard let out = Converter.faceCropAny(b, sp, key: u, outH: 900) else { return }
            let im = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
            DispatchQueue.main.async { if self.adjustGen == gen, self.picking { self.adjustView.photo.image = im } } }
    }
    func adjustBack() {
        adjustGen += 1; adjustIdx = -1
        sizeView.hover = -2; sizeView.setHover(-1); switchMode("cards")
    }
    func psExit() { if sizePanel.isVisible { sizePanel.ignoresMouseEvents = true; playClose { exit(0) } } else { exit(0) } }   // 포토샵 모드: 결과를 쓴 뒤 짧은 퇴장 → 종료 (2026-11-05)
    func visiblePanelRect() -> NSRect {   // 창에서 투명 여유를 뺀 실제 패널 자리 (화면 좌표)
        let f = sizePanel.frame, k = f.width / (baseSize.width + btnM * 2); return f.insetBy(dx: btnM * k, dy: btnM * k) }
    func adjustLimits(_ sp: Converter.WebSpec, _ f: Double, _ m: Double) -> (fLo: Double, mLo: Double, mHi: Double) {
        guard let h = pickHead else { return (faceRange.lowerBound, topRange.lowerBound, topRange.upperBound) }
        return Converter.faceLimits(h.W, h.H, (h.crown, h.chin, h.cx), sp, f, m) }
    // MARK: Custom (2026-11-05): 1차 크롭 → 원본·1차 저장 → 2차 3.5×4.5 → 고화질 저장 → 포토샵 5×7 시트
    let customQ = DispatchQueue(label: "custom.save")
    var customLoading = false
    var pickSpot = Spot(point: .zero, kind: .unknown), customOnlyDest: URL?, customOnlyTemp: URL?, customSaving = false
    var customSfx = "", customReady = false, customDest: URL?, customFull: CGImage?, customBase: CGImage?, customSrc: URL?, customFirst: CGImage?
    func beginCustom() {
        // 포토샵 인화: 같은 패널에서 Custom (미리보기 사진으로 자리만 고르고, 자르기·저장·인화지는 포토샵 스크립트가 함 — 증명~명함과 같은 원리, 2026-11-05)
        guard picking, let u = pickURLs.first else { return }
        customSrc = u; customReady = false; customFull = nil; customFirst = nil
        guard !customLoading else { return }; customLoading = true
        let gen = previewGen
        previewQ.async { [weak self] in   // 큰 사진(2400px) 준비는 뒤에서 (예전엔 화면 쪽에서 해 0.3초 멈춤, 2026-11-05)
            guard let self else { return }
            let src = CGImageSourceCreateWithURL(u as CFURL, nil)
            let b = src.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) }
            DispatchQueue.main.async {
                self.customLoading = false
                guard self.picking, self.previewGen == gen, self.customSrc == u else { return }
                guard let src, let b else { self.unusable("사진을 읽지 못했어요."); return }
                self.customBase = b; self.customView.applyTheme(); self.customView.start(b); self.switchMode("custom", animated: self.customOnlyDest == nil)
                if self.customOnlyDest != nil, !self.sizePanel.isVisible { self.playOpen(); self.sizePanel.makeKey(); self.sizePanel.makeFirstResponder(self.customView) }   // 포토샵 Custom: 사진이 준비된 뒤 등장
                self.customQ.async { [weak self] in   // 원본 크기 그림도 뒤에서 미리 (저장 때 씀)
                    guard let self, let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return }
                    let full = Converter.fullImage(src, props); DispatchQueue.main.async { if self.customSrc == u { self.customFull = full } } } } }
    }
    func customBack() { if customOnlyDest != nil { endPick() } else { switchMode("cards") } }
    // 포토샵 인화 → Custom (2026-11-05): 포토샵 화면 그대로 내보낸 사진으로 바로 Custom. 저장은 데스크톱, 끝나면 임시 폴더 지우고 종료
    func startCustomOnly(_ u: URL) {
        customOnlyDest = Controller.desktopDest(); customOnlyTemp = u.deletingLastPathComponent()
        picking = true; pickURLs = [u]; mode = "custom"; layoutHolder(); applyThemeAll()
        let m = NSEvent.mouseLocation, scr = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main ?? NSScreen.screens[0]
        let r = pickRect(center: NSPoint(x: scr.visibleFrame.midX, y: scr.visibleFrame.midY))
        sizePanel.ignoresMouseEvents = false; sizePanel.acceptsMouseMovedEvents = true; sizePanel.setFrame(r, display: false); fitHolder(r.size)
        beginCustom()   // 사진이 준비되면 그때 등장 (beginCustom 끝에서 playOpen)
    }
    func customOnlyQuit(after: Double) {   // 내보낸 임시 사진 지우고 끝
        guard customOnlyDest != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in if let t = self?.customOnlyTemp, t.lastPathComponent.hasPrefix("ydot_custom_") { try? FileManager.default.removeItem(at: t) }; exit(0) } }
    static func desktopDest() -> URL { if let d = ProcessInfo.processInfo.environment["DONUT_CUSTOM_DEST"] { return URL(fileURLWithPath: d, isDirectory: true) }; return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }
    // 이름 규칙 (2026-11-05 사용자 확정, 모든 흐름 공통): original · crop · 고화질 · 저화질. 겹치면 세트 전체에 같은 꼬리 _1, _2 …
    // 꼬리 k = 세트의 이름이 모두 비어 있는 가장 작은 값 (0 = 꼬리 없음) → 세트가 섞이지 않고 덮어쓰기 없음
    static func nextNumber(_ dir: URL, _ names: (String) -> [String]) -> Int {
        var k = 0
        while names(sfx(k)).contains(where: { nm in FileManager.default.fileExists(atPath: dir.appendingPathComponent(nm.precomposedStringWithCanonicalMapping).path) }) { k += 1 }
        return k
    }
    static func sfx(_ k: Int) -> String { k == 0 ? "" : "_\(k)" }
    static func origExt(_ u: URL) -> String { let e = u.pathExtension.lowercased(); return e.isEmpty ? "jpg" : e }
    static func cropFull(_ full: CGImage, _ base: CGImage, _ r: CGRect) -> CGImage? {   // 미리보기 좌표 → 원본 좌표로 잘라냄 (원본 해상도 그대로)
        let k = Double(full.width) / Double(base.width)
        var rr = CGRect(x: (r.minX * k).rounded(), y: (r.minY * k).rounded(), width: (r.width * k).rounded(), height: (r.height * k).rounded())
        rr = rr.intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height)); guard !rr.isEmpty else { return nil }
        return full.cropping(to: rr)
    }
    static func writeJPG(_ img: CGImage, _ url: URL, widthCm: Double, meta: [CFString: Any]) throws {
        var m = meta; let dpi = Double(img.width) / (widthCm / 2.54); m[kCGImagePropertyDPIWidth] = dpi; m[kCGImagePropertyDPIHeight] = dpi
        let flat = Converter.hasAlpha(img) ? (Converter.flatten(img) ?? img) : img
        let data = try Converter.encode(flat, .jpeg, 0.97, m)
        try data.write(to: url, options: .withoutOverwriting)
    }
    func customSaveFirst(_ r: CGRect, _ ratio: CustomRatio) {
        if psOut != nil { return }   // 포토샵: 1차 자리는 기억만 (2차 Save 때 함께 넘김)
        guard let u = customSrc, let base = customBase else { return }
        if testMode != nil {   // 테스트: 1차 크롭은 메모리에만
            customQ.async { [weak self] in guard let self else { return }; var full = DispatchQueue.main.sync { self.customFull }
                if full == nil, let src = CGImageSourceCreateWithURL(u as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] { full = Converter.fullImage(src, props) }
                self.testFull = full; self.testFirst = full.flatMap { Controller.cropFull($0, base, r) } }
            return }
        let ext = Controller.origExt(u), spot0 = pickSpot, fixed = customOnlyDest
        customQ.async { [weak self] in guard let self else { return }; let N = FileNames.current()
            let dest = fixed ?? (ProcessInfo.processInfo.environment["DONUT_CUSTOM_DEST"].map { URL(fileURLWithPath: $0, isDirectory: true) }) ?? ySnap().fixedFolder ?? Locator.resolve(spot0).folder ?? u.deletingLastPathComponent()   // 놓은 폴더(데스크톱이면 데스크톱), 포토샵이면 데스크톱
            let k = Controller.nextNumber(dest) { t in ["\(N.original)\(t).\(ext)", "\(N.crop)\(t).jpg", "\(N.high)\(t).jpg"] + (ySnap().deskFile ? ["\(N.sheet)\(t).png"] : []) }, t = Controller.sfx(k); DispatchQueue.main.sync { self.customSfx = t; self.customReady = true; self.customDest = dest }
            var failed: [String] = []
            do { try FileManager.default.copyItem(at: u, to: dest.appendingPathComponent("\(N.original)\(t).\(ext)")) } catch { failed.append("원본 복사: \(error.localizedDescription)") }
            let src = CGImageSourceCreateWithURL(u as CFURL, nil), props = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
            var full = DispatchQueue.main.sync { self.customFull }; if full == nil, let src { full = Converter.fullImage(src, props) }
            if let full, let c = Controller.cropFull(full, base, r) {
                do { try Controller.writeJPG(c, dest.appendingPathComponent("\(N.crop)\(t).jpg"), widthCm: ratio.key == "orig" ? Double(c.width) / 300 * 2.54 : ratio.w, meta: Converter.metadata(from: props)) } catch { failed.append("크롭 저장: \(error.localizedDescription)") }
                DispatchQueue.main.async { self.customFirst = c; self.customFull = full }
            } else { failed.append("크롭을 만들지 못했어요.") }
            debugLog("Custom 1차 저장 꼬리[\(t)] \(ratio.key) 실패: \(failed)")
            if !failed.isEmpty { DispatchQueue.main.async { self.customAlert(failed.joined(separator: "\n")) } } }
    }
    func customDone(_ r: CGRect, _ ratio: CustomRatio) {   // 프로필 Done: 1차 크롭만 (원본 · crop) 저장하고 끝
        if let o = psOut, let b = customBase {   // 포토샵: 1차 자리만 돌려줌 (only1 → 인화 스크립트가 원본·crop만)
            func f(_ v: CGFloat) -> String { String(Double(v)) }
            Converter.writeResult(o, [("ok", "1"), ("custom", "1"), ("only1", "1"), ("ratio", ratio.key), ("rw", String(ratio.w)), ("rh", String(ratio.h)),
                ("x1", f(r.minX)), ("y1", f(r.minY)), ("w1", f(r.width)), ("h1", f(r.height)), ("iw", String(b.width)), ("ih", String(b.height))])
            psExit(); return }
        if let side = testMode, let u = customSrc {
            customSaveFirst(r, ratio); endPick(); let (dir, _) = testDest(side), N = FileNames.current(), ext = side == "ps" ? "jpg" : Controller.origExt(u)
            testRun(side, "프로필 · Done (1차만)") { [weak self] in
                let t = Controller.sfx(Controller.nextNumber(dir) { t in ["\(N.original)\(t).\(ext)", "\(N.crop)\(t).jpg"] })
                return [("\(N.original)\(t).\(ext)", self?.testFull, "원본 그대로"), ("\(N.crop)\(t).jpg", self?.testFirst, "1차 크롭 · \(ratio.label)" + (self?.testFirst.map { "\n\($0.width)×\($0.height) px" } ?? ""))] }
            return }
        customSaveFirst(r, ratio); customSaving = true; endPick()
        customQ.async { [weak self] in DispatchQueue.main.async { self?.customSaving = false; self?.customOnlyQuit(after: 8) } }
    }
    func customSaveSecond(_ c1: CGRect, _ ratio: CustomRatio, _ r2: CGRect) {
        if let o = psOut, let b = customBase {   // 포토샵: 숫자만 돌려주고 끝 (미리보기 사진 픽셀, 위 기준)
            func f(_ v: CGFloat) -> String { String(Double(v)) }
            Converter.writeResult(o, [("ok", "1"), ("custom", "1"), ("ratio", ratio.key), ("rw", String(ratio.w)), ("rh", String(ratio.h)),
                ("x1", f(c1.minX)), ("y1", f(c1.minY)), ("w1", f(c1.width)), ("h1", f(c1.height)), ("x2", f(r2.minX)), ("y2", f(r2.minY)), ("w2", f(r2.width)), ("h2", f(r2.height)),
                ("iw", String(b.width)), ("ih", String(b.height))] + psProfileLay(b, c1))
            psExit(); return }
        guard let u = customSrc, let base = customBase else { return }
        if let side = testMode {
            endPick(); let (dir, _) = testDest(side), ys = ySnap(), N = FileNames.current(), ext = side == "ps" ? "jpg" : Controller.origExt(u)
            let (toFile, toPS) = side == "ps" ? (ys.psFile, ys.psPS) : (ys.deskFile, ys.deskPS), sx = side == "ps" ? "jpg" : "png"
            testRun(side, "프로필") { [weak self] in guard let self else { return [] }
                let t = Controller.sfx(Controller.nextNumber(dir) { t in ["\(N.original)\(t).\(ext)", "\(N.crop)\(t).jpg", "\(N.high)\(t).jpg"] + (toFile ? ["\(N.sheet)\(t).\(sx)"] : []) })
                guard let full = self.testFull, let c2 = Controller.cropFull(full, base, r2), let c1img = self.testFirst ?? Controller.cropFull(full, base, c1) else { return [("실패", nil, "사진을 다시 읽지 못했어요")] }
                let on = toFile || toPS
                return [("\(N.original)\(t).\(ext)", full, "원본 그대로"), ("\(N.crop)\(t).jpg", c1img, "1차 크롭 · \(c1img.width)×\(c1img.height) px"), ("\(N.high)\(t).jpg", c2, "2차 크롭 3.5×4.5 cm\n\(c2.width)×\(c2.height) px"),
                        on ? ("\(N.sheet)\(t).\(sx)", Sheet.make(polaroid: c1img, small: c2), "5×7 in 인화지\n" + [toFile ? "파일로" : nil, toPS ? "포토샵 새 문서로" : nil].compactMap { $0 }.joined(separator: " · ")) : ("인화지", nil, "인화지 출력 꺼짐\n(설정 › 인화지 출력)")] }
            return }
        customSaving = true; endPick()
        customQ.async { [weak self] in guard let self else { return }; let N = FileNames.current()   // 1차 저장이 끝난 뒤 (같은 줄에서 차례로)
            let (ready, t, dest, full0, first0) = DispatchQueue.main.sync { (self.customReady, self.customSfx, self.customDest ?? Controller.desktopDest(), self.customFull, self.customFirst) }
            let src = CGImageSourceCreateWithURL(u as CFURL, nil), props = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
            guard ready, let full = full0 ?? src.flatMap({ Converter.fullImage($0, props) }), let c2 = Controller.cropFull(full, base, r2), let c1img = first0 ?? Controller.cropFull(full, base, c1) else { DispatchQueue.main.async { self.customAlert("사진을 다시 읽지 못했어요.") }; return }
            do { try Controller.writeJPG(c2, dest.appendingPathComponent("\(N.high)\(t).jpg"), widthCm: 3.5, meta: Converter.metadata(from: props)) } catch { DispatchQueue.main.async { self.customAlert("고화질 저장: \(error.localizedDescription)") } }
            guard let sheet = Sheet.make(polaroid: c1img, small: c2) else { DispatchQueue.main.async { self.customAlert("인화지를 만들지 못했어요.") }; return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ydot_sheet_\(Int(Date().timeIntervalSince1970)).png")
            do { try Sheet.writePNG(sheet, tmp) } catch { DispatchQueue.main.async { self.customAlert("인화지 저장: \(error.localizedDescription)") }; return }
            debugLog("Custom 2차 저장 꼬리[\(t)] 시트 \(tmp.path)")
            if let o = ProcessInfo.processInfo.environment["DONUT_SHEET_OUT"] { try? FileManager.default.removeItem(atPath: o); try? FileManager.default.copyItem(at: tmp, to: URL(fileURLWithPath: o)); DispatchQueue.main.async { self.customSaving = false; self.customOnlyQuit(after: 1) }; return }   // 시험: 포토샵 대신 파일로
            let ys = ySnap(), (toFile, toPS) = (ys.deskFile, ys.deskPS)   // 설정 › 인화지 출력 (데스크톱 기본 = 둘 다 끔)
            if toFile { let to = dest.appendingPathComponent("\(N.sheet)\(t).png"); try? FileManager.default.copyItem(at: tmp, to: to) }
            DispatchQueue.main.async { if toPS { Sheet.openInPhotoshop(tmp, fallbackName: "\(N.sheet)\(t).png", dest: dest) }; self.customSaving = false; self.customOnlyQuit(after: 8) } }
    }
    func customAlert(_ why: String) { NSApp.activate(ignoringOtherApps: true); let a = NSAlert(); a.alertStyle = .warning; a.messageText = "프로필 저장 문제"; a.informativeText = why; a.addButton(withTitle: "확인"); a.runModal(); if !picking { customSaving = false; customOnlyQuit(after: 0.2) } }
    func adjustSave(_ head: Double, _ top: Double) {
        guard picking, adjustIdx >= 0 else { return }
        var sp = adjustView.spec; sp.headCm = head; sp.topCm = top   // Custom이면 조절 화면에서 정한 크기
        Sheet.customDims = sp.name == "Custom" ? (sp.w, sp.h) : nil
        if let o = psOut, let u = pickURLs.first {   // 포토샵 가이드: 자를 자리를 써 두고 끝
            let (img, why) = Converter.psCheck(u)
            if let why { Converter.writeResult(o, [("ok", "0"), ("reason", why)]); exit(0) }
            guard let img, let r = Converter.cropRect(img, sp) else { Converter.writeResult(o, [("ok", "0"), ("reason", "자를 자리를 계산하지 못했어요.")]); exit(0) }
            Converter.writeResult(o, [("ok", "1"), ("spec", sp.name), ("head", String(head)), ("top", String(top)), ("x", String(Double(r.minX))), ("y", String(Double(r.minY))), ("w", String(Double(r.width))), ("h", String(Double(r.height))), ("iw", String(img.width)), ("ih", String(img.height)), ("pw", String(sp.px.0)), ("ph", String(sp.px.1)), ("cmw", String(sp.w)), ("cmh", String(sp.h)), ("lay", Sheet.layString(Sheet.layout(sp.name, ySnap()), sp.name, style: Sheet.style(ySnap())))] + psSig(img, sp)); psExit(); return   // pw·ph = 300ppi 규격 픽셀
        }
        if let side = testMode, let u = pickURLs.first {   // 테스트: 같은 함수로 메모리에서만
            endPick(); let (dir, _) = testDest(side), ys = ySnap(), N = FileNames.current(), ext = side == "ps" ? "jpg" : Controller.origExt(u)
            let sheetOn = side == "ps" && (ys.psFile || ys.psPS)
            testRun(side, "\(sp.name) \(sp.fmt(sp.w))×\(sp.fmt(sp.h)) cm") {
                let t = Controller.sfx(Controller.nextNumber(dir) { t in ["\(N.original)\(t).\(ext)", "\(N.high)\(t).jpg", "\(N.low)\(t).jpg"] + (sheetOn && ys.psFile ? ["\(N.sheet)\(t).jpg"] : []) })
                guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any], let img = Converter.fullImage(src, props), let flat = Converter.flatten(img) else { return [("실패", nil, "사진을 읽지 못했어요")] }
                let (_, hi, dpi) = Converter.webSized(flat, want: sp, high: true, key: u), (_, lo, _) = Converter.webSized(flat, want: sp, high: false, key: u)
                var out: [(String, CGImage?, String)] = [("\(N.original)\(t).\(ext)", flat, "원본 그대로\n\(flat.width)×\(flat.height) px"), ("\(N.high)\(t).jpg", hi, "\(hi.width)×\(hi.height) px · \(dpi)ppi"), ("\(N.low)\(t).jpg", lo, "\(lo.width)×\(lo.height) px · 300ppi")]
                if side == "ps" { out.append(sheetOn ? ("\(N.sheet)\(t).jpg", Sheet.grid(lo, sp.name), "5×7 in 인화지\n" + [ys.psFile ? "파일로" : nil, ys.psPS ? "포토샵 새 문서로" : nil].compactMap { $0 }.joined(separator: " · ")) : ("인화지", nil, "인화지 출력 꺼짐\n(설정 › 인화지 출력)")) }
                return out }
            return }
        let urls = pickURLs
        endPick()
        _ = drop(urls, .web, spec: sp, both: true)   // 항상 고화질+저화질
    }
    func psProfileLay(_ base: CGImage, _ c1: CGRect) -> [(String, String)] {   // 포토샵 프로필 인화지 = 인화지 탭 '프로필' 배치 · 로고 사진·프레임 사진 그림은 1차 크롭으로 미리 그림
        let ys = ySnap(), st = Sheet.style(ys), L = Sheet.layout("프로필", ys); var out = [("lay", Sheet.layString(L, "프로필", style: st))]
        if let c = Controller.cropFull(base, base, c1), let dir = Sheet.writeItems(L, c, st) { out.append(("layItems", dir.path)) }
        return out }
    func psSig(_ img: CGImage, _ sp: Converter.WebSpec) -> [(String, String)] {   // 배치에 시그니처 포토가 있으면 그림(PNG)을 임시 폴더에 → 포토샵이 그대로 놓음 (다 쓰면 스크립트가 지움)
        let ys = ySnap(), L = Sheet.layout(sp.name, ys); guard L.cells.contains(where: { !$0.key.isEmpty }) else { return [] }   // 로고 사진 · 로고만 · 프레임 사진 그림을 임시 폴더에
        let (_, lo, _) = Converter.webSized(img, want: sp, high: false); guard let dir = Sheet.writeItems(L, lo, Sheet.style(ys)) else { return [] }
        return [("layItems", dir.path)] }
    func endPick() { if let o = psOut { Converter.writeResult(o, [("ok", "0"), ("reason", "cancel")]); psExit(); return }
        testMode = nil
        if customOnlyDest != nil, !customSaving { customOnlyQuit(after: 0.3) }
        guard picking else { return }; picking = false; pickURLs = []; adjustGen += 1; adjustIdx = -1; hideList(); previewReset()
        }   // 카드 화면으로 되돌리기는 퇴장이 끝나고 창이 사라진 뒤 (hideList) — 예전엔 0.2초 뒤라 퇴장 도중 카드 화면이 번쩍였음 (2026-11-05)
    var accepting = false   // 쉬프트를 떼면 false: 그 뒤의 놓기는 받지 않음
    var spot = Spot(point: .zero, kind: .unknown)
    var s: CGFloat = 0, goal: CGFloat = 0

    override init() {
        let rect = NSRect(x: 0, y: 0, width: donutSize, height: donutSize)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true   // 고리 그림자 (원형 catcher 모양대로 둥근 그림자, 2026-11-04 사용자 요청)
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        view = DonutView(frame: rect)
        panel.contentView = view
        sizePanel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: panelW, height: listH), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        sizePanel.isOpaque = false; sizePanel.backgroundColor = .clear; sizePanel.hasShadow = false;   // 그림자는 패널 레이어가 그림
        sizePanel.level = .popUpMenu; sizePanel.hidesOnDeactivate = false
        sizePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sizeView = SizeListView(frame: NSRect(origin: NSPoint(x: btnM, y: btnM), size: cardsSize))
        adjustView = AdjustView(frame: NSRect(origin: NSPoint(x: btnM, y: btnM), size: adjustSize)); adjustView.isHidden = true
        customView = CustomView(frame: NSRect(origin: NSPoint(x: btnM, y: btnM), size: customSize)); customView.isHidden = true
        let holder = HolderView(frame: NSRect(x: 0, y: 0, width: cardsSize.width + btnM * 2, height: cardsSize.height + btnM * 2)); for v in [sizeView as NSView, adjustView, customView] { holder.addSubview(v) }; sizePanel.contentView = holder
        previewPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: previewH()), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        previewPanel.isOpaque = false; previewPanel.backgroundColor = .clear; previewPanel.hasShadow = true; previewPanel.level = .popUpMenu; previewPanel.hidesOnDeactivate = false; previewPanel.ignoresMouseEvents = true
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]; previewPanel.contentView = previewView
        super.init()
        view.controller = self
        sizeView.controller = self
        adjustView.controller = self; customView.controller = self
        (sizePanel.contentView as? HolderView)?.onOutside = { [weak self] in guard let self, self.picking, !self.visiblePanelRect().contains(NSEvent.mouseLocation) else { return }; self.endPick() }
        yBtn = YButton(target: self, action: #selector(cycleTheme)); yBtn.isHidden = true   // 2026-11-05: y.는 상단바로 (떠 있는 버튼 없앰) yBtn.menuMaker = { [weak self] in self?.yMenu() ?? NSMenu() }; sizePanel.contentView?.addSubview(yBtn); layoutHolder(); applyThemeAll()
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.mouseDown() }
    }

    func mouseDown() {
        if picking { let p = NSEvent.mouseLocation; if !visiblePanelRect().insetBy(dx: -4, dy: -4).contains(p) { endPick() } }
        if psOut != nil || !enabled { return }   // 꺼 두면(메뉴 막대 y. › Shift Convert) 끌기 안 받음 · 포토샵 모드에서는 도넛(쉬프트 끌기)을 열지 않음   // 목록 밖 클릭 = 변환 없이 닫기 (목록 안 클릭은 뷰가 받음)
        dragCount = NSPasteboard(name: .drag).changeCount
        dragging = false
        shiftWas = CGEventSource.flagsState(.combinedSessionState).contains(.maskShift)
        debugLog("mouseDown count=\(dragCount) shift=\(shiftWas)")
        mouseTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        mouseTimer = t
    }

    func tick() {
        if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
            debugLog("mouseUp")
            mouseTimer?.invalidate(); mouseTimer = nil
            dragging = false
            if isOpen { close(keepTarget: true) }
            return
        }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let shift = flags.contains(.maskShift)
        let onlyShift = flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
        if !dragging {
            let pb = NSPasteboard(name: .drag)
            if pb.changeCount != dragCount, hasImages(pb) { dragging = true; debugLog("dragging") }
        }
        // 쉬프트를 누른 채 집은 경우(여러 장 선택 등)에는 한 번 뗐다 눌러야 열림
        if dragging, shift, onlyShift, !shiftWas, !isOpen { open() }
        if isOpen, !shift { close(keepTarget: false) }
        shiftWas = shift
    }

    func hasImages(_ pb: NSPasteboard) -> Bool {
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.contains { isImage($0) }
    }

    func isImage(_ u: URL) -> Bool {
        (try? u.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true
    }

    var scrollMon: Any?
    func open() {
        if picking { endPick() }
        if scrollMon == nil { scrollMon = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] e in self?.previewScroll(e) } }
        let p = NSEvent.mouseLocation
        debugLog("open at \(p)")
        if s == 0 {
            spot = Locator.snapshot(at: p)   // 도넛이 덮기 전에 아래 자리를 기억
            let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.screens[0]
            var o = NSPoint(x: p.x - donutSize / 2, y: p.y - donutSize / 2)
            o.x = min(max(o.x, screen.frame.minX), screen.frame.maxX - donutSize)
            o.y = min(max(o.y, screen.frame.minY), screen.frame.maxY - donutSize)
            panel.setFrameOrigin(o)
            debugLog("spot \(spot.kind)")
        }
        isOpen = true
        accepting = true
        panel.ignoresMouseEvents = false
        view.render(1); panel.invalidateShadow()   // 내용은 완성 상태로 한 번만
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        animate(to: 1)
    }

    // 쉬프트를 떼면 그 뒤의 놓기는 파인더로 그대로 가도록 도넛이 받지 않음
    func close(keepTarget: Bool) {
        isOpen = false
        if !keepTarget {
            accepting = false
            panel.ignoresMouseEvents = true
            view.select(nil)
            hideList()
        }
        animate(to: 0)
    }

    var animGen = 0
    // 열고 닫기 = 창 투명도만 맥 애니메이션(NSAnimationContext)에 맡김: 메인 스레드가 바빠도 끊기지 않고 주사율에 자동으로 맞음. 중간에 반대로 돌려도 현재 값에서 이어감(2026-11-04 실측). 열기·닫기 0.26초 ease-out
    func animate(to g: CGFloat) {
        goal = g; s = g; animGen += 1; let my = animGen   // 내용은 이미 완성 상태라 s는 목표값으로 (보이는 건 창 투명도뿐)
        let wins: [NSWindow] = [panel] + (sizePanel.isVisible && !picking ? [sizePanel] : []) + (previewPanel.isVisible && !picking ? [previewPanel] : [])
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.26; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94); for w in wins { w.animator().alphaValue = g } },
                                             completionHandler: { [weak self] in guard let self, self.animGen == my, g == 0 else { return }
            self.panel.alphaValue = 0; self.panel.orderOut(nil)
            self.view.select(nil)
            if !self.picking { self.hideList(animated: false); self.previewReset() } })   // 고리와 같이 이미 투명해짐 (고르기 중이면 목록은 둠)
    }

    func drop(_ urls: [URL], _ action: Action, spec: Converter.WebSpec? = nil, both: Bool = true) -> Bool {
        if action == .airdrop {   // 변환 없이 원본 파일을 에어드롭 창으로 (ydot의 airdropsend 도우미)
            let files = urls.filter { !$0.hasDirectoryPath }
            guard !files.isEmpty else { return false }
            let cands = [Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/airdropsend").path, Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("airdropsend").path, NSHomeDirectory() + "/Library/Application Support/cc/airdropsend"]   // 앱 안 것 먼저 (2026-11-05 ydot 혼자 동작)
            guard let helper = cands.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { toast.show("에어드롭 도우미를 찾지 못했어요 (ydot을 다시 설치해 주세요)"); return false }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) {
                let p = Process(); p.executableURL = URL(fileURLWithPath: helper); p.arguments = files.map(\.path); try? p.run() }
            return true
        }
        let images = urls.filter(isImage)
        guard !images.isEmpty else { return false }
        let where_ = spot
        // 끌기가 끝나 파인더가 답할 수 있게 된 뒤에 폴더를 물어봄
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { let N = FileNames.current()
            var dest = Locator.resolve(where_); if let f = ySnap().fixedFolder { dest.folder = f }   // 설정 › 사진 저장 위치
            debugLog("target \(dest.folder?.path ?? "원본 옆") \(dest.note ?? "")")
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Donut-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let jobs: [(URL, Bool)] = images.flatMap { u -> [(URL, Bool)] in action == .web && both ? [(u, false), (u, true)] : [(u, false)] }   // Product 고화질+저화질 = 두 파일
            var results = [Outcome?](repeating: nil, count: jobs.count)
            let lock = NSLock()
            var nums: [URL: String] = [:]   // Product: 사진마다 꼬리 → original · 고화질 · 저화질 (+ _1 …) (2026-11-05)
            if action == .web { for u in images { let folder = dest.folder ?? u.deletingLastPathComponent(), ext = Controller.origExt(u), taken = Set(nums.values)
                var k = Controller.nextNumber(folder) { t in ["\(N.original)\(t).\(ext)", "\(N.high)\(t).jpg", "\(N.low)\(t).jpg"] }; while taken.contains(Controller.sfx(k)) { k += 1 }; let t = Controller.sfx(k); nums[u] = t
                let o = staging.appendingPathComponent("\(N.original)\(t).\(ext)"); do { try FileManager.default.copyItem(at: u, to: o); results.append(.made(o, folder)) } catch { results.append(.failed(u, "원본 복사 실패")) } } }
            DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
                let nm = nums[jobs[i].0].map { (jobs[i].1 ? N.high : N.low) + $0 }
                let r = autoreleasepool { Converter.run(action, source: jobs[i].0, destFolder: dest.folder, staging: staging, webSpec: spec, webHigh: jobs[i].1, webName: nm) }
                lock.lock(); results[i] = r; lock.unlock()
            }
            var groups: [URL: [URL]] = [:], made: [URL] = [], failed: [String] = []
            for r in results.compactMap({ $0 }) {
                switch r {
                case .made(let file, let folder): groups[folder, default: []].append(file)
                case .failed(let u, let why): failed.append("\(u.lastPathComponent): \(why)")
                }
            }
            let copying = DispatchGroup()
            for (folder, files) in groups {
                copying.enter()
                FinderCopy.run(files, to: folder) { m, f in
                    lock.lock(); made += m; failed += f; lock.unlock()
                    copying.leave()
                }
            }
            copying.notify(queue: .main) {
                try? FileManager.default.removeItem(at: staging)
                var d = dest; if action == .web { d.desktopPoint = nil }   // Product는 놓은 자리에 꽂지 않음 (아이콘 겹침 없이 데스크톱 정렬대로)
                self.finish(made, failed, d)
            }
        }
        return true
    }

    func finish(_ made: [URL], _ failed: [String], _ dest: DropTarget) {
        var parts: [String] = []
        if let f = failed.first { parts.append(failed.count == 1 ? f : "\(failed.count)개 실패") }
        if !made.isEmpty, let note = dest.note { parts.append(note) }
        if !made.isEmpty, !Converter.lastWebSpec.isEmpty { parts.append("For Web " + Converter.lastWebSpec) }; Converter.lastWebSpec = ""
        if !parts.isEmpty { toast.show(parts.joined(separator: " · ")) }
        if let pt = dest.desktopPoint, !made.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Locator.placeOnDesktop(made, at: pt) }
        }
    }

    // 메뉴 막대 y. (2026-11-05 앱 나누기: Shift Convert = ydot 앱 자체). Shift Convert 켜기/끄기 · Panel Size · 끝내기
    var statusItem: NSStatusItem?
    var enabled: Bool { get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true } set { UserDefaults.standard.set(newValue, forKey: "enabled") } }   // 처음 = 켜짐
    func setUpMenu() {
        let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); statusItem = si
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.black]
            let sz = ("y." as NSString).size(withAttributes: a); ("y." as NSString).draw(at: NSPoint(x: (18 - sz.width) / 2, y: (18 - sz.height) / 2 + 1), withAttributes: a); return true }
        img.isTemplate = true; img.accessibilityDescription = "ydot"
        si.button?.image = img; si.button?.toolTip = "ydot"
        let m = NSMenu(); m.delegate = self; si.menu = m
    }
    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        let on = NSMenuItem(title: "Shift Convert", action: #selector(toggleEnabled), keyEquivalent: ""); on.target = self; on.state = enabled ? .on : .off
        on.toolTip = "사진을 집고 쉬프트를 누르면 변환 메뉴가 펼쳐져요"; m.addItem(on)
        let sizeItem = NSMenuItem(title: "Panel Size", action: nil, keyEquivalent: ""), sub = NSMenu()
        let cur = previewThumbH()
        for (t, h) in [("Small", 220.0), ("Medium", 300.0), ("Large", 400.0)] {
            let it = NSMenuItem(title: t, action: #selector(setPanelSize(_:)), keyEquivalent: ""); it.target = self; it.representedObject = h; it.state = abs(Double(cur) - h) < 1 ? .on : .off; sub.addItem(it) }
        sizeItem.submenu = sub; m.addItem(sizeItem)
        m.addItem(.separator())
        let om = NSMenuItem(title: "Open ydot", action: #selector(openMain), keyEquivalent: ""); om.target = self; m.addItem(om)
        let st = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); st.target = self; m.addItem(st)
        m.addItem(.separator())
        let q = NSMenuItem(title: "Quit ydot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""); m.addItem(q)
    }
    lazy var settings: SettingsController = { let s = SettingsController(); s.app = self; return s }()   // 'ydot' 창 하나 (앱을 누르면 · ⌘, = 설정 탭)
    var mainWin: SettingsController { settings }
    @objc func openSettings() { if picking { endPick() }; settings.show(); settings.requestTab("gen") }
    @objc func openMain() { if picking { endPick() }; settings.show() }
    @objc func toggleEnabled() { enabled.toggle(); if !enabled, isOpen { close(keepTarget: false) } }
    @objc func setPanelSize(_ sender: NSMenuItem) {
        guard let h = sender.representedObject as? Double else { return }; if ProcessInfo.processInfo.environment["DONUT_SIZESWITCH"] != nil || (ProcessInfo.processInfo.environment["DONUT_SIZEANIM"] != nil || ProcessInfo.processInfo.environment["DONUT_SIZEREC"] != nil || ProcessInfo.processInfo.environment["DONUT_TBTEST"] != nil || ProcessInfo.processInfo.environment["DONUT_SETTINGSTEST"] != nil || ProcessInfo.processInfo.environment["DONUT_SAMPLELOGIC"] != nil) { testPanelH = h } else { sharedDefaults.set(h, forKey: "previewH") }
        if sizePanel.isVisible { animatePanelSize() }   // 열린 패널도 부드럽게 (2026-11-05)
    }
    // 패널 크기 부드럽게 (y. 우클릭 · 메뉴 · 설정): 창은 처음에 한 번만 (지금 모습 ∪ 갈 모습) 크기로 → 그 안에서 배율만 0.3초 동안 바꿈 (버튼·y.는 화면 크기 그대로, 사진·바탕만 커지고 작아짐) → 끝에 창을 맞춤
    // 바뀌는 도중에 또 바꾸면 그 순간 모습에서 이어서 감 (두 단계 건너뛰기·연달아 바꾸기 모두 끊김 없이). 매 프레임 창 크기를 바꾸지 않음 (F11 시험 때 밀림 원인)
    var sizeAnim: Timer?, sizeAnimK: CGFloat = 0, sizeAnimC = NSPoint.zero
    func animatePanelSize() {
        guard sizePanel.isVisible, let holder = sizePanel.contentView else { return }
        let b = baseSize, full = NSSize(width: b.width + btnM * 2, height: b.height + btnM * 2), f = sizePanel.frame
        let k0 = sizeAnim != nil ? sizeAnimK : f.width / full.width, c0 = sizeAnim != nil ? sizeAnimC : NSPoint(x: f.midX, y: f.midY)
        sizeAnim?.invalidate(); sizeAnim = nil
        let r1 = pickRect(center: c0), k1 = r1.width / full.width, c1 = NSPoint(x: r1.midX, y: r1.midY)
        let v0 = NSRect(x: c0.x - full.width * k0 / 2, y: c0.y - full.height * k0 / 2, width: full.width * k0, height: full.height * k0), U = v0.union(r1).union(f).integral
        let m = mode
        func apply(_ k: CGFloat, _ c: NSPoint) {
            holder.bounds = NSRect(x: full.width / 2 - (c.x - U.minX) / k, y: full.height / 2 - (c.y - U.minY) / k, width: U.width / k, height: U.height / k)
            uiK = k; if m == "adjust" { adjustView.setUI() } else if m == "custom" { customView.setUI() } else { sizeView.setUI() }
            yBtn.frame = yRect(btnM + b.width, btnM + b.height) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sizePanel.setFrame(U, display: false); holder.frame = NSRect(origin: .zero, size: U.size); apply(k0, c0)
        CATransaction.commit(); sizePanel.display()
        sizeAnimK = k0; sizeAnimC = c0
        let t0 = CACurrentMediaTime(), dur = 0.3
        let tm = Timer(timeInterval: 1 / displayFPS, repeats: true) { [weak self] tm in
            guard let self, self.mode == m else { tm.invalidate(); self?.sizeAnim = nil; return }   // 도중에 화면이 바뀌면 그만 (전환이 크기를 맞춤)
            let t = min(1, (CACurrentMediaTime() - t0) / dur), e = CGFloat(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
            let k = k0 + (k1 - k0) * e, c = NSPoint(x: c0.x + (c1.x - c0.x) * e, y: c0.y + (c1.y - c0.y) * e); self.sizeAnimK = k; self.sizeAnimC = c
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if t >= 1 {
                tm.invalidate(); self.sizeAnim = nil
                self.sizePanel.setFrame(r1, display: false); holder.frame = NSRect(origin: .zero, size: r1.size); holder.bounds = NSRect(origin: .zero, size: full)
                uiK = k1; self.adjustView.setUI(); self.customView.setUI(); self.sizeView.setUI(); self.yBtn.frame = self.yRect(btnM + b.width, btnM + b.height)   // 끝: 안 보이는 화면도 새 배율로
            } else { apply(k, c) }
            CATransaction.commit(); self.sizePanel.display()
            debugLog(String(format: "크기 t=%.2f k=%.3f", t, k))
        }
        sizeAnim = tm; RunLoop.main.add(tm, forMode: .common)
    }
    func yMenu() -> NSMenu {   // y. 우클릭: Panel Size 바로 바꾸기 · Settings (2026-11-05)
        let m = NSMenu(); let cur = previewThumbH()
        let hd = NSMenuItem(title: "Panel Size", action: nil, keyEquivalent: ""); hd.isEnabled = false; m.addItem(hd)
        for (t, h) in [("Small", 220.0), ("Medium", 300.0), ("Large", 400.0)] {
            let it = NSMenuItem(title: t, action: #selector(setPanelSize(_:)), keyEquivalent: ""); it.target = self; it.representedObject = h; it.state = abs(Double(cur) - h) < 1 ? .on : .off; it.indentationLevel = 1; m.addItem(it) }
        m.addItem(.separator())
        let st = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); st.target = self; m.addItem(st)
        return m
    }
}

// MARK: - 설정 (2026-11-05 1단계: 일반 탭) — 파일 하나 ~/Library/Application Support/ydot/settings.json (포토샵 스크립트도 같이 읽음)
// 없거나 깨지면 기본값. 모르는 칸은 무시, 없는 칸은 기본값 → 버전이 달라도 안전
struct YCell: Codable, Equatable { var x: Int; var y: Int; var q: Int; var sig: Bool? = nil; var kind: String? = nil; var fid: String? = nil; var lh: Int? = nil   // kind: nil = 사진 · "logo" = 로고만 (lh = 높이 px) · "frame" = 프레임 사진 (fid = 프레임)
    var key: String { sig == true ? "s" : kind == "logo" ? "l\(lh ?? 71)" : kind == "frame" ? "f" + (fid ?? "") : "" } }   // sig = 시그니처 포토 (사진 3.5×4.5 + 아래 띠 + 로고 · 시그니처 탭 모양)   // 인화지 칸: 사진 왼쪽 위(px, 위 기준) · q = 시계 방향 90° 횟수
struct YLayout: Codable, Equatable { var land = false; var pad = 10; var stroke = 1; var gray = 204; var cells: [YCell] = [] }   // 규격 하나의 5×7 배치 (land = 가로 7×5)
struct YSample: Codable, Equatable { var id: String; var name: String; var file: String }
struct YDesign: Codable, Equatable { var sample: String? = nil; var spec = "증명"; var w = 413; var h = 531; var crop: [Double] = [] }   // 로고·프레임 탭 미리보기 사진: 샘플(nil = 고른 샘플) · 자른 규격 크기(300ppi px) · crop = 자른 자리 (0~1, 위 기준 x y w h · 비면 얼굴 기준 자동)
struct YFrame: Codable, Equatable { var id: String; var name: String; var file: String; var w = 531; var x = 59; var y = 59; var pw = 413 }   // 프레임: frames/ 안 파일 · w = 프레임 폭(px, 높이는 그림 비율) · 사진 왼쪽 위 x y · 사진 폭 pw (높이는 자른 규격 비율)   // file = samples/ 안의 파일 이름
struct YSettings: Codable, Equatable {
    var saveFolder = "drop"   // drop = 끌어 놓은 곳(기본) · desktop · 그 밖 = 폴더 경로
    var deskFile = false, deskPS = false   // 데스크톱 인화지: 파일로 · 포토샵 새 문서로 (기본 둘 다 끔 = 사진만 저장)
    var psFile = false, psPS = true        // 포토샵 인화 액션
    var deskSpecs: [String: [Double]] = [:], psSpecs: [String: [Double]] = [:]   // 규격 이름 → [얼굴, 여백] (cm). 없으면 기본값
    var logos: [YSample] = [], logoID = ""   // 인화지 로고: "" = 기본 로고 · "none" = 없음 · 그 밖 = logos/ 안 파일
    var polStrip = 63, logoH = 35, logoMargin = 24, logoAlign = "right"   // 폴라로이드 아래 띠·로고 높이·옆 여백 (300ppi px), 로고 자리
    var sigMT = 0, sigML = 0, sigMR = 0   // 로고 사진 위·왼쪽·오른쪽 여백 (px) · 아래 여백 = polStrip (로고 탭, 사용자 2026-11-07)
    var logoX: Int? = nil, logoY: Int? = nil   // 로고 왼쪽 위 (로고 사진 안 px) · nil = 아래 여백 안 오른쪽 (logoAlign·logoMargin)
    var design = YDesign()
    var frames: [YFrame] = [], frameID = ""
    var names: [String: String] = [:]   // 파일 이름: original · crop · high · low · sheet → 바꾼 이름 (없으면 기본)
    static let nameKeys = ["original", "crop", "high", "low", "sheet"], nameDefaults = ["original": "original", "crop": "crop", "high": "고화질", "low": "저화질", "sheet": "인화"]
    static func cleanName(_ v: String) -> String {   // 파일 이름에 못 쓰는 글자 빼기 · 40자까지
        var t = v.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: CharacterSet(charactersIn: "/:\\=\n\r\t")).joined()
        while t.hasPrefix(".") { t.removeFirst() }; return String(t.prefix(40)).precomposedStringWithCanonicalMapping }
    func fileName(_ k: String) -> String { let v = YSettings.cleanName(names[k] ?? ""); return v.isEmpty ? YSettings.nameDefaults[k]! : v }
    var layouts: [String: YLayout] = [:]   // 인화지 배치 (규격 이름 → 배치) · 없으면 기본 (Sheet.defaultLayout)
    var samples: [YSample] = [], curSample = ""   // 미리보기용 샘플 사진 (설정 폴더 samples/ 안의 줄인 복사본) · "" = 회색 실루엣
    func specs(_ side: String) -> [String: [Double]] { deskSpecs }   // 규격 하나로 합침 (데스크톱·포토샵 같은 값, 사용자 2026-11-06) · 예전 psSpecs 칸은 예전 ydot을 위해 같이 써 둠
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), z = YSettings()
        saveFolder = (try? c.decodeIfPresent(String.self, forKey: .saveFolder)) ?? nil ?? z.saveFolder
        deskFile = (try? c.decodeIfPresent(Bool.self, forKey: .deskFile)) ?? nil ?? z.deskFile
        deskPS = (try? c.decodeIfPresent(Bool.self, forKey: .deskPS)) ?? nil ?? z.deskPS
        psFile = (try? c.decodeIfPresent(Bool.self, forKey: .psFile)) ?? nil ?? z.psFile
        psPS = (try? c.decodeIfPresent(Bool.self, forKey: .psPS)) ?? nil ?? z.psPS
        deskSpecs = (try? c.decodeIfPresent([String: [Double]].self, forKey: .deskSpecs)) ?? nil ?? [:]
        psSpecs = (try? c.decodeIfPresent([String: [Double]].self, forKey: .psSpecs)) ?? nil ?? [:]
        if deskSpecs.isEmpty && !psSpecs.isEmpty { deskSpecs = psSpecs }; psSpecs = deskSpecs   // 합치기: 데스크톱 값 기준 (없으면 포토샵 값)
        samples = (try? c.decodeIfPresent([YSample].self, forKey: .samples)) ?? nil ?? []
        layouts = (try? c.decodeIfPresent([String: YLayout].self, forKey: .layouts)) ?? nil ?? [:]
        curSample = (try? c.decodeIfPresent(String.self, forKey: .curSample)) ?? nil ?? ""
        logos = (try? c.decodeIfPresent([YSample].self, forKey: .logos)) ?? nil ?? []
        names = (try? c.decodeIfPresent([String: String].self, forKey: .names)) ?? nil ?? [:]
        logoID = (try? c.decodeIfPresent(String.self, forKey: .logoID)) ?? nil ?? ""
        polStrip = (try? c.decodeIfPresent(Int.self, forKey: .polStrip)) ?? nil ?? z.polStrip
        logoH = (try? c.decodeIfPresent(Int.self, forKey: .logoH)) ?? nil ?? z.logoH
        logoMargin = (try? c.decodeIfPresent(Int.self, forKey: .logoMargin)) ?? nil ?? z.logoMargin
        logoAlign = (try? c.decodeIfPresent(String.self, forKey: .logoAlign)) ?? nil ?? z.logoAlign
        sigMT = (try? c.decodeIfPresent(Int.self, forKey: .sigMT)) ?? nil ?? 0; sigML = (try? c.decodeIfPresent(Int.self, forKey: .sigML)) ?? nil ?? 0; sigMR = (try? c.decodeIfPresent(Int.self, forKey: .sigMR)) ?? nil ?? 0
        logoX = (try? c.decodeIfPresent(Int.self, forKey: .logoX)) ?? nil; logoY = (try? c.decodeIfPresent(Int.self, forKey: .logoY)) ?? nil
        design = (try? c.decodeIfPresent(YDesign.self, forKey: .design)) ?? nil ?? YDesign()
        frames = (try? c.decodeIfPresent([YFrame].self, forKey: .frames)) ?? nil ?? []; frameID = (try? c.decodeIfPresent(String.self, forKey: .frameID)) ?? nil ?? ""
    }
    static var logoDir: URL { url.deletingLastPathComponent().appendingPathComponent("logos", isDirectory: true) }
    static var frameDir: URL { url.deletingLastPathComponent().appendingPathComponent("frames", isDirectory: true) }
    static var sampleDir: URL { url.deletingLastPathComponent().appendingPathComponent("samples", isDirectory: true) }
    static var url: URL { if let t = ProcessInfo.processInfo.environment["DONUT_SETTINGS_PATH"] { return URL(fileURLWithPath: t) }; return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ydot/settings.json") }   // DONUT_SETTINGS_PATH = 시험용
    static func load() -> YSettings { guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(YSettings.self, from: d) else { return YSettings() }; return s }
    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var me = self; me.psSpecs = me.deskSpecs
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; if let d = try? e.encode(me) { try? d.write(to: Self.url, options: .atomic) } }
    var fixedFolder: URL? {   // nil = 끌어 놓은 곳
        switch saveFolder { case "drop": return nil
        case "desktop": return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        default: var d: ObjCBool = false; return FileManager.default.fileExists(atPath: saveFolder, isDirectory: &d) && d.boolValue ? URL(fileURLWithPath: saveFolder, isDirectory: true) : nil }   // 폴더가 사라졌으면 끌어 놓은 곳
    }
}
enum YSStore { static let lock = NSLock(); static var value = YSettings.load(); static var side = "desk" }   // static = 처음 쓸 때 만들어짐 (파일 앞쪽 코드가 먼저 읽어도 안전 — 전역 변수로 두면 순서 때문에 켜자마자 충돌했음 2026-11-05)
struct FileNames { let original, crop, high, low, sheet: String   // 저장 때 한 번 읽어 씀 (설정 › 일반 › 파일 이름)
    static func current() -> FileNames { let s = ySettings; return FileNames(original: s.fileName("original"), crop: s.fileName("crop"), high: s.fileName("high"), low: s.fileName("low"), sheet: s.fileName("sheet")) } }
var ySettings: YSettings { get { YSStore.lock.lock(); defer { YSStore.lock.unlock() }; return YSStore.value } set { YSStore.lock.lock(); YSStore.value = newValue; YSStore.lock.unlock() } }   // 어느 스레드에서 읽어도 안전 (설정창은 메인에서 바꿈)
func ySnap() -> YSettings { ySettings }
var specSide: String { get { YSStore.lock.lock(); defer { YSStore.lock.unlock() }; return YSStore.side } set { YSStore.lock.lock(); YSStore.side = newValue; YSStore.lock.unlock() } }   // 지금 패널이 쓰는 규격 기본값: desk(Shift Convert) · ps(포토샵 가이드·인화)

enum LoginItem {   // 로그인 시 실행 = 설치 때 등록한 LaunchAgent(com.cc.donut)를 켜고 끄기만 (지금 떠 있는 ydot은 안 끔)
    static let label = "com.cc.donut"
    static func run(_ args: [String]) -> String { let p = Process(), o = Pipe(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = args; p.standardOutput = o; p.standardError = Pipe(); do { try p.run(); p.waitUntilExit() } catch { return "" }; return String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "" }
    static var enabled: Bool { let o = run(["print-disabled", "gui/\(getuid())"]); return !o.contains("\"\(label)\" => disabled") && !o.contains("\"\(label)\" => true") }
    static func set(_ on: Bool) { _ = run([on ? "enable" : "disable", "gui/\(getuid())/\(label)"]) }
}

// 설정창: 위 탭(일반 · 데스크톱 · 포토샵 · 시그니처 · 샘플) + 아래 막대(되돌리기 · 다시 · 취소 · 저장). 바꾼 건 저장을 눌러야 적용, 되돌리기는 탭마다 창을 닫을 때까지
struct GeneralDraft: Equatable { var enabled: Bool; var login: Bool; var size: Int; var theme: String; var s: YSettings }
final class SettingsWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with e: NSEvent) -> Bool { if onKey?(e) == true { return true }; return super.performKeyEquivalent(with: e) }
}
final class SettingsController: NSObject, NSToolbarDelegate, NSWindowDelegate {
    weak var app: Controller?
    var win: SettingsWindow!
    var generalMode = false   // true = '설정' 창 (일반만, 아래 막대 없음) · false = 'ydot' 창 (데스크톱·포토샵·시그니처·샘플) (사용자 2026-11-06)
    var tabs: [(id: String, title: String, sym: String)] { let all: [(id: String, title: String, sym: String)] = [("desk", "기본", "ruler"), ("sig", "로고", "signature"), ("frame", "프레임", "photo.artframe"), ("sheet", "인화지", "rectangle.grid.3x2"), ("gen", "설정", "gearshape")]; return generalMode ? all.filter { $0.id == "gen" } : all }   // 창 하나 · 일반 = '설정' 탭 맨 뒤 (사용자 2026-11-06)
    var tab = "desk"
    let body = YWin.Body(), foot = NSView(), note = NSTextField(labelWithString: ""), dirtyL = NSTextField(labelWithString: "")
    var undoB: NSButton!, redoB: NSButton!, cancelB: NSButton!, saveB: NSButton!, factoryB: NSButton!, undoSeg: NSSegmentedControl?
    var footStyle: Int { Int(ProcessInfo.processInfo.environment["DONUT_FOOT"] ?? "") ?? 1 }   // 아래 막대 = 1번 (사용자 2026-11-07) · 시안 0~4
    @objc func footSeg(_ s: NSSegmentedControl) { s.selectedSegment == 0 ? doUndo() : doRedo() }
    // 일반 탭 상태
    var saved: GeneralDraft!
    var draft: GeneralDraft! { didSet { refreshFoot() } }
    var hist: [String: [GeneralDraft]] = [:], redo: [String: [GeneralDraft]] = [:]   // 탭마다 따로 (창을 닫을 때까지)
    var specFields: [String: (NSTextField, NSTextField)] = [:]
    var swEnabled: NSSwitch!, swLogin: NSSwitch!, segSize: NSSegmentedControl!, segTheme: NSSegmentedControl!, folderPop: NSPopUpButton!, chk: [NSButton] = []

    func current() -> GeneralDraft {
        let sizes: [CGFloat] = [220, 300, 400]
        return GeneralDraft(enabled: app?.enabled ?? true, login: LoginItem.enabled, size: sizes.firstIndex(of: previewThumbH()) ?? 1, theme: cardTheme, s: ySettings) }
    func show() {
        if win == nil { build() }
        if !win.isVisible { saved = current(); draft = saved; resetHist(); cleanSampleFiles(); showTab(tab) }
        NSApp.activate(ignoringOtherApps: true); win.center(); win.makeKeyAndOrderFront(nil)
    }
    func build() {
        if generalMode {   // '설정' 창: 일반만 · 아래 막대 없음 (바꾸면 바로 적용)
            tab = "gen"; win = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 640), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            win.title = "설정"; win.isReleasedWhenClosed = false; win.delegate = self
            let cv = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 640)); win.contentView = cv; body.frame = cv.bounds; body.autoresizingMask = [.width, .height]; cv.addSubview(body)
            win.onKey = { [weak self] e in guard let self, e.modifierFlags.contains(.command) else { return false }
                switch e.charactersIgnoringModifiers?.lowercased() { case "z": e.modifierFlags.contains(.shift) ? self.doRedo() : self.doUndo(); return true
                case "w": self.win.performClose(nil); return true
                default: return false } }
            return }
        let WH: CGFloat = min(980, max(600, (NSScreen.main?.visibleFrame.height ?? 900) - 80))   // 세로 더 (사용자 2026-11-07)   // 세로 키움 (다 보이게, 사용자 2026-11-07) · 작은 화면은 맞춤
        win = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: WH), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = "ydot"; win.isReleasedWhenClosed = false; win.delegate = self; win.contentMinSize = NSSize(width: 720, height: 600); win.contentMaxSize = NSSize(width: 720, height: 4000)   // 세로만 늘리고 줄일 수 있게
        win.titlebarAppearsTransparent = true; win.backgroundColor = YWin.bar   // 위·아래 막대 = 옅은 그레이, 가운데 = 흰 (사용자 2026-11-06)
        if false, let tf = win.contentView?.superview {   // (로고·탭 사이 그림자 시안 · 안 씀)   // 신호등·로고 줄과 탭 줄 사이 그림자 (ydot 패널 상단바처럼 선 없이, 사용자 2026-11-07)
            let sh = YWin.Shade(frame: NSRect(x: 0, y: tf.bounds.height - 28 - 6, width: tf.bounds.width, height: 6)); sh.autoresizingMask = [.width, .minYMargin]; tf.addSubview(sh, positioned: .above, relativeTo: nil) }
        let tb = NSToolbar(identifier: "ydot.settings"); tb.delegate = self; tb.displayMode = .iconAndLabel; tb.selectedItemIdentifier = NSToolbarItem.Identifier(tab)
        win.toolbar = tb; win.toolbarStyle = .preference
        let tbtn = NSButton(image: NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "밝게·다크")!, target: self, action: #selector(winThemeToggle)); tbtn.isBordered = false; tbtn.toolTip = "밝게 ↔ 다크 (ydot 창)"; tbtn.symbolConfiguration = .init(pointSize: 14, weight: .regular); tbtn.contentTintColor = .secondaryLabelColor   // 상단바 오른쪽 ◐ (Shift Convert 패널처럼, 사용자 2026-11-07)
        let tv = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 28)); tbtn.frame = NSRect(x: 6, y: 3, width: 22, height: 22); tv.addSubview(tbtn)
        let acc = NSTitlebarAccessoryViewController(); acc.view = tv; acc.layoutAttribute = .trailing; win.addTitlebarAccessoryViewController(acc); applyWinTheme()
        let cv = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: WH)); win.contentView = cv
        foot.frame = NSRect(x: 0, y: 0, width: 720, height: 48); foot.autoresizingMask = [.width]; cv.addSubview(foot)
        let line = NSBox(frame: NSRect(x: 0, y: 47, width: 720, height: 1)); line.boxType = .separator; line.autoresizingMask = [.width]; line.isHidden = YWin.inv; foot.addSubview(line)   // 반전 색 = 구분선 없이 그림자만 (사용자 2026-11-07)
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; note.frame = NSRect(x: 16, y: 16, width: 300, height: 16); foot.addSubview(note)
        dirtyL.font = .systemFont(ofSize: 11); dirtyL.textColor = .systemOrange; dirtyL.frame = NSRect(x: 144, y: 16, width: 150, height: 16); dirtyL.isHidden = true; foot.addSubview(dirtyL)
        func b(_ t: String, _ a: Selector, _ x: CGFloat, _ w: CGFloat, _ fs: CGFloat = 13) -> NSButton { let x0 = NSButton(title: t, target: self, action: a); x0.bezelStyle = .rounded; x0.font = .systemFont(ofSize: fs); x0.frame = NSRect(x: x, y: 9, width: w, height: 30); foot.addSubview(x0); return x0 }
        func ib(_ sym: String, _ a: Selector, _ x: CGFloat, _ tip: String) -> NSButton { let x0 = NSButton(title: "", target: self, action: a); x0.bezelStyle = .rounded; x0.image = NSImage(systemSymbolName: sym, accessibilityDescription: tip); x0.imagePosition = .imageOnly; x0.toolTip = tip; x0.frame = NSRect(x: x, y: 9, width: 36, height: 30); foot.addSubview(x0); return x0 }
        func gray(_ x0: NSButton, _ t: String) { x0.attributedTitle = NSAttributedString(string: t, attributes: [.foregroundColor: YWin.dyn(0.38, 0.72), .font: NSFont.systemFont(ofSize: 13)]) }
        let R: CGFloat = 720 - 16 - 76   // 저장 x
        cancelB = b("취소", #selector(doCancel), R - 76 - 8, 76); saveB = b("저장", #selector(doSave), R, 76); saveB.keyEquivalent = "\r"
        factoryB = NSButton(title: "초기값으로 설정", target: self, action: #selector(doFactory)); factoryB.bezelStyle = .rounded; gray(factoryB, "초기값으로 설정"); factoryB.toolTip = "처음 ydot 값으로 (저장해야 적용)"; foot.addSubview(factoryB)
        switch footStyle {
        case 1:   // 왼쪽: 초기값(글자만) · 아이콘 ↶ ↷ / 오른쪽: 취소 · 저장
            factoryB.isBordered = false; factoryB.frame = NSRect(x: 12, y: 9, width: 110, height: 30)
            undoB = ib("arrow.uturn.backward", #selector(doUndo), 128, "실행 취소 ⌘Z"); redoB = ib("arrow.uturn.forward", #selector(doRedo), 168, "다시 실행 ⇧⌘Z"); dirtyL.frame = NSRect(x: 216, y: 16, width: 260, height: 16)
            cancelB.isHidden = true   // 취소 버튼 없음 → 탭을 옮기거나 창을 닫을 때 저장할지 물어봄 (사용자 2026-11-07)
        case 2:   // 왼쪽: [↶|↷] 묶음 + 저장 안 됨 / 오른쪽: 초기값(글자만) · 취소 · 저장
            undoB = ib("arrow.uturn.backward", #selector(doUndo), 0, ""); redoB = ib("arrow.uturn.forward", #selector(doRedo), 0, ""); undoB.isHidden = true; redoB.isHidden = true
            let sg = NSSegmentedControl(images: [NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil) ?? NSImage(), NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil) ?? NSImage()], trackingMode: .momentary, target: self, action: #selector(footSeg(_:)))
            sg.segmentStyle = .rounded; sg.setToolTip("실행 취소 ⌘Z", forSegment: 0); sg.setToolTip("다시 실행 ⇧⌘Z", forSegment: 1); sg.frame = NSRect(x: 16, y: 12, width: 76, height: 24); foot.addSubview(sg); undoSeg = sg
            dirtyL.frame = NSRect(x: 104, y: 16, width: 200, height: 16); factoryB.isBordered = false; factoryB.frame = NSRect(x: R - 76 - 8 - 118, y: 9, width: 112, height: 30)
        case 3:   // 왼쪽: 초기값 / 가운데: 저장 안 됨 / 오른쪽: ↶ ↷ (작게) | 취소 · 저장
            factoryB.frame = NSRect(x: 16, y: 9, width: 122, height: 30)
            undoB = ib("arrow.uturn.backward", #selector(doUndo), R - 84 - 92, "실행 취소 ⌘Z"); redoB = ib("arrow.uturn.forward", #selector(doRedo), R - 84 - 52, "다시 실행 ⇧⌘Z")
            for x0 in [undoB!, redoB!] { x0.isBordered = false }
            dirtyL.alignment = .center; dirtyL.frame = NSRect(x: 160, y: 16, width: 200, height: 16)
        case 4:   // 작게 한 줄: 초기값 · [실행 취소 | 다시 실행] … 취소 · 저장 (모두 작은 크기)
            for x0 in [cancelB!, saveB!] { x0.controlSize = .small; x0.font = .systemFont(ofSize: 12); x0.frame.origin.y = 12; x0.frame.size.height = 24 }
            factoryB.controlSize = .small; factoryB.frame = NSRect(x: 16, y: 12, width: 108, height: 24); gray(factoryB, "초기값으로 설정")
            undoB = ib("arrow.uturn.backward", #selector(doUndo), 0, ""); redoB = ib("arrow.uturn.forward", #selector(doRedo), 0, ""); undoB.isHidden = true; redoB.isHidden = true
            let sg = NSSegmentedControl(labels: ["실행 취소", "다시 실행"], trackingMode: .momentary, target: self, action: #selector(footSeg(_:))); sg.controlSize = .small; sg.font = .systemFont(ofSize: 11); sg.segmentStyle = .rounded
            sg.sizeToFit(); sg.frame.origin = NSPoint(x: 132, y: 13); foot.addSubview(sg); undoSeg = sg; dirtyL.frame = NSRect(x: 132 + sg.frame.width + 12, y: 16, width: 180, height: 16)
        default:   // 지금 모양 정리: 초기값 박스 글자 가운데 · 실행 취소/다시 실행 글자 작게
            factoryB.frame = NSRect(x: 16, y: 9, width: 122, height: 30)
            redoB = b("다시 실행 ⇧⌘Z", #selector(doRedo), R - 84 - 112, 112, 11); undoB = b("실행 취소 ⌘Z", #selector(doUndo), R - 84 - 112 - 102, 102, 11); dirtyL.frame = NSRect(x: 150, y: 16, width: 150, height: 16) }
        undoB.toolTip = "이 탭에서 바꾼 것 하나 취소 (창을 닫을 때까지)"; redoB.toolTip = "취소한 것 다시"; cancelB.toolTip = "마지막으로 저장한 상태로"
        body.frame = NSRect(x: 0, y: 48, width: 720, height: WH - 48); body.autoresizingMask = [.width, .height]; cv.addSubview(body)
        let topLine = NSBox(frame: NSRect(x: 0, y: WH - 1, width: 720, height: 1)); topLine.boxType = .separator; topLine.autoresizingMask = [.width, .minYMargin]; topLine.isHidden = YWin.inv; cv.addSubview(topLine)   // 탭 줄 아래 구분선 (아래 막대와 같게, 사용자 2026-11-07)
        win.onKey = { [weak self] e in guard let self, e.modifierFlags.contains(.command) else { return false }
            switch e.charactersIgnoringModifiers?.lowercased() { case "z": e.modifierFlags.contains(.shift) ? self.doRedo() : self.doUndo(); return true
            case "w": self.win.performClose(nil); return true
            case "s": self.doSave(); return true
            case ",": self.requestTab("gen"); return true   // ⌘, = 설정 탭
            default: return false } }
    }
    // ── 탭
    var winTheme: String { get { UserDefaults.standard.string(forKey: "ydotWinTheme") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "ydotWinTheme") } }   // "" = 맥 설정 따라 · light · dark
    func applyWinTheme() { let a: NSAppearance? = winTheme == "dark" ? NSAppearance(named: .darkAqua) : winTheme == "light" ? NSAppearance(named: .aqua) : nil; win?.appearance = a; layoutEd.win?.appearance = a }
    @objc func winThemeToggle() {   // 밝게 ↔ 다크: 창 전체가 0.35초 동안 부드럽게 바뀜 (패널처럼, 사용자 2026-11-07)
        let dk = win.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua; winTheme = dk ? "light" : "dark"
        for w in [win, layoutEd.win].compactMap({ $0 }) where w.isVisible { if let fv = w.contentView?.superview { fv.wantsLayer = true; let t = CATransition(); t.type = .fade; t.duration = 0.35; t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); fv.layer?.add(t, forKey: "theme") } }
        applyWinTheme() }
    static let testID = NSToolbarItem.Identifier("test")   // 맨 오른쪽 '테스트' 버튼 (탭 아님 · 사용자 2026-11-06)
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { tabs.map { NSToolbarItem.Identifier($0.id) } + (generalMode ? [] : [.flexibleSpace, Self.testID]) }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(t) }
    func toolbarSelectableItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { tabs.map { NSToolbarItem.Identifier($0.id) } }
    @objc func testClicked(_ it: NSToolbarItem) { showTestSheet() }
    var testSheet: NSWindow?
    func showTestSheet() {   // 테스트: 사진 고르기 (샘플 + 샘플 없음 · 업로드) → 데스크톱/포토샵 고르기 → 패널
        guard win.attachedSheet == nil else { return }; win.makeFirstResponder(nil)
        let W: CGFloat = 600, H: CGFloat = 430
        let sw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H), styleMask: [.titled], backing: .buffered, defer: false); sw.backgroundColor = YWin.bar
        let cv = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H)); sw.contentView = cv
        let t = NSTextField(labelWithString: "사진 선택"); t.font = .systemFont(ofSize: 13, weight: .semibold); t.frame = NSRect(x: 20, y: H - 36, width: 300, height: 18); cv.addSubview(t)
        let mid = YWin.Body(frame: NSRect(x: 0, y: 52, width: W, height: H - 52 - 48)); cv.addSubview(mid)
        let sc = NSScrollView(frame: mid.bounds); sc.hasVerticalScroller = true; sc.autohidesScrollers = true; sc.scrollerStyle = .overlay; sc.drawsBackground = false
        let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false; sc.documentView = doc; mid.addSubview(sc); mid.raiseShades()
        let grid = SampleFlow(); grid.translatesAutoresizingMaskIntoConstraints = false; doc.addSubview(grid)   // 규격 탭 샘플과 같은 모양 (한 줄 6장, 사용자 2026-11-07)
        grid.items = (draft?.s.samples ?? []).map { ($0.id, NSImage(contentsOf: YSettings.sampleDir.appendingPathComponent($0.file)), $0.name) } + [("", SampleGrid.silhouette, "No image")]; grid.cur = "\u{0}"; grid.cols = stripBig ? 4 : 6; testFlow = grid
        let zs = NSSegmentedControl(labels: ["기본", "확대"], trackingMode: .selectOne, target: self, action: #selector(testZoom(_:))); zs.selectedSegment = stripBig ? 1 : 0; zs.segmentStyle = .rounded; zs.sizeToFit(); zs.frame.origin = NSPoint(x: W - 20 - zs.frame.width, y: H - 40); cv.addSubview(zs)
        grid.onPick = { [weak grid, weak self] id in grid?.cur = id; grid?.reload(); self?.testOpenBtn?.isEnabled = true }   // 한 번 = 고르기만 (파란 테두리) · 열기 켜짐
        grid.onDouble = { [weak self] id in self?.testPicked(id) }          // 두 번 = 이 사진으로 테스트 (사용자 2026-11-07)
        grid.onDrop = { [weak self] u in self?.testDropped(u) }
        let unsel: () -> Void = { [weak grid, weak self] in grid?.cur = "\u{0}"; grid?.reload(); self?.testOpenBtn?.isEnabled = false }   // 사진 아닌 곳 누름 = 선택 풀기 · 열기 꺼짐
        grid.onBlank = unsel; doc.onBlank = unsel
        NSLayoutConstraint.activate([doc.widthAnchor.constraint(equalTo: sc.contentView.widthAnchor), grid.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 20), grid.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -20), grid.topAnchor.constraint(equalTo: doc.topAnchor, constant: 16), grid.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -16)])
        let line = NSBox(frame: NSRect(x: 0, y: 51, width: W, height: 1)); line.boxType = .separator; cv.addSubview(line)
        // 아래 막대: 왼쪽 업로드… · 오른쪽 취소(Esc) · 열기(Return, 파란 기본 버튼 · 고르기 전엔 꺼짐) — 맥 열기 창처럼 (사용자 2026-11-07)
        let up = NSButton(title: "업로드…", target: self, action: #selector(testUpload)); up.bezelStyle = .rounded; up.frame = NSRect(x: 16, y: 11, width: 100, height: 30); cv.addSubview(up)
        let open = NSButton(title: "열기", target: self, action: #selector(testSheetOpen)); open.bezelStyle = .rounded; open.keyEquivalent = "\r"; open.isEnabled = false; open.frame = NSRect(x: W - 16 - 84, y: 11, width: 84, height: 30); cv.addSubview(open); testOpenBtn = open
        let cancel = NSButton(title: "취소", target: self, action: #selector(testSheetCancel)); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"; cancel.frame = NSRect(x: open.frame.minX - 8 - 84, y: 11, width: 84, height: 30); cv.addSubview(cancel)
        testSheet = sw; win.beginSheet(sw) { [weak self] _ in self?.testSheet = nil }
        DispatchQueue.main.async { grid.reload() }
    }
    var testFlow: SampleFlow?, testOpenBtn: NSButton?
    @objc func testSheetOpen() { guard let id = testFlow?.cur, id != "\u{0}" else { return }; testPicked(id) }
    @objc func testZoom(_ z: NSSegmentedControl) { stripBig = z.selectedSegment == 1; testFlow?.cols = stripBig ? 4 : 6; testFlow?.reload(animated: true) }   // 규격 탭 샘플과 같은 크기 설정
    func closeTestSheet() { if let sw = testSheet { win.endSheet(sw); sw.orderOut(nil) } }
    @objc func testSheetCancel() { closeTestSheet() }
    func testPicked(_ id: String) {   // "" = 샘플 없음
        let u = draft?.s.samples.first { $0.id == id }.map { YSettings.sampleDir.appendingPathComponent($0.file) }
        closeTestSheet(); DispatchQueue.main.async { [weak self] in self?.askTestSide(u) } }
    @objc func testUpload() { guard let sw = testSheet else { return }
        let p = NSOpenPanel(); p.allowedContentTypes = [.image]; p.allowsMultipleSelection = false; p.prompt = "열기"
        p.beginSheetModal(for: sw) { [weak self] r in guard r == .OK, let u = p.url else { return }; self?.testDropped(u) } }
    func testDropped(_ u: URL) { closeTestSheet(); DispatchQueue.main.async { [weak self] in self?.askTestSide(u) } }   // 업로드한 사진은 이번 테스트에만 (샘플에 안 넣음)
    func askTestSide(_ u: URL?) {
        let a = NSAlert(); a.messageText = "어디로 테스트할까요?"; a.addButton(withTitle: "포토샵"); a.addButton(withTitle: "데스크톱"); a.addButton(withTitle: "취소")   // 기본(Return) = 포토샵 (사용자 2026-11-07)
        a.buttons[2].keyEquivalent = "\u{1b}"
        a.beginSheetModal(for: win) { [weak self] r in
            let side = r == .alertFirstButtonReturn ? "ps" : r == .alertSecondButtonReturn ? "desk" : nil
            guard let side else { return }; DispatchQueue.main.async { self?.app?.startTest(side, u) } } }
    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar f: Bool) -> NSToolbarItem? {
        if id == Self.testID { let it = NSToolbarItem(itemIdentifier: id); it.label = "테스트"; it.image = { let i = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "테스트")?.withSymbolConfiguration(.init(paletteColors: [.white, .systemRed])); i?.isTemplate = false; return i }(); it.target = self; it.action = #selector(testClicked(_:)); it.toolTip = "샘플 사진으로 패널을 돌려 봐요 (파일은 안 만듦)"; return it }
        guard let d = tabs.first(where: { $0.id == id.rawValue }) else { return nil }
        let it = NSToolbarItem(itemIdentifier: id); it.label = d.title; it.image = NSImage(systemSymbolName: d.sym, accessibilityDescription: d.title) ?? NSImage(systemSymbolName: "square", accessibilityDescription: nil)
        it.target = self; it.action = #selector(tabClicked(_:)); return it }
    @objc func tabClicked(_ it: NSToolbarItem) { requestTab(it.itemIdentifier.rawValue) }
    func requestTab(_ t: String) {   // 다른 탭으로: 이 탭에 저장 안 한 게 있으면 먼저 물어봄
        guard t != tab, draft != nil, saved != nil, merge(saved, draft, tab) != saved else { showTab(t); return }
        let a = NSAlert(); a.messageText = "\(tabs.first { $0.id == tab }?.title ?? "") 탭에서 바꾼 것을 저장할까요?"; a.addButton(withTitle: "저장"); a.addButton(withTitle: "저장 안 함"); a.addButton(withTitle: "취소")
        a.buttons[2].keyEquivalent = "\u{1b}"
        a.beginSheetModal(for: win) { [weak self] r in guard let self else { return }
            switch r { case .alertFirstButtonReturn: self.doSave(); self.showTab(t)
            case .alertSecondButtonReturn: self.draft = self.merge(self.draft, self.saved, self.tab); self.hist[self.tab] = nil; self.redo[self.tab] = nil; self.showTab(t)   // 이 탭 것만 되돌림
            default: self.win.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(self.tab) } } }
    func showTab(_ t: String) {
        tab = t; win.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(t); body.subviews.forEach { $0.removeFromSuperview() }
        if t == "gen" { buildGeneral() } else if t == "desk" || t == "ps" { buildSpecs(t) } else if t == "sheet" { buildSheetTab() } else if t == "sample" { buildSample() } else if t == "sig" { buildSig() } else if t == "frame" { buildFrame() } else {
            let l = NSTextField(wrappingLabelWithString: "이 탭은 다음 업데이트에서 들어가요."); l.alignment = .center; l.textColor = .secondaryLabelColor
            l.frame = NSRect(x: 0, y: body.bounds.midY - 20, width: body.bounds.width, height: 40); l.autoresizingMask = [.width, .minYMargin, .maxYMargin]; body.addSubview(l) }
        body.raiseShades()
        if !generalMode, let cv = win.contentView { let inst = t == "gen" || t == "sample" || t == "sheet"; foot.isHidden = inst; body.bottomBar = !inst; body.frame = inst ? cv.bounds : NSRect(x: 0, y: 48, width: cv.bounds.width, height: cv.bounds.height - 48) }   // 설정 탭 = 바로 적용이라 아래 막대 없음
        DispatchQueue.main.async { [weak self] in self?.win.makeFirstResponder(nil) }   // 들어가자마자 입력 칸에 커서 가 있지 않게
        refreshFoot()
    }
    // ── 일반 탭 (맥 시스템 설정처럼 묶음 상자)
    func group(_ title: String, _ rows: [NSView], sub: String? = nil, acc: [NSView] = []) -> NSView {   // 제목(+설명) 왼쪽 · 버튼 오른쪽 → 모든 탭 같은 모양 (2026-11-05 정리)
        let st = NSStackView(); st.orientation = .vertical; st.alignment = .leading; st.spacing = 6
        let h = NSTextField(labelWithString: title); h.font = .systemFont(ofSize: 13, weight: .semibold)
        let tcol = NSStackView(views: [h]); tcol.orientation = .vertical; tcol.alignment = .leading; tcol.spacing = 1
        if let sub { let l = NSTextField(labelWithString: sub); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; tcol.addArrangedSubview(l) }
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let hdr = NSStackView(views: [tcol, spacer] + acc); hdr.alignment = .bottom; hdr.spacing = 6; hdr.translatesAutoresizingMaskIntoConstraints = false
        st.addArrangedSubview(hdr); hdr.widthAnchor.constraint(equalTo: st.widthAnchor).isActive = true
        let box = GroupBox(); box.translatesAutoresizingMaskIntoConstraints = false
        let inner = NSStackView(); inner.orientation = .vertical; inner.spacing = 0; inner.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(inner)
        NSLayoutConstraint.activate([inner.leadingAnchor.constraint(equalTo: box.leadingAnchor), inner.trailingAnchor.constraint(equalTo: box.trailingAnchor), inner.topAnchor.constraint(equalTo: box.topAnchor), inner.bottomAnchor.constraint(equalTo: box.bottomAnchor)])
        for (i, r) in rows.enumerated() {
            if i > 0 { let sep = NSBox(); sep.boxType = .separator; sep.translatesAutoresizingMaskIntoConstraints = false; inner.addArrangedSubview(sep); sep.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -24).isActive = true }
            inner.addArrangedSubview(r); r.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true }
        st.addArrangedSubview(box); box.widthAnchor.constraint(equalTo: st.widthAnchor).isActive = true
        return st
    }
    func row(_ title: String, _ sub: String?, _ right: NSView) -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        let t = NSTextField(labelWithString: title); t.font = .systemFont(ofSize: 13)
        let col = NSStackView(views: [t]); col.orientation = .vertical; col.alignment = .leading; col.spacing = 1
        if let sub { let s = NSTextField(labelWithString: sub); s.font = .systemFont(ofSize: 11); s.textColor = .secondaryLabelColor; col.addArrangedSubview(s) }
        for x in [col, right] { x.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(x) }
        NSLayoutConstraint.activate([col.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12), col.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12), right.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            v.heightAnchor.constraint(greaterThanOrEqualToConstant: title.isEmpty ? 26 : sub == nil ? 38 : 46), col.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -12)])
        return v
    }
    func twoChecks(_ a: NSButton, _ b: NSButton) -> NSView { let s = NSStackView(views: [a, b]); s.spacing = 0; for x in [a, b] { x.widthAnchor.constraint(equalToConstant: 90).isActive = true; x.imagePosition = .imageOnly; x.alignment = .center }; return s }
    func buildGeneral() {
        swEnabled = NSSwitch(); swEnabled.target = self; swEnabled.action = #selector(genChanged)
        swLogin = NSSwitch(); swLogin.target = self; swLogin.action = #selector(genChanged)
        segSize = NSSegmentedControl(labels: ["Small", "Medium", "Large"], trackingMode: .selectOne, target: self, action: #selector(genChanged))
        segTheme = NSSegmentedControl(labels: ["그레이", "다크"], trackingMode: .selectOne, target: self, action: #selector(genChanged))
        folderPop = NSPopUpButton(); folderPop.target = self; folderPop.action = #selector(folderChanged)
        nameFields = [:]
        func nameRow(_ k: String, _ title: String, _ sub: String?) -> NSView { let f = NSTextField(); f.placeholderString = YSettings.nameDefaults[k]; f.identifier = NSUserInterfaceItemIdentifier(k); f.target = self; f.action = #selector(nameEdited(_:)); f.cell?.sendsActionOnEndEditing = true
            f.widthAnchor.constraint(equalToConstant: 150).isActive = true; nameFields[k] = f; let ext = NSTextField(labelWithString: k == "original" ? ".원래 확장자" : k == "sheet" ? ".png · 포토샵 .jpg" : ".jpg"); ext.font = .systemFont(ofSize: 11); ext.textColor = .secondaryLabelColor
            let st = NSStackView(views: [f, ext]); st.spacing = 6; return row(title, sub, st) }
        let nameBox = group("파일 이름", [nameRow("original", "원본", nil), nameRow("crop", "프로필 1차 크롭", nil), nameRow("high", "고화질", "규격대로 자른 사진"), nameRow("low", "저화질", "300ppi 규격 크기"), nameRow("sheet", "인화지", "인화지를 파일로 내보낼 때")],
                            sub: "바꾸면 바로 적용 · 데스크톱·포토샵 같이 · 겹치면 세트 전체에 _1, _2 …", acc: [smallBtn("⟲ 기본값", #selector(namesDefaults))])
        chk = (0..<4).map { _ in let c = NSButton(checkboxWithTitle: "", target: self, action: #selector(genChanged)); return c }
        let head = NSStackView(views: ["데스크톱", "포토샵"].map { let l = NSTextField(labelWithString: $0); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; l.alignment = .center; l.widthAnchor.constraint(equalToConstant: 90).isActive = true; return l }); head.spacing = 0
        let outReset = smallBtn("⟲ 기본값", #selector(outDefaults))
        let sections = [
            group("앱", [row("Shift Convert", "사진을 집고 Shift를 누르면 패널이 열려요", swEnabled), row("로그인할 때 ydot 실행", nil, swLogin),
                         row("패널 크기", "패널 상단바 − + 로도 바꿀 수 있어요", segSize), row("패널 바탕", "패널 상단바 ◐ 로도 바뀌어요", segTheme)]),
            group("저장", [row("Shift Convert 저장 위치", "기본 = 사진을 끌어 놓은 곳 · 포토샵은 늘 데스크톱", folderPop)]), nameBox,
            group("인화지 출력", [row("", nil, head), row("인화지를 파일로 내보내기", "데스크톱 = 저장 위치 · 포토샵 = 데스크톱", twoChecks(chk[0], chk[2])), row("포토샵 새 문서(Untitled)로 열기", "포토샵이 있을 때", twoChecks(chk[1], chk[3]))], sub: "둘 다 끄면 인화지는 만들지 않고 사진 파일만 저장해요", acc: [outReset]),
        ]
        scrollPage(sections + [note11("지금 데스크톱 인화지는 프로필에서만 만들어요")])
        fillGeneral()
    }
    func folderTitle(_ f: String) -> String { f == "drop" ? "끌어 놓은 곳" : f == "desktop" ? "데스크톱" : (f as NSString).lastPathComponent }
    func fillGeneral() {
        guard tab == "gen", swEnabled != nil else { return }; let d = draft!
        swEnabled.state = d.enabled ? .on : .off; swLogin.state = d.login ? .on : .off; segSize.selectedSegment = d.size; segTheme.selectedSegment = d.theme == "dark" ? 1 : 0
        folderPop.removeAllItems(); folderPop.addItems(withTitles: ["끌어 놓은 곳", "데스크톱"]); if !["drop", "desktop"].contains(d.s.saveFolder) { folderPop.addItem(withTitle: folderTitle(d.s.saveFolder)); folderPop.lastItem?.toolTip = d.s.saveFolder }
        folderPop.menu?.addItem(.separator()); folderPop.addItem(withTitle: "폴더 고르기…")
        folderPop.selectItem(at: d.s.saveFolder == "drop" ? 0 : d.s.saveFolder == "desktop" ? 1 : 2)
        for (i, v) in [d.s.deskFile, d.s.deskPS, d.s.psFile, d.s.psPS].enumerated() { chk[i].state = v ? .on : .off }
        for (k, f) in nameFields { let v = d.s.names[k] ?? ""; f.stringValue = v == YSettings.nameDefaults[k] ? "" : v }
    }
    @objc func genChanged() {
        var d = draft!; d.enabled = swEnabled.state == .on; d.login = swLogin.state == .on; d.size = segSize.selectedSegment; d.theme = segTheme.selectedSegment == 1 ? "dark" : "sidebar"
        d.s.deskFile = chk[0].state == .on; d.s.deskPS = chk[1].state == .on; d.s.psFile = chk[2].state == .on; d.s.psPS = chk[3].state == .on; commit(d)
    }
    @objc func folderChanged() {
        var d = draft!; let i = folderPop.indexOfSelectedItem, t = folderPop.titleOfSelectedItem ?? ""
        if t == "폴더 고르기…" {
            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = "고르기"
            if p.runModal() == .OK, let u = p.url { d.s.saveFolder = u.path } else { fillGeneral(); return }
        } else { d.s.saveFolder = i == 0 ? "drop" : i == 1 ? "desktop" : d.s.saveFolder }
        commit(d); fillGeneral()
    }
    var nameFields: [String: NSTextField] = [:]
    @objc func nameEdited(_ f: NSTextField) {
        guard let k = f.identifier?.rawValue else { return }; var d = draft!
        let v = YSettings.cleanName(f.stringValue), def = YSettings.nameDefaults[k]!
        var m = d.s.names; if v.isEmpty || v == def { m[k] = nil } else { m[k] = v }
        var t = d.s; t.names = m; let all = YSettings.nameKeys.map { t.fileName($0).lowercased() }
        if Set(all).count < all.count { NSSound.beep(); f.stringValue = (d.s.names[k] ?? ""); f.toolTip = "다른 칸과 같은 이름은 쓸 수 없어요 (파일이 겹쳐요)"; return }   // 같은 이름 막기
        d.s.names = m; commit(d); fillGeneral() }
    @objc func namesDefaults() { var d = draft!; d.s.names = [:]; commit(d); fillGeneral() }
    @objc func outDefaults() { var d = draft!; let z = YSettings(); d.s.deskFile = z.deskFile; d.s.deskPS = z.deskPS; d.s.psFile = z.psFile; d.s.psPS = z.psPS; commit(d); fillGeneral() }
    func resetHist() { for t in tabs { hist[t.id] = [saved]; redo[t.id] = [] } }
    func commit(_ d: GeneralDraft) { guard d != draft else { return }; hist[tab, default: [saved]].append(d); redo[tab] = []; draft = d; if tab == "gen" { applyGen() }; if tab == "sample" { applySample() } }
    func applySample() {   // 샘플 = 올리면 바로 저장 (저장 버튼·초기값 없음, 사용자 2026-11-06) · 뺀 사진 파일도 바로 정리
        guard let d = draft else { return }; var ys = ySettings; ys.samples = d.s.samples; ys.curSample = d.s.curSample; ySettings = ys; ys.save()
        saved = merge(saved, d, "sample"); hist["sample"] = [saved]; redo["sample"] = []; cleanSampleFiles(); refreshFoot() }   // 기록 먼저 → 되돌리기 버튼이 바로 켜짐
    func applyGen() {   // 일반 탭 = 바꾸면 바로 적용 (맥 시스템 설정처럼, 2026-11-05). 저장·취소는 다른 탭만
        guard let d = draft, let app else { return }
        if d.enabled != app.enabled { app.enabled = d.enabled }
        if d.login != LoginItem.enabled { LoginItem.set(d.login) }
        let h = [220.0, 300.0, 400.0][max(0, min(2, d.size))]; if abs(Double(previewThumbH()) - h) > 0.5 { let it = NSMenuItem(); it.representedObject = h; app.setPanelSize(it) }
        if d.theme != cardTheme { cardTheme = d.theme; app.applyThemeAll() }
        var ys = ySettings; ys.saveFolder = d.s.saveFolder; ys.deskFile = d.s.deskFile; ys.deskPS = d.s.deskPS; ys.psFile = d.s.psFile; ys.psPS = d.s.psPS; ys.names = d.s.names
        ySettings = ys; ys.save()
        saved = merge(saved, d, "gen"); refreshFoot() }
    func merge(_ cur: GeneralDraft, _ from: GeneralDraft, _ t: String) -> GeneralDraft {   // 되돌리기는 그 탭 몫만 (다른 탭에서 바꾼 건 그대로)
        var d = cur
        switch t {
        case "gen": d.enabled = from.enabled; d.login = from.login; d.size = from.size; d.theme = from.theme
            d.s.saveFolder = from.s.saveFolder; d.s.deskFile = from.s.deskFile; d.s.deskPS = from.s.deskPS; d.s.psFile = from.s.psFile; d.s.psPS = from.s.psPS; d.s.names = from.s.names
        case "desk": d.s.deskSpecs = from.s.deskSpecs; d.s.psSpecs = from.s.deskSpecs
        case "sample": d.s.samples = from.s.samples; d.s.curSample = from.s.curSample
        case "sheet": d.s.layouts = from.s.layouts
        case "sig": d.s.logos = from.s.logos; d.s.logoID = from.s.logoID; d.s.polStrip = from.s.polStrip; d.s.logoH = from.s.logoH; d.s.logoMargin = from.s.logoMargin; d.s.logoAlign = from.s.logoAlign
            d.s.sigMT = from.s.sigMT; d.s.sigML = from.s.sigML; d.s.sigMR = from.s.sigMR; d.s.logoX = from.s.logoX; d.s.logoY = from.s.logoY; d.s.design = from.s.design
        case "frame": d.s.frames = from.s.frames; d.s.frameID = from.s.frameID; d.s.design = from.s.design
        default: break }
        return d }
    func refill() { if tab == "sheet" { buildSheetThumbs() }; if tab == "gen" { fillGeneral() } else if tab == "desk" || tab == "ps" { fillSpecs() } else if tab == "sample" { sampleGrid?.reload(); sampleTabFill() } else if tab == "sig" { fillSig() } else if tab == "frame" { fillFrame() } }
    // ── 데스크톱 · 포토샵 탭: 규격 기본값 (얼굴 · 여백, cm)
    static let specOrder: [String] = Converter.baseSpecs.map(\.name).filter { $0 != "소형" } + ["프로필"]   // 인화지 탭·배치 편집 (프로필 인화지 = 맨 끝, 사용자 2026-11-07)
    func specVal(_ side: String, _ name: String) -> (Double, Double) {
        let b = Converter.baseOf(name), o = draft.s.deskSpecs[name]
        return ((o?.count ?? 0) >= 2 ? o![0] : b.headCm, (o?.count ?? 0) >= 2 ? o![1] : b.topCm) }
    func customWH() -> (Double, Double) { let s = Converter.customStart(draft.s); return (s.w, s.h) }
    func setSpec(_ side: String, _ name: String, _ v: (Double, Double)?) {   // nil = 기본값으로
        var d = draft!; let b = Converter.baseOf(name)
        var m = d.s.deskSpecs
        if name == "Custom" { let (w, h) = customWH(), f = v?.0 ?? b.headCm, t = v?.1 ?? b.topCm   // Custom = 가로·세로도 같이
            m[name] = abs(f - b.headCm) > 0.001 || abs(t - b.topCm) > 0.001 || abs(w - b.w) > 0.001 || abs(h - b.h) > 0.001 ? [f, t, w, h] : nil }
        else if let v, abs(v.0 - b.headCm) > 0.001 || abs(v.1 - b.topCm) > 0.001 { m[name] = [v.0, v.1] } else { m[name] = nil }
        d.s.deskSpecs = m; d.s.psSpecs = m; commit(d); fillSpecs() }   // 칸도 늘 같이 (커서 있던 칸이 저장 때 옛 값으로 다시 들어가지 않게)
    // ── 규격 탭 (첫 패널처럼 · 사용자 2026-11-07): 위 샘플 고르기 · 두 줄 선반(샘플이 규격대로 잘림 + 정수리·턱 점선) · 고른 규격은 아래에서 슬라이더(0.05씩)
    var specK: CGFloat { get { let v = UserDefaults.standard.double(forKey: "specCardK"); return v >= 12 && v <= 26 ? CGFloat(v) : 18 } set { UserDefaults.standard.set(Double(newValue), forKey: "specCardK") } }   // 규격 탭 사진 크기 (1 cm = pt) · 기본 18 (예전 14)
    var stripBig: Bool { get { UserDefaults.standard.bool(forKey: "sampleStripBig") } set { UserDefaults.standard.set(newValue, forKey: "sampleStripBig") } }   // 샘플 크기: 기본 · 확대
    var stripH: CGFloat { stripBig ? 210 : 112 }

    var pageDoc: FlippedView?, specNone = false, specAdjBox: NSView?
    var specSel = "증명", specCards: [String: SpecCard] = [:], specBig: SpecCard?, specName = NSTextField(labelWithString: "")
    var faceSl = NSSlider(), topSl = NSSlider(), faceOut = NSTextField(labelWithString: ""), topOut = NSTextField(labelWithString: ""), specResetB: NSButton?
    var specBase: (String, URL, CGImage)?, specPhotoCache: [String: CGImage] = [:]
    func specBaseImage() -> (URL, CGImage)? {   // 지금 고른 샘플 (없으면 sample 그림) · 샘플이 바뀔 때만 다시 읽음
        let id = draft?.s.curSample ?? ""; if let b = specBase, b.0 == id { return (b.1, b.2) }
        var u: URL?; if let sm = draft?.s.samples.first(where: { $0.id == id }) { u = YSettings.sampleDir.appendingPathComponent(sm.file) }
        if u == nil || !FileManager.default.fileExists(atPath: u!.path) { u = Controller.testSilhouette() }
        guard let url = u, let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        specBase = (id, url, img); specPhotoCache = [:]; return (url, img) }
    func specPhoto(_ n: String, _ v: (Double, Double), card: Bool = false) -> CGImage? {   // card = 규격 박스 카드 (Custom은 가로·세로와 상관없이 늘 같은 모양)   // 그 값으로 자른 사진 (변환과 같은 함수)
        guard let (u, b) = specBaseImage() else { return nil }; var sp = Converter.baseOf(n)
        if n == "Custom" && !card { let (w, h) = customWH(); sp = Converter.WebSpec(name: "Custom", w: w, h: h) }
        let key = "\(n)|\(v.0)|\(v.1)|\(sp.w)|\(sp.h)"; if let c = specPhotoCache[key] { return c }
        sp.headCm = v.0; sp.topCm = v.1; guard let out = Converter.faceCropAny(b, sp, key: u, outH: 420) ?? Optional(Converter.webSized(b, want: sp, high: false, key: u).1) else { return nil }   // 조절 화면과 같은 함수 (비율 그대로 · 사진 밖은 검정)
        if specPhotoCache.count > 80 { specPhotoCache = [:] }; specPhotoCache[key] = out; return out }
    func buildSpecs(_ side: String) {
        specCards = [:]
        // 샘플 고르기 (바로 저장 · 샘플 탭과 같음)
        let all = NSButton(title: " 전체 초기화", target: self, action: #selector(specResetAll)); all.bezelStyle = .rounded; all.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium)); all.imagePosition = .imageLeading
        let sp0 = NSView(); sp0.setContentHuggingPriority(.init(1), for: .horizontal)
        let tl = NSTextField(labelWithString: "규격"); tl.font = .systemFont(ofSize: 13, weight: .semibold)
        let topRow = NSStackView(views: [tl, sp0, all]); topRow.alignment = .centerY
        // 샘플 (맨 아래 · 여러 줄 · − + 로 크기, 사용자 2026-11-07)
        let flow = SampleFlow(); flow.translatesAutoresizingMaskIntoConstraints = false; flow.onPick = { [weak self] id in self?.pickSpecSample(id) }; flow.onDelete = { [weak self] id in self?.deleteSpecSample(id) }; sampleFlow = flow; fillSampleStrip()
        let zoom = NSSegmentedControl(labels: ["기본", "확대"], trackingMode: .selectOne, target: self, action: #selector(stripZoom(_:))); zoom.selectedSegment = stripBig ? 1 : 0; zoom.segmentStyle = .rounded; zoom.controlSize = .regular   // 두 단계 (차이 크게, 사용자 2026-11-07)
        let sLbl = NSTextField(labelWithString: "샘플"); sLbl.font = .systemFont(ofSize: 13, weight: .semibold)
        let sp1 = NSView(); sp1.setContentHuggingPriority(.init(1), for: .horizontal)
        let sHdr = NSStackView(views: [sLbl, sp1, zoom]); sHdr.alignment = .centerY; sHdr.spacing = 6
        let sInner = NSStackView(views: [flow]); sInner.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16); sInner.translatesAutoresizingMaskIntoConstraints = false
        flow.widthAnchor.constraint(equalTo: sInner.widthAnchor, constant: -32).isActive = true
        let box3 = GroupBox(); box3.translatesAutoresizingMaskIntoConstraints = false; box3.addSubview(sInner)
        NSLayoutConstraint.activate([sInner.leadingAnchor.constraint(equalTo: box3.leadingAnchor), sInner.trailingAnchor.constraint(equalTo: box3.trailingAnchor), sInner.topAnchor.constraint(equalTo: box3.topAnchor), sInner.bottomAnchor.constraint(equalTo: box3.bottomAnchor)])
        // 선반 두 줄
        func shelf(_ names: [String], _ gap: CGFloat) -> NSStackView { let r = NSStackView(views: names.map { n in let c = SpecCard(n, k: specK, labels: true); c.onClick = { [weak self] in self?.selectSpec($0) }; specCards[n] = c; return c }); r.spacing = gap; r.alignment = .bottom; return r }   // 간격: 위 30 · 아래 46 (사용자 2026-11-07)
        let s1 = shelf(["증명", "반명함", "여권", "Custom"], 30), s2 = shelf(["명함", "미국비자", "중국비자"], 46)   // 첫 패널과 같은 순서 (사용자 2026-11-07)
        let line = NSBox(); line.boxType = .separator
        let board = NSStackView(views: [s1, line, s2]); board.orientation = .vertical; board.alignment = .centerX; board.spacing = 12; board.edgeInsets = NSEdgeInsets(top: 14, left: 22, bottom: 14, right: 22)
        line.translatesAutoresizingMaskIntoConstraints = false; line.widthAnchor.constraint(equalTo: board.widthAnchor, constant: -44).isActive = true
        let box1 = GroupBox(); box1.translatesAutoresizingMaskIntoConstraints = false; board.translatesAutoresizingMaskIntoConstraints = false; box1.addSubview(board)
        NSLayoutConstraint.activate([board.leadingAnchor.constraint(equalTo: box1.leadingAnchor), board.trailingAnchor.constraint(equalTo: box1.trailingAnchor), board.topAnchor.constraint(equalTo: box1.topAnchor), board.bottomAnchor.constraint(equalTo: box1.bottomAnchor)])
        // 아래: 고른 규격 크게 + 슬라이더 (맥 기본 슬라이더 · 0.05씩)
        let big = SpecCard("증명", k: 30, labels: false); specBig = big
        specName.font = .systemFont(ofSize: 14, weight: .semibold)
        func sl(_ s: NSSlider, _ t: String, _ out: NSTextField, _ lo: Double, _ hi: Double) -> NSView {
            s.minValue = lo; s.maxValue = hi; s.isContinuous = true; s.target = self; s.action = #selector(specSlid(_:)); s.controlSize = .regular; s.translatesAutoresizingMaskIntoConstraints = false; s.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
            let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 13); l.textColor = .secondaryLabelColor; l.widthAnchor.constraint(equalToConstant: 34).isActive = true
            out.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular); out.alignment = .right; out.widthAnchor.constraint(equalToConstant: 66).isActive = true
            let r = NSStackView(views: [l, s, out]); r.spacing = 10; return r }
        let rs = NSButton(title: " 이 규격 초기화", target: self, action: #selector(specReset(_:))); rs.bezelStyle = .rounded; rs.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil); rs.imagePosition = .imageLeading; rs.toolTip = "저장한 값으로 되돌리기"; specResetB = rs
        let cw = sl(cwSl, "가로", cwOut, 2, 7), ch = sl(chSl, "세로", chOut, 2.5, 9); cw.isHidden = true; ch.isHidden = true; customRows = [cw, ch]
        cwSl.action = #selector(customSizeSlid(_:)); chSl.action = #selector(customSizeSlid(_:))
        let ctl = NSStackView(views: [specName, cw, ch, sl(faceSl, "얼굴", faceOut, 1.0, 4.5), sl(topSl, "여백", topOut, -0.5, 1.5), rs]); ctl.orientation = .vertical; ctl.alignment = .leading; ctl.spacing = 16
        let det = NSStackView(views: [big, ctl]); det.spacing = 30; det.alignment = .centerY; det.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28); det.translatesAutoresizingMaskIntoConstraints = false
        let box2 = GroupBox(); box2.translatesAutoresizingMaskIntoConstraints = false; box2.addSubview(det)
        NSLayoutConstraint.activate([det.leadingAnchor.constraint(equalTo: box2.leadingAnchor), det.trailingAnchor.constraint(lessThanOrEqualTo: box2.trailingAnchor), det.topAnchor.constraint(equalTo: box2.topAnchor), det.bottomAnchor.constraint(equalTo: box2.bottomAnchor)])
        let aL = NSTextField(labelWithString: "조정"); aL.font = .systemFont(ofSize: 13, weight: .semibold)
        scrollPage([topRow, box1, aL, box2, sHdr, box3]); specAdjBox = box2; specNone = false
        let unsel: () -> Void = { [weak self] in guard let self, !self.specNone else { return }; self.specNone = true; self.fillSpecs() }   // 규격 아닌 곳 누름 = 선택 풀기 (사용자 2026-11-07)
        box1.onBlank = unsel; pageDoc?.onBlank = unsel
        fillSpecs() }
    var sampleFlow: SampleFlow?
    func fillSampleStrip(animated: Bool = false) { guard let f = sampleFlow, let d = draft else { return }
        f.items = d.s.samples.map { ($0.id, NSImage(contentsOf: YSettings.sampleDir.appendingPathComponent($0.file)), $0.name) } + [("", SampleGrid.silhouette, "No image")]; f.cur = d.s.curSample; f.cols = stripBig ? 4 : 6; f.reload(animated: animated) }
    @objc func stripZoom(_ z: NSSegmentedControl) { let b = z.selectedSegment == 1; guard b != stripBig else { return }; stripBig = b; fillSampleStrip(animated: true) }
    func deleteSpecSample(_ id: String) {   // 규격 탭에서 샘플 빼기 (샘플 탭처럼 바로 저장 · 원본 사진은 그대로, ydot이 만든 작은 복사본만 지움)
        guard !id.isEmpty, draft != nil else { return }; draft.s.samples.removeAll { $0.id == id }; if draft.s.curSample == id { draft.s.curSample = draft.s.samples.last?.id ?? "" }
        saved.s.samples = draft.s.samples; saved.s.curSample = draft.s.curSample; var ys = ySettings; ys.samples = draft.s.samples; ys.curSample = draft.s.curSample; ySettings = ys; ys.save()
        cleanSampleFiles(); specBase = nil; fillSampleStrip(animated: true); fillSpecs() }
    func pickSpecSample(_ id: String) { let b = NSButton(); b.identifier = NSUserInterfaceItemIdentifier(id); specSamplePick(b) }
    @objc func specSamplePick(_ b: NSButton) {   // 샘플 바꾸기 = 바로 저장 (샘플 탭과 같음, 저장 버튼과 상관없음)
        let id = b.identifier?.rawValue ?? ""; guard draft != nil, draft.s.curSample != id else { return }
        draft.s.curSample = id; saved.s.curSample = id; var ys = ySettings; ys.curSample = id; ySettings = ys; ys.save(); specBase = nil; fillSampleStrip(); fillSpecs() }
    var specAnim: Timer?, specMorph = false
    func bigCamera(_ n: String, _ v: (Double, Double), dims: (Double, Double)? = nil, animated: Bool) {   // 큰 사진 = 같은 원본에서 창(프레임)만 옮김 · animated = 0.5초 부드럽게
        guard let big = specBig, let (u, b) = specBaseImage() else { return }
        var sp = Converter.baseOf(n); if n == "Custom" { let (w, h) = dims ?? customWH(); sp = Converter.WebSpec(name: "Custom", w: w, h: h) }
        let old = [big.holder, big.clip, big.img].map { ($0.presentation() ?? $0).frame }   // 지금 보이는 자리에서 출발
        sp.headCm = v.0; sp.topCm = v.1; big.setCamera(b, Converter.faceCropRect(b, sp, key: u)); big.layoutSubtreeIfNeeded()
        CATransaction.begin(); CATransaction.setDisableActions(true); big.placeLayers(big.targetRect()); CATransaction.commit()
        guard animated else { return }
        let tf = CAMediaTimingFunction(name: .easeInEaseOut)
        for (l, o) in zip([big.holder, big.clip, big.img], old) { let n = l.frame
            for (key, from, to) in [("bounds", NSValue(rect: CGRect(origin: .zero, size: o.size)), NSValue(rect: CGRect(origin: .zero, size: n.size))), ("position", NSValue(point: CGPoint(x: o.midX, y: o.midY)), NSValue(point: CGPoint(x: n.midX, y: n.midY)))] {
                let a = CABasicAnimation(keyPath: key); a.fromValue = from; a.toValue = to; a.duration = 0.5; a.timingFunction = tf; l.add(a, forKey: "cam." + key) } }
        let sp2 = CABasicAnimation(keyPath: "shadowPath"); sp2.fromValue = CGPath(rect: CGRect(origin: .zero, size: old[0].size), transform: nil); sp2.toValue = big.holder.shadowPath; sp2.duration = 0.5; sp2.timingFunction = tf; big.holder.add(sp2, forKey: "cam.sp") }
    func selectSpec(_ n: String) {   // 규격 바꾸기: 큰 사진 틀이 새 비율로 변신 + 손잡이 미끄러짐 + 숫자가 세면서 파랗게 빛났다 원래 색 (사용자 2026-11-07 · G-6)
        if specNone { specNone = false; if n == specSel { fillSpecs(); return } }
        guard n != specSel, let big = specBig else { specSel = n; fillSpecs(); return }
        let f0 = faceSl.doubleValue, t0 = topSl.doubleValue, dur = 0.5
        specMorph = true; specSel = n; fillSpecs(); specMorph = false   // 큰 사진은 같은 원본에서 창만 0.5초 동안 옮김 (사진을 바꿔 끼우지 않음, 사용자 2026-11-07)
        let f1 = faceSl.doubleValue, t1 = topSl.doubleValue, st = CACurrentMediaTime()
        faceSl.doubleValue = f0; topSl.doubleValue = t0; specAnim?.invalidate()
        specAnim = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] tm in guard let self else { tm.invalidate(); return }
            let p = min(1, (CACurrentMediaTime() - st) / dur), e = 1 - pow(1 - p, 3), f = f0 + (f1 - f0) * e, t = t0 + (t1 - t0) * e
            self.faceSl.doubleValue = f; self.topSl.doubleValue = t; self.faceOut.stringValue = String(format: "%.2f cm", f); self.topOut.stringValue = String(format: "%.2f cm", t)
            let glow = NSColor.controlAccentColor.blended(withFraction: CGFloat(max(0, (p - 0.55) / 0.45)), of: .labelColor) ?? .labelColor   // 파랗게 → 마지막에 원래 색
            for o in [self.faceOut, self.topOut] { o.textColor = p >= 1 ? .labelColor : glow }
            if p >= 1 { tm.invalidate(); self.faceSl.doubleValue = f1; self.topSl.doubleValue = t1; self.faceOut.stringValue = String(format: "%.2f cm", f1); self.topOut.stringValue = String(format: "%.2f cm", t1) } }
    }
    var cwSl = NSSlider(), chSl = NSSlider(), cwOut = NSTextField(labelWithString: ""), chOut = NSTextField(labelWithString: ""), customRows: [NSView] = []
    @objc func customSizeSlid(_ s: NSSlider) {   // Custom 처음 크기 (가로·세로 0.1 cm씩) — 끄는 동안 사진만, 놓을 때 한 번 기록
        let w = (cwSl.doubleValue * 10).rounded() / 10, h = (chSl.doubleValue * 10).rounded() / 10; cwSl.doubleValue = w; chSl.doubleValue = h
        cwOut.stringValue = String(format: "%.1f cm", w); chOut.stringValue = String(format: "%.1f cm", h)
        let v = specVal(tab, "Custom"), sp = Converter.WebSpec(name: "Custom", w: w, h: h, headCm: v.0, topCm: v.1)
        if let (u, b) = specBaseImage(), let im = Converter.faceCropAny(b, sp, key: u, outH: 420) { specBig?.dims = (w, h); _ = im; specBig?.set(nil, v.0, v.1, changed: false); specBig?.invalidateIntrinsicContentSize(); bigCamera("Custom", v, dims: (w, h), animated: false) }
        specName.stringValue = "Custom   \(trim(w))×\(trim(h)) cm"
        let up = NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .keyDown
        if up { var d = draft!; let b = Converter.customBase; d.s.deskSpecs["Custom"] = abs(v.0 - b.headCm) > 0.001 || abs(v.1 - b.topCm) > 0.001 || abs(w - b.w) > 0.001 || abs(h - b.h) > 0.001 ? [v.0, v.1, w, h] : nil; d.s.psSpecs = d.s.deskSpecs; commit(d); fillSpecs() } }
    func specBigLayerSize() -> String? { guard let b = specBig else { return nil }; return "\(b.img.frame.size) 그림 \((b.img.contents as! CGImage?).map { "\($0.width)×\($0.height)" } ?? "-")" }
    @objc func specSlid(_ s: NSSlider) {
        let v0 = specVal(tab, specSel); var f = (faceSl.doubleValue * 20).rounded() / 20, t = (topSl.doubleValue * 20).rounded() / 20   // 0.05씩
        let b = Converter.baseOf(specSel); f = min(specSel == "Custom" ? customWH().1 : b.h, f)
        faceSl.doubleValue = f; topSl.doubleValue = t; faceOut.stringValue = String(format: "%.2f cm", f); topOut.stringValue = String(format: "%.2f cm", t)
        specCards[specSel]?.set(specPhoto(specSel, (f, t)), f, t, changed: true); specBig?.set(nil, f, t, changed: false); bigCamera(specSel, (f, t), animated: false)
        let up = NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .keyDown
        if up, abs(f - v0.0) > 0.001 || abs(t - v0.1) > 0.001 { setSpec(tab, specSel, (f, t)) } }   // 놓을 때 한 번만 기록 (실행 취소 한 칸)
    func fillSpecs() {
        guard tab == "desk", draft != nil else { return }
        let cwh = customWH()
        for (n, c) in specCards { let v = specVal(tab, n), o = saved.s.deskSpecs[n].map { ($0[0], $0[1]) }; let b = Converter.baseOf(n)
            // Custom 카드 = 크기 그대로 (가로·세로를 바꿔도 규격 박스가 늘었다 줄지 않게, 사진만 안에서 채움)
            let ref = o ?? (b.headCm, b.topCm); c.set(specPhoto(n, v, card: true), v.0, v.1, changed: abs(v.0 - ref.0) > 0.001 || abs(v.1 - ref.1) > 0.001 || draft.s.deskSpecs[n] != saved.s.deskSpecs[n]); c.selected = n == specSel }
        let v = specVal(tab, specSel); var b = Converter.baseOf(specSel); let isC = specSel == "Custom"
        if isC { b = Converter.WebSpec(name: "Custom", w: cwh.0, h: cwh.1) }
        if let r0 = customRows.first, r0.isHidden == isC {   // Custom 줄(가로·세로)이 생기거나 없어질 때 조정 박스가 부드럽게 늘고 줄게 (사용자 2026-11-07)
            if specMorph, let cv = win.contentView { if isC { customRows.forEach { $0.alphaValue = 0 } }
                NSAnimationContext.runAnimationGroup { c in c.duration = 0.45; c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); c.allowsImplicitAnimation = true
                    customRows.forEach { $0.isHidden = !isC; $0.animator().alphaValue = isC ? 1 : 0 }; cv.layoutSubtreeIfNeeded() } }
            else { customRows.forEach { $0.isHidden = !isC; $0.alphaValue = 1 } } }; if isC { cwSl.doubleValue = cwh.0; chSl.doubleValue = cwh.1; cwOut.stringValue = String(format: "%.1f cm", cwh.0); chOut.stringValue = String(format: "%.1f cm", cwh.1) }
        specBig?.dims = isC ? cwh : nil; specBig?.setSpec(specSel); specBig?.set(specPhoto(specSel, v), v.0, v.1, changed: false); bigCamera(specSel, v, animated: specMorph)
        specName.stringValue = "\(specSel)   \(trim(b.w))×\(trim(b.h)) cm"; faceSl.maxValue = min(4.5, b.h); faceSl.doubleValue = v.0; topSl.doubleValue = v.1
        faceOut.stringValue = String(format: "%.2f cm", v.0); topOut.stringValue = String(format: "%.2f cm", v.1); specResetB?.identifier = NSUserInterfaceItemIdentifier(specSel)
        if specNone { specCards.values.forEach { $0.selected = false } }   // 고른 규격 없음: 조정 박스는 흐리게 · 못 씀
        func en(_ v: NSView) { if let c = v as? NSControl { c.isEnabled = !specNone }; v.subviews.forEach(en) }; if let b = specAdjBox { en(b); b.alphaValue = specNone ? 0.45 : 1 } }
    func scrollPage(_ views: [NSView]) {
        let st = NSStackView(views: views); st.orientation = .vertical; st.alignment = .leading; st.spacing = 14; st.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false; doc.addSubview(st); pageDoc = doc
        let sc = NSScrollView(frame: body.bounds); sc.autoresizingMask = [.width, .height]; sc.hasVerticalScroller = true; sc.autohidesScrollers = true; sc.scrollerStyle = .overlay; sc.drawsBackground = false; sc.documentView = doc; body.addSubview(sc)
        NSLayoutConstraint.activate([doc.widthAnchor.constraint(equalTo: sc.contentView.widthAnchor), st.topAnchor.constraint(equalTo: doc.topAnchor, constant: 20), st.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -20),
            st.centerXAnchor.constraint(equalTo: doc.centerXAnchor), st.widthAnchor.constraint(equalTo: doc.widthAnchor, constant: -56)])   // 좌우 여백 28 (예전 60, 사용자 2026-11-07)
        for v in views { v.widthAnchor.constraint(equalTo: st.widthAnchor).isActive = true }
    }
    func smallBtn(_ t: String, _ a: Selector) -> NSButton { let b = NSButton(title: t, target: self, action: a); b.bezelStyle = .rounded; b.controlSize = .small; b.font = .systemFont(ofSize: 11); return b }
    func note11(_ t: String) -> NSTextField { let l = NSTextField(wrappingLabelWithString: t); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; return l }
    // ── 인화지 탭: 규격마다 배치 (작은 그림 · 누르면 전체화면 편집 창, 사용자 2026-11-06)
    lazy var layoutEd: LayoutEditor = { let e = LayoutEditor(); e.owner = self; return e }()
    var sheetThumbBox: NSStackView?
    func buildSheetTab() {
        let box = NSStackView(); box.orientation = .vertical; box.alignment = .leading; box.spacing = 18; box.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18); sheetThumbBox = box
        let ed = NSButton(title: " 배치 편집…", target: self, action: #selector(openLayout0)); ed.bezelStyle = .rounded; ed.image = NSImage(systemSymbolName: "rectangle.and.pencil.and.ellipsis", accessibilityDescription: nil); ed.imagePosition = .imageLeading
        scrollPage([group("배치", [box], acc: [ed]), sampleMgrBox()]); buildSheetThumbs() }   // 아래 = 샘플 (샘플 탭을 여기로 옮김, 사용자 2026-11-07)
    func buildSheetThumbs() {
        guard let box = sheetThumbBox, let d = draft else { return }; box.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var row: NSStackView?
        for (i, n) in Self.specOrder.enumerated() {
            if i % 3 == 0 { let r = NSStackView(); r.spacing = 14; r.alignment = .top; box.addArrangedSubview(r); row = r }
            let L = Sheet.layout(n, d.s), (W, H) = Sheet.sheetWH(L), img = layoutEd.photo(n).flatMap { Sheet.render($0, L, n, scale: 0.4, style: Sheet.style(d.s)) }
            let b = SheetThumb(); b.imageScaling = .scaleProportionallyUpOrDown; b.image = img.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }   // 한 번 = 고르기 · 두 번 = 배치 편집 (사용자 2026-11-07)
            b.identifier = NSUserInterfaceItemIdentifier(n); b.toolTip = "두 번 눌러 \(n) 배치 편집"; b.on = n == sheetSel
            b.onTap = { [weak self] in self?.sheetSel = n; self?.markSheetSel() }; b.onDouble = { [weak self] in self?.sheetSel = n; self?.markSheetSel(); self?.layoutEd.open(n) }
            let tw: CGFloat = L.land ? 196 : 146; b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: tw).isActive = true; b.heightAnchor.constraint(equalToConstant: tw * CGFloat(H) / CGFloat(W)).isActive = true
            let l = NSTextField(labelWithString: n); l.font = .systemFont(ofSize: 12, weight: .medium)
            let c = NSTextField(labelWithString: "\(L.cells.count)장" + (d.s.layouts[n] != nil ? " · 바꿈" : "")); c.font = .systemFont(ofSize: 11); c.textColor = .secondaryLabelColor
            let col = NSStackView(views: [b, l, c]); col.orientation = .vertical; col.spacing = 4; col.alignment = .centerX; col.translatesAutoresizingMaskIntoConstraints = false; col.widthAnchor.constraint(equalToConstant: 200).isActive = true; row?.addArrangedSubview(col) } }
    var sheetSel = "증명"
    func markSheetSel() { func walk(_ v: NSView) { if let t = v as? SheetThumb { t.on = t.identifier?.rawValue == sheetSel }; v.subviews.forEach(walk) }; if let b = sheetThumbBox { walk(b) } }
    @objc func openLayout0() { layoutEd.open(sheetSel) }   // 배치 편집… = 고른 규격
    func layoutsSaved(_ m: [String: YLayout]) {   // 편집 창 저장 = 바로 적용
        var ys = ySettings; ys.layouts = m; ySettings = ys; ys.save(); draft?.s.layouts = m; saved?.s.layouts = m; hist["sheet"] = nil; refreshFoot(); if tab == "sheet" { buildSheetThumbs() } }
    // ── 샘플 탭: 미리보기에 쓸 사진 (설정 폴더에 줄인 복사본 · 원본은 안 건드림)
    var sampleGrid: SampleGrid?
    @objc func pickSamples() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = false; p.allowedContentTypes = [.image]; p.prompt = "추가"
        p.beginSheetModal(for: win) { [weak self] r in if r == .OK { self?.addSamples(p.urls) } } }
    func addSamples(_ urls: [URL]) {
        var d = draft!; let dir = YSettings.sampleDir; try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for u in urls {
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { continue }
            let id = UUID().uuidString, file = id + ".jpg", rep = NSBitmapImageRep(cgImage: img)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]), (try? data.write(to: dir.appendingPathComponent(file))) != nil else { continue }
            d.s.samples.append(YSample(id: id, name: u.deletingPathExtension().lastPathComponent, file: file)); d.s.curSample = id }
        draft = d; applySample(); samplesChanged() }
    func selectSample(_ id: String) { var d = draft!; d.s.curSample = id; draft = d; applySample(); samplesChanged() }   // 샘플 = 바로 저장 (기록 없음)
    func deleteSample(_ id: String) { var d = draft!; d.s.samples.removeAll { $0.id == id }; if d.s.curSample == id { d.s.curSample = d.s.samples.last?.id ?? "" }; draft = d; applySample(); samplesChanged() }   // 파일은 저장할 때 정리 (되돌리기로 살릴 수 있게)
    func samplesChanged() { sampleGrid?.reload(); sampleTabFill(); if tab == "sheet" { buildSheetThumbs() }; fillSampleStrip(); designFlowFill(); if tab == "sig" || tab == "frame" { renderDesign() } }
    func cleanSampleFiles() {   // 저장된 목록·지금 목록 어디에도 없는 우리 파일만 지움 (samples/ · logos/ 폴더 안, 우리가 붙인 이름 = UUID)
        func clean(_ dir: URL, _ keep: Set<String>) { for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where UUID(uuidString: (f as NSString).deletingPathExtension) != nil && !keep.contains(f) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) } }
        clean(YSettings.sampleDir, Set((saved?.s.samples ?? []).map(\.file) + (draft?.s.samples ?? []).map(\.file)))
        clean(YSettings.logoDir, Set((saved?.s.logos ?? []).map(\.file) + (draft?.s.logos ?? []).map(\.file)))
        clean(YSettings.frameDir, Set((saved?.s.frames ?? []).map(\.file) + (draft?.s.frames ?? []).map(\.file))) }
    // ── 시그니처 탭: 인화지 로고 · 폴라로이드 띠 (미리보기 = 실제 인화지 그리는 코드 그대로)
    var logoGrid: SampleGrid?, sigFields: [String: NSTextField] = [:], alignSeg: NSSegmentedControl?, polPreview = NSImageView(), sheetPreview = NSImageView()
    var designCanvas: DesignCanvas?, designF: [String: NSTextField] = [:], designInfo: NSTextField?, frameGrid: SampleGrid?, designFlow: SampleFlow?, dragBase: GeneralDraft?, dpKey = "", dpImg: CGImage?, sampleTabFlow: SampleFlow?
    var cropPop: NSPopUpButton?, cropW: NSTextField?, cropH: NSTextField?, cropV: CropView?, cropSample = "", cropURL: URL?, cropCustomViews: [NSView] = []
    static func isLogoFile(_ u: URL) -> Bool { ["ai", "pdf", "png", "jpg", "jpeg", "tif", "tiff", "heic"].contains(u.pathExtension.lowercased()) }
    func cm(_ px: Int) -> String { trim(Double(px) * 2.54 / 300) }
    func sampleCG() -> CGImage? {
        if let sm = draft.s.samples.first(where: { $0.id == draft.s.curSample }), let src = CGImageSourceCreateWithURL(YSettings.sampleDir.appendingPathComponent(sm.file) as CFURL, nil), let im = CGImageSourceCreateImageAtIndex(src, 0, nil) { return im }
        var r = NSRect(origin: .zero, size: SampleGrid.silhouette.size); return SampleGrid.silhouette.cgImage(forProposedRect: &r, context: nil, hints: nil) }
    func renderSigPreview() {
        guard let photo = sampleCG() else { return }; let st = Sheet.style(draft.s)
        polPreview.image = Sheet.polaroid(photo, st).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        sheetPreview.image = Sheet.make(polaroid: photo, small: photo, style: st).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
    @objc func sigEdited(_ sender: Any) {
        var d = draft!; func px(_ k: String, _ cur: Int, _ lo: Double, _ hi: Double) -> Int { guard let f = sigFields[k], let v = Double(f.stringValue.replacingOccurrences(of: ",", with: ".")) else { return cur }; return Int((min(hi, max(lo, v)) / 2.54 * 300).rounded()) }
        d.s.polStrip = px("strip", d.s.polStrip, 0, 3); d.s.logoH = px("logoH", d.s.logoH, 0.05, 2.5); d.s.logoMargin = px("margin", d.s.logoMargin, 0, 1.5)
        d.s.logoAlign = ["left", "center", "right"][max(0, alignSeg?.selectedSegment ?? 2)]
        commit(d); fillSig() }
    @objc func pickLogos() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = false; p.prompt = "추가"
        p.allowedContentTypes = [.pdf, .png, .jpeg, .tiff, .heic] + [UTType(filenameExtension: "ai")].compactMap { $0 }
        p.beginSheetModal(for: win) { [weak self] r in if r == .OK { self?.addLogos(p.urls) } } }
    func addLogos(_ urls: [URL]) {
        var d = draft!; let dir = YSettings.logoDir; try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for u in urls where Self.isLogoFile(u) {
            let id = UUID().uuidString, file = id + "." + u.pathExtension.lowercased()
            guard (try? FileManager.default.copyItem(at: u, to: dir.appendingPathComponent(file))) != nil, Sheet.logoArt(dir.appendingPathComponent(file).path) != nil else { try? FileManager.default.removeItem(at: dir.appendingPathComponent(file)); continue }   // 그릴 수 없는 파일은 빼기
            d.s.logos.append(YSample(id: id, name: u.deletingPathExtension().lastPathComponent, file: file)); d.s.logoID = id }
        commit(d); fillSig() }
    func selectLogo(_ id: String) { var d = draft!; d.s.logoID = id; commit(d); fillSig() }
    func deleteLogo(_ id: String) { var d = draft!; d.s.logos.removeAll { $0.id == id }; if d.s.logoID == id { d.s.logoID = "" }; commit(d); fillSig() }
    func trim(_ v: Double) -> String { let r = (v * 100).rounded() / 100; return r == r.rounded() ? String(Int(r)) : String(r) }
    @objc func specEdited(_ f: NSTextField) {
        guard let id = f.identifier?.rawValue, let bar = id.firstIndex(of: "|") else { return }
        let kind = id[..<bar], name = String(id[id.index(after: bar)...]), b = Converter.baseSpecs.first { $0.name == name }!
        var v = specVal(tab, name); let x = Double(f.stringValue.replacingOccurrences(of: ",", with: ".")) ?? (kind == "f" ? v.0 : v.1)
        if kind == "f" { v.0 = min(b.h, max(1.0, x)) } else { v.1 = min(1.5, max(-0.5, x)) }   // 밖의 값은 맞춤
        v = ((v.0 * 100).rounded() / 100, (v.1 * 100).rounded() / 100); setSpec(tab, name, v); fillSpecs() }
    @objc func specReset(_ b: NSButton) { if let n = b.identifier?.rawValue, n == "Custom" { var d = draft!; d.s.deskSpecs["Custom"] = saved.s.deskSpecs["Custom"]; d.s.psSpecs = d.s.deskSpecs; commit(d); fillSpecs(); return }
        if let n = b.identifier?.rawValue { let o = saved.s.deskSpecs[n]; setSpec(tab, n, o?.count == 2 ? (o![0], o![1]) : nil); fillSpecs() } }   // ↺ = 저장한 값으로 (처음 값은 왼쪽 아래 '초기값으로 설정', 사용자 2026-11-06)
    @objc func specResetAll() { var d = draft!; d.s.deskSpecs = saved.s.deskSpecs; d.s.psSpecs = saved.s.deskSpecs; commit(d); fillSpecs() }
    @objc func doFactory() {   // 초기값으로 설정: 이 탭을 처음 ydot 값으로 (실행 취소 가능 · 저장해야 적용)
        win.makeFirstResponder(nil); guard var d = draft else { return }; let z = YSettings()
        let a = NSAlert(); a.messageText = "\(tabs.first { $0.id == tab }?.title ?? "") 탭을 처음 값으로 되돌릴까요?"
        a.informativeText = tab == "sample" ? "샘플 사진 목록이 비워져요." : tab == "sig" ? "여백·로고 크기·자리가 처음 값이 되고 샘플 로고(y.)를 써요. 추가한 로고는 목록에 남아요." : tab == "frame" ? "모든 프레임의 크기·사진 자리가 처음 값이 돼요. 추가한 프레임은 목록에 남아요." : "모든 규격의 얼굴·여백이 처음 값이 돼요."
        a.informativeText += "\n저장을 눌러야 적용돼요 · ⌘Z로 취소할 수 있어요"
        a.addButton(withTitle: "처음 값으로"); a.addButton(withTitle: "취소")
        a.beginSheetModal(for: win) { [weak self] r in guard r == .alertFirstButtonReturn, let self else { return }
            switch self.tab {
            case "desk": d.s.deskSpecs = [:]; d.s.psSpecs = [:]
            case "sig": d.s.polStrip = z.polStrip; d.s.logoH = z.logoH; d.s.logoMargin = z.logoMargin; d.s.logoAlign = z.logoAlign; d.s.logoID = z.logoID; d.s.sigMT = 0; d.s.sigML = 0; d.s.sigMR = 0; d.s.logoX = nil; d.s.logoY = nil; d.s.design = z.design
            case "frame": for i in d.s.frames.indices { var f = d.s.frames[i]; SettingsController.fitFrame(&f, Sheet.frameAspect(YSettings.frameDir.appendingPathComponent(f.file).path), d.s.design); d.s.frames[i] = f }
            case "sample": d.s.samples = []; d.s.curSample = ""
            default: return }
            self.commit(d); self.refill() } }
    // ── 되돌리기 · 저장
    @objc func doUndo() { win.makeFirstResponder(nil); guard var h = hist[tab], h.count > 1 else { NSSound.beep(); return }; redo[tab, default: []].append(h.removeLast()); hist[tab] = h; draft = merge(draft, h.last!, tab); if tab == "gen" { applyGen() }; refill() }
    @objc func doRedo() { win.makeFirstResponder(nil); guard let d = redo[tab]?.popLast() else { NSSound.beep(); return }; hist[tab, default: [saved]].append(d); draft = merge(draft, d, tab); if tab == "gen" { applyGen() }; refill() }
    @objc func doCancel() { draft = saved; resetHist(); refill() }
    @objc func doSave() {
        win.makeFirstResponder(nil)   // 입력 중인 칸도 먼저 반영
        guard let d = draft else { return }
        var ns = d.s; let cur = ySettings   // 일반 값은 늘 지금 값 그대로 (설정 창에서 바로 바뀌므로)
        ns.saveFolder = cur.saveFolder; ns.deskFile = cur.deskFile; ns.deskPS = cur.deskPS; ns.psFile = cur.psFile; ns.psPS = cur.psPS; ns.names = cur.names
        ySettings = ns; ns.save()
        saved = current(); draft = saved; cleanSampleFiles()
        saveB.title = "저장됨 ✓"; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.saveB.title = "저장" }
    }
    func refreshFoot() {
        guard win != nil, undoB != nil else { return }
        let dirty = draft != nil && draft != saved
        let which = dirty ? tabs.filter { merge(saved, draft, $0.id) != saved }.map(\.title).joined(separator: "·") : ""
        dirtyL.stringValue = dirty ? "● 저장 안 됨 (\(which))" : ""; dirtyL.toolTip = dirty ? "바뀐 것 있음 · 저장해야 적용돼요" : nil; dirtyL.isHidden = !dirty; note.isHidden = true
        undoB.isEnabled = (hist[tab]?.count ?? 0) > 1; redoB.isEnabled = !(redo[tab]?.isEmpty ?? true); undoSeg?.setEnabled(undoB.isEnabled, forSegment: 0); undoSeg?.setEnabled(redoB.isEnabled, forSegment: 1); cancelB.isEnabled = dirty; saveB.isEnabled = dirty || saveB.title != "저장"
        win.isDocumentEdited = dirty
    }
    func windowWillUseStandardFrame(_ w: NSWindow, defaultFrame f: NSRect) -> NSRect {   // 상단바 더블클릭(확대) = 가로 그대로, 세로만 그 화면에 꽉 (사용자 2026-11-07)
        let v = (w.screen ?? NSScreen.main)?.visibleFrame ?? f; return NSRect(x: w.frame.minX, y: v.minY, width: w.frame.width, height: v.height) }
    func windowShouldClose(_ w: NSWindow) -> Bool {   // 저장 안 한 게 있으면 물어봄
        guard draft != nil, draft != saved else { return true }
        let a = NSAlert(); a.messageText = "바꾼 설정을 저장할까요?"; a.informativeText = "저장하지 않으면 바꾼 내용이 사라져요."; a.addButton(withTitle: "저장"); a.addButton(withTitle: "저장 안 함"); a.addButton(withTitle: "취소")
        switch a.runModal() { case .alertFirstButtonReturn: doSave(); return true
        case .alertSecondButtonReturn: doCancel(); return true
        default: return false }
    }
}
final class FlippedView: NSView { override var isFlipped: Bool { true }; var onBlank: (() -> Void)?
    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(nil); onBlank?() } }   // 빈 곳(묶음 상자·줄 포함) 누르면 입력 칸 커서 빠짐 · 입력값은 반영
final class SampleGrid: NSView {   // 칸 목록: 샘플 사진 · 로고 (클릭 = 고르기 · × = 빼기 · 파일 끌어다 놓기 = 추가)
    weak var owner: SettingsController?
    var kind = "sample"
    var tileW: CGFloat { kind == "logo" ? 150 : 104 }
    var tileH: CGFloat { kind == "logo" ? 64 : 134 }
    let gap: CGFloat = 14, pad: CGFloat = 14
    var heightC: NSLayoutConstraint?, lastW: CGFloat = 0
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    static let silhouette: NSImage = NSImage(size: NSSize(width: 100, height: 130), flipped: false) { r in
        NSColor(white: 0.86, alpha: 1).setFill(); r.fill(); NSColor(white: 0.74, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 30, y: 62, width: 40, height: 40)).fill()
        let b = NSBezierPath(); b.move(to: NSPoint(x: 12, y: 0)); b.curve(to: NSPoint(x: 50, y: 50), controlPoint1: NSPoint(x: 15, y: 35), controlPoint2: NSPoint(x: 30, y: 50)); b.curve(to: NSPoint(x: 88, y: 0), controlPoint1: NSPoint(x: 70, y: 50), controlPoint2: NSPoint(x: 85, y: 35)); b.close(); b.fill(); return true }
    func reload() {
        subviews.forEach { $0.removeFromSuperview() }
        guard let o = owner, let d = o.draft else { return }
        let items: [(String, String, NSImage?)] = kind == "frame" ? d.s.frames.map { ($0.id, $0.name, Sheet.frameThumb(YSettings.frameDir.appendingPathComponent($0.file).path)) } : kind == "logo"
            ? [("", "샘플 로고", Sheet.logoThumb(""))] + d.s.logos.map { ($0.id, $0.name, Sheet.logoThumb(YSettings.logoDir.appendingPathComponent($0.file).path)) } + [("none", "로고 없음", nil)]
            : d.s.samples.map { ($0.id, $0.name, NSImage(contentsOf: YSettings.sampleDir.appendingPathComponent($0.file))) } + [("", "No image", SampleGrid.silhouette)]
        let cur = kind == "frame" ? (o.curFrame()?.id ?? "") : kind == "logo" ? d.s.logoID : kind == "test" ? "\u{0}" : d.s.curSample
        let W = bounds.width > 100 ? bounds.width : 600, cols = max(1, Int((W - pad * 2 + gap) / (tileW + gap)))
        for (i, it) in items.enumerated() {
            let x = pad + CGFloat(i % cols) * (tileW + gap), y = pad + CGFloat(i / cols) * (tileH + 22 + gap), on = it.0 == cur
            let iv = NSImageView(frame: NSRect(x: x, y: y, width: tileW, height: tileH)); iv.image = it.2; iv.imageScaling = .scaleProportionallyUpOrDown; iv.wantsLayer = true
            iv.layer?.cornerRadius = 6; iv.layer?.masksToBounds = true; iv.layer?.backgroundColor = (kind == "logo" ? NSColor.white : NSColor(white: 0.5, alpha: 0.12)).cgColor
            iv.layer?.borderWidth = on ? 3 : 0.5; iv.layer?.borderColor = (on ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            let b = NSButton(frame: iv.frame); b.isTransparent = true; b.title = ""; b.identifier = NSUserInterfaceItemIdentifier(it.0); b.target = self; b.action = #selector(pick(_:)); b.toolTip = it.1
            let l = NSTextField(labelWithString: it.1); l.font = .systemFont(ofSize: 11); l.alignment = .center; l.lineBreakMode = .byTruncatingMiddle; l.frame = NSRect(x: x - 4, y: y + tileH + 4, width: tileW + 8, height: 15); l.textColor = on ? .controlAccentColor : .labelColor
            addSubview(iv); addSubview(b); addSubview(l)
            if !it.0.isEmpty && it.0 != "none" && kind != "test" { let xb = NSButton(title: "×", target: self, action: #selector(del(_:))); xb.bezelStyle = .circular; xb.controlSize = .small; xb.identifier = NSUserInterfaceItemIdentifier(it.0); xb.toolTip = kind == "logo" ? "로고 빼기" : "샘플에서 빼기"
                xb.frame = NSRect(x: x + tileW - 22, y: y + 2, width: 20, height: 20); addSubview(xb) } }
        let rows = (items.count + cols - 1) / cols, h = pad * 2 + CGFloat(rows) * (tileH + 22) + CGFloat(rows - 1) * gap
        if heightC == nil { heightC = heightAnchor.constraint(equalToConstant: h); heightC?.isActive = true } else { heightC?.constant = h }
    }
    override func layout() { super.layout(); if abs(bounds.width - lastW) > 1 { lastW = bounds.width; reload() } }
    @objc func pick(_ b: NSButton) { let id = b.identifier?.rawValue ?? ""; if kind == "test" { owner?.testPicked(id); return }; if kind == "frame" { owner?.selectFrame(id); return }; kind == "logo" ? owner?.selectLogo(id) : owner?.selectSample(id) }
    @objc func del(_ b: NSButton) { if let id = b.identifier?.rawValue, kind == "frame" { owner?.deleteFrame(id); return }; if let id = b.identifier?.rawValue { kind == "logo" ? owner?.deleteLogo(id) : owner?.deleteSample(id) } }
    func urls(_ s: NSDraggingInfo) -> [URL] { (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).filter { kind == "frame" ? SettingsController.isFrameFile($0) : kind == "logo" ? SettingsController.isLogoFile($0) : (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true } }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { urls(s).isEmpty ? [] : .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { let u = urls(s); guard !u.isEmpty else { return false }; if kind == "test" { owner?.testDropped(u[0]); return true }; if kind == "frame" { owner?.addFrames(u); return true }; kind == "logo" ? owner?.addLogos(u) : owner?.addSamples(u); return true }
}
enum YWin {   // ydot 창 색: 위·아래 막대 · 가운데 · 묶음 상자
    static func dyn(_ l: CGFloat, _ d: CGFloat) -> NSColor { NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: d, alpha: 1) : NSColor(white: l, alpha: 1) } }
    static let inv = ProcessInfo.processInfo.environment["DONUT_WINOLD"] == nil   // 막대·박스 흰 + 가운데 회색 + 탭 줄·아래 막대 그림자 (사용자 2026-11-07) · DONUT_WINOLD = 예전 색 (비교용)
    static let bar = inv ? dyn(1, 0.145) : dyn(0.935, 0.19), mid = inv ? dyn(0.955, 0.165) : dyn(1, 0.145), box = inv ? dyn(1, 0.27) : dyn(0.955, 0.2)
    final class Shade: NSView {   // 옅어지는 그림자 띠 (up = 아래에서 위로) · 마우스는 통과 · 스크롤 내용 위에 얹힘
        let g = CAGradientLayer(); var up = false { didSet { g.startPoint = CGPoint(x: 0.5, y: up ? 0 : 1); g.endPoint = CGPoint(x: 0.5, y: up ? 1 : 0) } }
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.addSublayer(g); g.startPoint = CGPoint(x: 0.5, y: 1); g.endPoint = CGPoint(x: 0.5, y: 0) }
        required init?(coder: NSCoder) { fatalError() }
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() { let dk = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua; g.colors = [NSColor.black.withAlphaComponent(dk ? 0.24 : 0.06).cgColor, NSColor.black.withAlphaComponent(0).cgColor] }
        override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); g.frame = bounds; CATransaction.commit() }
        override func hitTest(_ p: NSPoint) -> NSView? { nil } }
    final class Body: NSView {   // 가운데 바탕 · 반전 색이면 위(탭 줄)·아래(아래 막대) 그림자를 내용 위에 얹음 (선 없이, 사용자 2026-11-07)
        let top = Shade(frame: .zero), bot = Shade(frame: .zero)
        var bottomBar = true { didSet { bot.isHidden = !YWin.inv || !bottomBar } }
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() { layer?.backgroundColor = YWin.mid.cgColor }
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; bot.up = true; top.isHidden = !YWin.inv; bot.isHidden = !YWin.inv; raiseShades() }
        func raiseShades() { for v in [top, bot] { v.removeFromSuperview(); addSubview(v, positioned: .above, relativeTo: nil) }; needsLayout = true }   // 탭을 다시 그린 뒤 맨 위로
        override func layout() { super.layout(); top.frame = NSRect(x: 0, y: bounds.height - 7, width: bounds.width, height: 7); bot.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 7) }
        required init?(coder: NSCoder) { fatalError() } }
}
final class FillTile: NSView {   // 샘플 칸: 사진이 칸을 꽉 채움 (맥이 다시 그려도 사라지지 않게 updateLayer에서 늘 다시 넣음)
    var cg: CGImage? { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?, onDouble: (() -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layerContentsRedrawPolicy = .onSetNeedsDisplay }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contents = cg; layer?.contentsGravity = .resizeAspectFill; layer?.masksToBounds = true; layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.1).cgColor }
    override func mouseDown(with e: NSEvent) { if e.clickCount >= 2, let d = onDouble { d() } else { onTap?() } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class SampleFlow: NSView {   // 샘플 사진 여러 줄 (넘치면 다음 줄) · 누르면 고름 · 크기 바꿀 때 부드럽게 (위 내용은 그대로, 사진만 커지고 줄이 내려감)
    override var isFlipped: Bool { true }
    var items: [(String, NSImage?, String)] = [], cur = "", h: CGFloat = 81, cols = 6, onPick: ((String) -> Void)?, onDouble: ((String) -> Void)?, hc: NSLayoutConstraint?, lastW: CGFloat = 0, btns: [String: FillTile] = [:]
    func reload(animated: Bool = false) {
        let ids = Set(items.map(\.0)); for (k, b) in btns where !ids.contains(k) { b.removeFromSuperview(); btns[k] = nil }
        let gap: CGFloat = 12, W = bounds.width > 50 ? bounds.width : 600, w = floor((W - gap * CGFloat(cols - 1)) / CGFloat(cols)); h = (w * 45 / 35).rounded(); var x: CGFloat = 0, y: CGFloat = 0, frames: [(NSView, NSRect)] = []   // 박스 폭에 맞춤: 기본 6장 · 확대 4장 (사용자 2026-11-07)
        for (id, im, nm) in items {
            if x + w > W + 0.5 && x > 0 { x = 0; y += h + gap }
            let b: FillTile; if let o = btns[id] { b = o } else {
                b = FillTile(frame: NSRect(x: x, y: y, width: w, height: h)); b.identifier = NSUserInterfaceItemIdentifier(id); b.onTap = { [weak self] in self?.onPick?(id) }; b.onDouble = onDouble == nil ? nil : { [weak self] in self?.onDouble?(id) }
                b.layer?.cornerRadius = 6; addSubview(b); btns[id] = b }
            b.cg = im.flatMap { i -> CGImage? in var r = NSRect(origin: .zero, size: i.size); return i.cgImage(forProposedRect: &r, context: nil, hints: nil) }   // 칸을 꽉 채움 (사진 좌우 빈 곳 없게, 사용자 2026-11-07)
            b.toolTip = nm; b.layer?.borderWidth = id == cur ? 2.5 : 0.5; b.layer?.borderColor = (id == cur ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            frames.append((b, NSRect(x: x, y: y, width: w, height: h))); x += w + gap }
        let total = items.isEmpty ? 0 : y + h
        if hc == nil { hc = heightAnchor.constraint(equalToConstant: total); hc?.isActive = true }
        if animated { NSAnimationContext.runAnimationGroup { c in c.duration = 0.28; c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); c.allowsImplicitAnimation = true
                for (b, f) in frames { b.animator().frame = f }; hc?.animator().constant = total; window?.layoutIfNeeded() } }
        else { for (b, f) in frames { b.frame = f }; hc?.constant = total } }
    @objc func tap(_ b: NSButton) { onPick?(b.identifier?.rawValue ?? "") }
    override func layout() { super.layout(); if abs(bounds.width - lastW) > 1 { lastW = bounds.width; reload() } }
    var onDrop: ((URL) -> Void)? { didSet { if onDrop != nil { registerForDraggedTypes([.fileURL]) } } }   // 사진을 끌어다 놓기 (테스트 창)
    var onBlank: (() -> Void)?   // 사진 아닌 빈 곳 누름 (선택 풀기)
    override func mouseDown(with e: NSEvent) { onBlank?(); super.mouseDown(with: e) }
    var onDelete: ((String) -> Void)?   // 있으면: 커서를 대면 오른쪽 위 × · 우클릭 '삭제' (No image는 안 지움)
    lazy var xBtn: NSButton = { let b = NSButton(title: "", target: self, action: #selector(xTap)); b.isBordered = false; b.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "빼기")?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular)); b.contentTintColor = NSColor(white: 0.25, alpha: 0.85); b.toolTip = "샘플에서 빼기"; b.isHidden = true; return b }()
    var hoverID = ""
    override func updateTrackingAreas() { trackingAreas.forEach(removeTrackingArea); if onDelete != nil { addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)) }; super.updateTrackingAreas() }
    func tile(at p: NSPoint) -> (String, NSView)? { btns.first { $0.value.frame.contains(p) }.map { ($0.key, $0.value) } }
    override func mouseMoved(with e: NSEvent) { showX(tile(at: convert(e.locationInWindow, from: nil))) }
    override func mouseExited(with e: NSEvent) { showX(nil) }
    func showX(_ t: (String, NSView)?) { guard onDelete != nil else { return }; guard let (id, b) = t, !id.isEmpty else { xBtn.isHidden = true; hoverID = ""; return }
        if xBtn.superview !== self { addSubview(xBtn) }; hoverID = id; xBtn.frame = NSRect(x: b.frame.maxX - 24, y: b.frame.minY + 4, width: 20, height: 20); addSubview(xBtn, positioned: .above, relativeTo: nil); xBtn.isHidden = false }
    @objc func xTap() { let id = hoverID; showX(nil); if !id.isEmpty { onDelete?(id) } }
    override func menu(for e: NSEvent) -> NSMenu? { guard onDelete != nil, let (id, _) = tile(at: convert(e.locationInWindow, from: nil)), !id.isEmpty else { return nil }
        let m = NSMenu(); let i = NSMenuItem(title: "삭제", action: #selector(menuDelete(_:)), keyEquivalent: ""); i.target = self; i.representedObject = id; m.addItem(i); return m }
    @objc func menuDelete(_ i: NSMenuItem) { if let id = i.representedObject as? String { onDelete?(id) } }
    func dropURL(_ s: NSDraggingInfo) -> URL? { (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first { (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true } }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { onDrop != nil && dropURL(s) != nil ? .copy : [] }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { guard let u = dropURL(s) else { return false }; onDrop?(u); return true }
}
final class SpecCard: NSView {   // 규격 탭 카드: 샘플을 그 규격대로 자른 사진 + 정수리·턱 점선 (+ 이름 · 값)
    var name: String, k: CGFloat, labels: Bool, onClick: ((String) -> Void)?
    let img = CALayer(), holder = CALayer(), clip = CALayer(), g1 = CAShapeLayer(), g2 = CAShapeLayer(), sel = CALayer(), nameL = NSTextField(labelWithString: ""), valL = NSTextField(labelWithString: "")
    var f = 0.0, t = 0.0
    var selected = false { didSet { sel.isHidden = !selected } }
    override var isFlipped: Bool { true }
    init(_ n: String, k: CGFloat, labels: Bool) {
        name = n; self.k = k; self.labels = labels; super.init(frame: .zero); wantsLayer = true; translatesAutoresizingMaskIntoConstraints = false
        sel.cornerRadius = 9; sel.isHidden = true; layer?.addSublayer(sel)
        holder.shadowColor = NSColor.black.cgColor; holder.shadowOpacity = 0.25; holder.shadowRadius = 3.5; holder.shadowOffset = CGSize(width: 0, height: 1.8); layer?.addSublayer(holder)   // 그림자 = 틀 · 사진 = 안에서 꽉 채움 (크기 바뀌는 동안 늘어나 보이지 않게, 사용자 2026-11-07)
        clip.masksToBounds = true; clip.backgroundColor = NSColor.black.cgColor; holder.addSublayer(clip); img.contentsGravity = .resizeAspectFill; clip.addSublayer(img)
        for l in [holder, clip, img] { l.actions = ["contents": NSNull()] }   // 맥 기본처럼 아래로 옅게 (뒤집힌 뷰라 +가 아래, 예전엔 위로 갔음)
        for g in [g1, g2] { g.fillColor = nil; g.lineWidth = 1; g.lineDashPattern = [3, 2]; layer?.addSublayer(g) }
        nameL.font = .systemFont(ofSize: 12, weight: .medium); nameL.alignment = .center; valL.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); valL.alignment = .center
        if labels { addSubview(nameL); addSubview(valL) }
        setSpec(n) }
    required init?(coder: NSCoder) { fatalError() }
    func setSpec(_ n: String) { name = n; nameL.stringValue = n; invalidateIntrinsicContentSize(); needsLayout = true }
    var dims: (Double, Double)?   // Custom = 설정의 가로·세로
    var bwh: (w: Double, h: Double) { if let d = dims { return (d.0, d.1) }; let b = Converter.baseOf(name); return (b.w, b.h) }
    var wh: (CGFloat, CGFloat) { let b = bwh; let s = labels ? k : min(k, 150 / CGFloat(b.h), 130 / CGFloat(b.w)); return (CGFloat(b.w) * s, CGFloat(b.h) * s) }
    override var intrinsicContentSize: NSSize { let (w, h) = wh; return labels ? NSSize(width: max(w, 92) + 12, height: h + 46) : NSSize(width: 130 + 24, height: 150 + 8) }   // 큰 사진 칸은 크기 고정 (조정 박스가 규격마다 커졌다 작아지지 않게)
    func set(_ im: CGImage?, _ f: Double, _ t: Double, changed: Bool) {
        self.f = f; self.t = t; CATransaction.begin(); CATransaction.setDisableActions(true); if camBase == nil { img.contents = im; img.contentsGravity = .resizeAspectFill }; CATransaction.commit(); valL.stringValue = "얼굴 \(fmt(f)) · 여백 \(fmt(t))"; valL.textColor = changed ? .systemOrange : .secondaryLabelColor; needsLayout = true }   // 사진은 바로 바꿈 (페이드 중엔 두 사진이 겹쳐 보였음)
    func fmt(_ v: Double) -> String { let r = (v * 100).rounded() / 100; return r == r.rounded() ? String(Int(r)) : String(r) }
    override func layout() {
        super.layout(); let (w, h) = wh, b = bwh, s = h / CGFloat(b.h)
        let x = ((bounds.width - w) / 2).rounded(), y: CGFloat = labels ? 6 : ((bounds.height - h) / 2).rounded()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sel.frame = bounds; sel.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.13).cgColor; sel.borderWidth = 1.5; sel.borderColor = NSColor.controlAccentColor.cgColor
        placeLayers(CGRect(x: x, y: y, width: w, height: h))
        let y1 = y + CGFloat(t) * s, y2 = min(y + h, y + CGFloat(t + f) * s)
        for (g, yy) in [(g1, y1), (g2, y2)] { let p = CGMutablePath(); p.move(to: CGPoint(x: x - 5, y: yy.rounded() + 0.5)); p.addLine(to: CGPoint(x: x + w + 5, y: yy.rounded() + 0.5)); g.path = p; g.strokeColor = NSColor.controlAccentColor.cgColor; g.isHidden = true }   // 파란 점선 뺌 (사용자 2026-11-07)
        CATransaction.commit()
        if labels { nameL.frame = NSRect(x: 0, y: y + h + 5, width: bounds.width, height: 16); valL.frame = NSRect(x: 0, y: y + h + 22, width: bounds.width, height: 14) } }
    override func mouseDown(with e: NSEvent) { onClick?(name) }
    var camBase: CGImage?, camCrop: CGRect?   // 큰 사진: 원본 한 장 + 보일 자리 (있으면 사진을 바꿔 끼우지 않고 창만 옮김)
    func setCamera(_ base: CGImage?, _ crop: CGRect?) { camBase = base; camCrop = crop; if base != nil, crop != nil, img.contents as! CGImage? !== base { img.contents = base; img.contentsGravity = .resize } }
    func targetRect() -> CGRect { let (w, h) = wh; return CGRect(x: ((bounds.width - w) / 2).rounded(), y: labels ? 6 : ((bounds.height - h) / 2).rounded(), width: w, height: h) }
    func placeLayers(_ r: CGRect) {
        holder.frame = r; holder.shadowPath = CGPath(rect: CGRect(origin: .zero, size: r.size), transform: nil); clip.frame = CGRect(origin: .zero, size: r.size)
        if let b = camBase, let c = camCrop, c.width > 0 { let k = r.width / c.width; img.frame = CGRect(x: -c.minX * k, y: -c.minY * k, width: CGFloat(b.width) * k, height: CGFloat(b.height) * k) }
        else { img.frame = clip.bounds } }
}
final class DesignCanvas: NSView {   // 로고 사진 · 프레임 사진 편집판 (로고·프레임 탭): 실제 인화와 같은 그림 + 자처럼 치수(cm) · 로고/사진 손으로 끌기 · 프레임 사진 오른쪽 아래 손잡이 = 크기 (비율 그대로)
    weak var owner: SettingsController?
    var mode = "logo"
    var img: CGImage?, W: CGFloat = 1, H: CGFloat = 1
    var photoR = CGRect.zero, logoR: CGRect?   // 300ppi px · 위 기준
    var drag = "", start = CGPoint.zero, startR = CGRect.zero, hot = ""
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    var k: CGFloat { max(0.01, min((bounds.width - 150) / W, (bounds.height - 74) / H)) }
    var org: CGPoint { CGPoint(x: ((bounds.width - W * k) / 2 + 30).rounded(), y: ((bounds.height - H * k) / 2 + 14).rounded()) }
    func v(_ r: CGRect) -> CGRect { CGRect(x: org.x + r.minX * k, y: org.y + r.minY * k, width: r.width * k, height: r.height * k) }
    func px(_ p: NSPoint) -> CGPoint { CGPoint(x: (p.x - org.x) / k, y: (p.y - org.y) / k) }
    static func cm(_ px: CGFloat) -> String { String(format: "%.2f", Double(px) * 2.54 / 300) }
    var handle: CGRect { let r = v(photoR); return CGRect(x: r.maxX - 6, y: r.maxY - 6, width: 12, height: 12) }
    override func draw(_ dirty: NSRect) {
        let c = v(CGRect(x: 0, y: 0, width: W, height: H))
        if let img { NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)).draw(in: c, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]) }
        let gray = NSColor(white: 0.62, alpha: 1); gray.setStroke()
        let edge = NSBezierPath(rect: c.insetBy(dx: -0.5, dy: -0.5)); edge.lineWidth = 1; edge.stroke()   // 미리보기 사진 둘레 회색 1px (사용자 2026-11-07)
        let pr = v(photoR); let pe = NSBezierPath(rect: pr.insetBy(dx: 0.5, dy: 0.5)); pe.lineWidth = 1; gray.setStroke(); pe.stroke()
        let dimC = NSColor.secondaryLabelColor, act = NSColor.controlAccentColor
        func lab(_ t: String, _ p: NSPoint, _ col: NSColor, align: String = "c") {
            let a = NSAttributedString(string: t, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: col]); let s = a.size()
            let x = align == "r" ? p.x - s.width : align == "l" ? p.x : p.x - s.width / 2; a.draw(at: NSPoint(x: x, y: p.y - s.height / 2)) }
        func hDim(_ y: CGFloat, _ x0: CGFloat, _ x1: CGFloat, _ t: String, _ col: NSColor) {   // 가로 치수: 끝 눈금 + 가운데 숫자 (위)
            guard x1 - x0 > 0.5 else { return }; col.setStroke(); let p = NSBezierPath(); p.lineWidth = 1
            p.move(to: NSPoint(x: x0, y: y)); p.line(to: NSPoint(x: x1, y: y)); for x in [x0, x1] { p.move(to: NSPoint(x: x, y: y - 3.5)); p.line(to: NSPoint(x: x, y: y + 3.5)) }; p.stroke(); lab(t, NSPoint(x: (x0 + x1) / 2, y: y - 8), col) }
        func vDim(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ t: String, _ col: NSColor, left: Bool = true) {   // 세로 치수: 숫자는 옆
            guard y1 - y0 > 0.5 else { return }; col.setStroke(); let p = NSBezierPath(); p.lineWidth = 1
            p.move(to: NSPoint(x: x, y: y0)); p.line(to: NSPoint(x: x, y: y1)); for y in [y0, y1] { p.move(to: NSPoint(x: x - 3.5, y: y)); p.line(to: NSPoint(x: x + 3.5, y: y)) }; p.stroke(); lab(t, NSPoint(x: left ? x - 6 : x + 6, y: (y0 + y1) / 2), col, align: left ? "r" : "l") }
        func guide(_ a: NSPoint, _ b: NSPoint, _ col: NSColor) { col.withAlphaComponent(0.7).setStroke(); let p = NSBezierPath(); p.lineWidth = 1; p.setLineDash([3, 3], count: 2, phase: 0); p.move(to: a); p.line(to: b); p.stroke() }
        let busy = !drag.isEmpty
        // 바깥 자: 위 = 왼쪽 여백 · 사진 폭 · 오른쪽 여백 / 왼쪽 = 위 여백 · 사진 높이 · 아래 여백
        let ty = c.minY - 12, lx = c.minX - 12
        hDim(ty, c.minX, pr.minX, Self.cm(photoR.minX), dimC); hDim(ty, pr.minX, pr.maxX, Self.cm(photoR.width), busy && drag == "size" ? act : dimC); hDim(ty, pr.maxX, c.maxX, Self.cm(W - photoR.maxX), dimC)
        vDim(lx, c.minY, pr.minY, Self.cm(photoR.minY), dimC); vDim(lx, pr.minY, pr.maxY, Self.cm(photoR.height), busy && drag == "size" ? act : dimC); vDim(lx, pr.maxY, c.maxY, Self.cm(H - photoR.maxY), dimC)
        lab((mode == "frame" ? "프레임 " : "전체 ") + Self.cm(W) + " × " + Self.cm(H) + " cm", NSPoint(x: c.midX, y: c.maxY + 14), dimC)
        if mode == "logo", let l0 = logoR {   // 로고: 왼쪽·오른쪽 끝에서 · 아래 끝에서 (점선 + 숫자) · 끄는 중엔 파란색
            let l = v(l0), col = busy ? act : dimC, gy = l.midY
            guide(NSPoint(x: c.minX, y: gy), NSPoint(x: l.minX, y: gy), col); guide(NSPoint(x: l.maxX, y: gy), NSPoint(x: c.maxX, y: gy), col)
            if l.minX - c.minX > 26 { lab(Self.cm(l0.minX), NSPoint(x: (c.minX + l.minX) / 2, y: gy - 8), col) }
            if c.maxX - l.maxX > 26 { lab(Self.cm(W - l0.maxX), NSPoint(x: (l.maxX + c.maxX) / 2, y: gy - 8), col) }
            vDim(c.maxX + 12, l.maxY, c.maxY, Self.cm(H - l0.maxY), col, left: false); vDim(c.maxX + 12, l.minY, l.maxY, Self.cm(l0.height), col, left: false)
            (hot == "logo" || busy ? act : NSColor(white: 0.5, alpha: 0.6)).setStroke(); let b = NSBezierPath(rect: l.insetBy(dx: -2.5, dy: -2.5)); b.lineWidth = 1; b.setLineDash([2, 2], count: 2, phase: 0); b.stroke() }
        if mode == "frame" {   // 사진 둘레 = 끌어 옮기기 · 손잡이 = 크기
            (hot == "photo" || busy ? act : NSColor(white: 0.5, alpha: 0.6)).setStroke(); let b = NSBezierPath(rect: pr.insetBy(dx: -1.5, dy: -1.5)); b.lineWidth = 1; b.setLineDash([3, 2], count: 2, phase: 0); b.stroke()
            let h = handle; NSColor.white.setFill(); NSBezierPath(ovalIn: h).fill(); act.setStroke(); let hp = NSBezierPath(ovalIn: h.insetBy(dx: 0.5, dy: 0.5)); hp.lineWidth = 1.5; hp.stroke() }
    }
    func hit(_ p: NSPoint) -> String {
        if mode == "frame" { if handle.insetBy(dx: -4, dy: -4).contains(p) { return "size" }; if v(photoR).contains(p) { return "photo" } }
        if mode == "logo", let l = logoR, v(l).insetBy(dx: -4, dy: -4).contains(p) { return "logo" }
        return "" }
    override func updateTrackingAreas() { super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self)) }
    override func mouseMoved(with e: NSEvent) { let h = hit(convert(e.locationInWindow, from: nil)); if h != hot { hot = h; needsDisplay = true }; (h == "size" ? NSCursor.crosshair : h.isEmpty ? NSCursor.arrow : NSCursor.openHand).set() }
    override func mouseExited(with e: NSEvent) { hot = ""; needsDisplay = true; NSCursor.arrow.set() }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil); drag = hit(p); guard !drag.isEmpty else { return }
        start = px(p); startR = drag == "logo" ? (logoR ?? .zero) : photoR; owner?.designDragBegan(); if drag != "size" { NSCursor.closedHand.set() } }
    override func mouseDragged(with e: NSEvent) {
        guard !drag.isEmpty else { return }; let q = px(convert(e.locationInWindow, from: nil)), dx = q.x - start.x, dy = q.y - start.y
        var r = startR
        if drag == "size" { let a = startR.height / max(1, startR.width); var w = max(30, startR.width + dx); w = min(w, W - r.minX, (H - r.minY) / a); r.size = CGSize(width: w.rounded(), height: (w * a).rounded()) }
        else { r.origin = CGPoint(x: startR.minX + dx, y: startR.minY + dy)
            let snap = 5 / k   // 가운데에 가까우면 붙음 (가로·세로)
            if abs(r.midX - W / 2) < snap { r.origin.x = (W - r.width) / 2 }; if drag == "photo", abs(r.midY - H / 2) < snap { r.origin.y = (H - r.height) / 2 }
            r.origin.x = min(max(0, r.origin.x), W - r.width).rounded(); r.origin.y = min(max(0, r.origin.y), H - r.height).rounded() }
        owner?.designDragged(drag, r) }
    override func mouseUp(with e: NSEvent) { guard !drag.isEmpty else { return }; drag = ""; owner?.designDragEnded(); needsDisplay = true; NSCursor.arrow.set() }
}

final class CropView: NSView {   // 샘플 자르기: 사진 위에 규격 비율 창 · 안 끌기 = 옮기기 · 모서리 = 크기 (비율 그대로)
    var img: CGImage?, crop = CGRect.zero, aspect: CGFloat = 413.0 / 531.0, drag = "", start = CGPoint.zero, startR = CGRect.zero   // crop = 사진 px (위 기준)
    override var isFlipped: Bool { true }
    var fit: CGRect { guard let img else { return bounds }; let s = min((bounds.width - 20) / CGFloat(img.width), (bounds.height - 20) / CGFloat(img.height)), w = CGFloat(img.width) * s, h = CGFloat(img.height) * s; return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h) }
    var s: CGFloat { guard let img else { return 1 }; return fit.width / CGFloat(img.width) }
    func v(_ r: CGRect) -> CGRect { let f = fit; return CGRect(x: f.minX + r.minX * s, y: f.minY + r.minY * s, width: r.width * s, height: r.height * s) }
    override func draw(_ d: NSRect) {
        guard let img else { return }; let f = fit
        NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)).draw(in: f, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let c = v(crop); let dim = NSBezierPath(rect: f); dim.append(NSBezierPath(rect: c)); dim.windingRule = .evenOdd; NSColor.black.withAlphaComponent(0.45).setFill(); dim.fill()
        NSColor.white.setStroke(); let b = NSBezierPath(rect: c.insetBy(dx: 0.5, dy: 0.5)); b.lineWidth = 1.5; b.stroke()
        NSColor.white.withAlphaComponent(0.35).setStroke(); let g = NSBezierPath(); g.lineWidth = 0.5
        for i in 1...2 { let x = c.minX + c.width * CGFloat(i) / 3, y = c.minY + c.height * CGFloat(i) / 3; g.move(to: NSPoint(x: x, y: c.minY)); g.line(to: NSPoint(x: x, y: c.maxY)); g.move(to: NSPoint(x: c.minX, y: y)); g.line(to: NSPoint(x: c.maxX, y: y)) }; g.stroke()
        for p in [NSPoint(x: c.minX, y: c.minY), NSPoint(x: c.maxX, y: c.minY), NSPoint(x: c.minX, y: c.maxY), NSPoint(x: c.maxX, y: c.maxY)] { NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill() } }
    func corner(_ p: NSPoint) -> String { let c = v(crop); for (n, q) in [("tl", NSPoint(x: c.minX, y: c.minY)), ("tr", NSPoint(x: c.maxX, y: c.minY)), ("bl", NSPoint(x: c.minX, y: c.maxY)), ("br", NSPoint(x: c.maxX, y: c.maxY))] where hypot(p.x - q.x, p.y - q.y) < 10 { return n }; return c.contains(p) ? "move" : "" }
    override func mouseDown(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); drag = corner(p); start = p; startR = crop }
    override func mouseDragged(with e: NSEvent) {
        guard let img, !drag.isEmpty else { return }; let p = convert(e.locationInWindow, from: nil), dx = (p.x - start.x) / s, dy = (p.y - start.y) / s, IW = CGFloat(img.width), IH = CGFloat(img.height)
        var r = startR
        if drag == "move" { r.origin.x = min(max(0, startR.minX + dx), IW - r.width); r.origin.y = min(max(0, startR.minY + dy), IH - r.height) }
        else {   // 반대쪽 모서리 고정 · 비율 그대로
            let ax = drag.hasSuffix("l") ? startR.maxX : startR.minX, ay = drag.hasPrefix("t") ? startR.maxY : startR.minY
            var w = drag.hasSuffix("l") ? startR.width - dx : startR.width + dx; w = max(40, w)
            let maxW = min(drag.hasSuffix("l") ? ax : IW - ax, (drag.hasPrefix("t") ? ay : IH - ay) * aspect); w = min(w, maxW); let h = w / aspect
            r = CGRect(x: drag.hasSuffix("l") ? ax - w : ax, y: drag.hasPrefix("t") ? ay - h : ay, width: w, height: h) }
        crop = r; needsDisplay = true }
    override func mouseUp(with e: NSEvent) { drag = "" }
}

final class SheetThumb: NSImageView {   // 인화지 탭 썸네일: 한 번 = 고르기(파란 테두리) · 두 번 = 열기
    var onTap: (() -> Void)?, onDouble: (() -> Void)?
    var on = false { didSet { paint() } }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; paint() }
    required init?(coder: NSCoder) { fatalError() }
    func paint() { layer?.borderWidth = on ? 2.5 : 0.5; layer?.borderColor = (on ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); paint() }
    override func mouseDown(with e: NSEvent) { if e.clickCount >= 2 { onDouble?() } else { onTap?() } }
}
final class GroupBox: NSView {   // 시스템 설정 같은 둥근 묶음 상자 (밝게·어둡게 자동)
    var onBlank: (() -> Void)?   // 빈 곳 누름 (선택 풀기)
    override func mouseDown(with e: NSEvent) { onBlank?(); super.mouseDown(with: e) }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.cornerRadius = 9; layer?.borderWidth = 0.5; setShade() }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    func setShade() { let dk = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua; let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(dk ? 0.35 : 0.08); sh.shadowBlurRadius = 5; sh.shadowOffset = NSSize(width: 0, height: -1); shadow = sh }   // 연한 그림자 (사용자 2026-11-07) · 맥이 layer 그림자를 덮어써서 NSShadow로
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); setShade() }
    override func updateLayer() { let dk = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = YWin.box.cgColor; layer?.borderColor = (dk ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0, alpha: 0.08)).cgColor }
}

// MARK: - 인화지 배치 편집 창 (전체화면 · 포토샵처럼: 끌기·스마트 안내선·회전·⌘C ⌘V ⌘J·방향키 1px · 사용자 2026-11-06)
final class LayoutWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with e: NSEvent) -> Bool { if onKey?(e) == true { return true }; return super.performKeyEquivalent(with: e) }
}
final class LayoutEditor: NSObject, NSWindowDelegate {
    weak var owner: SettingsController?
    var win: LayoutWindow?
    var lays: [String: YLayout] = [:], orig: [String: YLayout] = [:], spec = "증명", sel: Set<Int> = []
    var undoS: [([String: YLayout], String, Set<Int>)] = [], redoS: [([String: YLayout], String, Set<Int>)] = []
    var clip: [YCell] = []
    var photos: [String: CGImage] = [:]
    let canvas = SheetCanvas()
    let specPop = NSPopUpButton(), padF = NSTextField(), strokeF = NSTextField(), grayF = NSTextField(), logoHF = NSTextField()
    let countL = NSTextField(labelWithString: ""), warnL = NSTextField(labelWithString: "")
    var undoB: NSButton!, redoB: NSButton!, topBar: NSStackView?
    func fitTop() {   // 화면이 좁으면 위 막대 버튼을 아이콘만 (글자는 마우스를 올리면) — 작은 화면·가상 맥에서 잘리지 않게
        guard let top = topBar, let w = win else { return }; let bs = top.arrangedSubviews.compactMap { $0 as? NSButton }.filter { $0.image != nil }
        bs.forEach { $0.imagePosition = .imageLeading }; top.layoutSubtreeIfNeeded()
        if top.fittingSize.width > w.frame.width - 40 { bs.forEach { b in b.imagePosition = .imageOnly; if b.toolTip?.hasPrefix(b.title) != true { b.toolTip = b.title + " · " + (b.toolTip ?? "") } } } }
    func windowDidResize(_ n: Notification) { fitTop() }
    var L: YLayout { get { lays[spec] ?? Sheet.defaultLayout(spec) } set { lays[spec] = newValue } }
    var style: Sheet.PolStyle { Sheet.style(owner?.draft?.s ?? ySettings) }
    static let BX = 720, BY = 170   // 인화지 밖에 둘 수 있는 자리 (300ppi px · 양옆·위아래)
    func board(_ l: YLayout? = nil) -> CGRect { let (W, H) = Sheet.sheetWH(l ?? L); return CGRect(x: -Self.BX, y: -Self.BY, width: W + 2 * Self.BX, height: H + 2 * Self.BY) }
    func sheetRect(_ l: YLayout? = nil) -> CGRect { let (W, H) = Sheet.sheetWH(l ?? L); return CGRect(x: 0, y: 0, width: W, height: H) }
    var photoKey = "-"
    func photo(_ n: String) -> CGImage? {   // 칸에 보일 사진: 샘플(고른 것) → 규격 크기로 얼굴 기준 자름 · 없으면 sample 그림 (샘플이 바뀔 때만 다시)
        let key = owner?.draft?.s.curSample ?? ""; if key != photoKey { photos = [:]; photoKey = key }
        if let p = photos[n] { return p }
        guard let sp = Converter.webSpecs.first(where: { $0.name == (n == "프로필" ? "증명" : n) }) else { return nil }   // 프로필 = 3.5×4.5
        var u: URL?; if let d = owner?.draft, let sm = d.s.samples.first(where: { $0.id == d.s.curSample }) { u = YSettings.sampleDir.appendingPathComponent(sm.file) }
        if u == nil || !FileManager.default.fileExists(atPath: u!.path) { u = Controller.testSilhouette() }
        guard let url = u, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1800, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let (_, out, _) = Converter.webSized(img, want: sp, high: false, key: url); photos[n] = out; return out }
    // ── 열기 · 닫기
    func open(_ s: String) {
        guard let d = owner?.draft else { return }
        if let w = win, w.isVisible { switchSpec(s); w.makeKeyAndOrderFront(nil); return }
        lays = [:]; for n in SettingsController.specOrder { lays[n] = Sheet.layout(n, d.s) }; orig = lays; undoS = []; redoS = []; sel = []; spec = s
        if win == nil { build(); owner?.applyWinTheme() }
        guard let w = win else { return }
        let scr = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let scr { w.setFrame(scr.visibleFrame, display: false) }   // 화면 꽉 채움 (맥 전체화면 전환 애니메이션 없이 바로 열고 닫힘 · 2026-11-06 최적화)
        fillPop(); fill(); fitTop(); w.contentView?.layoutSubtreeIfNeeded(); canvas.refresh()
        NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); w.makeFirstResponder(canvas) }
    func close() { win?.orderOut(nil) }
    @objc func cancel() {
        guard lays != orig, let w = win else { close(); return }
        let a = NSAlert(); a.messageText = "바꾼 배치를 저장할까요?"; a.addButton(withTitle: "저장"); a.addButton(withTitle: "저장 안 함"); a.addButton(withTitle: "취소")
        a.beginSheetModal(for: w) { r in if r == .alertFirstButtonReturn { self.save() } else if r == .alertSecondButtonReturn { self.close() } } }
    @objc func save() {
        if let empty = SettingsController.specOrder.first(where: { (lays[$0]?.cells.isEmpty ?? false) }), let w = win {   // 사진 없는 배치는 저장 안 함
            let a = NSAlert(); a.messageText = "\(empty) 인화지에 사진이 없어요"; a.informativeText = "사진을 하나 이상 넣거나 '초기값으로 설정'을 눌러 주세요."; a.addButton(withTitle: "확인"); switchSpec(empty); a.beginSheetModal(for: w, completionHandler: nil); return }
        var m: [String: YLayout] = [:]; for (n, l) in lays where l != Sheet.defaultLayout(n) { m[n] = l }   // 기본과 같으면 안 적음
        owner?.layoutsSaved(m); orig = lays; close() }
    func windowShouldClose(_ s: NSWindow) -> Bool { cancel(); return false }
    // ── 창 만들기
    func build() {
        let w = LayoutWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "인화지 배치"; w.titlebarAppearsTransparent = true; w.isReleasedWhenClosed = false; w.delegate = self; w.collectionBehavior = [.fullScreenPrimary]; w.animationBehavior = .none; w.backgroundColor = YWin.bar; w.minSize = NSSize(width: 900, height: 640)
        let cv = NSView(); w.contentView = cv; win = w
        func btn(_ t: String, _ sym: String, _ a: Selector, _ tip: String) -> NSButton { let b = NSButton(title: t, target: self, action: a); b.bezelStyle = .rounded; b.image = NSImage(systemSymbolName: sym, accessibilityDescription: t); b.imagePosition = .imageLeading; b.toolTip = tip; return b }
        func sep() -> NSView { let v = NSBox(); v.boxType = .separator; v.translatesAutoresizingMaskIntoConstraints = false; v.heightAnchor.constraint(equalToConstant: 22).isActive = true; v.widthAnchor.constraint(equalToConstant: 1).isActive = true; return v }
        specPop.target = self; specPop.action = #selector(popChanged); specPop.font = .systemFont(ofSize: 13)
        undoB = btn("실행 취소", "arrow.uturn.backward", #selector(undo), "⌘Z"); redoB = btn("다시 실행", "arrow.uturn.forward", #selector(redo), "⇧⌘Z")
        let top = NSStackView(views: [specPop, sep(), btn("인화지 회전", "rotate.right", #selector(rotateSheet), "인화지를 90° 돌려요 (세로 5×7 ↔ 가로 7×5)"), btn("사진 회전", "rotate.right.fill", #selector(rotateSel), "고른 사진 90° · R"), sep(),
            btn("사진 추가", "plus", #selector(addCell), "사진 칸 하나 더"), btn("로고 사진", "person.crop.square.badge.camera", #selector(addSig), "로고가 있는 사진 넣기 · 모양은 로고 탭"), btn("로고", "signature", #selector(addLogo), "로고만 넣기 · 크기는 오른쪽 '로고 높이'"), btn("프레임 사진", "photo.artframe", #selector(addFrameCell(_:)), "프레임 사진 넣기 · 모양은 프레임 탭"), btn("복사", "doc.on.doc", #selector(copySel), "⌘C"), btn("붙여넣기", "doc.on.clipboard", #selector(paste), "⌘V"), btn("복제", "plus.square.on.square", #selector(dupSel), "⌘J · ⌥ 누르고 끌기"), btn("빼기", "trash", #selector(deleteSel), "⌫"), sep(), undoB, redoB])
        top.spacing = 8; top.translatesAutoresizingMaskIntoConstraints = false; cv.addSubview(top); topBar = top
        // 오른쪽: 칸 모양 · 맞추기 · 정보
        func numF(_ f: NSTextField, _ tip: String) -> NSView { f.alignment = .right; f.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular); f.target = self; f.action = #selector(fieldEdited(_:)); f.cell?.sendsActionOnEndEditing = true; f.toolTip = tip; f.translatesAutoresizingMaskIntoConstraints = false; f.widthAnchor.constraint(equalToConstant: 64).isActive = true; return f }
        func line(_ t: String, _ v: NSView, _ u: String) -> NSView { let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 13); let s = NSView(); s.setContentHuggingPriority(.init(1), for: .horizontal); let uu = NSTextField(labelWithString: u); uu.textColor = .secondaryLabelColor; uu.font = .systemFont(ofSize: 12); let st = NSStackView(views: [l, s, v, uu]); st.spacing = 6; return st }
        func hdr(_ t: String) -> NSTextField { let h = NSTextField(labelWithString: t); h.font = .systemFont(ofSize: 13, weight: .semibold); return h }
        let alignBox = NSStackView(views: [btn("가로 가운데", "align.horizontal.center", #selector(centerH), "고른 사진(없으면 전부)을 인화지 가로 가운데로"), btn("세로 가운데", "align.vertical.center", #selector(centerV), "고른 사진(없으면 전부)을 인화지 세로 가운데로")]); alignBox.orientation = .vertical; alignBox.alignment = .leading; alignBox.spacing = 8
        countL.font = .systemFont(ofSize: 12); countL.textColor = .secondaryLabelColor; warnL.font = .systemFont(ofSize: 12, weight: .medium); warnL.textColor = .systemRed
        let right = NSStackView(views: [hdr("스트로크 · 여백"), line("여백", numF(padF, "사진 둘레 흰 여백 (300ppi px · 10 = 약 0.85 mm)"), "px"), line("선 두께", numF(strokeF, "0 = 선 없음"), "px"), line("선 밝기", numF(grayF, "0 검정 ~ 255 흰"), "0~255"), hdr("맞추기"), alignBox, hdr("로고"), line("로고 높이", numF(logoHF, "고른 로고 칸의 높이"), "cm"), countL, warnL])
        right.orientation = .vertical; right.alignment = .leading; right.spacing = 12; right.setCustomSpacing(22, after: right.views[3]); right.setCustomSpacing(22, after: alignBox); right.translatesAutoresizingMaskIntoConstraints = false
        for v in right.views.prefix(4).dropFirst() { v.widthAnchor.constraint(equalToConstant: 210).isActive = true }; right.views[7].widthAnchor.constraint(equalToConstant: 210).isActive = true
        cv.addSubview(right)
        canvas.ed = self; canvas.translatesAutoresizingMaskIntoConstraints = false; cv.addSubview(canvas)
        // 아래 막대
        let factory = NSButton(title: "초기값으로 설정", target: self, action: #selector(factory)); factory.bezelStyle = .rounded; factory.attributedTitle = NSAttributedString(string: "초기값으로 설정", attributes: [.foregroundColor: YWin.dyn(0.38, 0.72), .font: NSFont.systemFont(ofSize: 13)]); factory.toolTip = "이 규격을 처음 배치로"
        let cancelB = NSButton(title: "취소", target: self, action: #selector(cancel)); cancelB.bezelStyle = .rounded
        let saveB = NSButton(title: "저장", target: self, action: #selector(save)); saveB.bezelStyle = .rounded; saveB.keyEquivalent = "\r"
        let sp = NSView(); sp.setContentHuggingPriority(.init(1), for: .horizontal)
        let bot = NSStackView(views: [factory, sp, cancelB, saveB]); bot.spacing = 10; bot.translatesAutoresizingMaskIntoConstraints = false; cv.addSubview(bot)
        for b in [cancelB, saveB] { b.widthAnchor.constraint(equalToConstant: 90).isActive = true }
        let midBG = YWin.Body(); midBG.translatesAutoresizingMaskIntoConstraints = false; cv.addSubview(midBG, positioned: .below, relativeTo: nil)   // 맨 아래 (오른쪽 칸을 가리지 않게)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: cv.topAnchor, constant: 40), top.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            midBG.topAnchor.constraint(equalTo: cv.topAnchor, constant: 84), midBG.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -60), midBG.leadingAnchor.constraint(equalTo: cv.leadingAnchor), midBG.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: midBG.topAnchor), canvas.bottomAnchor.constraint(equalTo: midBG.bottomAnchor), canvas.leadingAnchor.constraint(equalTo: midBG.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -24),
            right.topAnchor.constraint(equalTo: midBG.topAnchor, constant: 28), right.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28), right.widthAnchor.constraint(equalToConstant: 230),
            bot.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 18), bot.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -18), bot.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14)])
        w.onKey = { [weak self] e in guard let self, e.modifierFlags.contains(.command) else { return false }
            if w.firstResponder is NSTextView { return false }   // 숫자 칸 입력 중엔 기본 동작
            let sh = e.modifierFlags.contains(.shift)
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "c": self.copySel(); case "v": self.paste(); case "j": self.dupSel(); case "x": self.copySel(); self.deleteSel()
            case "a": self.sel = Set(self.L.cells.indices); self.canvas.refresh()
            case "d": self.sel = []; self.canvas.refresh()
            case "z": sh ? self.redo() : self.undo()
            case "s": self.save(); case "w": self.cancel()
            default: return false }
            return true }
    }
    func fillPop() { specPop.removeAllItems(); for n in SettingsController.specOrder { if let sp = Converter.baseSpecs.first(where: { $0.name == n }) { specPop.addItem(withTitle: "\(n)  \(sp.fmt(sp.w))×\(sp.fmt(sp.h)) cm") } else { specPop.addItem(withTitle: "\(n) 인화지") }; specPop.lastItem?.representedObject = n }
        specPop.selectItem(at: SettingsController.specOrder.firstIndex(of: spec) ?? 0) }
    func fill() {
        let l = L; if !(win?.firstResponder is NSTextView) { padF.stringValue = "\(l.pad)"; strokeF.stringValue = "\(l.stroke)"; grayF.stringValue = "\(l.gray)" }
        let sr = sheetRect(l), os = l.cells.map { outer($0, l) }, inside = os.filter { sr.contains($0) }.count, out = os.filter { !$0.intersects(sr) }.count, cut = os.count - inside - out
        countL.stringValue = "\(inside + cut)장 인화" + (out > 0 ? " · 밖에 \(out)장" : "") + " · " + (l.land ? "가로 7×5 in" : "세로 5×7 in") + (sel.isEmpty ? "" : " · \(sel.count)개 고름")
        let ov = overlaps(); var w: [String] = []; if !ov.isEmpty { w.append("겹친 사진이 있어요") }; if cut > 0 { w.append("인화지에 걸쳐 잘리는 사진이 있어요") }
        warnL.stringValue = w.joined(separator: "\n"); warnL.isHidden = w.isEmpty
        undoB?.isEnabled = !undoS.isEmpty; redoB?.isEnabled = !redoS.isEmpty
        let lg = sel.filter { $0 < l.cells.count && l.cells[$0].kind == "logo" }.sorted(); logoHF.isEnabled = !lg.isEmpty
        if !(win?.firstResponder is NSTextView) { logoHF.stringValue = lg.first.map { DesignCanvas.cm(CGFloat(l.cells[$0].lh ?? 71)) } ?? "" } }
    func changed() { fixSel(); fill(); canvas.refresh() }
    func fixSel() { let n = L.cells.count; sel = sel.filter { $0 >= 0 && $0 < n } }   // 고른 번호가 칸 수를 넘지 않게 (실행 취소·규격 바꾸기 뒤 충돌 방지)
    func record() { undoS.append((lays, spec, sel)); if undoS.count > 300 { undoS.removeFirst() }; redoS = [] }
    @objc func undo() { guard let u = undoS.popLast() else { NSSound.beep(); return }; redoS.append((lays, spec, sel)); lays = u.0; spec = u.1; sel = u.2; fillPop(); changed() }
    @objc func redo() { guard let u = redoS.popLast() else { NSSound.beep(); return }; undoS.append((lays, spec, sel)); lays = u.0; spec = u.1; sel = u.2; fillPop(); changed() }
    @objc func popChanged() { if let n = specPop.selectedItem?.representedObject as? String { switchSpec(n) } }
    func switchSpec(_ n: String) { guard n != spec else { return }; spec = n; sel = []; fillPop(); changed() }
    // ── 모양 계산
    func outer(_ c: YCell, _ l: YLayout? = nil) -> CGRect { let l = l ?? L, (w, h) = Sheet.size(spec, c, style); return CGRect(x: c.x - l.pad, y: c.y - l.pad, width: w + 2 * l.pad, height: h + 2 * l.pad) }
    func clamped(_ c: YCell, _ l: YLayout) -> YCell {   // 칸이 판(인화지 + 둘레 놓아 두는 자리) 밖으로 못 나감 · 인화지 밖에 둔 칸은 인화 안 됨
        let b = board(l), o = outer(c, l); var c = c
        if o.minX < b.minX { c.x += Int(b.minX - o.minX) } else if o.maxX > b.maxX { c.x -= Int(o.maxX - b.maxX) }
        if o.minY < b.minY { c.y += Int(b.minY - o.minY) } else if o.maxY > b.maxY { c.y -= Int(o.maxY - b.maxY) }
        return c }
    func overlaps() -> Set<Int> { let cs = L.cells; var s = Set<Int>(); for i in cs.indices { for j in cs.indices where j > i { let r = outer(cs[i]).intersection(outer(cs[j])); if !r.isNull && r.width > 0.5 && r.height > 0.5 { s.insert(i); s.insert(j) } } }; return s }
    // ── 동작
    @objc func rotateSel() {   // 고른 사진 90° (가운데 기준) · 안 골랐으면 전부
        fixSel(); let idx = sel.isEmpty ? Set(L.cells.indices) : sel; guard !idx.isEmpty else { return }; record(); var l = L
        for i in idx { let c = l.cells[i], (w, h) = Sheet.size(spec, c, style), cx = c.x + w / 2, cy = c.y + h / 2; var n = c; n.q = (c.q + 1) % 4; let (w2, h2) = Sheet.size(spec, n, style); n.x = cx - w2 / 2; n.y = cy - h2 / 2; l.cells[i] = clamped(n, l) }
        L = l; changed() }
    @objc func rotateSheet() {   // 인화지 시계 방향 90° (사진도 같이 돔)
        record(); var l = L; let (_, H) = Sheet.sheetWH(l); l.land.toggle()
        l.cells = l.cells.map { c in let (_, h) = Sheet.size(spec, c, style); var n = c; n.x = H - c.y - h; n.y = c.x; n.q = (c.q + 1) % 4; return n }
        l.cells = l.cells.map { clamped($0, l) }; L = l; changed() }
    @objc func addSig() { record(); var l = L; let (W, H) = Sheet.sheetWH(l), (w, h) = Sheet.size(spec, YCell(x: 0, y: 0, q: 0, sig: true), style); l.cells.append(clamped(YCell(x: (W - w) / 2, y: (H - h) / 2, q: 0, sig: true), l)); sel = [l.cells.count - 1]; L = l; changed() }
    @objc func addLogo() { record(); var l = L; var c = YCell(x: 0, y: 0, q: 0); c.kind = "logo"; c.lh = 71; let (W, H) = Sheet.sheetWH(l), (w, h) = Sheet.size(spec, c, style); c.x = (W - w) / 2; c.y = (H - h) / 2; l.cells.append(clamped(c, l)); sel = [l.cells.count - 1]; L = l; changed() }   // 로고만 (기본 높이 0.6 cm)
    @objc func addFrameCell(_ b: NSButton) {   // 프레임 사진: 프레임이 여럿이면 골라서
        let fs = owner?.draft?.s.frames ?? []
        guard !fs.isEmpty else { if let w = win { let a = NSAlert(); a.messageText = "프레임이 없어요"; a.informativeText = "ydot 창 › 프레임 탭에서 프레임을 먼저 추가해 주세요."; a.beginSheetModal(for: w, completionHandler: nil) }; return }
        if fs.count == 1 { addFrame(fs[0].id); return }
        let m = NSMenu(); for f in fs { let it = NSMenuItem(title: f.name, action: #selector(frameMenu(_:)), keyEquivalent: ""); it.target = self; it.representedObject = f.id; if let t = Sheet.frameThumb(YSettings.frameDir.appendingPathComponent(f.file).path) { t.size = NSSize(width: 18 * t.size.width / max(1, t.size.height), height: 18); it.image = t }; m.addItem(it) }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height + 4), in: b) }
    @objc func frameMenu(_ it: NSMenuItem) { if let id = it.representedObject as? String { addFrame(id) } }
    func addFrame(_ id: String) { record(); var l = L; var c = YCell(x: 0, y: 0, q: 0); c.kind = "frame"; c.fid = id; let (W, H) = Sheet.sheetWH(l), (w, h) = Sheet.size(spec, c, style); c.x = (W - w) / 2; c.y = (H - h) / 2; l.cells.append(clamped(c, l)); sel = [l.cells.count - 1]; L = l; changed() }
    @objc func addCell() { record(); var l = L; let (W, H) = Sheet.sheetWH(l), (w, h) = Sheet.cellWH(spec, 0); l.cells.append(clamped(YCell(x: (W - w) / 2, y: (H - h) / 2, q: 0), l)); sel = [l.cells.count - 1]; L = l; changed() }
    @objc func copySel() { fixSel(); let cs = L.cells; clip = sel.sorted().compactMap { $0 < cs.count ? cs[$0] : nil } }
    @objc func paste() { guard !clip.isEmpty else { NSSound.beep(); return }; record(); var l = L; let start = l.cells.count
        for c in clip { var n = c; n.x += 40; n.y += 40; l.cells.append(clamped(n, l)) }; clip = clip.map { var n = $0; n.x += 40; n.y += 40; return n }
        sel = Set(start..<l.cells.count); L = l; changed() }
    @objc func dupSel() { guard !sel.isEmpty else { NSSound.beep(); return }; copySel(); paste() }
    @objc func deleteSel() { fixSel(); guard !sel.isEmpty else { NSSound.beep(); return }; record(); var l = L; l.cells = l.cells.enumerated().filter { !sel.contains($0.offset) }.map(\.element); sel = []; L = l; changed() }
    func nudge(_ dx: Int, _ dy: Int) { fixSel(); guard !sel.isEmpty else { return }; record(); var l = L; for i in sel { var c = l.cells[i]; c.x += dx; c.y += dy; l.cells[i] = clamped(c, l) }; L = l; changed() }
    func center(_ horiz: Bool) {
        fixSel(); let idx = sel.isEmpty ? Set(L.cells.indices) : sel; guard !idx.isEmpty else { return }; record(); var l = L; let (W, H) = Sheet.sheetWH(l)
        let bb = idx.map { outer(l.cells[$0], l) }.reduce(CGRect.null) { $0.union($1) }
        let d = horiz ? Int(((CGFloat(W) - bb.width) / 2 - bb.minX).rounded()) : Int(((CGFloat(H) - bb.height) / 2 - bb.minY).rounded())
        for i in idx { if horiz { l.cells[i].x += d } else { l.cells[i].y += d } }; L = l; changed() }
    @objc func centerH() { center(true) }
    @objc func centerV() { center(false) }
    @objc func fieldEdited(_ f: NSTextField) {
        if f === logoHF { let v = Double(f.stringValue.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? -1; fixSel()   // 고른 로고 칸 높이 (cm)
            let idx = sel.filter { L.cells[$0].kind == "logo" }; guard v > 0, !idx.isEmpty else { fill(); return }; record(); var l = L
            for i in idx { var c = l.cells[i]; let (w0, h0) = Sheet.size(spec, c, style); c.lh = max(8, min(1200, Int((v / 2.54 * 300).rounded()))); let (w1, h1) = Sheet.size(spec, c, style); c.x += (w0 - w1) / 2; c.y += (h0 - h1) / 2; l.cells[i] = clamped(c, l) }
            L = l; changed(); return }
        let v = Int(f.stringValue.trimmingCharacters(in: .whitespaces)) ?? -1; var l = L
        if f === padF { guard v >= 0 else { fill(); return }; l.pad = min(120, v) } else if f === strokeF { guard v >= 0 else { fill(); return }; l.stroke = min(30, v) } else { guard v >= 0 else { fill(); return }; l.gray = min(255, v) }
        guard l != L else { fill(); return }; record(); l.cells = l.cells.map { clamped($0, l) }; L = l; changed() }
    @objc func factory() { record(); L = Sheet.defaultLayout(spec); sel = []; changed() }
}
final class SheetCanvas: NSView {   // 인화지 판: 끌기(스마트 안내선) · 빈 곳 끌기 = 범위 선택 · ⇧클릭 · ⌥끌기 = 복제 · 방향키 1px(⇧ 10px) · R 회전 · ⌫ 빼기 · Esc 닫기
    weak var ed: LayoutEditor?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var img: CGImage?, k: CGFloat = 1, org = CGPoint.zero
    var guides: [(Bool, CGFloat)] = []   // (세로선?, 인화지 px)
    var dragFrom: CGPoint?, startCells: [Int: YCell] = [:], moved = false, marquee: CGRect?, marqueeBase: Set<Int> = []
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); refresh() }
    func fit() { guard let ed else { return }; let (W, H) = Sheet.sheetWH(ed.L), b = ed.board(), m: CGFloat = 20
        k = max(0.05, min((bounds.width - m * 2) / b.width, (bounds.height - m * 2) / b.height)); org = CGPoint(x: ((bounds.width - CGFloat(W) * k) / 2).rounded(), y: ((bounds.height - CGFloat(H) * k) / 2).rounded()) }   // 인화지가 가운데, 둘레에 놓아 두는 자리
    func refresh() { guard let ed, bounds.width > 10 else { return }; fit()
        var dim = CGColor(gray: 0.84, alpha: 0.6); effectiveAppearance.performAsCurrentDrawingAppearance { dim = YWin.dyn(0.84, 0.1).withAlphaComponent(0.6).cgColor }
        if let p = ed.photo(ed.spec) { img = Sheet.render(p, ed.L, ed.spec, scale: min(1, k * (window?.backingScaleFactor ?? 2)), style: ed.style, board: ed.board(), dim: dim) }; needsDisplay = true }
    func vr(_ o: CGRect) -> NSRect { NSRect(x: org.x + o.minX * k, y: org.y + o.minY * k, width: o.width * k, height: o.height * k) }
    func toSheet(_ e: NSEvent) -> CGPoint { let p = convert(e.locationInWindow, from: nil); return CGPoint(x: (p.x - org.x) / k, y: (p.y - org.y) / k) }
    func hit(_ p: CGPoint) -> Int? { guard let ed else { return nil }; return ed.L.cells.indices.reversed().first { ed.outer(ed.L.cells[$0]).contains(p) } }
    override func draw(_ r: NSRect) {
        YWin.dyn(0.84, 0.1).setFill(); bounds.fill()
        guard let ed, let img else { return }; let (W, H) = Sheet.sheetWH(ed.L), sr = NSRect(x: org.x, y: org.y, width: CGFloat(W) * k, height: CGFloat(H) * k)
        NSGraphicsContext.saveGraphicsState(); let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.28); sh.shadowBlurRadius = 14; sh.shadowOffset = NSSize(width: 0, height: -4); sh.set(); NSColor.white.setFill(); sr.fill(); NSGraphicsContext.restoreGraphicsState()
        let br = vr(ed.board()); NSImage(cgImage: img, size: br.size).draw(in: br, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let sl = NSBezierPath(rect: sr.insetBy(dx: -0.5, dy: -0.5)); sl.lineWidth = 1; NSColor.black.withAlphaComponent(0.12).setStroke(); sl.stroke()   // 인화지 가장자리
        for i in ed.overlaps() { NSColor.systemRed.withAlphaComponent(0.28).setFill(); vr(ed.outer(ed.L.cells[i])).fill() }
        for i in ed.sel where i < ed.L.cells.count { let p = NSBezierPath(rect: vr(ed.outer(ed.L.cells[i])).insetBy(dx: 1, dy: 1)); p.lineWidth = 2; NSColor.controlAccentColor.setStroke(); p.stroke() }
        NSColor.systemPink.setStroke()
        for (v, pos) in guides { let p = NSBezierPath(); if v { let x = org.x + pos * k; p.move(to: NSPoint(x: x, y: sr.minY)); p.line(to: NSPoint(x: x, y: sr.maxY)) } else { let y = org.y + pos * k; p.move(to: NSPoint(x: sr.minX, y: y)); p.line(to: NSPoint(x: sr.maxX, y: y)) }; p.lineWidth = 1; p.stroke() }
        if let m = marquee { let p = NSBezierPath(rect: vr(m)); p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); NSColor.labelColor.withAlphaComponent(0.7).setStroke(); p.stroke(); NSColor.controlAccentColor.withAlphaComponent(0.08).setFill(); p.fill() }
    }
    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self); guard let ed else { return }; ed.fixSel(); let p = toSheet(e), shift = e.modifierFlags.contains(.shift)
        moved = false; guides = []
        if let i = hit(p) {
            if shift { if ed.sel.contains(i) { ed.sel.remove(i) } else { ed.sel.insert(i) } } else if !ed.sel.contains(i) { ed.sel = [i] }
            if e.modifierFlags.contains(.option), !ed.sel.isEmpty {   // ⌥끌기 = 복제해서 끌기 (포토샵처럼)
                ed.record(); var l = ed.L; let start = l.cells.count; for j in ed.sel.sorted() { l.cells.append(l.cells[j]) }; ed.sel = Set(start..<l.cells.count); ed.L = l; moved = true }
            dragFrom = ed.sel.isEmpty ? nil : p; startCells = Dictionary(uniqueKeysWithValues: ed.sel.map { ($0, ed.L.cells[$0]) })
        } else { dragFrom = nil; marquee = CGRect(origin: p, size: .zero); marqueeKeep = p; marqueeBase = shift ? ed.sel : []; if !shift { ed.sel = [] } }
        ed.changed() }
    override func mouseDragged(with e: NSEvent) {
        guard let ed else { return }; let p = toSheet(e)
        if marquee != nil { let a = marqueeKeep, r = CGRect(x: min(a.x, p.x), y: min(a.y, p.y), width: abs(p.x - a.x), height: abs(p.y - a.y)); marquee = r
            ed.sel = marqueeBase.union(Set(ed.L.cells.indices.filter { ed.outer(ed.L.cells[$0]).intersects(r) })); ed.fill(); needsDisplay = true; return }
        guard let from = dragFrom, !startCells.isEmpty else { return }
        if !moved { ed.record(); moved = true }
        var l = ed.L; let (W, H) = Sheet.sheetWH(l), bd = ed.board(l); var dx = p.x - from.x, dy = p.y - from.y
        let bb0 = startCells.values.map { ed.outer($0, l) }.reduce(CGRect.null) { $0.union($1) }
        var bb = bb0.offsetBy(dx: dx, dy: dy); guides = []
        if !e.modifierFlags.contains(.command) {   // 스마트 안내선: 인화지 가장자리·가운데, 다른 사진 가장자리·가운데 (⌘ 누르면 끔)
            let thr = 7 / k, others = l.cells.indices.filter { startCells[$0] == nil }.map { ed.outer(l.cells[$0], l) }
            let xs: [CGFloat] = [0, CGFloat(W) / 2, CGFloat(W)] + others.flatMap { (o: CGRect) -> [CGFloat] in [o.minX, o.midX, o.maxX] }, ys: [CGFloat] = [0, CGFloat(H) / 2, CGFloat(H)] + others.flatMap { (o: CGRect) -> [CGFloat] in [o.minY, o.midY, o.maxY] }
            func best(_ edges: [CGFloat], _ cands: [CGFloat]) -> (CGFloat, CGFloat)? { var b: (CGFloat, CGFloat)?; for ed in edges { for c in cands where abs(c - ed) < thr && (b == nil || abs(c - ed) < abs(b!.0)) { b = (c - ed, c) } }; return b }
            if let (a, c) = best([bb.minX, bb.midX, bb.maxX], xs) { dx += a; guides.append((true, c)) }
            if let (a, c) = best([bb.minY, bb.midY, bb.maxY], ys) { dy += a; guides.append((false, c)) }
            bb = bb0.offsetBy(dx: dx, dy: dy) }
        if bb.minX < bd.minX { dx += bd.minX - bb.minX } else if bb.maxX > bd.maxX { dx -= bb.maxX - bd.maxX }   // 판 밖으로는 못 나감 (인화지 밖은 됨)
        if bb.minY < bd.minY { dy += bd.minY - bb.minY } else if bb.maxY > bd.maxY { dy -= bb.maxY - bd.maxY }
        let ix = Int(dx.rounded()), iy = Int(dy.rounded())
        for (i, c) in startCells where i < l.cells.count { var n = c; n.x += ix; n.y += iy; l.cells[i] = n }
        ed.L = l; ed.changed() }
    var marqueeKeep = CGPoint.zero
    override func mouseUp(with e: NSEvent) { marquee = nil; guides = []; dragFrom = nil; startCells = [:]; ed?.changed() }
    override func keyDown(with e: NSEvent) {
        guard let ed else { return }; let n = e.modifierFlags.contains(.shift) ? 10 : 1
        switch e.keyCode {
        case 123: ed.nudge(-n, 0); case 124: ed.nudge(n, 0); case 125: ed.nudge(0, n); case 126: ed.nudge(0, -n)
        case 51, 117: ed.deleteSel()
        case 53: ed.cancel()
        default: if e.charactersIgnoringModifiers?.lowercased() == "r" { ed.rotateSel() } else { super.keyDown(with: e) } } }
}

// MARK: - 실행

// 창 없이 변환만 확인: Donut --selftest <입력 폴더> <출력 폴더>
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--selftest" {
    let input = URL(fileURLWithPath: CommandLine.arguments[2]), output = URL(fileURLWithPath: CommandLine.arguments[3])
    let files = (try? FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)) ?? []
    for f in files.sorted(by: { $0.path < $1.path }) where !f.lastPathComponent.hasPrefix(".") {
        for a in Action.allCases {
            let t0 = CACurrentMediaTime()
            let forced = ProcessInfo.processInfo.environment["DONUT_WEBSPEC"].flatMap { n in Converter.webSpecs.first { $0.name == n } }
            if a == .web, forced != nil { let r2 = Converter.run(a, source: f, destFolder: output, staging: output, webSpec: forced, webHigh: true); if case .made(let u, _) = r2 { print("\(f.lastPathComponent)\t\(a.title) 고화질\t\(u.lastPathComponent)") } }
            let r = Converter.run(a, source: f, destFolder: output, staging: output, webSpec: forced)
            let ms = Int((CACurrentMediaTime() - t0) * 1000)
            switch r {
            case .made(let u, _): print("\(f.lastPathComponent)\t\(a.title)\t\(u.lastPathComponent)\t\(ms)ms")
            case .failed(_, let why): print("\(f.lastPathComponent)\t\(a.title)\t실패: \(why)")
            }
        }
    }
    exit(0)
}

// 얼굴 인식 확인 시트용: Donut --headtest <입력 폴더> <출력 폴더> → 각 사진에 정수리(빨강)·턱(파랑)·얼굴 가운데·증명 자를 자리(초록) 표시한 JPG + 결과 줄
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--headtest" {
    let input = URL(fileURLWithPath: CommandLine.arguments[2]), output = URL(fileURLWithPath: CommandLine.arguments[3])
    let files = ((try? FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)) ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.path < $1.path }
    for f in files {
        guard let src = CGImageSourceCreateWithURL(f as CFURL, nil), let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { print("\(f.lastPathComponent)\t읽기 실패"); continue }
        let n = Converter.faceCount(img), hl = Converter.headLine(img), W = img.width, H = img.height
        var status = n == 1 ? "ok" : "얼굴 \(n)개"; if W > H { status = "가로" }; if hl == nil { status += " / 정수리·턱 못 찾음" }
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        if let h = hl {
            let lw = max(2.0, Double(W) / 300)
            func hline(_ y: Double, _ c: CGColor) { ctx.setStrokeColor(c); ctx.setLineWidth(lw); ctx.move(to: CGPoint(x: 0, y: Double(H) - y)); ctx.addLine(to: CGPoint(x: Double(W), y: Double(H) - y)); ctx.strokePath() }
            hline(h.crown, CGColor(red: 1, green: 0.15, blue: 0.15, alpha: 1)); hline(h.chin, CGColor(red: 0.1, green: 0.45, blue: 1, alpha: 1))
            ctx.setStrokeColor(CGColor(red: 1, green: 0.8, blue: 0, alpha: 0.9)); ctx.setLineWidth(lw * 0.6); ctx.move(to: CGPoint(x: h.cx, y: 0)); ctx.addLine(to: CGPoint(x: h.cx, y: Double(H))); ctx.strokePath()
            let sp = Converter.webSpecs[0], k = Converter.cmPx(sp.headCm) / (h.chin - h.crown), (tw, th) = sp.px, cw = Double(tw) / k, ch = Double(th) / k
            let x = h.cx - cw / 2, y = h.crown - Converter.cmPx(sp.topCm) / k
            ctx.setStrokeColor(CGColor(red: 0.1, green: 0.85, blue: 0.3, alpha: 1)); ctx.setLineWidth(lw); ctx.stroke(CGRect(x: x, y: Double(H) - y - ch, width: cw, height: ch))
            status += String(format: "\t얼굴높이 %.0f%%\t%.0f\t%.0f\t%.0f\t%d\t%d", (h.chin - h.crown) / Double(H) * 100, h.crown, h.chin, h.cx, W, H)
        }
        if let out = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(output.appendingPathComponent(f.deletingPathExtension().lastPathComponent + ".jpg") as CFURL, "public.jpeg" as CFString, 1, nil) { CGImageDestinationAddImage(d, out, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary); CGImageDestinationFinalize(d) }
        print("\(f.lastPathComponent)\t\(status)"); fflush(stdout)
    }
    exit(0)
}

// 파인더 복사만 확인: Donut --copytest <놓을 폴더> <임시 파일들>
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--copytest" {
    FinderCopy.run(CommandLine.arguments[3...].map { URL(fileURLWithPath: $0) }, to: URL(fileURLWithPath: CommandLine.arguments[2])) { made, failed in
        print("만듦:", made.map(\.lastPathComponent), "실패:", failed)
        exit(0)
    }
    dispatchMain()
}

if let out = ProcessInfo.processInfo.environment["DONUT_PREVIEW"] {   // 시험용: 카드 패널만 그려 PNG로 (DONUT_PREVIEW_PHOTO = 썸네일용 사진 한 장)
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let sc = NSScreen.main!.frame; let rect = NSRect(x: sc.midX - panelW / 2 - 30, y: sc.midY - listH / 2 - 30, width: panelW + 60, height: listH + 60)
    let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false); p.isOpaque = false; p.backgroundColor = .clear
    p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1); p.ignoresMouseEvents = true
    let host = NSView(frame: NSRect(origin: .zero, size: rect.size)); p.contentView = host
    if let t = ProcessInfo.processInfo.environment["DONUT_CARD_THEME"] { UserDefaults.standard.set(t, forKey: "cardTheme") }
    let bg = NSView(frame: NSRect(origin: .zero, size: rect.size)); bg.wantsLayer = true; let g = CAGradientLayer(); g.frame = bg.bounds; g.colors = [NSColor(srgbRed: 0.66, green: 0.74, blue: 0.84, alpha: 1).cgColor, NSColor(srgbRed: 0.3, green: 0.34, blue: 0.42, alpha: 1).cgColor]; bg.layer?.addSublayer(g); host.addSubview(bg)
    let sc0 = CGFloat(Double(ProcessInfo.processInfo.environment["DONUT_PREVIEW_SCALE"] ?? "1") ?? 1)   // 시험: 패널 크기 배율 (fitHolder와 같은 방식)
    let holder = NSView(frame: NSRect(x: 30 - btnM * sc0, y: 30 - btnM * sc0, width: (panelW + btnM * 2) * sc0, height: (listH + btnM * 2) * sc0)); holder.bounds = NSRect(x: 0, y: 0, width: panelW + btnM * 2, height: listH + btnM * 2); host.addSubview(holder)
    let l = SizeListView(frame: NSRect(x: btnM, y: btnM, width: panelW, height: listH)); holder.addSubview(l); l.setHover(0)
    if let pv = ProcessInfo.processInfo.environment["DONUT_PREVIEW_PHOTO"], let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: pv) as CFURL, nil),
       let b = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
        for (i, sp) in Converter.webSpecs.enumerated() { let (_, o, _) = Converter.webSized(b, want: sp, high: false, key: URL(fileURLWithPath: pv)); l.setThumb(i, NSImage(cgImage: o, size: NSSize(width: o.width, height: o.height))) } }
    p.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(p.windowNumber), "-x", "-o", "-t", "png", out]; try? c.run(); c.waitUntilExit(); exit(0) }
    app.run()
}
// 포토샵 연동 (ydot 가이드.jsx · ydot 인화.jsx가 부름)
//  Donut --psguide <사진> <결과파일>  : 카드 패널 → 얼굴 크기 조절 → Save → 자를 자리(원본 px)를 결과파일에
//  Donut --pscrop <사진> <규격 이름> <얼굴cm> <위여백cm> <저장 폴더> <결과파일> : 창 없이 고화질·저화질 만들기
if CommandLine.arguments.count == 8, CommandLine.arguments[1] == "--pscrop" {
    let a = CommandLine.arguments, u = URL(fileURLWithPath: a[2]), dest = URL(fileURLWithPath: a[6], isDirectory: true), out = a[7]
    guard var sp = Converter.webSpecs.first(where: { $0.name == a[3] }), let head = Double(a[4]), let top = Double(a[5]) else { Converter.writeResult(out, [("ok", "0"), ("reason", "규격 정보가 잘못됐어요.")]); exit(0) }
    guard head >= 1.0, head <= 5.0, top >= 0, top <= 1.5 else { Converter.writeResult(out, [("ok", "0"), ("reason", "얼굴 크기·위 여백 값이 범위를 벗어났어요.")]); exit(0) }
    sp.headCm = head; sp.topCm = top
    let (_, why) = Converter.psCheck(u)
    if let why { Converter.writeResult(out, [("ok", "0"), ("reason", why)]); exit(0) }
    var made: [(String, String)] = []
    for high in [true, false] {
        switch Converter.run(.web, source: u, destFolder: dest, staging: dest, webSpec: sp, webHigh: high) {
        case .made(let f, _): made.append((high ? "high" : "low", f.path))
        case .failed(_, let why): Converter.writeResult(out, [("ok", "0"), ("reason", "변환 실패: " + why)]); exit(0)
        }
    }
    Converter.writeResult(out, [("ok", "1")] + made); exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
final class AppDelegate: NSObject, NSApplicationDelegate {   // 켜진 ydot을 다시 누르면 (Finder·Dock·Launchpad) = 'ydot' 창
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool { controller.openMain(); return true }
}
let appDelegate = AppDelegate(); app.delegate = appDelegate
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--sheettest" {   // 시험: 사진 한 장으로 Custom 인화지만 만들어 PNG로 (창 없음)
    let u = URL(fileURLWithPath: CommandLine.arguments[2])
    if let src = CGImageSourceCreateWithURL(u as CFURL, nil), let im = CGImageSourceCreateImageAtIndex(src, 0, nil),
       let c1 = im.cropping(to: CGRect(x: 0, y: 0, width: im.width, height: min(im.height, im.width * 7 / 5))),
       let c2 = im.cropping(to: CGRect(x: im.width / 5, y: im.height / 30, width: im.width * 3 / 5, height: im.width * 3 / 5 * 45 / 35)),
       let sh = Sheet.make(polaroid: c1, small: c2) { try? Sheet.writePNG(sh, URL(fileURLWithPath: CommandLine.arguments[3])); print("ok") }
    exit(0)
}
//  Donut --pscustom <포토샵에서 내보낸 사진> : 포토샵 인화에서 Custom을 골랐을 때 (스크립트가 끝난 뒤 따로 실행됨 → 포토샵에 인화지를 열 수 있음)
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--pscustom" {
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async { controller.startCustomOnly(URL(fileURLWithPath: CommandLine.arguments[2])) }
    if ProcessInfo.processInfo.environment["DONUT_PSCUSTOM_AUTO"] != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { controller.customView.doSave(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { controller.customView.doSave() } } }   // 시험: 1차·2차 저장 자동
    DispatchQueue.main.asyncAfter(deadline: .now() + 3600) { if !controller.customSaving { controller.endPick() } }   // 1시간 그대로면 닫음
    app.run()
}
if (CommandLine.arguments.count == 4 || CommandLine.arguments.count == 7), CommandLine.arguments[1] == "--psguide" {   // 7개면 + 규격 이름·얼굴·여백 (그 규격 조절 화면으로 바로)
    controller.psOut = CommandLine.arguments[3]; specSide = "ps"
    if CommandLine.arguments.count == 7, let i = Converter.webSpecs.firstIndex(where: { $0.name == CommandLine.arguments[4] }), let h = Double(CommandLine.arguments[5]), let t = Double(CommandLine.arguments[6]) { controller.psPreset = (i, h, t) }
    let m = NSEvent.mouseLocation; controller.panel.setFrameOrigin(NSPoint(x: m.x - donutSize / 2, y: m.y - donutSize / 2))   // 패널은 커서 자리에
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async { if !controller.beginPick([URL(fileURLWithPath: CommandLine.arguments[2])]) { controller.unusable("사진을 읽지 못했어요.") } }
    if let v = ProcessInfo.processInfo.environment["DONUT_PSAUTO"], v != "custom" {   // 시험 전용: 3초 뒤 증명 → 2초 뒤 Save
        let hadPreset = controller.psPreset != nil, autoIdx = Int(ProcessInfo.processInfo.environment["DONUT_PSAUTO"] ?? "") ?? 0; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if !hadPreset { controller.pick(autoIdx) }; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { controller.adjustView.doSave() } } }
    if ProcessInfo.processInfo.environment["DONUT_PSAUTO"] == "custom" { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { controller.beginCustom(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { controller.customView.goBack(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { debugLog("뒤로 뒤 화면 \(controller.mode)"); controller.beginCustom(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { controller.customView.doSave(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { controller.customView.doSave() } } } } } }   // 시험: 포토샵 Custom → 뒤로 → 다시 Custom → 저장 두 번
    if ProcessInfo.processInfo.environment["DONUT_PSAUTO"] == "cancel" { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { controller.endPick() } }   // 시험: 취소
    DispatchQueue.main.asyncAfter(deadline: .now() + 1800) { controller.endPick() }   // 30분 동안 아무것도 안 하면 취소로 끝 (포토샵이 계속 기다리지 않게)
    app.run()
}
controller.setUpMenu()
if let out = ProcessInfo.processInfo.environment["DONUT_BTNPREVIEW"] {   // 미리보기: 진짜 맥 기본 버튼 · 지금 Save · 네이티브 Save (밝게·다크 창 따로 — 기본 버튼은 창마다 하나)
    DispatchQueue.main.async {
        var wins: [NSWindow] = []
        for (row, ap) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 350), styleMask: [.titled], backing: .buffered, defer: false); w.title = row == 0 ? "밝게" : "다크"; w.appearance = NSAppearance(named: ap)
            let band = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 350)); band.wantsLayer = true; w.contentView = band
            let c = panelColors(row == 0 ? "sidebar" : "dark"); band.layer?.backgroundColor = c.bg.cgColor
            let bar = NSView(frame: NSRect(x: 16, y: 34, width: 608, height: 70)); bar.wantsLayer = true; bar.layer?.cornerRadius = 16; bar.layer?.backgroundColor = c.btn.cgColor; band.addSubview(bar)
            let nat = NSButton(title: "Save", target: nil, action: nil); nat.bezelStyle = .rounded; nat.controlSize = .large; nat.keyEquivalent = "\r"; nat.sizeToFit(); nat.frame.origin = NSPoint(x: 60, y: (70 - nat.frame.height) / 2); bar.addSubview(nat)
            let cur = PillButton("Save", target: nil, action: #selector(NSObject.description)); cur.nativeBlue = false; cur.frame = NSRect(x: 260, y: 18, width: 72, height: 34); cur.layer?.cornerRadius = 17; bar.addSubview(cur); cur.style(c, primary: true)
            let nw = PillButton("Save", target: nil, action: #selector(NSObject.description)); nw.nativeBlue = true; nw.frame = NSRect(x: 460, y: 18, width: 72, height: 34); nw.layer?.cornerRadius = 17; bar.addSubview(nw); nw.style(c, primary: true)
            let bar2 = NSView(frame: NSRect(x: 16, y: 34 + 110, width: 608, height: 70)); bar2.wantsLayer = true; bar2.layer?.cornerRadius = 16; bar2.layer?.backgroundColor = c.btn.cgColor; band.addSubview(bar2)
            let nat2 = NSButton(title: "Default", target: nil, action: nil); nat2.bezelStyle = .rounded; nat2.controlSize = .large; nat2.sizeToFit(); nat2.frame.origin = NSPoint(x: 50, y: (70 - nat2.frame.height) / 2); bar2.addSubview(nat2)
            let cur2 = PillButton("Default", hint: "⌘0", target: nil, action: #selector(NSObject.description)); cur2.frame = NSRect(x: 250, y: 22, width: cur2.fitWidth(), height: 26); bar2.addSubview(cur2); cur2.style(c)
            let nat3 = NSButton(title: "Default", target: nil, action: nil); nat3.bezelStyle = .rounded; nat3.controlSize = .large; nat3.sizeToFit(); nat3.frame.origin = NSPoint(x: 460, y: (70 - nat3.frame.height) / 2); bar.superview?.addSubview(NSView()); band.addSubview(nat3); nat3.frame.origin = NSPoint(x: 476, y: 144 + (70 - nat3.frame.height) / 2); nat3.isHidden = true
            let pane = NSView(frame: NSRect(x: 16, y: 34 + 220, width: 608, height: 70)); pane.wantsLayer = true; pane.layer?.cornerRadius = 16; pane.layer?.backgroundColor = c.bg.cgColor; band.addSubview(pane)
            let nat4 = NSButton(title: "← 뒤로", target: nil, action: nil); nat4.bezelStyle = .rounded; nat4.controlSize = .large; nat4.sizeToFit(); nat4.frame.origin = NSPoint(x: 50, y: (70 - nat4.frame.height) / 2); pane.addSubview(nat4)
            let cur4 = PillButton("← 뒤로", target: nil, action: #selector(NSObject.description)); cur4.frame = NSRect(x: 250, y: 22, width: cur4.fitWidth(66), height: 26); pane.addSubview(cur4); cur4.style(c)
            for (x, t) in [(46, "① 진짜 맥 버튼"), (250, "② ydot 새 버튼"), (440, "③ 새 Save")] { let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 11); l.textColor = c.sub; l.sizeToFit(); l.frame.origin = NSPoint(x: CGFloat(x), y: 10); band.addSubview(l) }
            w.setFrameOrigin(NSPoint(x: 300 + row * 20, y: 300)); wins.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        func cap(_ k: Int) { let w = wins[k]; w.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", out.replacingOccurrences(of: ".png", with: k == 0 ? "_light.png" : "_dark.png")]; try? c.run(); c.waitUntilExit()
                if k == 0 { cap(1) } else { exit(0) } } }
        cap(0) }
} else if ProcessInfo.processInfo.environment["DONUT_NAMELOGIC"] != nil {   // 시험: 파일 이름 칸 (화면 안 씀 · DONUT_SETTINGS_PATH 필수)
    DispatchQueue.main.async { let s = controller.settings; s.build(); s.saved = s.current(); s.draft = s.saved; s.resetHist(); s.showTab("gen")
        func put(_ k: String, _ v: String) { let f = s.nameFields[k]!; f.stringValue = v; s.nameEdited(f) }
        put("high", "HQ"); print("NL 고화질→HQ: 바로 적용 \(FileNames.current().high)(HQ) 파일 \(YSettings.load().fileName("high"))(HQ)")
        put("low", "hq"); print("NL 저화질→hq(같은 이름): 막힘 \(FileNames.current().low)(저화질)")
        put("original", "  ../원본:사진/ "); print("NL 못 쓰는 글자 빼기 → '\(FileNames.current().original)'(원본사진)")
        put("crop", ""); print("NL 비우면 기본 → \(FileNames.current().crop)(crop)")
        s.doUndo(); print("NL 되돌리기 → 원본 \(FileNames.current().original)(original)")
        s.namesDefaults(); print("NL 기본값 → \(FileNames.current().high)(고화질)")
        fflush(stdout); exit(0) }
} else if ProcessInfo.processInfo.environment["DONUT_SWITCHTEST"] != nil {   // 시험: 기본 탭 규격 바꾸기 전환 (화면 녹화로 봄)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.openMain(); let m = controller.settings; m.showTab("desk")
        if let w = m.win { w.setFrameOrigin(NSPoint(x: 60, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - w.frame.height - 20)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { m.selectSpec("Custom")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { m.selectSpec("반명함"); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { let h0 = m.win.frame.height; m.win.zoom(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { print("SW 확대: 높이 \(Int(h0)) → \(Int(m.win.frame.height)) · 폭 \(Int(m.win.frame.width)) · 화면 \(Int(m.win.screen?.visibleFrame.height ?? 0))"); exit(0) } } } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_CUSTSPEC"] {   // 시험: 기본 탭 규격 박스 Custom (가로·세로)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.openMain(); let m = controller.settings; m.showTab("desk")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { m.selectSpec("Custom"); m.cwSl.doubleValue = 4; m.chSl.doubleValue = 5; m.customSizeSlid(m.cwSl)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(m.win.windowNumber), "-x", "-o", out]; try? c.run(); c.waitUntilExit(); print("CS Custom 카드 \(m.specCards["Custom"]?.dims.map { "\($0.0)×\($0.1)" } ?? "-")"); exit(0) } } }
} else if ProcessInfo.processInfo.environment["DONUT_ZOOMTEST"] != nil {   // 시험: 규격 탭 샘플 기본↔확대 움직임 (화면 녹화로 봄)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.openMain(); let m = controller.settings; m.showTab("desk"); m.stripBig = false; m.fillSampleStrip()
        if let w = m.win { w.setFrameOrigin(NSPoint(x: 60, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - w.frame.height - 20)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if let sc = m.body.subviews.compactMap({ $0 as? NSScrollView }).first, let d = sc.documentView { d.scroll(NSPoint(x: 0, y: d.bounds.height)) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { m.stripBig = true; m.fillSampleStrip(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { m.stripBig = false; m.fillSampleStrip(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if let f = m.sampleFlow, let b = f.btns["s2"] { f.showX(("s2", b)) }
                    if let out = ProcessInfo.processInfo.environment["DONUT_ZOOMSHOT"] { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(m.win.windowNumber), "-x", "-o", out]; try? c.run(); c.waitUntilExit() }
                    let n0 = m.draft.s.samples.count; m.deleteSpecSample("s2"); print("ZT 빼기 \(n0) → \(m.draft.s.samples.count) · 파일에도 \(YSettings.load().samples.count)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) } } } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_LAYTEST"] {   // 시험: 인화지 탭 · 배치 편집 창 (회전·이동·복사·인화지 회전·저장) (DONUT_SETTINGS_PATH 필수)
    func shot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    print("LT 기본 증명 \(Sheet.layString(Sheet.defaultLayout("증명"), style: Sheet.PolStyle()))"); print("LT 기본 반명함 \(Sheet.layString(Sheet.defaultLayout("반명함"), style: Sheet.PolStyle()).prefix(60))")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings; let t0 = CACurrentMediaTime(); m.showTab("sheet"); print("LT 인화지 탭 열기 \(Int((CACurrentMediaTime() - t0) * 1000))ms")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shot(m.win, out + "_tab.png"); let ed = m.layoutEd; let t1 = CACurrentMediaTime(); ed.open("증명"); print("LT 편집 창 열기 \(Int((CACurrentMediaTime() - t1) * 1000))ms"); let t2 = CACurrentMediaTime(); ed.close(); print("LT 닫기 \(Int((CACurrentMediaTime() - t2) * 1000))ms"); let t3 = CACurrentMediaTime(); ed.open("증명"); print("LT 다시 열기 \(Int((CACurrentMediaTime() - t3) * 1000))ms")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { guard let w = ed.win else { exit(1) }; shot(w, out + "_ed.png")
                var t0 = CACurrentMediaTime(); ed.photos = [:]; for n in SettingsController.specOrder { _ = ed.photo(n) }; print("LT 사진 7개 \(Int((CACurrentMediaTime() - t0) * 1000))ms")
                t0 = CACurrentMediaTime(); m.buildSheetThumbs(); print("LT 인화지 탭 그림 \(Int((CACurrentMediaTime() - t0) * 1000))ms")
                t0 = CACurrentMediaTime(); for _ in 0..<20 { ed.canvas.refresh() }; print("LT 판 다시 그리기 1번 \(Int((CACurrentMediaTime() - t0) * 1000 / 20))ms")
                ed.sel = [0]; ed.rotateSel(); ed.nudge(3, 0); print("LT 0번 회전·→3 \(ed.L.cells[0]) 겹침 \(ed.overlaps().count)")
                ed.copySel(); ed.paste(); print("LT 붙여넣기 → \(ed.L.cells.count)장 고름 \(ed.sel)")
                ed.rotateSheet(); print("LT 인화지 회전 → 가로 \(ed.L.land) 크기 \(Sheet.sheetWH(ed.L))")
                ed.sel = []; ed.switchSpec("반명함"); ed.sel = [0, 1]; ed.centerH(); ed.addSig(); ed.nudge(1100, 0); ed.addSig(); print("LT 시그니처 포토 2개(하나는 밖) → \(ed.countL.stringValue) / \(Sheet.layString(ed.L, "반명함", style: ed.style).split(separator: ";").count - 1)칸 포토샵으로")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shot(w, out + "_ed2.png"); ed.switchSpec("증명"); ed.canvas.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shot(w, out + "_ed3.png"); ed.undo(); print("LT 실행 취소 → 규격 \(ed.spec) 증명 가로 \(ed.lays["증명"]!.land)")
                        ed.save(); let saved = YSettings.load().layouts; print("LT 저장 → 바꾼 규격 \(saved.keys.sorted()) 증명 \(saved["증명"]?.cells.count ?? -1)장")
                        if let p = ed.photo("증명"), let g = Sheet.grid(p, "증명") { try? Sheet.writePNG(g, URL(fileURLWithPath: out + "_grid.png")); print("LT 인화지 그림 \(g.width)×\(g.height)") }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(m.win, out + "_tab2.png"); exit(0) } } } } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_FOOTTEST"] {   // 시험: 아래 막대 (실행 취소·다시 실행·초기값으로 설정) · ↺ = 저장한 값 (DONUT_SETTINGS_PATH 필수)
    func shot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings; if ProcessInfo.processInfo.environment["DONUT_WINDARK"] != nil { m.win.appearance = NSAppearance(named: .darkAqua) }; m.showTab("desk")
        print("FT 반명함 처음 값 \(m.specVal("desk", "반명함"))(2.4,0.25)")
        m.setSpec("desk", "증명", (3.0, 0.3)); m.doSave(); m.setSpec("desk", "증명", (3.2, 0.3)); shot(m.win, out + "_dirty.png"); if let im = m.specPhoto("증명", (3.2, 0.3)) { try? Sheet.writePNG(im, URL(fileURLWithPath: out + "_ph32.png")); print("FT 미리보기 사진 \(im.width)×\(im.height)") }; if let b = m.specBigLayerSize() { print("FT 큰 칸 \(b)") }
        let rb = NSButton(); rb.identifier = NSUserInterfaceItemIdentifier("증명"); m.specReset(rb); print("FT ↺ → \(m.specVal("desk", "증명"))(3.0,0.3 저장한 값)")
        m.doUndo(); print("FT 실행 취소 → \(m.specVal("desk", "증명"))(3.2)"); m.doRedo(); print("FT 다시 실행 → \(m.specVal("desk", "증명"))(3.0)")
        m.doFactory()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if let sh = m.win.attachedSheet { shot(sh, out + "_factory.png"); m.win.endSheet(sh, returnCode: .alertFirstButtonReturn) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { print("FT 초기값으로 → \(m.specVal("desk", "증명"))(2.6,0.25) 저장 안 됨 표시 \(!m.dirtyL.isHidden)"); m.doUndo(); print("FT 실행 취소 → \(m.specVal("desk", "증명"))(3.0)")
                m.setSpec("desk", "증명", (3.4, 0.3)); m.requestTab("sig")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if let sh = m.win.attachedSheet { shot(sh, out + "_ask.png"); print("FT 탭 옮길 때 물어봄 ✓"); m.win.endSheet(sh, returnCode: .alertSecondButtonReturn) } else { print("FT 탭 옮길 때 물어봄 ✗") }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { print("FT 저장 안 함 → 탭 \(m.tab)(sig) 증명 \(m.specVal("desk", "증명"))(3.0 저장한 값)"); m.win.displayIfNeeded(); shot(m.win, out + "_sig.png"); exit(0) } } } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_CARDSHOT"] {   // 시험: 첫 패널만 찍고 끝 (DONUT_WINPHOTO)
    let photo = ProcessInfo.processInfo.environment["DONUT_WINPHOTO"] ?? ""
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { _ = controller.beginPick([URL(fileURLWithPath: photo)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if let it = controller.sizeView.items[0] { let v = controller.sizeView, w = v.window!; let r = w.convertToScreen(v.convert(it.cell.frame, to: nil)); let H = NSScreen.screens[0].frame.height; CGWarpMouseCursorPosition(CGPoint(x: r.midX, y: H - r.midY)); CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: r.midX, y: H - r.midY), mouseButton: .left)?.post(tap: .cghidEventTap) }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if ProcessInfo.processInfo.environment["DONUT_PRESS"] != nil { controller.sizeView.pressed = 0; controller.sizeView.paintBox(0, 0) }; let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(controller.sizePanel.windowNumber), "-x", "-o", out]; try? c.run(); c.waitUntilExit(); exit(0) } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_SHEETKEYS"] {   // 시험: 사진 선택 창 아래 막대 (열기 꺼짐 → 고르면 켜짐 → Return = 열기 · Esc = 취소)
    func shot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    func key(_ w: NSWindow, _ ch: String, _ code: UInt16) { if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code) { NSApp.sendEvent(e) } }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { m.showTestSheet()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { let sw = m.testSheet!; shot(sw, out + "_0.png"); print("SK 처음 열기 켜짐 \(m.testOpenBtn!.isEnabled)(false)")
                key(sw, "\r", 36); print("SK 고르기 전 Return → 창 그대로 \(m.testSheet != nil)(true)")
                m.testFlow!.onPick?(""); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shot(sw, out + "_1.png"); print("SK 고른 뒤 열기 켜짐 \(m.testOpenBtn!.isEnabled)(true)")
                    key(sw, "\r", 36); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { print("SK Return → 사진 창 닫힘 \(m.testSheet == nil)(true) · 포토샵/데스크톱 고르기 \(m.win.attachedSheet != nil)(true)")
                        if let a = m.win.attachedSheet { m.win.endSheet(a); a.orderOut(nil) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { m.showTestSheet()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { key(m.testSheet!, "\u{1b}", 53)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { print("SK Esc → 닫힘 \(m.testSheet == nil)(true)"); fflush(stdout); exit(0) } } } } } } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_WINSHOT"] {   // 시험: ydot 창 탭마다 찍기 (DONUT_WINDARK = 다크)
    func shot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings
        if ProcessInfo.processInfo.environment["DONUT_WINDARK"] != nil { m.win.appearance = NSAppearance(named: .darkAqua) }
        var tabs = ["desk", "sheet", "sig", "gen"]
        func next() { guard !tabs.isEmpty else { exit(0) }; let t = tabs.removeFirst(); m.showTab(t); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(m.win, out + "_\(t).png"); next() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { next() } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_LFTEST"] {   // 시험: 로고·프레임 탭 · 인화지 탭 · 자르기 창 · 배치 편집 (로고 사진·로고·프레임 사진) · 인화 그림 (DONUT_SETTINGS_PATH 필수 · DONUT_FRAMEFILE = 프레임 그림)
    func shot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    let env = ProcessInfo.processInfo.environment
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings
        if env["DONUT_WINDARK"] != nil { m.win.appearance = NSAppearance(named: .darkAqua) }
        if let sf = env["DONUT_SAMPLEFILE"], m.draft.s.samples.isEmpty { m.showTab("sample"); m.addSamples([URL(fileURLWithPath: sf)]) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { m.showTab("sig")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(m.win, out + "_logo.png")
                var d = m.draft!; d.s.sigMT = 30; d.s.sigML = 30; d.s.sigMR = 30; d.s.polStrip = 120; d.s.logoX = 60; d.s.logoY = 30 + 531 + 40; m.commit(d); m.renderDesign()
                print("LF 로고 사진 크기 \(Sheet.style(m.draft.s).sigW)×\(Sheet.style(m.draft.s).sigH) (473×681) · 로고 자리 \(Sheet.logoRect(Sheet.style(m.draft.s)).map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "없음")(60,601)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shot(m.win, out + "_logo2.png"); m.showCropSheet(m.draft.s.samples.first?.id ?? "")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { if let sw = m.win.attachedSheet { shot(sw, out + "_crop.png") }; m.cropPop?.selectItem(at: m.cropPop!.indexOfItem(withRepresentedObject: "반명함")); m.cropSpecChanged(); m.cropApply()
                        print("LF 자르기 반명함 → 사진 \(m.draft.s.design.w)×\(m.draft.s.design.h)(354×472) crop \(m.draft.s.design.crop.count)")
                        m.showTab("frame")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { if let f = env["DONUT_FRAMEFILE"] { m.addFrames([URL(fileURLWithPath: f)]) }
                            print("LF 프레임 \(m.draft.s.frames.count)개 · \(m.draft.s.frames.first.map { "w \($0.w) 사진 \($0.x),\($0.y) 폭 \($0.pw)" } ?? "-")")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(m.win, out + "_frame.png"); m.showTab("sample")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shot(m.win, out + "_sample.png"); m.showTab("sheet")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { shot(m.win, out + "_sheet.png"); let ed = m.layoutEd; ed.open("증명")
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { guard let w = ed.win else { exit(1) }
                                            ed.addSig(); ed.nudge(-400, -700); ed.addLogo(); ed.nudge(0, 820); if let fid = m.draft.s.frames.first?.id { ed.addFrame(fid); ed.nudge(450, -700) }
                                            ed.sel = [ed.L.cells.count - 2]; ed.logoHF.stringValue = "1"; ed.fieldEdited(ed.logoHF); ed.sel = []; ed.changed()
                                            print("LF 편집: 칸 \(ed.L.cells.count) · 로고 높이 \(ed.L.cells.first { $0.kind == "logo" }?.lh ?? -1)(118) · 포토샵 \(Sheet.layString(ed.L, "증명", style: ed.style).split(separator: ";").suffix(3).joined(separator: " | "))")
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(w, out + "_ed.png"); ed.switchSpec("프로필")
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(w, out + "_ed_prof.png"); ed.switchSpec("증명")
                                                    let st = ed.style, L = ed.L, ph = ed.photo("증명")!
                                                    if let im = Sheet.render(ph, L, "증명", style: st) { try? Sheet.writePNG(im, URL(fileURLWithPath: out + "_sheet_out.png")) }
                                                    if let dir = Sheet.writeItems(L, ph, st) { print("LF 포토샵 그림: \(((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted())") }
                                                    if let pm = Sheet.make(polaroid: ph, small: ph) { try? Sheet.writePNG(pm, URL(fileURLWithPath: out + "_profile_out.png")) }
                                                    print("LF 프로필 기본 \(Sheet.layString(Sheet.defaultLayout("프로필"), "프로필", style: st))"); fflush(stdout); exit(0) } } } } } } } } } } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_THEMETEST"] {   // 시험: ydot 창 상단바 ◐
    func shot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings; m.winTheme = "light"; m.applyWinTheme()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(m.win, out + "_a.png"); m.winThemeToggle(); print("TH 누름 → \(m.winTheme)(dark)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(m.win, out + "_b.png"); m.winThemeToggle(); print("TH 다시 → \(m.winTheme)(light)"); fflush(stdout); exit(0) } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_UNSELTEST"] {   // 시험: 빈 곳 누르면 선택 풀기 (규격 박스 · 사진 선택 창 · 배치 편집) + 인화지 탭 샘플
    func shot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    func click(_ v: NSView, _ p: NSPoint) { guard let w = v.window else { return }; let q = v.convert(p, to: nil)
        for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] { if let e = NSEvent.mouseEvent(with: t, location: q, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { w.sendEvent(e) } } }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings; m.showTab("desk")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { guard let box = m.specCards["증명"]?.superview?.superview?.superview else { exit(1) }
            click(box, NSPoint(x: 8, y: 8)); print("UN 규격 박스 빈 곳 → 선택 없음 \(m.specNone)(true) · 카드 파랑 \(m.specCards["증명"]!.selected)(false) · 조정 흐림 \(m.specAdjBox!.alphaValue < 1)(true)")
            shot(m.win, out + "_desk.png"); m.selectSpec("증명"); print("UN 증명 다시 누름 → \(!m.specNone && m.specCards["증명"]!.selected)(true)")
            m.showTestSheet()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { guard let g = m.testFlow, let sw = m.testSheet else { exit(1) }; g.onPick?(""); let on1 = m.testOpenBtn!.isEnabled
                click(g, NSPoint(x: g.bounds.width - 10, y: g.bounds.height - 4)); print("UN 사진 선택 창: 고름 열기 \(on1)(true) → 빈 곳 → 열기 \(m.testOpenBtn!.isEnabled)(false) 고른 것 \(g.cur == "\u{0}")(true)")
                shot(sw, out + "_sheet.png"); m.closeTestSheet(); m.showTab("sheet")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { shot(m.win, out + "_tab.png"); let ed = m.layoutEd; ed.open("증명")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { ed.sel = [0]; ed.canvas.refresh(); click(ed.canvas, NSPoint(x: 30, y: 30)); print("UN 배치 편집 빈 곳 → 선택 \(ed.sel.count)(0)"); fflush(stdout); exit(0) } } } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_TESTRUN"] {   // 시험: 테스트 버튼 흐름 (DONUT_TESTSIDE desk·ps · DONUT_TESTKIND 규격 번호·prof·done · DONUT_WINPHOTO) → 결과 창 캡처
    let env = ProcessInfo.processInfo.environment, side = env["DONUT_TESTSIDE"] ?? "desk", kind = env["DONUT_TESTKIND"] ?? "0", photo = env["DONUT_WINPHOTO"] ?? ""
    func shot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shot(m.win, out + "_win.png")
            if env["DONUT_TESTSHEET"] != nil { m.showTestSheet(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if let sw = m.testSheet { shot(sw, out + "_sheet.png") }; m.testPicked("")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if let sh = m.win.attachedSheet { shot(sh, out + "_side.png") }; print("TR 시트 → 샘플 없음 → 고르기 창 \(m.win.attachedSheet != nil)"); exit(0) } }; return }
            controller.startTest(side, photo == "none" ? nil : URL(fileURLWithPath: photo))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { shot(controller.sizePanel, out + "_cards.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if kind == "prof" || kind == "done" { controller.beginCustom()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { shot(controller.sizePanel, out + "_panel.png"); if kind == "done" { controller.customView.doDone() } else { controller.customView.doSave(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.customView.doSave() } } } }
                else if kind == "direct" { controller.pickDirect(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { shot(controller.sizePanel, out + "_direct0.png"); let a = controller.adjustView; a.wSl.doubleValue = 4; a.hSl.doubleValue = 5; a.sizeChanged()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shot(controller.sizePanel, out + "_panel.png"); print("TR Custom 크기 \(a.spec.w)×\(a.spec.h) 이름 \(a.spec.name)"); a.doSave() } } }
                else { controller.pick(Int(kind) ?? 0); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { shot(controller.sizePanel, out + "_panel.png"); controller.adjustView.doSave() } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) { if let sh = m.win.attachedSheet { shot(sh, out + "_result.png") }; print("TR 패널 닫힘 \(!controller.picking) 테스트모드 끝 \(controller.testMode == nil) 결과창 \(m.win.attachedSheet != nil)"); exit(0) } } } }
} else if let out = ProcessInfo.processInfo.environment["DONUT_WINTEST"] {   // 시험: ydot 창 하나 (탭·설정 탭 아래 막대·커서) + 창 열린 채 Shift Convert 패널 (조절 → Esc) + 저장 값
    func wshot(_ w: NSWindow, _ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(w.windowNumber), "-x", "-o", p]; try? c.run(); c.waitUntilExit() }
    func key(_ v: NSView, _ code: UInt16) { if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.sizePanel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) { v.keyDown(with: e) } }
    let photo = ProcessInfo.processInfo.environment["DONUT_WINPHOTO"] ?? ""
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { controller.openMain(); let m = controller.settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { wshot(m.win, out.replacingOccurrences(of: ".png", with: "_desk.png")); print("WIN 제목 '\(m.win.title)' 탭 \(m.tabs.map(\.title)) · 데스크톱 탭 아래 막대 보임 \(!m.foot.isHidden) · 커서 없음 \(!(m.win.firstResponder is NSTextView))")
            controller.openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { wshot(m.win, out.replacingOccurrences(of: ".png", with: "_gen.png")); print("WIN ⌘, → 탭 \(m.tab)(gen) · 아래 막대 숨김 \(m.foot.isHidden) · 커서 없음 \(!(m.win.firstResponder is NSTextView))")
                var d = m.draft!; d.s.names["high"] = "HQ"; m.commit(d); m.showTab("desk"); m.setSpec("desk", "증명", (3.1, 0.3)); m.doSave()
                print("WIN 저장 → 고화질 \(YSettings.load().fileName("high"))(HQ) · 증명 \(YSettings.load().deskSpecs["증명"] ?? [])([3.1,0.3])")
                _ = controller.beginPick([URL(fileURLWithPath: photo)])
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { controller.pick(0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { wshot(controller.sizePanel, out.replacingOccurrences(of: ".png", with: "_panel.png")); print("WIN 창 열린 채 패널 → 조절 \(controller.mode)(adjust) 열림 \(controller.picking)(true)"); key(controller.adjustView, 53)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { print("WIN Esc → 패널 닫힘 \(!controller.picking)(true) · ydot 창 그대로 \(m.win.isVisible)(true)"); fflush(stdout); exit(0) } } } } } }
} else if let src = ProcessInfo.processInfo.environment["DONUT_SAMPLELOGIC"] {   // 시험: 샘플 추가·빼기·되돌리기·저장 때 파일 정리 (화면 안 씀 · DONUT_SETTINGS_PATH 필수)
    DispatchQueue.main.async { let s = controller.settings; s.build(); s.saved = s.current(); s.draft = s.saved; s.resetHist(); s.tab = "sample"
        func n() -> Int { ((try? FileManager.default.contentsOfDirectory(atPath: YSettings.sampleDir.path)) ?? []).filter { $0.hasSuffix(".jpg") }.count }
        let n0 = n(); s.addSamples([URL(fileURLWithPath: src), URL(fileURLWithPath: src)]); print("SL 추가 2장 → 목록 \(s.draft.s.samples.count) 파일 \(n())(\(n0 + 2)) 고른 것 = 마지막 \(s.draft.s.curSample == s.draft.s.samples.last?.id)")
        let id = s.draft.s.samples.last!.id; s.deleteSample(id); print("SL 빼기 → 목록 \(s.draft.s.samples.count) 파일 아직 \(n())(되돌리기용)")
        s.doUndo(); print("SL 되돌리기 → 다시 \(s.draft.s.samples.contains { $0.id == id })")
        s.deleteSample(id); s.doSave(); print("SL 저장 → 파일 \(n())(\(n0 + 1)) 설정 파일 목록 \(YSettings.load().samples.count)")
        fflush(stdout); exit(0) }
} else if let out = ProcessInfo.processInfo.environment["DONUT_SETTINGSRENDER"] {   // 시험: 화면에 띄우지 않고 설정창 내용만 그림으로 (화면 안 씀)
    DispatchQueue.main.async { let s = controller.settings; s.build(); s.saved = s.current(); s.draft = s.saved; s.resetHist()
        for (ap, suf, tb) in [(NSAppearance.Name.aqua, "", "gen"), (.aqua, "_desk", "desk"), (.aqua, "_sample", "sample"), (.aqua, "_sig", "sig")] { s.win.appearance = NSAppearance(named: ap); s.showTab(tb)
            let v = s.win.contentView!; v.layoutSubtreeIfNeeded(); if let sc = s.body.subviews.first as? NSScrollView { sc.layoutSubtreeIfNeeded(); sc.documentView?.layoutSubtreeIfNeeded() }
            v.appearance = NSAppearance(named: ap); v.needsDisplay = true
            if let r = v.bitmapImageRepForCachingDisplay(in: v.bounds) { NSAppearance(named: ap)!.performAsCurrentDrawingAppearance { v.cacheDisplay(in: v.bounds, to: r) }; try? r.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out.replacingOccurrences(of: ".png", with: suf + ".png"))) } }
        exit(0) }
} else if let out = ProcessInfo.processInfo.environment["DONUT_SETTINGSTEST"] {   // 시험: 설정창 열기 → 캡처 → 바꾸기·되돌리기 확인 (저장은 안 함 · 실제 설정 안 건드림)
    func wshot(_ p: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(controller.settings.win.windowNumber), "-x", "-t", "png", p]; try? c.run(); c.waitUntilExit() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { let s = controller.settings; s.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { wshot(out); let d0 = s.draft!
            s.segSize.selectedSegment = 2; s.genChanged(); s.chk[0].state = .on; s.genChanged(); s.swEnabled.state = .off; s.genChanged()
            print("ST 바꾼 뒤 기록 \(s.hist["gen"]?.count ?? 0)개 · 저장 안 눌러도 적용됨: 파일 \(ySettings.deskFile)(true) 크기 \(Int(previewThumbH()))(400) · 저장 버튼 꺼짐 \(!s.saveB.isEnabled)"); wshot(out.replacingOccurrences(of: ".png", with: "_dirty.png"))
            s.doUndo(); s.doUndo(); print("ST 되돌리기 2번 → 바로 적용: 파일 \(ySettings.deskFile)(false) 크기 \(s.draft.size)(2) 파일 \(s.draft.s.deskFile)(false) 켜짐 \(s.draft.enabled)(\(d0.enabled))")
            s.doRedo(); print("ST 다시 → 파일 \(s.draft.s.deskFile)(true)"); s.doCancel(); print("ST 취소 → 처음과 같음 \(s.draft == d0)")
            s.showTab("desk"); s.setSpec("desk", "증명", (3.0, 0.3)); s.fillSpecs(); wshot(out.replacingOccurrences(of: ".png", with: "_desk.png")); s.showTab("gen"); s.doUndo(); print("ST 일반탭 되돌리기는 데스크톱 값 유지 → 증명 \(s.specVal("desk", "증명"))(3.0,0.3)"); s.showTab("desk"); s.doUndo(); print("ST 데스크톱 되돌리기 → 증명 \(s.specVal("desk", "증명"))(2.6,0.25)"); s.showTab("sample"); s.win.displayIfNeeded(); wshot(out.replacingOccurrences(of: ".png", with: "_sample.png")); s.showTab("sig"); s.win.displayIfNeeded(); wshot(out.replacingOccurrences(of: ".png", with: "_sig.png")); s.alignSeg?.selectedSegment = 1; s.sigEdited(s); print("ST 시그니처 가운데 → \(s.draft.s.logoAlign)(center) 되돌리기 가능 \((s.hist["sig"]?.count ?? 0) > 1)"); s.doUndo(); print("ST 되돌리기 → \(s.draft.s.logoAlign)(right)"); s.showTab("gen")
            NSApp.appearance = NSAppearance(named: .darkAqua); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { wshot(out.replacingOccurrences(of: ".png", with: "_dark.png")); fflush(stdout); exit(0) } } }
} else if let t = ProcessInfo.processInfo.environment["DONUT_PICKTEST"], let out = ProcessInfo.processInfo.environment["DONUT_PICKSHOT"] {
    if let th = ProcessInfo.processInfo.environment["DONUT_CARD_THEME"] { cardTheme = th; controller.applyThemeAll() }   // 시험: 고르기 패널을 띄워 그 창만 그림자째 캡처 (out 앞 = 그대로, _hover = 증명에 올린 상태)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { _ = controller.beginPick([URL(fileURLWithPath: t)]) }
    func shot(_ path: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(controller.sizePanel.windowNumber), "-x", "-t", "png", path]; try? c.run(); c.waitUntilExit() }
    if ProcessInfo.processInfo.environment["DONUT_F11TEST"] != nil {   // 시험: F11 상태에서 열기 → 자동 닫기(Esc와 같은 endPick) → 다시 열기 → 사용자 Esc. 메인 스레드 멈춤(50ms+) 기록
        var last = CACurrentMediaTime(); Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in let n = CACurrentMediaTime(); if n - last > 0.05 { debugLog(String(format: "멈춤 %.0fms", (n - last) * 1000)) }; last = n }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { debugLog("자동 닫기"); controller.endPick()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { debugLog("다시 열기"); _ = controller.beginPick([URL(fileURLWithPath: t)]); DispatchQueue.main.asyncAfter(deadline: .now() + 3) { debugLog("Custom 열기"); controller.beginCustom(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { debugLog("Custom 화면 \(controller.mode)") } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 14) { debugLog("끝"); exit(0) } } }
    } else if ProcessInfo.processInfo.environment["DONUT_HITTEST"] != nil {   // 시험: 화면마다 버튼 가운데를 클릭했을 때 그 버튼이 받는지
        func check(_ name: String, _ b: NSView) { guard let w = b.window, let cv = w.contentView else { print("HIT \(name): 창 없음"); return }
            let p = b.convert(NSPoint(x: b.bounds.midX, y: b.bounds.midY), to: nil), top = cv.superview ?? cv, hv = top.hitTest(top.convert(p, from: nil))   // hitTest는 부모 좌표
            var ok = false; var x: NSView? = hv; while let v = x { if v === b { ok = true; break }; x = v.superview }
            print("HIT \(name): \(ok ? "OK" : "막힘 → \(hv.map { String(describing: type(of: $0)) } ?? "없음")")") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { let c = controller
            check("카드 상단바 ◐", c.sizeView.tbar.toggle); check("카드 스테퍼", c.sizeView.tbar.stepper); check("카드 신호등", c.sizeView.tbar.lights); c.pick(0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { check("조절 뒤로", c.adjustView.back); check("조절 Default", c.adjustView.reset); check("조절 Save", c.adjustView.save); check("조절 얼굴 게이지", c.adjustView.slider); check("조절 여백 게이지", c.adjustView.topSlider); check("조절 상단바 ◐", c.adjustView.tbar.toggle); check("조절 스테퍼", c.adjustView.tbar.stepper); c.adjustView.slider.doubleValue = 3.4; c.adjustView.reset.performClick(nil); print("ACT 조절 Default → 얼굴 \(c.adjustView.head) (기본 2.6)"); c.adjustView.back.performClick(nil); print("ACT 조절 뒤로 → 화면 \(c.mode)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { c.beginCustom()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { check("Custom 뒤로", c.customView.back); check("Custom Default", c.customView.reset); check("Custom Save", c.customView.save); check("Custom 비율", c.customView.seg); check("Custom 확대", c.customView.zoomS); check("Custom 상단바 ◐", c.customView.tbar.toggle); check("Custom Done", c.customView.done); c.customView.stage.zoom(to: 2.5); c.customView.reset.performClick(nil); print("ACT Custom Default → 확대 \(c.customView.stage.z) (1)"); c.customView.back.performClick(nil); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { print("ACT Custom 뒤로 → 화면 \(c.mode)"); fflush(stdout); exit(0) } } } } }
    } else if let mov = ProcessInfo.processInfo.environment["DONUT_SIZEREC"] {   // 시험: 화면 녹화하며 카드 Small→Large(두 단계) → 조절로 → Large→Small → 도중에 바꾸기
        func setH(_ h: Double) { let it = NSMenuItem(); it.representedObject = h; controller.setPanelSize(it) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let f = controller.sizePanel.frame, H = NSScreen.screens[0].frame.height; print("REC 가운데 \(Int(f.midX)) \(Int(H - f.midY))"); fflush(stdout)
            let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-v", "-V", "7", "-x", "-k", mov]; try? c.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { setH(400)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { controller.pick(0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { setH(220)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { setH(400); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { setH(300) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { c.waitUntilExit(); exit(0) } } } } } }
    } else if ProcessInfo.processInfo.environment["DONUT_KEYTEST"] != nil {   // 시험: 백스페이스 = 뒤로 · Esc = 닫기 (조절·프로필)
        func key(_ v: NSView, _ code: UInt16) { if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.sizePanel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) { v.keyDown(with: e) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { controller.pick(0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { key(controller.adjustView, 51)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { print("KEY 조절 백스페이스 → \(controller.mode)(cards) 열림 \(controller.picking)(true)"); controller.pick(0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { key(controller.adjustView, 53)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { print("KEY 조절 Esc → 열림 \(controller.picking)(false)"); fflush(stdout); exit(0) } } } } }
    } else if ProcessInfo.processInfo.environment["DONUT_TBTEST"] != nil {   // 시험: 상단바 — 올렸을 때 · ◐ 누름 · 스테퍼 + · 초록
        func bg(_ n: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(controller.sizePanel.windowNumber), "-x", "-o", out.replacingOccurrences(of: ".png", with: "_\(n).png")]; try? c.run() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { let t = controller.sizeView.tbar; bg("0"); t.lights.hover = true; t.toggle.hovering = true; t.toggle.paint(); t.stepper.hot = 1; t.stepper.needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { bg("1hover"); t.lights.hover = false; t.toggle.hovering = false; t.toggle.paint(); t.stepper.hot = -1; t.toggle.onClick?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { bg("2spin")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { bg("3dark"); print("TB 바탕 \(cardTheme) ◐ 돌아감 \(t.toggle.isDark)"); t.stepper.onStep?(1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { bg("4large"); print("TB 스테퍼 + → \(Int(previewThumbH()))(400) 글자 \(t.stepper.title)"); t.stepper.onStep?(-1)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { bg("5zoom"); print("TB 스테퍼 − → \(Int(previewThumbH()))(300)"); fflush(stdout); t.toggle.onClick?(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { exit(0) } } } } } } }
    } else if ProcessInfo.processInfo.environment["DONUT_SIZEANIM"] != nil {   // 시험: 크기 부드럽게 — 카드 Small→Large(두 단계) · 조절 Large→Small · 도중에 또 바꾸기 · Custom. 도중 캡처 + 메인 멈춤 측정
        func setH(_ h: Double) { let it = NSMenuItem(); it.representedObject = h; controller.setPanelSize(it) }
        func bg(_ name: String) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(controller.sizePanel.windowNumber), "-x", "-o", "-t", "png", out.replacingOccurrences(of: ".png", with: "_\(name).png")]; try? c.run() }   // 기다리지 않음 (도중 모습)
        var last = CACurrentMediaTime(), worst = 0.0; Timer.scheduledTimer(withTimeInterval: 0.004, repeats: true) { _ in let n = CACurrentMediaTime(); worst = max(worst, n - last); last = n }
        func step(_ tag: String, _ h: Double, then: @escaping () -> Void) { worst = 0; let f0 = controller.sizePanel.frame; setH(h)
            for (i, d) in [0.07, 0.15, 0.23].enumerated() { DispatchQueue.main.asyncAfter(deadline: .now() + d) { bg("\(tag)_\(i + 1)") } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { let f1 = controller.sizePanel.frame; print(String(format: "ANIM %@ 창 %.0f×%.0f → %.0f×%.0f · uiK %.3f · 가장 긴 멈춤 %.0fms", tag, f0.width, f0.height, f1.width, f1.height, uiK, worst * 1000)); fflush(stdout); bg("\(tag)_end"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: then) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { bg("cards_start")
            step("cards_SL", 400) { controller.pick(0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { bg("adj_start")
                    step("adj_LS", 220) {
                        setH(400); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { step("adj_interrupt", 300) { controller.adjustView.goBack()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { controller.beginCustom()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { bg("cus_start"); step("cus_ML", 400) { step("cus_LS", 220) { exit(0) } } } } } } } } } }
    } else if ProcessInfo.processInfo.environment["DONUT_SIZESWITCH"] != nil {   // 시험: 열린 채로 Panel Size 바꾸기 (y. 모양 확인)
        func setH(_ h: Double) { let it = NSMenuItem(); it.representedObject = h; controller.setPanelSize(it) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { shot(out.replacingOccurrences(of: ".png", with: "_a.png")); setH(400)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shot(out.replacingOccurrences(of: ".png", with: "_b400.png")); controller.pick(0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { shot(out.replacingOccurrences(of: ".png", with: "_c400adj.png")); setH(220)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shot(out.replacingOccurrences(of: ".png", with: "_d220adj.png")); controller.adjustView.goBack()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { shot(out.replacingOccurrences(of: ".png", with: "_e220.png")); exit(0) } } } } }
    } else if ProcessInfo.processInfo.environment["DONUT_PICKCLOSE"] != nil {   // 시험: 열린 뒤 닫기 (등장·퇴장 확인)
        if ProcessInfo.processInfo.environment["DONUT_PICKCLOSE"] == "adjust" { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { controller.pick(0) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { controller.endPick(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) } }
    } else if ProcessInfo.processInfo.environment["DONUT_PICKCUSTOM"] != nil {   // 시험: Custom 1차(확대 1.6) → 2차 저장까지, 화면마다 캡처 (저장은 DONUT_CUSTOM_DEST, 시트는 DONUT_SHEET_OUT)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { shot(out); controller.sizeView.setHover(customCell)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { shot(out.replacingOccurrences(of: ".png", with: "_hover.png")); controller.beginCustom()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if ProcessInfo.processInfo.environment["DONUT_SCROLLTEST"] != nil {   // 시험: 진짜 스크롤 이벤트를 자르기 화면 가운데에 → 확대되는지
                        let st = controller.customView.stage; st.zoom(to: 2); let z0 = st.z, x0 = st.ix, y0 = st.iy, p = st.window!.convertPoint(toScreen: st.convert(NSPoint(x: st.bounds.midX, y: st.bounds.midY), to: nil)), H = NSScreen.screens[0].frame.height
                        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x, y: H - p.y), mouseButton: .left)?.post(tap: .cghidEventTap)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { for _ in 0..<6 { CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 20, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { print("SCROLL 확대 \(z0) → \(st.z) (같아야 함) · 이동 x \(Int(x0))→\(Int(st.ix)) y \(Int(y0))→\(Int(st.iy)) (바뀌어야 함)"); fflush(stdout); exit(0) } }; return }
                    controller.customView.stage.zoom(to: 1.6); shot(out.replacingOccurrences(of: ".png", with: "_custom1.png"))
                    if ProcessInfo.processInfo.environment["DONUT_PICKCUSTOM"] == "done" { controller.customView.seg.selectedSegment = 2; controller.customView.ratioChanged(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shot(out.replacingOccurrences(of: ".png", with: "_orig.png")); controller.customView.doDone(); DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) } }; return }
                    controller.customView.doSave()
                    if ProcessInfo.processInfo.environment["DONUT_STEPSHOT"] != nil { for (i, d) in [0.12, 0.45, 0.8, 1.35].enumerated() { DispatchQueue.main.asyncAfter(deadline: .now() + d) { let c = Process(); c.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); c.arguments = ["-l", String(controller.sizePanel.windowNumber), "-x", "-o", out.replacingOccurrences(of: ".png", with: "_step\(i + 1).png")]; try? c.run() } } }
                    if ProcessInfo.processInfo.environment["DONUT_PICKCUSTOM"] == "back" { DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { controller.customView.goBack(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { controller.customView.goBack(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) } } }; return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { shot(out.replacingOccurrences(of: ".png", with: "_custom2.png")); controller.customView.doSave()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { exit(0) } } } } }
    } else {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { shot(out); controller.sizeView.setHover(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { shot(out.replacingOccurrences(of: ".png", with: "_hover.png")); controller.pick(0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shot(out.replacingOccurrences(of: ".png", with: "_adjust.png")); controller.adjustView.slider.doubleValue = 3.4; controller.adjustView.topSlider.doubleValue = 0.6; controller.adjustView.changed()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shot(out.replacingOccurrences(of: ".png", with: "_adjust34.png")); if ProcessInfo.processInfo.environment["DONUT_PICKSAVE"] != nil { controller.adjustView.doSave(); DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(0) } } else { exit(0) } } } } }
    }
}
DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { Converter.warmUp() }   // 켠 지 3초 뒤 뒤에서 비전 모델 미리 불러 둠
_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
if !CommandLine.arguments.contains("--login"), !ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("DONUT_") && $0 != "DONUT_LOG" && $0 != "DONUT_LOGO" && $0 != "DONUT_SETTINGS_PATH" }) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { controller.openMain() }   // 앱을 눌러 켰을 때 = 'ydot' 창 (로그인 자동 실행은 --login → 조용히)
}
app.run()

// ── 로고 탭 · 프레임 탭 (사용자 2026-11-07): 위 = 소스 (로고 · 프레임) · 가운데 = 편집판 (자른 샘플 + 여백·로고 / 프레임 + 사진, 손으로 옮기고 숫자로도) · 아래 = 샘플 (두 번 = 규격대로 자르기)
extension SettingsController {
    func buildSig() {
        sigFields = [:]; designF = [:]
        let grid = SampleGrid(); grid.kind = "logo"; grid.owner = self; logoGrid = grid; grid.translatesAutoresizingMaskIntoConstraints = false
        let logoBox = group("로고", [grid], sub: "ai·pdf·png·jpg 등 그림 파일 · 끌어다 놓아도 돼요", acc: [smallBtn("＋ 로고 추가…", #selector(pickLogos))])
        let edit = designEditor("logo", [("mt", "위 여백"), ("mb", "아래 여백"), ("ml", "왼쪽 여백"), ("mr", "오른쪽 여백"), ("-", ""), ("lh", "로고 높이"), ("lx", "로고 왼쪽에서"), ("ly", "로고 아래에서")])
        let editBox = group("로고 사진", [edit], sub: "샘플을 두 번 누르면 규격대로 잘라 여기에 넣어요 · 로고는 손으로 옮겨요", acc: [smallBtn("↺ 초기화", #selector(sigDefaults))])
        scrollPage([logoBox, editBox, designSampleBox()])
        grid.reload(); fillSig() }
    func fillSig() { guard tab == "sig", draft != nil else { return }; logoGrid?.reload(); designFlowFill(); renderDesign() }
    @objc func sigDefaults() { var d = draft!; let z = YSettings(); d.s.polStrip = z.polStrip; d.s.logoH = z.logoH; d.s.logoMargin = z.logoMargin; d.s.logoAlign = z.logoAlign; d.s.sigMT = 0; d.s.sigML = 0; d.s.sigMR = 0; d.s.logoX = nil; d.s.logoY = nil; commit(d); fillSig() }
    func buildFrame() {
        designF = [:]
        let grid = SampleGrid(); grid.kind = "frame"; grid.owner = self; frameGrid = grid; grid.translatesAutoresizingMaskIntoConstraints = false
        let srcBox = group("프레임", [grid], sub: "png·jpg·ai·pdf·psd 등 그림 파일 · 끌어다 놓아도 돼요 · 골라서 아래에서 맞춰요", acc: [smallBtn("＋ 프레임 추가…", #selector(pickFrames))])
        let edit = designEditor("frame", [("fw", "프레임 가로"), ("fh", "프레임 세로"), ("-", ""), ("pw", "사진 가로"), ("ph", "사진 세로"), ("px", "사진 왼쪽에서"), ("py", "사진 위에서")])
        let editBox = group("프레임 사진", [edit], sub: "프레임 위에 자른 샘플을 얹어요 · 사진은 손으로 옮기고 오른쪽 아래 동그라미로 크기", acc: [smallBtn("↺ 초기화", #selector(frameDefaults))])
        scrollPage([srcBox, editBox, designSampleBox()])
        grid.reload(); fillFrame() }
    func fillFrame() { guard tab == "frame", draft != nil else { return }; frameGrid?.reload(); designFlowFill(); renderDesign() }
    // 편집판 + 숫자 칸 (cm)
    func designEditor(_ mode: String, _ fields: [(String, String)]) -> NSView {
        let cv = DesignCanvas(); cv.owner = self; cv.mode = mode; designCanvas = cv; cv.translatesAutoresizingMaskIntoConstraints = false
        cv.widthAnchor.constraint(equalToConstant: 390).isActive = true; cv.heightAnchor.constraint(equalToConstant: 400).isActive = true
        let info = NSTextField(wrappingLabelWithString: ""); info.font = .systemFont(ofSize: 11); info.textColor = .secondaryLabelColor; designInfo = info
        let col = NSStackView(views: [info]); col.orientation = .vertical; col.alignment = .leading; col.spacing = 7; col.setCustomSpacing(14, after: info)
        for (k, t) in fields {
            if k == "-" { let sp = NSView(); sp.heightAnchor.constraint(equalToConstant: 4).isActive = true; col.addArrangedSubview(sp); continue }
            let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 12); l.widthAnchor.constraint(equalToConstant: 92).isActive = true
            let f = NSTextField(); f.alignment = .right; f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); f.identifier = NSUserInterfaceItemIdentifier(k); f.target = self; f.action = #selector(designEdited(_:)); f.cell?.sendsActionOnEndEditing = true
            f.widthAnchor.constraint(equalToConstant: 58).isActive = true; designF[k] = f
            let u = NSTextField(labelWithString: "cm"); u.font = .systemFont(ofSize: 11); u.textColor = .secondaryLabelColor
            let r = NSStackView(views: [l, f, u]); r.spacing = 6; col.addArrangedSubview(r) }
        info.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let h = NSStackView(views: [cv, col]); h.alignment = .top; h.spacing = 4; h.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 8, right: 12); return h }
    // 아래 샘플 상자 (한 번 = 고르기 · 두 번 = 규격대로 자르기)
    func designSampleBox() -> NSView {
        let flow = SampleFlow(); flow.translatesAutoresizingMaskIntoConstraints = false; designFlow = flow
        flow.onPick = { [weak self] id in self?.designPickSample(id) }; flow.onDouble = { [weak self] id in self?.showCropSheet(id) }
        let zoom = NSSegmentedControl(labels: ["기본", "확대"], trackingMode: .selectOne, target: self, action: #selector(designZoom(_:))); zoom.selectedSegment = stripBig ? 1 : 0; zoom.segmentStyle = .rounded
        let inner = NSStackView(views: [flow]); inner.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        flow.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -32).isActive = true
        designFlowFill(); return group("샘플", [inner], sub: "두 번 누르면 규격에 맞춰 잘라요", acc: [zoom]) }
    func designFlowFill(animated: Bool = false) { guard let f = designFlow, let d = draft else { return }; f.cols = stripBig ? 4 : 6
        f.items = d.s.samples.map { ($0.id, NSImage(contentsOf: YSettings.sampleDir.appendingPathComponent($0.file)), $0.name) } + [("", SampleGrid.silhouette, "No image")]; f.cur = d.s.design.sample ?? d.s.curSample; f.reload(animated: animated) }
    @objc func designZoom(_ z: NSSegmentedControl) { stripBig = z.selectedSegment == 1; designFlowFill(animated: true) }
    func designPickSample(_ id: String) { var d = draft!; guard d.s.design.sample ?? d.s.curSample != id else { return }; d.s.design.sample = id; d.s.design.crop = []; commit(d); designFlowFill(); renderDesign() }   // 다른 샘플 = 얼굴 기준 자동 자르기
    // 편집판에 넣을 사진: 고른 샘플을 자른 자리(없으면 얼굴 기준)로 규격 크기에
    func designSource(_ id: String) -> (CGImage, URL?)? {
        var u: URL?; if let sm = draft.s.samples.first(where: { $0.id == id }) { u = YSettings.sampleDir.appendingPathComponent(sm.file) }
        if u == nil || !FileManager.default.fileExists(atPath: u!.path) { u = Controller.testSilhouette() }
        guard let url = u, let src = CGImageSourceCreateWithURL(url as CFURL, nil), let im = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1800, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return (im, url) }
    func designSpec(_ name: String, _ w: Int, _ h: Int) -> Converter.WebSpec { if let s = Converter.webSpecs.first(where: { $0.name == name }) { return s }; var c = Converter.customStart(draft.s); c = Converter.WebSpec(name: "Custom", w: Double(w) * 2.54 / 300, h: Double(h) * 2.54 / 300, headCm: c.headCm, topCm: c.topCm); return c }
    static func autoCrop(_ im: CGImage, _ sp: Converter.WebSpec, _ url: URL?) -> CGRect {   // 얼굴 기준 (못 찾으면 가운데) · 사진 안으로
        let a = CGFloat(sp.w / sp.h), IW = CGFloat(im.width), IH = CGFloat(im.height)
        var r = Converter.faceCropRect(im, sp, key: url) ?? { let w = min(IW, IH * a); return CGRect(x: (IW - w) / 2, y: (IH - w / a) / 2, width: w, height: w / a) }()
        if r.width > IW { r.size = CGSize(width: IW, height: IW / a) }; if r.height > IH { r.size = CGSize(width: IH * a, height: IH) }
        r.origin.x = min(max(0, r.minX), IW - r.width); r.origin.y = min(max(0, r.minY), IH - r.height); return r }
    func designPhoto() -> CGImage? {
        let ds = draft.s.design, id = ds.sample ?? draft.s.curSample, key = "\(id)|\(ds.crop)|\(ds.w)x\(ds.h)|\(ds.spec)"
        if key == dpKey, let i = dpImg { return i }
        guard let srcI = designSource(id) else { return nil }; let (im, url) = srcI
        let IW = CGFloat(im.width), IH = CGFloat(im.height)
        let r = ds.crop.count == 4 ? CGRect(x: ds.crop[0] * IW, y: ds.crop[1] * IH, width: ds.crop[2] * IW, height: ds.crop[3] * IH) : Self.autoCrop(im, designSpec(ds.spec, ds.w, ds.h), url)
        guard let ctx = CGContext(data: nil, width: max(1, ds.w), height: max(1, ds.h), bitsPerComponent: 8, bytesPerRow: 0, space: Converter.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high; let k = CGFloat(ds.w) / r.width
        ctx.draw(im, in: CGRect(x: -r.minX * k, y: CGFloat(ds.h) - (IH - r.minY) * k, width: IW * k, height: IH * k))
        dpKey = key; dpImg = ctx.makeImage(); return dpImg }
    func curFrame() -> YFrame? { draft.s.frames.first { $0.id == draft.s.frameID } ?? draft.s.frames.first }
    func renderDesign() {
        guard let cv = designCanvas, let d = draft else { return }; let st = Sheet.style(d.s), ds = d.s.design
        let spName = ds.spec == "Custom" ? "Custom" : ds.spec, sz = "\(DesignCanvas.cm(CGFloat(ds.w)))×\(DesignCanvas.cm(CGFloat(ds.h))) cm"
        func setF(_ k: String, _ px: CGFloat?, _ on: Bool = true) { guard let f = designF[k] else { return }; f.isEnabled = on; if win.firstResponder !== f.currentEditor() { f.stringValue = px.map { DesignCanvas.cm($0) } ?? "" } }
        guard let photo = designPhoto() else { return }
        if cv.mode == "logo" {
            cv.img = Sheet.polaroid(photo, st); cv.W = CGFloat(st.sigW); cv.H = CGFloat(st.sigH); cv.photoR = CGRect(x: st.ml, y: st.mt, width: st.pw, height: st.ph); cv.logoR = Sheet.logoRect(st)
            setF("mt", CGFloat(st.mt)); setF("mb", CGFloat(st.strip)); setF("ml", CGFloat(st.ml)); setF("mr", CGFloat(st.mr))
            let l = cv.logoR; setF("lh", l.map { $0.height }, l != nil); setF("lx", l.map { $0.minX }, l != nil); setF("ly", l.map { cv.H - $0.maxY }, l != nil)
            designInfo?.stringValue = "사진 \(sz) · \(spName)\n전체 \(DesignCanvas.cm(cv.W))×\(DesignCanvas.cm(cv.H)) cm" + (l == nil ? "\n로고 없음 (위에서 로고를 골라요)" : "")
        } else {
            guard let f = curFrame(), let fd = st.frames[f.id] else { cv.img = nil; cv.W = 1; cv.H = 1; cv.photoR = .zero; for k in designF.keys { setF(k, nil, false) }; designInfo?.stringValue = "프레임이 없어요\n위에서 프레임을 추가해 주세요"; cv.needsDisplay = true; return }
            cv.img = Sheet.framePhoto(photo, fd); cv.W = CGFloat(fd.w); cv.H = CGFloat(fd.h); cv.photoR = CGRect(x: fd.x, y: fd.y, width: fd.pw, height: fd.ph); cv.logoR = nil
            setF("fw", CGFloat(fd.w)); setF("fh", CGFloat(fd.h)); setF("pw", CGFloat(fd.pw)); setF("ph", CGFloat(fd.ph)); setF("px", CGFloat(fd.x)); setF("py", CGFloat(fd.y))
            designInfo?.stringValue = "\(f.name)\n사진 비율 = 자른 샘플 (\(sz) · \(spName)) · 크기는 비율 그대로" }
        cv.needsDisplay = true }
    @objc func designEdited(_ f: NSTextField) {
        guard let k = f.identifier?.rawValue, var d = draft, let v = Double(f.stringValue.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) else { renderDesign(); return }
        let px = Int((max(0, min(30, v)) / 2.54 * 300).rounded()), st = Sheet.style(d.s)
        switch k {
        case "mt": d.s.sigMT = px; case "mb": d.s.polStrip = px; case "ml": d.s.sigML = px; case "mr": d.s.sigMR = px
        case "lh": d.s.logoH = max(6, px); if d.s.logoX == nil, let r = Sheet.logoRect(st) { d.s.logoX = Int(r.minX); d.s.logoY = Int(r.minY) }
        case "lx", "ly": guard let r = Sheet.logoRect(st) else { break }; d.s.logoX = k == "lx" ? px : Int(r.minX); d.s.logoY = k == "ly" ? st.sigH - px - Int(r.height.rounded()) : Int(r.minY)
        default:
            guard let i = d.s.frames.firstIndex(where: { $0.id == (curFrame()?.id ?? "") }), let fd = st.frames[d.s.frames[i].id] else { break }
            let a = CGFloat(fd.w) / CGFloat(max(1, fd.h)), pa = CGFloat(fd.pw) / CGFloat(max(1, fd.ph))
            switch k { case "fw": d.s.frames[i].w = max(60, px); case "fh": d.s.frames[i].w = max(60, Int((CGFloat(px) * a).rounded()))
            case "pw": d.s.frames[i].pw = max(30, px); case "ph": d.s.frames[i].pw = max(30, Int((CGFloat(px) * pa).rounded()))
            case "px": d.s.frames[i].x = px; case "py": d.s.frames[i].y = px; default: break } }
        commit(d); renderDesign() }
    // 손으로 끌기: 끄는 동안은 기록 없이 바로 보이고, 놓으면 한 번 기록 (실행 취소 한 번에)
    func designDragBegan() { dragBase = draft }
    func designDragged(_ kind: String, _ r: CGRect) {
        guard var d = draft else { return }
        if kind == "logo" { d.s.logoX = Int(r.minX); d.s.logoY = Int(r.minY) }
        else if let i = d.s.frames.firstIndex(where: { $0.id == (curFrame()?.id ?? "") }) { d.s.frames[i].x = Int(r.minX); d.s.frames[i].y = Int(r.minY); d.s.frames[i].pw = Int(r.width) }
        draft = d; renderDesign() }
    func designDragEnded() { guard let b = dragBase else { return }; let fin = draft!; draft = b; dragBase = nil; commit(fin); renderDesign() }
    // 샘플 자르기 창 (두 번 누르면)
    func showCropSheet(_ id: String) {
        guard win.attachedSheet == nil, let srcI = designSource(id) else { return }; let (im, url) = srcI; win.makeFirstResponder(nil)
        let W: CGFloat = 640, H: CGFloat = 620, ds = draft.s.design
        let sw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H), styleMask: [.titled], backing: .buffered, defer: false); sw.backgroundColor = YWin.bar
        let cv = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H)); sw.contentView = cv
        let t = NSTextField(labelWithString: "샘플 자르기"); t.font = .systemFont(ofSize: 13, weight: .semibold); t.frame = NSRect(x: 20, y: H - 36, width: 200, height: 18); cv.addSubview(t)
        let pop = NSPopUpButton(frame: NSRect(x: W - 20 - 300, y: H - 42, width: 180, height: 26)); cropPop = pop
        for sp in Converter.webSpecs { pop.addItem(withTitle: "\(sp.name)  \(sp.fmt(sp.w))×\(sp.fmt(sp.h)) cm"); pop.lastItem?.representedObject = sp.name }
        pop.addItem(withTitle: "Custom (직접)"); pop.lastItem?.representedObject = "Custom"; pop.target = self; pop.action = #selector(cropSpecChanged); cv.addSubview(pop)
        let fw = NSTextField(frame: NSRect(x: W - 20 - 112, y: H - 40, width: 44, height: 22)), fh = NSTextField(frame: NSRect(x: W - 20 - 52, y: H - 40, width: 44, height: 22)); cropW = fw; cropH = fh
        let xl = NSTextField(labelWithString: "×"); xl.frame = NSRect(x: W - 20 - 66, y: H - 38, width: 12, height: 18); let ul = NSTextField(labelWithString: "cm"); ul.font = .systemFont(ofSize: 11); ul.textColor = .secondaryLabelColor; ul.frame = NSRect(x: W - 20 - 6, y: H - 37, width: 22, height: 16)
        for f in [fw, fh] { f.alignment = .right; f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); f.target = self; f.action = #selector(cropSpecChanged); f.cell?.sendsActionOnEndEditing = true; cv.addSubview(f) }
        cv.addSubview(xl); cv.addSubview(ul); cropCustomViews = [fw, fh, xl, ul]
        let mid = YWin.Body(frame: NSRect(x: 0, y: 52, width: W, height: H - 52 - 52)); cv.addSubview(mid)
        let v = CropView(frame: mid.bounds); v.autoresizingMask = [.width, .height]; v.img = im; mid.addSubview(v); mid.raiseShades(); cropV = v
        let line = NSBox(frame: NSRect(x: 0, y: 51, width: W, height: 1)); line.boxType = .separator; cv.addSubview(line)
        let note = NSTextField(labelWithString: "창 안을 끌면 옮기고, 모서리를 끌면 크기 (비율 그대로)"); note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; note.frame = NSRect(x: 18, y: 18, width: 330, height: 16); cv.addSubview(note)
        let ok = NSButton(title: "적용", target: self, action: #selector(cropApply)); ok.bezelStyle = .rounded; ok.keyEquivalent = "\r"; ok.frame = NSRect(x: W - 16 - 84, y: 11, width: 84, height: 30); cv.addSubview(ok)
        let no = NSButton(title: "취소", target: self, action: #selector(cropCancel)); no.bezelStyle = .rounded; no.keyEquivalent = "\u{1b}"; no.frame = NSRect(x: ok.frame.minX - 8 - 84, y: 11, width: 84, height: 30); cv.addSubview(no)
        cropSample = id; cropURL = url
        let name = Converter.webSpecs.contains { $0.name == ds.spec } ? ds.spec : "Custom"
        pop.selectItem(at: pop.indexOfItem(withRepresentedObject: name)); fw.stringValue = DesignCanvas.cm(CGFloat(ds.w)); fh.stringValue = DesignCanvas.cm(CGFloat(ds.h))
        let (sp, w, h) = cropSpec(); v.aspect = CGFloat(w) / CGFloat(h)
        if (ds.sample ?? draft.s.curSample) == id, ds.crop.count == 4 { v.crop = CGRect(x: ds.crop[0] * CGFloat(im.width), y: ds.crop[1] * CGFloat(im.height), width: ds.crop[2] * CGFloat(im.width), height: ds.crop[3] * CGFloat(im.height)) } else { v.crop = Self.autoCrop(im, sp, url) }
        for x in cropCustomViews { x.isHidden = name != "Custom" }
        win.beginSheet(sw) { [weak self] _ in self?.cropV = nil } }
    func cropSpec() -> (Converter.WebSpec, Int, Int) {   // 고른 규격 (Custom = 숫자 칸) · px
        let n = cropPop?.selectedItem?.representedObject as? String ?? "증명"
        if n != "Custom", let s = Converter.webSpecs.first(where: { $0.name == n }) { return (s, s.px.0, s.px.1) }
        func cmv(_ f: NSTextField?) -> Double { min(15, max(1, Double(f?.stringValue.replacingOccurrences(of: ",", with: ".") ?? "") ?? 3.5)) }
        let w = cmv(cropW), h = cmv(cropH), c = Converter.customStart(draft.s), sp = Converter.WebSpec(name: "Custom", w: w, h: h, headCm: c.headCm, topCm: c.topCm); return (sp, sp.px.0, sp.px.1) }
    @objc func cropSpecChanged() { guard let v = cropV, let im = v.img else { return }; let n = cropPop?.selectedItem?.representedObject as? String ?? ""
        for x in cropCustomViews { x.isHidden = n != "Custom" }; let (sp, w, h) = cropSpec(); v.aspect = CGFloat(w) / CGFloat(h); v.crop = Self.autoCrop(im, sp, cropURL); v.needsDisplay = true }
    @objc func cropCancel() { if let s = win.attachedSheet { win.endSheet(s); s.orderOut(nil) } }
    @objc func cropApply() {
        guard let v = cropV, let im = v.img else { cropCancel(); return }; let (sp, w, h) = cropSpec(), IW = Double(im.width), IH = Double(im.height), r = v.crop
        var d = draft!; d.s.design = YDesign(sample: cropSample, spec: sp.name, w: w, h: h, crop: [Double(r.minX) / IW, Double(r.minY) / IH, Double(r.width) / IW, Double(r.height) / IH])
        cropCancel(); commit(d); designFlowFill(); renderDesign() }
    // 프레임 소스
    static func isFrameFile(_ u: URL) -> Bool { let e = u.pathExtension.lowercased(); if ["ai", "pdf", "eps", "svg"].contains(e) { return true }; return (try? u.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) ?? !e.isEmpty }
    @objc func pickFrames() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = false; p.prompt = "추가"; p.allowedContentTypes = [.image, .pdf] + [UTType(filenameExtension: "ai"), UTType(filenameExtension: "psd"), UTType(filenameExtension: "svg")].compactMap { $0 }
        p.beginSheetModal(for: win) { [weak self] r in if r == .OK { self?.addFrames(p.urls) } } }
    func addFrames(_ urls: [URL]) {
        var d = draft!; let dir = YSettings.frameDir; try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); var bad: [String] = []
        for u in urls where Self.isFrameFile(u) {
            let id = UUID().uuidString, file = id + "." + u.pathExtension.lowercased(), to = dir.appendingPathComponent(file)
            guard (try? FileManager.default.copyItem(at: u, to: to)) != nil, Sheet.frameSource(to.path) != nil else { try? FileManager.default.removeItem(at: to); bad.append(u.lastPathComponent); continue }
            var f = YFrame(id: id, name: u.deletingPathExtension().lastPathComponent, file: file); Self.fitFrame(&f, Sheet.frameAspect(to.path), d.s.design)
            d.s.frames.append(f); d.s.frameID = id }
        commit(d); fillFrame()
        if !bad.isEmpty { let a = NSAlert(); a.messageText = "열 수 없는 그림이에요"; a.informativeText = bad.joined(separator: "\n"); a.beginSheetModal(for: win, completionHandler: nil) } }
    static func fitFrame(_ f: inout YFrame, _ aspect: CGFloat, _ ds: YDesign) {   // 처음 자리: 프레임 폭 = 사진 폭 × 1.3 · 사진은 가로 가운데, 위 여백 = 옆 여백 (넘치면 사진을 줄임)
        let w = Int((CGFloat(ds.w) * 1.3).rounded()), h = CGFloat(w) / max(0.05, aspect), pa = CGFloat(ds.w) / CGFloat(max(1, ds.h))
        var pw = CGFloat(ds.w), m = (CGFloat(w) - pw) / 2; if m + pw / pa > h - m { pw = max(30, (h - 2 * m) * pa); m = (CGFloat(w) - pw) / 2 }
        f.w = w; f.pw = Int(pw.rounded()); f.x = Int(m.rounded()); f.y = Int(min(m, max(0, (h - pw / pa) / 2)).rounded()) }
    func selectFrame(_ id: String) { var d = draft!; d.s.frameID = id; commit(d); fillFrame() }
    func deleteFrame(_ id: String) { var d = draft!; d.s.frames.removeAll { $0.id == id }; if d.s.frameID == id { d.s.frameID = d.s.frames.last?.id ?? "" }; commit(d); fillFrame() }
    @objc func frameDefaults() { var d = draft!; guard let i = d.s.frames.firstIndex(where: { $0.id == (curFrame()?.id ?? "") }) else { return }
        var f = d.s.frames[i]; Self.fitFrame(&f, Sheet.frameAspect(YSettings.frameDir.appendingPathComponent(f.file).path), d.s.design); d.s.frames[i] = f; commit(d); fillFrame() }
    // 샘플 탭 (규격 탭 샘플과 같은 모양 · 사진 꽉 채움 · 기본 6장 / 확대 4장, 사용자 2026-11-07)
    func buildSample() {
        let add = smallBtn("＋ 사진 추가…", #selector(pickSamples))
        let flow = SampleFlow(); flow.translatesAutoresizingMaskIntoConstraints = false; sampleTabFlow = flow
        flow.onPick = { [weak self] id in self?.selectSample(id) }; flow.onDelete = { [weak self] id in self?.deleteSample(id) }; flow.onDrop = { [weak self] u in self?.addSamples([u]) }
        let zoom = NSSegmentedControl(labels: ["기본", "확대"], trackingMode: .selectOne, target: self, action: #selector(sampleTabZoom(_:))); zoom.selectedSegment = stripBig ? 1 : 0; zoom.segmentStyle = .rounded
        let inner = NSStackView(views: [flow]); inner.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        flow.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -32).isActive = true
        scrollPage([group("샘플 사진", [inner], sub: "고른 샘플이 미리보기에 들어가요 · 실제 인화엔 안 쓰여요 · 끌어다 놓아도 돼요", acc: [zoom, add])])
        sampleTabFill() }
    func sampleMgrBox() -> NSView {   // 샘플 상자 (추가·고르기·빼기·끌어다 놓기 · 바로 저장)
        let add = smallBtn("＋ 사진 추가…", #selector(pickSamples))
        let flow = SampleFlow(); flow.translatesAutoresizingMaskIntoConstraints = false; sampleTabFlow = flow
        flow.onPick = { [weak self] id in self?.selectSample(id) }; flow.onDelete = { [weak self] id in self?.deleteSample(id) }; flow.onDrop = { [weak self] u in self?.addSamples([u]) }
        let zoom = NSSegmentedControl(labels: ["기본", "확대"], trackingMode: .selectOne, target: self, action: #selector(sampleTabZoom(_:))); zoom.selectedSegment = stripBig ? 1 : 0; zoom.segmentStyle = .rounded
        let inner = NSStackView(views: [flow]); inner.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        flow.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -32).isActive = true
        let g = group("샘플", [inner], sub: "고른 샘플로 인화지를 미리 봐요 · 실제 인화엔 안 쓰여요 · 끌어다 놓아도 돼요", acc: [zoom, add]); sampleTabFill(); return g }
    func sampleTabFill(animated: Bool = false) { guard let f = sampleTabFlow, let d = draft else { return }; f.cols = stripBig ? 4 : 6
        f.items = d.s.samples.map { ($0.id, NSImage(contentsOf: YSettings.sampleDir.appendingPathComponent($0.file)), $0.name) } + [("", SampleGrid.silhouette, "No image")]; f.cur = d.s.curSample; f.reload(animated: animated) }
    @objc func sampleTabZoom(_ z: NSSegmentedControl) { stripBig = z.selectedSegment == 1; sampleTabFill(animated: true) }
}
