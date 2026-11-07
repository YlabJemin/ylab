// 와콤 펜 팬/스크롤만 방향 뒤집기 (2026-10-07)
// 와콤 드라이버(Wacom_IOManager)가 보낸 스크롤 이벤트만 골라 세로·가로 중 설정 파일에서 켠 방향만 반대로 바꿈
// MX Master·트랙패드 등 하드웨어 스크롤(보낸 프로세스 pid=0)은 건드리지 않음
// 필요 권한: 손쉬운 사용, 입력 모니터링
import Cocoa

func log(_ s: String) {
  let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
  FileHandle.standardError.write("\(f.string(from: Date())) \(s)\n".data(using: .utf8)!)
}
var wacomPID: [Int32: Bool] = [:]  // pid → 와콤 드라이버인지 (pid마다 한 번만 확인)
func isWacom(_ pid: Int32) -> Bool {
  if pid <= 0 { return false }
  if let v = wacomPID[pid] { return v }
  var buf = [CChar](repeating: 0, count: 4096)
  let v = proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 && String(cString: buf).contains("Wacom_IOManager")
  wacomPID[pid] = v; return v
}
// 뒤집을 방향은 설정 파일에서 읽음 → 바꿀 때 재컴파일 불필요(재컴파일하면 권한을 다시 허용해야 함)
// ~/Library/Application Support/cc/wacom-scroll.json  {"vertical": true, "horizontal": true, "repost": true, "tail": true, "speed": 1.0, "zoomSpeed": 1.0, "zoomVertical": true, "zoomHorizontal": true, "mode": "lineOrig", "zoomMode": "pixel"}  (mode/zoomMode = lineFp·lineOrig·pixel, speed=속도 배율, zoom*=Option+스크롤(패닝/줌) 따로, repost 방식에서만, repost=false면 값 고쳐쓰기 방식, tail로 위치 선택)
let configPath = NSHomeDirectory() + "/Library/Application Support/cc/wacom-scroll.json"
var flipV = true, flipH = false, atTail = true, repost = true, speed = 1.0, configMtime = Date.distantPast
// 줌(패닝/줌 버튼 = Option + 스크롤)은 따로: 속도·방향
var zoomSpeed = 1.0, zoomFlipV = true, zoomFlipH = true
// 보내는 방식: "lineFp"(줄=줄인 고정소수 누적), "lineOrig"(줄=원래 줄 값×배율 누적), "pixel"(픽셀·연속 스크롤)
var mode = "lineOrig", zoomMode = "pixel"
// pixel 방식에서 fine=true면 소수점 값까지 매번 보냄(부드럽지만 포토샵 줌처럼 신호 개수에 반응하는 앱은 안 느려짐)
var fine = false, zoomFine = false
var accOrigLine = [[0.0, 0.0], [0.0, 0.0]]  // [스크롤/줌][세로/가로]
var accZoomPt = [0.0, 0.0], accZoomLine = [0.0, 0.0]
// 속도 배율로 줄이면 생기는 소수점 나머지를 모아 두는 곳 (세로, 가로)
var accPt = [0.0, 0.0], accLine = [0.0, 0.0]
let marker: Int64 = 0x57AC0F  // 이 프로그램이 보낸 스크롤 표시
func reloadConfig() {
  guard let m = (try? FileManager.default.attributesOfItem(atPath: configPath))?[.modificationDate] as? Date, m != configMtime,
    let d = FileManager.default.contents(atPath: configPath),
    let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
  configMtime = m; atTail = (j["tail"] as? Bool) ?? true; repost = (j["repost"] as? Bool) ?? true
  flipV = (j["vertical"] as? Bool) ?? true; flipH = (j["horizontal"] as? Bool) ?? false
  speed = (j["speed"] as? Double) ?? 1.0; accPt = [0, 0]; accLine = [0, 0]
  zoomSpeed = (j["zoomSpeed"] as? Double) ?? speed; zoomFlipV = (j["zoomVertical"] as? Bool) ?? flipV; zoomFlipH = (j["zoomHorizontal"] as? Bool) ?? flipH
  accZoomPt = [0, 0]; accZoomLine = [0, 0]; accOrigLine = [[0, 0], [0, 0]]
  mode = (j["mode"] as? String) ?? "lineOrig"; zoomMode = (j["zoomMode"] as? String) ?? mode
  fine = (j["fine"] as? Bool) ?? false; zoomFine = (j["zoomFine"] as? Bool) ?? false
  pinchScale = (j["pinchScale"] as? Double) ?? 0.01
  pinchSmooth = (j["pinchSmooth"] as? Bool) ?? true; pinchSmoothFactor = (j["pinchSmoothFactor"] as? Double) ?? 0.35; pinchEndDelay = (j["pinchEndDelay"] as? Double) ?? 0.15
  tpEndDelay = (j["tpEndDelay"] as? Double) ?? 0.15; tpSmooth = (j["tpSmooth"] as? Bool) ?? true; tpSmoothFactor = (j["tpSmoothFactor"] as? Double) ?? 0.6
  tpStyle = (j["tpStyle"] as? String) ?? "velocity"; tpWindow = (j["tpWindow"] as? Double) ?? 0.04; tpLag = (j["tpLag"] as? Double) ?? 0.025; tpCatchup = (j["tpCatchup"] as? Double) ?? 0.12
  tpEndAdapt = (j["tpEndAdapt"] as? Bool) ?? true; tpEndGapMult = (j["tpEndGapMult"] as? Double) ?? 3.0; tpEndMin = (j["tpEndMin"] as? Double) ?? 0.025; tpEndMax = (j["tpEndMax"] as? Double) ?? 0.12
  log("트랙패드식 보내기: \(tpStyle) 창 \(tpWindow) 지연 \(tpLag) 보정 \(tpCatchup), 끝 판정 적응 \(tpEndAdapt) ×\(tpEndGapMult) 최소 \(tpEndMin) 최대 \(tpEndMax)")
  momentumHz = (j["momentumHz"] as? Double) ?? 120; fpScale = (j["fpScale"] as? Double) ?? 1.0; momentumBoost = (j["momentumBoost"] as? Double) ?? 1.0
  appConfig = (j["apps"] as? [String: [String: Any]]) ?? [:]
  glide = ((j["momentumStyle"] as? String) ?? "glide") == "glide"
  momentumOn = (j["momentum"] as? Bool) ?? true; momentumMin = (j["momentumMin"] as? Double) ?? 300; momentumDecay = (j["momentumDecay"] as? Double) ?? 0.95
  baseCfg = ["fpScale": fpScale, "momentumBoost": momentumBoost, "momentumDecay": momentumDecay, "momentumMin": momentumMin]; curApp = "-"
  log("설정 읽음: 세로 뒤집기 \(flipV), 가로 뒤집기 \(flipH), 뒤에서 처리 \(atTail), 새로 보내기 \(repost), 속도 \(speed), 줌 속도 \(zoomSpeed), 줌 세로 뒤집기 \(zoomFlipV), 방식 \(mode)/줌 \(zoomMode), 부드럽게 \(fine)/줌 \(zoomFine), 핀치배율 \(pinchScale) 고르게 \(pinchSmooth) \(pinchSmoothFactor), 트랙패드 끝대기 \(tpEndDelay) 고르게 \(tpSmooth) \(tpSmoothFactor), 관성 \(momentumOn) \(glide ? "이어서" : "관성신호") 최소 \(momentumMin) 감속 \(momentumDecay)")
}
// 맥이 가로 이동량을 앞쪽 값으로 다시 계산해 버려서, 기본은 처리 맨 뒤(tail)에서 뒤집음
// 설정 {"tail": false} 로 맨 앞(head)에서 뒤집게 바꿀 수 있음 (재컴파일 불필요)
var taps: [CFMachPort] = []
// 지금 커서 위치 (보낼 때마다 새로 읽음 — 옛 위치를 쓰면 커서가 그 자리로 되돌아가 잔상처럼 보임)
func currentCursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

// MARK: - 핀치(확대) 신호 보내기 — 트랙패드 두 손가락 벌리기와 같은 신호(맥 비공개 필드 사용)
//  필드 55=이벤트 종류(29=제스처), 110=제스처 종류(8=확대), 113=확대량, 132=단계(1 시작, 2 진행, 4 끝)
var pinchActive = false, pinchEndWork: DispatchWorkItem?
var pinchScale = 0.01  // 픽셀 1당 확대량 (설정 pinchScale)
func postPinch(_ mag: Double, phase: Int64, at loc: CGPoint) {
  guard let e = CGEvent(source: nil) else { return }
  e.setIntegerValueField(CGEventField(rawValue: 55)!, value: 29)
  e.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8)
  e.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
  e.setDoubleValueField(CGEventField(rawValue: 113)!, value: mag)
  e.location = currentCursor()
  e.setIntegerValueField(.eventSourceUserData, value: marker)
  e.post(tap: .cgSessionEventTap)
}
// 핀치도 고르게: 받은 확대량을 모아 두고 1/120초마다 남은 양의 pinchSmoothFactor만큼 보냄
var pinchSmooth = true, pinchSmoothFactor = 0.35, pinchEndDelay = 0.15
var pinchPending = 0.0, pinchLastInput = Date.distantPast, pinchLoc = CGPoint.zero, pinchTimer: DispatchSourceTimer?
func pinchTick() {
  let out = abs(pinchPending) < 0.0005 ? pinchPending : pinchPending * pinchSmoothFactor
  pinchPending -= out
  if out != 0 { postPinch(out, phase: 2, at: pinchLoc) }
  if pinchPending == 0 && Date().timeIntervalSince(pinchLastInput) > pinchEndDelay {
    postPinch(0, phase: 4, at: pinchLoc); pinchActive = false
    pinchTimer?.cancel(); pinchTimer = nil
  }
}
func pinch(_ mag: Double, at loc: CGPoint) {
  pinchLoc = loc; pinchLastInput = Date()
  if !pinchActive { postPinch(0, phase: 1, at: loc); pinchActive = true }
  if !pinchSmooth {
    postPinch(mag, phase: 2, at: loc)
    pinchEndWork?.cancel()
    let w = DispatchWorkItem { postPinch(0, phase: 4, at: loc); pinchActive = false }
    pinchEndWork = w
    DispatchQueue.main.asyncAfter(deadline: .now() + pinchEndDelay, execute: w)
    return
  }
  pinchPending += mag
  if pinchTimer == nil {
    let t = DispatchSource.makeTimerSource(queue: .main)
    t.schedule(deadline: .now(), repeating: 1.0 / 120)
    t.setEventHandler { pinchTick() }
    t.resume(); pinchTimer = t
  }
}

// MARK: - 트랙패드식 스크롤 (단계: 1 시작, 2 진행, 4 끝 — 필드 99 = scrollPhase)
var tpActive = false, tpEndWork: DispatchWorkItem?, tpAcc = [0.0, 0.0]
// 픽셀 필드는 정수라서 소수점을 다음 신호로 이어받음(안 그러면 느리게 끌 때 이동량이 버려져 AppKit 앱이 덜 움직임, 2026-11-01)
var pxRem = [0.0, 0.0]
func postTP(_ dy: Double, _ dx: Double, phase: Int64, momentum: Int64 = 0, at loc: CGPoint) {
  let ty = dy + pxRem[0], tx = dx + pxRem[1]
  let iy = Int32(ty.rounded(.towardZero)), ix = Int32(tx.rounded(.towardZero))
  pxRem = [ty - Double(iy), tx - Double(ix)]
  guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: iy, wheel2: ix, wheel3: 0) else { return }
  // 진짜 트랙패드 값 비율: 고정소수 = 픽셀 × fpScale(0.1), 줄 = 고정소수 정수부(0이 아니면 최소 1)
  let fy = dy * fpScale, fx = dx * fpScale
  e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fy)
  e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fx)
  if fpScale != 1 {
    func ln(_ f: Double) -> Int64 { f == 0 ? 0 : Int64(f.sign == .minus ? -1 : 1) * max(1, Int64(abs(f))) }
    e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: abs(dy) < 0.5 ? 0 : ln(fy))
    e.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: abs(dx) < 0.5 ? 0 : ln(fx))
  }
  e.setIntegerValueField(CGEventField(rawValue: 99)!, value: phase)
  e.setIntegerValueField(CGEventField(rawValue: 123)!, value: momentum)  // 관성 단계: 1 시작, 2 진행, 3 끝
  // 진짜 트랙패드는 관성 신호에 필드 173도 같이 보냄(시작 1, 진행 2, 끝 19) — 없으면 카톡 등이 관성을 무시함 (2026-10-30 기록으로 확인)
  if momentum != 0 { e.setIntegerValueField(CGEventField(rawValue: 173)!, value: momentum == 3 ? 19 : momentum) }
  e.location = currentCursor()
  e.setIntegerValueField(.eventSourceUserData, value: marker)
  e.post(tap: .cgSessionEventTap)
}
// 설정: tpEndDelay(이 시간 동안 입력 없으면 손 뗀 것으로 봄), tpSmooth/tpSmoothFactor(1/120초마다 남은 양의 몇 %를 보낼지)
//       momentum(관성 켜기), momentumMin(관성 시작 최소 속도 px/초), momentumDecay(1/120초마다 속도 유지 비율)
var tpEndDelay = 0.15, tpSmooth = true, tpSmoothFactor = 0.6
var momentumOn = true, momentumMin = 300.0, momentumDecay = 0.95
var fpScale = 1.0  // 고정소수 이동량 = 픽셀 × 이 값 (진짜 트랙패드 0.1)
var momentumBoost = 1.0  // 관성 시작 속도 배율
// 앱별 설정: 설정 "apps": {"번들ID": {"fpScale":…, "momentumBoost":…, "momentumDecay":…, "momentumMin":…}} — 스크롤 시작할 때 커서 아래 창의 앱으로 고름
var appConfig: [String: [String: Any]] = [:], baseCfg: [String: Double] = [:], curApp = ""
func appUnderCursor() -> String {
  let p = currentCursor()
  guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return "" }
  for w in list {
    guard (w[kCGWindowLayer as String] as? Int) == 0, let b = w[kCGWindowBounds as String] as? [String: Any],
      let r = CGRect(dictionaryRepresentation: b as CFDictionary), r.contains(p), let pid = w[kCGWindowOwnerPID as String] as? Int32 else { continue }
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
  }
  return ""
}
func applyAppConfig() {
  let app = appUnderCursor()
  let o = appConfig[app] ?? [:]
  fpScale = (o["fpScale"] as? Double) ?? baseCfg["fpScale"]!
  momentumBoost = (o["momentumBoost"] as? Double) ?? baseCfg["momentumBoost"]!
  momentumDecay = (o["momentumDecay"] as? Double) ?? baseCfg["momentumDecay"]!
  momentumMin = (o["momentumMin"] as? Double) ?? baseCfg["momentumMin"]!
  if app != curApp { curApp = app; log("스크롤 앱: \(app.isEmpty ? "?" : app) (fpScale \(fpScale), 관성 배율 \(momentumBoost), 감속 \(momentumDecay))") }
}
var momentumHz = 120.0, momAcc = [0.0, 0.0], momTick = 0  // 관성 신호 보내는 횟수(초당)와 모아 둔 양
var glide = true  // true: 손 뗀 뒤에도 일반 스크롤(진행 단계)로 이어서 감속 — 앱이 관성 신호를 무시하는 문제 회피
var tpPending = [0.0, 0.0], tpLastInput = Date.distantPast, tpLoc = CGPoint.zero, tpTimer: DispatchSourceTimer?
var tpVel = [0.0, 0.0], inMomentum = false, momVel = [0.0, 0.0]
var outVel = [0.0, 0.0]  // 화면에 실제로 나가는 스크롤 속도(px/초) — 관성 시작 속도로 씀
var velAtInput = [0.0, 0.0]  // 마지막 입력 순간의 속도(입력 속도와 출력 속도 중 큰 쪽) — 손 뗀 뒤 속도가 떨어지기 전 값
// 속도 추적 방식(tpStyle "velocity", 2026-11-01): 와콤 입력은 9 ms 간격이 기본이지만 12~20 ms로 늦게 오는 게 22%라
//  '남은 양의 60%' 방식(drain)은 그 들쭉날쭉함을 그대로 화면에 보냄 → 크롬은 프레임에 맞춰 다시 샘플링해 숨기지만 카톡·파인더(AppKit)는 멈칫멈칫.
//  velocity: 최근 tpWindow초 창의 평균 속도로 매 틱 일정하게 보내고, (실제 밀림 − 목표 지연 v×tpLag)을 tpCatchup씩 보정. 입력보다 앞서가진 않음
var tpStyle = "velocity", tpWindow = 0.04, tpLag = 0.025, tpCatchup = 0.12
var tpPosIn = [0.0, 0.0], tpPosOut = [0.0, 0.0], tpHist: [(Date, Double, Double)] = []
// 손 뗌 판정을 입력 간격에 맞춤: 끝 대기 = max(tpEndDelay, 평균 간격 × tpEndGapMult), 최대 tpEndMax — 느리게 끌 때 틈마다 관성이 끼어들던 문제
// 2026-11-01 저녁: 빠르게 끌다 뗄 때 밀린 양(지연 25 ms)을 다 보낸 뒤 손 뗌 판정(50 ms)까지 멈춰 있다 관성이 시작돼 "급하게 멈춤"으로 느껴짐
//  → 입력이 자주 올 때는 판정을 tpEndMin(0.025)까지 당김. 적응 끔(tpEndAdapt false)이면 예전처럼 tpEndDelay 고정
var tpEndAdapt = true, tpEndGapMult = 3.0, tpEndMin = 0.025, tpEndMax = 0.12, tpAvgGap = 0.01
func currentEndGap() -> Double { tpEndAdapt ? min(tpEndMax, max(tpEndMin, tpAvgGap * tpEndGapMult)) : tpEndDelay }
func windowVel(_ now: Date) -> [Double] {
  // 창 시작 시각 이전의 마지막 기록 위치와 지금 위치의 차 ÷ 창 길이(제스처가 창보다 짧아도 창 길이로 나눠 처음엔 천천히 올라감)
  let tw = now.addingTimeInterval(-tpWindow)
  var p = (tpHist.first?.1 ?? 0, tpHist.first?.2 ?? 0)
  for h in tpHist.reversed() where h.0 <= tw { p = (h.1, h.2); break }
  return [(tpPosIn[0] - p.0) / tpWindow, (tpPosIn[1] - p.1) / tpWindow]
}
func tpStopTimer() { tpTimer?.cancel(); tpTimer = nil }
func tpStartTimer() {
  if tpTimer != nil { return }
  let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
  t.schedule(deadline: .now(), repeating: 1.0 / 120, leeway: .microseconds(500))
  t.setEventHandler { tpTick() }
  t.resume(); tpTimer = t
}
func endMomentum() {
  guard inMomentum else { return }
  if glide { postTP(0, 0, phase: 4, at: tpLoc); tpActive = false } else { postTP(0, 0, phase: 0, momentum: 3, at: tpLoc) }
  inMomentum = false
}
func tpTick() {
  if inMomentum {
    let d = [momVel[0] / 120, momVel[1] / 120]
    if abs(d[0]) < 0.3 && abs(d[1]) < 0.3 { endMomentum(); tpStopTimer(); return }
    momVel = [momVel[0] * momentumDecay, momVel[1] * momentumDecay]
    if glide { postTP(d[0], d[1], phase: 2, at: tpLoc); return }
    // 관성 신호는 진짜 트랙패드처럼 momentumHz(기본 60)번/초로 모아서 보냄 — 카톡(맥 기본 스크롤)은 화면 한 장에 관성 신호 하나만 반영해서 120번이면 반이 버려짐
    momAcc[0] += d[0]; momAcc[1] += d[1]; momTick += 1
    if momTick >= max(1, Int((120 / momentumHz).rounded())) {
      postTP(momAcc[0], momAcc[1], phase: 0, momentum: 2, at: tpLoc); momAcc = [0, 0]; momTick = 0
    }
    return
  }
  var out = [0.0, 0.0]
  let now = Date()
  if tpStyle == "velocity" {
    if let first = tpHist.first, now.timeIntervalSince(first.0) > tpWindow * 2, tpHist.count > 2 { tpHist.removeFirst(tpHist.count / 2) }  // 오래된 기록 정리
    let v = windowVel(now)
    for a in 0..<2 {
      let e = tpPosIn[a] - tpPosOut[a]
      var o = v[a] / 120 + (e - v[a] * tpLag) * tpCatchup
      if e >= 0 { o = max(0, min(o, e)) } else { o = min(0, max(o, e)) }
      if abs(e) < 0.05 { o = e }
      tpPosOut[a] += o; out[a] = o; tpPending[a] = tpPosIn[a] - tpPosOut[a]
      outVel[a] = outVel[a] * 0.6 + o * 120 * 0.4
    }
  } else {
    for a in 0..<2 {
      out[a] = abs(tpPending[a]) < 0.05 ? tpPending[a] : tpPending[a] * tpSmoothFactor
      tpPending[a] -= out[a]
      outVel[a] = outVel[a] * 0.6 + out[a] * 120 * 0.4
    }
  }
  // 손 뗌: 남은 양이 있어도 기다리지 않고 바로 관성으로 이어감 (빈 구간 없이)
  if tpActive && now.timeIntervalSince(tpLastInput) > currentEndGap() {
    let speed = (velAtInput[0] * velAtInput[0] + velAtInput[1] * velAtInput[1]).squareRoot()
    if momentumOn && speed > momentumMin {
      if glide { postTP(out[0], out[1], phase: 2, at: tpLoc) } else { postTP(out[0], out[1], phase: 4, at: tpLoc); tpActive = false }
      // 남은 양은 관성 속도에 더해서 끊김 없이 소화
      momVel = [velAtInput[0] * momentumBoost + tpPending[0] * 120 * (1 - momentumDecay), velAtInput[1] * momentumBoost + tpPending[1] * 120 * (1 - momentumDecay)]
      log("관성 시작: 속도 \(Int(speed)) px/초 (세로 \(Int(momVel[0])), 가로 \(Int(momVel[1])))")
      tpPending = [0, 0]; tpPosIn = [0, 0]; tpPosOut = [0, 0]; tpHist = []; inMomentum = true; momAcc = [0, 0]; momTick = 0
      if glide { postTP(momVel[0] / 120, momVel[1] / 120, phase: 2, at: tpLoc) } else { postTP(momVel[0] / 120, momVel[1] / 120, phase: 0, momentum: 1, at: tpLoc) }
      momVel = [momVel[0] * momentumDecay, momVel[1] * momentumDecay]
      outVel = [0, 0]; tpVel = [0, 0]; velAtInput = [0, 0]
      return
    }
    if abs(tpPending[0]) < 0.05 && abs(tpPending[1]) < 0.05 {
      postTP(out[0] + tpPending[0], out[1] + tpPending[1], phase: 4, at: tpLoc); tpActive = false
      tpPending = [0, 0]; tpPosIn = [0, 0]; tpPosOut = [0, 0]; tpHist = []
      if Int(((velAtInput[0] * velAtInput[0] + velAtInput[1] * velAtInput[1]).squareRoot())) > 30 { log("관성 없음: 속도 \(Int((velAtInput[0] * velAtInput[0] + velAtInput[1] * velAtInput[1]).squareRoot())) px/초 < 최소 \(Int(momentumMin))") }
      tpStopTimer(); outVel = [0, 0]; tpVel = [0, 0]; velAtInput = [0, 0]
      return
    }
  }
  if abs(out[0]) > 0.0001 || abs(out[1]) > 0.0001 { postTP(out[0], out[1], phase: 2, at: tpLoc) }
}
func trackpadScroll(_ dy: Double, _ dx: Double, at loc: CGPoint) {
  let now = Date(), dt = max(now.timeIntervalSince(tpLastInput), 0.004)
  // 최근 속도(px/초)를 부드럽게 추적. 오래 쉬었다 시작하면 새로 잼
  if dt > 0.2 { tpVel = [0, 0] } else {
    tpVel = [tpVel[0] * 0.7 + (dy / dt) * 0.3, tpVel[1] * 0.7 + (dx / dt) * 0.3]
  }
  for a in 0..<2 { velAtInput[a] = abs(tpVel[a]) > abs(outVel[a]) ? tpVel[a] : outVel[a] }
  tpLoc = loc
  // 입력 간격 평균(손 뗌 판정용). 새 제스처면 처음값
  tpAvgGap = dt > 0.2 ? 0.01 : tpAvgGap * 0.7 + dt * 0.3
  tpLastInput = now
  if glide && inMomentum { inMomentum = false } else { endMomentum() }  // 관성 중에 다시 움직이면 관성 멈춤(glide는 같은 스크롤로 이어감)
  if !tpActive {
    applyAppConfig(); postTP(0, 0, phase: 1, at: loc); tpActive = true
    pxRem = [0, 0]; tpPosIn = [0, 0]; tpPosOut = [0, 0]; tpHist = [(now, 0, 0)]
  }
  if tpStyle == "velocity" {
    tpPosIn[0] += dy; tpPosIn[1] += dx; tpHist.append((now, tpPosIn[0], tpPosIn[1]))
    tpPending = [tpPosIn[0] - tpPosOut[0], tpPosIn[1] - tpPosOut[1]]
  } else if tpSmooth { tpPending[0] += dy; tpPending[1] += dx }
  else { postTP(dy, dx, phase: 2, at: loc) }
  tpStartTimer()
}

// 반환값 false = 원래 이벤트를 버림 (repost 방식에서 새 이벤트를 대신 보냈을 때)
// 기록 모드(설정 "probe": true, 시작할 때 읽음): 와콤 아닌 스크롤·제스처 신호의 값 전부를 로그에 남김 (트랙패드 신호 비교용)
var probe = false, probeT0 = 0.0
func probeLog(_ ev: CGEvent, _ tag: String) {
  let t = Double(ev.timestamp) / 1e9
  if probeT0 == 0 || t - probeT0 > 2 { probeT0 = t; log("---- 기록 시작") }
  var parts: [String] = []
  for i in 0..<256 {
    guard let f = CGEventField(rawValue: UInt32(i)) else { continue }
    let v = ev.getIntegerValueField(f)
    if v != 0 && i != 58 && i != 59 { parts.append("\(i)=\(v)") }
  }
  let fp = String(format: "fp=%.2f,%.2f", ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
  log(String(format: "P %@ +%.3f type=%d ", tag, t - probeT0, ev.type.rawValue) + fp + " " + parts.joined(separator: " "))
}
func handle(_ ev: CGEvent, tail: Bool) -> Bool {
  if probe && !tail {
    let mine = ev.getIntegerValueField(.eventSourceUserData) == marker
    if mine || !isWacom(Int32(ev.getIntegerValueField(.eventSourceUnixProcessID))) { probeLog(ev, mine ? "나" : "패드") }
  }
  guard ev.getIntegerValueField(.eventSourceUserData) != marker,
    isWacom(Int32(ev.getIntegerValueField(.eventSourceUnixProcessID))) else { return true }
  reloadConfig()
  if probe && !tail {  // 와콤 원래 입력도 기록: 시각, 픽셀(96/97), 줄(11/12), 고정소수
    let t = Double(ev.timestamp) / 1e9
    if probeT0 == 0 || t - probeT0 > 2 { probeT0 = t; log("---- 기록 시작") }
    log(String(format: "W +%.3f px=%ld,%ld line=%ld,%ld fp=%.2f,%.2f%@", t - probeT0,
      ev.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), ev.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
      ev.getIntegerValueField(.scrollWheelEventDeltaAxis1), ev.getIntegerValueField(.scrollWheelEventDeltaAxis2),
      ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
      ev.flags.contains(.maskAlternate) ? " 줌" : ""))
  }
  // repost 방식(기본): 맨 앞에서 와콤 스크롤을 버리고, 방향을 바꾼 새 스크롤(원래와 같은 줄 단위·비연속)을 보냄
  //  → 값을 고쳐 쓰면 맥이 가로 이동량 등을 원래 값으로 다시 계산해서 안 먹는 문제 회피
  if repost {
    guard !tail else { return true }
    // 원래 와콤 신호와 같은 형태(줄 단위, 비연속)로 만들고, 줄·픽셀·고정소수 값을 모두 원래의 반대로 채움
    // Option 눌린 스크롤 = 와콤 패닝/줌 → 줌 설정 사용
    let zoom = ev.flags.contains(.maskAlternate)
    let sp = zoom ? zoomSpeed : speed
    let sgn = zoom ? [zoomFlipV ? -1.0 : 1.0, zoomFlipH ? -1.0 : 1.0] : [flipV ? -1.0 : 1.0, flipH ? -1.0 : 1.0]
    let pt = [ev.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), ev.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)]
    let fp = [ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)]
    // 속도 배율 적용: 픽셀·줄 값은 정수라서 나머지를 모아 두었다가 1 이상 쌓이면 보냄
    var outPt = [Int64](repeating: 0, count: 2), outLine = [Int32](repeating: 0, count: 2), outFp = [0.0, 0.0]
    for a in 0..<2 {
      if zoom {
        accZoomPt[a] += Double(pt[a]) * sp * sgn[a]
        outPt[a] = Int64(accZoomPt[a].rounded(.towardZero)); accZoomPt[a] -= Double(outPt[a])
        outFp[a] = fp[a] * sp * sgn[a]
        accZoomLine[a] += outFp[a]
        outLine[a] = Int32(accZoomLine[a].rounded(.towardZero)); accZoomLine[a] -= Double(outLine[a])
      } else {
        accPt[a] += Double(pt[a]) * sp * sgn[a]
        outPt[a] = Int64(accPt[a].rounded(.towardZero)); accPt[a] -= Double(outPt[a])
        outFp[a] = fp[a] * sp * sgn[a]
        accLine[a] += outFp[a]
        outLine[a] = Int32(accLine[a].rounded(.towardZero)); accLine[a] -= Double(outLine[a])
      }
    }
    let md = zoom ? zoomMode : mode, zi = zoom ? 1 : 0
    if !zoom && md == "trackpad" {
      let dy = Double(pt[0]) * sp * sgn[0], dx = Double(pt[1]) * sp * sgn[1]
      if dy != 0 || dx != 0 { trackpadScroll(dy, dx, at: ev.location) }
      return false
    }
    if zoom && md == "pinch" {
      // 세로 값 기준. 원래 와콤: 위로(+) = 확대. 방향은 zoomVertical로 뒤집음
      let mag = Double(pt[0]) * sp * sgn[0] * pinchScale
      if mag != 0 { pinch(mag, at: ev.location) }
      return false
    }
    if md == "lineOrig" {  // 원래 줄 값(와콤이 보낸 칸 수)에 배율을 곱해 누적
      let ol = [Double(ev.getIntegerValueField(.scrollWheelEventDeltaAxis1)), Double(ev.getIntegerValueField(.scrollWheelEventDeltaAxis2))]
      for a in 0..<2 {
        accOrigLine[zi][a] += ol[a] * sp * sgn[a]
        outLine[a] = Int32(accOrigLine[zi][a].rounded(.towardZero)); accOrigLine[zi][a] -= Double(outLine[a])
      }
    }
    if sp == 1.0 {  // 배율이 1이면 원래 줄 값을 그대로(방향만) 사용
      outLine = [Int32(sgn[0]) * Int32(ev.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                 Int32(sgn[1]) * Int32(ev.getIntegerValueField(.scrollWheelEventDeltaAxis2))]
    }
    let ne: CGEvent
    if md == "pixel" {  // 픽셀 단위 연속 스크롤 (트랙패드처럼 부드럽게)
      // 1픽셀 모일 때까지 기다리지 않고, 소수점 이동량(고정소수)도 매번 같이 보냄 → 더 매끄럽게
      let useFine = zoom ? zoomFine : fine
      let fineFp = [Double(pt[0]) * sp * sgn[0], Double(pt[1]) * sp * sgn[1]]
      if useFine {
        if outPt == [0, 0] && abs(fineFp[0]) < 0.0001 && abs(fineFp[1]) < 0.0001 { return false }
      } else if outPt == [0, 0] { return false }  // 1픽셀 모일 때만 보냄 → 신호 개수도 배율만큼 줄어듦
      guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: Int32(outPt[0]), wheel2: Int32(outPt[1]), wheel3: 0) else { return true }
      ne = e
      if useFine {
        ne.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fineFp[0])
        ne.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fineFp[1])
      }
    } else {
      if outPt == [0, 0] && outLine == [0, 0] && abs(outFp[0]) < 0.0001 && abs(outFp[1]) < 0.0001 { return false }
      guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
        wheel1: outLine[0], wheel2: outLine[1], wheel3: 0) else { return true }
      ne = e
      ne.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
      ne.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: outPt[0])
      ne.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: outPt[1])
      ne.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: outFp[0])
      ne.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: outFp[1])
    }
    ne.location = ev.location; ne.flags = ev.flags
    ne.setIntegerValueField(.eventSourceUserData, value: marker)
    ne.post(tap: .cgSessionEventTap)
    return false
  }
  guard tail == atTail else { return true }
  if flipV {
    for f in [CGEventField.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1] { ev.setIntegerValueField(f, value: -ev.getIntegerValueField(f)) }
    ev.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
  }
  if flipH {
    for f in [CGEventField.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2] { ev.setIntegerValueField(f, value: -ev.getIntegerValueField(f)) }
    ev.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -ev.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
  }
  return true
}
let cbHead: CGEventTapCallBack = { _, type, ev, _ in
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { for t in taps { CGEvent.tapEnable(tap: t, enable: true) }; return Unmanaged.passUnretained(ev) }
  if probe && type.rawValue == 29 { probeLog(ev, ev.getIntegerValueField(.eventSourceUserData) == marker ? "나" : "패드") }
  if type == .scrollWheel, !handle(ev, tail: false) { return nil }
  return Unmanaged.passUnretained(ev)
}
let cbTail: CGEventTapCallBack = { _, type, ev, _ in
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { for t in taps { CGEvent.tapEnable(tap: t, enable: true) }; return Unmanaged.passUnretained(ev) }
  if type == .scrollWheel, !handle(ev, tail: true) { return nil }
  return Unmanaged.passUnretained(ev)
}
log("wacom-scroll 시작")
reloadConfig()
probe = (((try? JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: configPath) ?? Data())) as? [String: Any])?["probe"] as? Bool) ?? false
func start() -> Bool {
  guard CGPreflightListenEventAccess(), CGPreflightPostEventAccess() else { return false }
  for (place, cb) in [(CGEventTapPlacement.headInsertEventTap, cbHead), (.tailAppendEventTap, cbTail)] {
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: place, options: .defaultTap,
      eventsOfInterest: (1 << CGEventType.scrollWheel.rawValue) | (probe && place == .headInsertEventTap ? 1 << 29 : 0), callback: cb, userInfo: nil) else { return false }
    taps.append(t)
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
  }
  log("와콤 스크롤 뒤집기 시작"); return true
}
if !start() {
  log("권한 부족 → 권한 허용 대기")
  let asked = NSHomeDirectory() + "/Library/Application Support/cc/wacom-scroll-asked"
  if !FileManager.default.fileExists(atPath: asked) {
    FileManager.default.createFile(atPath: asked, contents: nil)
    _ = CGRequestListenEventAccess(); _ = CGRequestPostEventAccess()
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(1) }  // launchd가 다시 실행하며 재확인
}
CFRunLoopRun()
