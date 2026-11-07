// ydot 인화 (2026-11-04, 이름 2026-11-05): 카드에서 규격 고르기 → ① 데스크톱 "original.jpg" ② 규격대로 자른 "고화질.jpg" ③ 300ppi 규격 크기 "저화질.jpg" (겹치면 세트 전체에 _1, _2 …) (Custom을 고르면 화면 그대로를 Shift Convert Custom으로) ④ 새 5×7in 캔버스(Untitled-N)에 인화지 배치 → 바로 ⌘P
// 작업하던 원본 사진은 건드리지 않음(프로필만 예외: 끝에 원본 탭을 1차 크롭대로 잘라 둠, ⌘Z로 되돌림): 합친 복사본 하나로 ①~④를 하고 그 복사본만 닫음 (원본 탭은 인화 전 그대로, 히스토리도 안 남음)
// 저장은 JPG 12 Baseline(⌘⇧S와 같음). 16비트면 자르기·줄이기는 16비트로 하고 저장할 때만 8비트. 이름이 겹치면 세트 전체에 같은 꼬리 _1 … (덮어쓰기 없음)
#target photoshop
//@include-common
YDOT.run(function () {
    if (app.documents.length == 0) YDOT.fail("열린 사진이 없어요.");
    var doc = app.activeDocument, units = app.preferences.rulerUnits, work = null, sheet = null, step = "준비";
    var SFX = ""; function named(base) { return File(Folder.desktop.fsName + "/" + base + SFX + ".jpg"); }   // SFX = 이름 꼬리(_1 …). T(위 좌표)와 이름이 겹치던 버그 고침 (2026-11-05)
    try {
        app.preferences.rulerUnits = Units.PIXELS;
        var r = YDOT.pick(doc, null, true); if (!r) YDOT.stop();   // 매번 직접 고름. 안 고르고 닫으면 조용히 끝
        var NM = { o: r.nOriginal || "original", c: r.nCrop || "crop", h: r.nHigh || "고화질", l: r.nLow || "저화질", s: r.nSheet || "인화" };   // ydot 설정 › 파일 이름 (예전 ydot이면 기본 이름)
        var toFile = r.psFile == "1", toPS = r.psPS != "0", makeSheet = toFile || toPS;   // ydot 설정 › 인화지 출력 (예전 ydot = 값 없음 → 새 문서로, 지금과 같음) (2026-11-05)
        if (r.custom == "1") {   // Custom (2026-11-05): 패널에서 고른 자리대로 포토샵이 직접 — original · crop(1차) · 고화질(2차) + 폴라로이드 인화지
            var cs = r.scale, CW0 = doc.width.as("px"), CH0 = doc.height.as("px");
            function box(x, y, w, h) { var l = Math.max(0, Math.round(Number(x) / cs)), t = Math.max(0, Math.round(Number(y) / cs)); return [l, t, Math.min(CW0, Math.round((Number(x) + Number(w)) / cs)), Math.min(CH0, Math.round((Number(y) + Number(h)) / cs))]; }
            var only1 = r.only1 == "1";   // 프로필 Done = 1차 크롭만 (원본 · crop), 고화질·인화지 없음 (2026-11-05)
            var b1 = box(r.x1, r.y1, r.w1, r.h1), b2 = only1 ? b1 : box(r.x2, r.y2, r.w2, r.h2);
            if (b1[2] - b1[0] < 10 || b2[2] - b2[0] < 10) YDOT.fail("자를 자리를 계산하지 못했어요.");
            step = "복사본 만들기"; work = doc.duplicate("ydot 인화", true); work.flatten();
            if (work.mode != DocumentMode.RGB) work.changeMode(ChangeMode.RGB);
            SFX = YDOT.nextSfx(only1 ? [NM.o, NM.c] : toFile ? [NM.o, NM.c, NM.h, NM.s] : [NM.o, NM.c, NM.h]);
            step = "원본 저장"; YDOT.saveJPG(work, named(NM.o));
            step = "crop 저장"; var c1 = work.duplicate("ydot crop", true); c1.crop([UnitValue(b1[0], "px"), UnitValue(b1[1], "px"), UnitValue(b1[2], "px"), UnitValue(b1[3], "px")]); YDOT.saveJPG(c1, named(NM.c));
            if (only1) { YDOT.closeQuiet(c1); c1 = null; } else {
            step = "고화질 저장"; app.activeDocument = work; work.crop([UnitValue(b2[0], "px"), UnitValue(b2[1], "px"), UnitValue(b2[2], "px"), UnitValue(b2[3], "px")]); YDOT.saveJPG(work, named(NM.h));
            step = "인화지 만들기"; try { if (makeSheet) sheet = r.lay ? YDOT.sheetLay(work, r.lay, null, r.layItems) : YDOT.customSheet(c1, work, r); } finally { YDOT.closeQuiet(c1); }   // 프로필 인화지 = 인화지 탭 프로필 배치 (예전 ydot = 고정 배치)
            }
        } else {
        var W = doc.width.as("px"), H = doc.height.as("px"), s = r.scale;
        var x = Number(r.x) / s, y = Number(r.y) / s, w = Number(r.w) / s, h = Number(r.h) / s, pw = Number(r.pw), ph = Number(r.ph);
        if (!(w > 10 && h > 10 && pw > 10 && ph > 10)) YDOT.fail("자를 자리를 계산하지 못했어요.");
        var L = Math.max(0, Math.round(x)), T = Math.max(0, Math.round(y)), CW = Math.min(Math.round(w), W - L), CH = Math.min(Math.round(h), H - T);
        // 합친 복사본 하나 (원본은 그대로)
        step = "복사본 만들기";
        work = doc.duplicate("ydot 인화", true); work.flatten();
        if (work.mode != DocumentMode.RGB) work.changeMode(ChangeMode.RGB);
        SFX = YDOT.nextSfx(toFile ? [NM.o, NM.h, NM.l, NM.s] : [NM.o, NM.h, NM.l]);
        step = "원본 저장"; YDOT.saveJPG(work, named(NM.o));
        step = "자르기"; work.crop([UnitValue(L, "px"), UnitValue(T, "px"), UnitValue(L + CW, "px"), UnitValue(T + CH, "px")]);
        step = "고화질 저장"; YDOT.saveJPG(work, named(NM.h));
        step = "300ppi로 줄이기"; work.resizeImage(UnitValue(pw, "px"), UnitValue(ph, "px"), 300, ResampleMethod.AUTOMATIC);
        step = "저화질 저장"; YDOT.saveJPG(work, named(NM.l));
        step = "인화지 만들기"; if (makeSheet) sheet = r.lay ? YDOT.sheetLay(work, r.lay, r.laySig, r.layItems) : YDOT.sheet(work, r.spec);   // ydot 설정 › 인화지 배치 (예전 ydot = 값 없음 → 예전 배치)   // work를 그대로 씀 (눕힘·sRGB 변환도 work에서)
        }
    } catch (e) {
        app.preferences.rulerUnits = units;
        if (e && e.ydotMsg !== undefined) { YDOT.closeQuiet(work); throw e; }
        YDOT.closeQuiet(work);
        var saved = step == "인화지 만들기" ? "\n파일은 데스크톱에 저장됐어요." : "";
        YDOT.fail("인화 중 '" + step + "' 단계에서 문제가 생겼어요.\n작업하던 사진은 그대로예요." + saved + "\n\n(" + (e && e.message ? e.message : e) + ")");
    }
    YDOT.closeQuiet(work);
    if (r.custom == "1" && b1) { try { app.activeDocument = doc; doc.crop([UnitValue(b1[0], "px"), UnitValue(b1[1], "px"), UnitValue(b1[2], "px"), UnitValue(b1[3], "px")]); } catch (eC) {} }   // 프로필: 원본 탭도 1차 크롭대로 잘라 둠 (⌘Z로 되돌림, 저장 안 함 · 사용자 2026-11-05)
    if (sheet && toFile) { try { YDOT.saveJPG(sheet, named(NM.s)); } catch (e3) { app.preferences.rulerUnits = units; YDOT.fail("인화지를 파일로 저장하지 못했어요.\n사진 파일은 데스크톱에 저장됐어요.\n\n(" + (e3 && e3.message ? e3.message : e3) + ")"); } }
    app.preferences.rulerUnits = units;
    if (sheet && !toPS) { YDOT.closeQuiet(sheet); sheet = null; }   // 파일로만: 새 문서는 닫음
    if (sheet) app.activeDocument = sheet;   // 인화지가 맨 앞 → ⌘P
});
