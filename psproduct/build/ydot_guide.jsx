// ydot 가이드: 규격을 고르면(Shift Convert 카드 패널) ydot 기본값(또는 조절한 값)으로 잘릴 자리를 안내선 4개로 표시. 문서 내용은 바꾸지 않음
#target photoshop
// ydot 포토샵 연동 공통 (ydot_guide.jsx · ydot_print.jsx 맨 앞에 붙여 빌드됨)
// 원칙: 원본 문서는 절대 바꾸지 않음(복제본으로만 작업), 단위 설정은 끝나면 되돌림, 실패하면 이유를 알리고 멈춤
var YDOT = {};
YDOT.title = "ydot";
YDOT.findDonut = function () {
    var h = Folder("~").fsName, c = ["/Applications/ydot.app/Contents/MacOS/Donut", h + "/Applications/ydot.app/Contents/MacOS/Donut",   // 새 ydot = Shift Convert 자체 (2026-11-05)
             "/Applications/ydot.app/Contents/Helpers/Shift Convert.app/Contents/MacOS/Donut", h + "/Applications/ydot.app/Contents/Helpers/Shift Convert.app/Contents/MacOS/Donut"];   // 예전 한 몸 ydot
    for (var i = 0; i < c.length; i++) { if (File(c[i]).exists) return c[i]; }
    return null;
};
YDOT.q = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; };   // 셸용 따옴표
YDOT.tmp = function () {
    var f = Folder(Folder.temp.fsName + "/ydot_ps_" + (new Date().getTime()) + "_" + Math.floor(Math.random() * 100000));
    f.create(); return f;
};
YDOT.readResult = function (path) {   // 키=값 줄 → 객체
    var f = File(path), o = {};
    if (!f.exists) return null;
    f.encoding = "UTF-8"; if (!f.open("r")) return null;
    while (!f.eof) { var l = f.readln(), i = l.indexOf("="); if (i > 0) o[l.substring(0, i)] = l.substring(i + 1); }
    f.close(); return o;
};
YDOT.cleanup = function (folder) { try { var fs = folder.getFiles(); for (var i = 0; i < fs.length; i++) fs[i].remove(); folder.remove(); } catch (e) {} };
YDOT.fail = function (msg) { throw { ydotMsg: msg }; };   // 멈춤: YDOT.run이 알림을 한 번만 띄움 (포토샵 오류 창은 안 뜸)
YDOT.stop = function () { throw { ydotMsg: "" }; };       // 조용히 멈춤 (취소)
YDOT.run = function (fn) {
    try { fn(); }
    catch (e) {
        if (e && e.ydotMsg !== undefined) { if (e.ydotMsg) alert(e.ydotMsg, YDOT.title, true); }
        else alert("문제가 생겨 멈췄어요.\n\n(" + (e && e.message ? e.message : e) + ")", YDOT.title, true);
    }
};
YDOT.exportFlat = function (doc, file, maxEdge) {   // 원본은 그대로 두고, 합친 복제본을 8비트 RGB JPG로 저장. 줄였다면 배율 반환
    var dup = doc.duplicate("ydot_tmp", true), scale = 1;
    try {
        dup.flatten();
        if (dup.mode != DocumentMode.RGB) dup.changeMode(ChangeMode.RGB);
        if (dup.bitsPerChannel != BitsPerChannelType.EIGHT) dup.bitsPerChannel = BitsPerChannelType.EIGHT;
        if (maxEdge) {
            var w = dup.width.as("px"), h = dup.height.as("px"), m = Math.max(w, h);
            if (m > maxEdge) { scale = maxEdge / m; dup.resizeImage(UnitValue(Math.round(w * scale), "px"), UnitValue(Math.round(h * scale), "px"), dup.resolution, ResampleMethod.BICUBIC); }
        }
        var o = new JPEGSaveOptions(); o.quality = 12; o.embedColorProfile = true; o.formatOptions = FormatOptions.STANDARDBASELINE;
        dup.saveAs(file, o, true, Extension.LOWERCASE);
    } finally { dup.close(SaveOptions.DONOTSAVECHANGES); }
    return scale;
};
// 인화지 배치 (사용자 샘플 액션과 같은 결과): 사진 + 사방 10px 확장 선택 → 1px 회색(204) 가운데 선. 칸 = 사진 + 20px, 칸끼리 맞붙여 캔버스 가운데
// rot = 시계 방향 90° 눕힘 (반명함·중국비자, 사용자 샘플대로)
YDOT.layouts = {
    "증명": { c: 3, r: 3, rot: false }, "여권": { c: 3, r: 3, rot: false },
    "반명함": { c: 2, r: 5, rot: true }, "중국비자": { c: 2, r: 4, rot: true },
    "소형": { c: 3, r: 4, rot: false }, "미국비자": { c: 2, r: 3, rot: false },
    "명함": { c: 2, r: 2, rot: false }
};
YDOT.sheet = function (src, spec) {
    var L = YDOT.layouts[spec]; if (!L) throw new Error("'" + spec + "' 규격의 인화지 배치가 없어요.");
    var SW = 1500, SH = 2100, pad = 10;   // 5×7in 300ppi
    // 받은 문서(인화용 복사본)를 그대로 씀
    var dup = src, sheet = null;
    try {
        app.activeDocument = dup; dup.flatten();
        if (dup.mode != DocumentMode.RGB) dup.changeMode(ChangeMode.RGB);
        if (dup.bitsPerChannel != BitsPerChannelType.EIGHT) dup.bitsPerChannel = BitsPerChannelType.EIGHT;
        try { dup.convertProfile("sRGB IEC61966-2.1", Intent.RELATIVECOLORIMETRIC, true, false); } catch (e) {}
        if (L.rot) dup.rotateCanvas(90);
        var pw = Math.round(dup.width.as("px")), ph = Math.round(dup.height.as("px")), tw = pw + pad * 2, th = ph + pad * 2;
        if (L.c * tw > SW || L.r * th > SH) throw new Error("사진이 5×7 인화지에 다 들어가지 않아요 (" + spec + ").");
        dup.activeLayer.isBackgroundLayer = false;
        // 새 캔버스: ⌘N 5×7in 300ppi와 같음 (이름 없이 → Untitled-N)
        sheet = app.documents.add(UnitValue(SW, "px"), UnitValue(SH, "px"), 300, undefined, NewDocumentMode.RGB, DocumentFill.WHITE, 1, BitsPerChannelType.EIGHT, "sRGB IEC61966-2.1");
        app.activeDocument = dup;
        var base = dup.activeLayer.duplicate(sheet, ElementPlacement.PLACEATBEGINNING);   // 클립보드 안 씀
        app.activeDocument = sheet; sheet.activeLayer = sheet.layers[0]; var tile = sheet.activeLayer;
        // 칸 하나 만들기: 사진 영역 선택 → 10px 확장 → 1px 회색 가운데 선 (사용자 액션과 같은 명령)
        var x0 = Math.round((SW - L.c * tw) / 2) + pad, y0 = Math.round((SH - L.r * th) / 2) + pad;
        var b = tile.bounds; tile.translate(UnitValue(x0 - b[0].as("px"), "px"), UnitValue(y0 - b[1].as("px"), "px"));
        var s1 = new ActionDescriptor(), rr = new ActionReference(), tr = new ActionReference();
        rr.putProperty(charIDToTypeID("Chnl"), charIDToTypeID("fsel")); s1.putReference(charIDToTypeID("null"), rr);
        tr.putEnumerated(charIDToTypeID("Chnl"), charIDToTypeID("Chnl"), charIDToTypeID("Trsp")); s1.putReference(charIDToTypeID("T   "), tr);
        executeAction(charIDToTypeID("setd"), s1, DialogModes.NO);
        var ex = new ActionDescriptor(); ex.putUnitDouble(charIDToTypeID("By  "), charIDToTypeID("#Pxl"), pad); ex.putBoolean(stringIDToTypeID("selectionModifyEffectAtCanvasBounds"), false);
        executeAction(charIDToTypeID("Expn"), ex, DialogModes.NO);
        var st = new ActionDescriptor(), col = new ActionDescriptor();
        st.putInteger(charIDToTypeID("Wdth"), 1); st.putEnumerated(charIDToTypeID("Lctn"), charIDToTypeID("StrL"), charIDToTypeID("Cntr"));
        st.putUnitDouble(charIDToTypeID("Opct"), charIDToTypeID("#Prc"), 100); st.putEnumerated(charIDToTypeID("Md  "), charIDToTypeID("BlnM"), charIDToTypeID("Nrml"));
        col.putDouble(charIDToTypeID("Rd  "), 204); col.putDouble(charIDToTypeID("Grn "), 204); col.putDouble(charIDToTypeID("Bl  "), 204);
        st.putObject(charIDToTypeID("Clr "), charIDToTypeID("RGBC"), col);
        executeAction(charIDToTypeID("Strk"), st, DialogModes.NO);
        sheet.selection.deselect();
        // 나머지 칸: 복제해서 정확한 픽셀만큼 이동
        for (var r = 0; r < L.r; r++) for (var c = 0; c < L.c; c++) {
            if (r == 0 && c == 0) continue;
            var t = tile.duplicate(); t.translate(UnitValue(c * tw, "px"), UnitValue(r * th, "px"));
        }
        // 칸들만 한 레이어로 병합 (흰 배경은 그대로)
        var bg = sheet.backgroundLayer; bg.visible = false; sheet.mergeVisibleLayers(); bg.visible = true;
        sheet.activeLayer = sheet.layers[0];
    } catch (e) {
        if (sheet) { try { sheet.close(SaveOptions.DONOTSAVECHANGES); } catch (e2) {} }
        throw e;
    }
    app.activeDocument = sheet;
    return sheet;
};
// 인화지 배치 (ydot 설정 › 인화지, 2026-11-06): lay = "W,H,여백,선두께,선밝기;x,y,q;…" — x,y = 사진 왼쪽 위(px), q = 시계 방향 90° 횟수. 칸마다: 사진 → 여백만큼 넓힌 선택 → 안쪽 선
YDOT.sheetLay = function (src, lay, sigPath, itemsDir) {   // 특별 칸 그림: itemsDir/키.png (s 로고 사진 · l높이 로고만 · f아이디 프레임 사진 · ydot이 만든 PNG, 다 쓰면 지움) · sigPath = 예전 ydot (로고 사진 하나)
    var parts = String(lay).split(";"), h = parts[0].split(","), SW = Number(h[0]), SH = Number(h[1]), pad = Number(h[2]), sw = Number(h[3]), gray = Number(h[4]);
    var cells = [], need = {};
    for (var i = 1; i < parts.length; i++) { if (!parts[i]) continue; var c = parts[i].split(","); var q = ((Number(c[2]) % 4) + 4) % 4, key = c.length > 3 ? String(c[3]) : ""; cells.push({ x: Number(c[0]), y: Number(c[1]), q: q, k: key }); need[key + "|" + q] = true; }
    var dir = itemsDir ? Folder(itemsDir) : null, itemDocs = {}, sigFile = sigPath ? File(sigPath) : null;
    function itemFile(key) { if (dir && dir.exists) { var f = File(dir.fsName + "/" + key + ".png"); if (f.exists) return f; } return key == "s" && sigFile && sigFile.exists ? sigFile : null; }
    if (!(SW > 0 && SH > 0) || cells.length == 0) throw new Error("인화지 배치를 읽지 못했어요.");
    var dup = src, sheet = null, rots = {};
    try {
        app.activeDocument = dup; dup.flatten();
        if (dup.mode != DocumentMode.RGB) dup.changeMode(ChangeMode.RGB);
        if (dup.bitsPerChannel != BitsPerChannelType.EIGHT) dup.bitsPerChannel = BitsPerChannelType.EIGHT;
        try { dup.convertProfile("sRGB IEC61966-2.1", Intent.RELATIVECOLORIMETRIC, true, false); } catch (e) {}
        for (var k in need) {
            var bar = k.lastIndexOf("|"), key = k.substring(0, bar), qq = Number(k.substring(bar + 1));
            if (key) { var f = itemFile(key); if (!f) continue; if (!itemDocs[key]) { var od = app.open(f); itemDocs[key] = od; if (od.mode != DocumentMode.RGB) od.changeMode(ChangeMode.RGB); if (od.bitsPerChannel != BitsPerChannelType.EIGHT) od.bitsPerChannel = BitsPerChannelType.EIGHT; od.flatten(); } app.activeDocument = itemDocs[key]; var s2 = itemDocs[key].duplicate("ydot 칸 " + k, true); }
            else { app.activeDocument = dup; var s2 = dup.duplicate("ydot 칸 " + k, true); }
            if (qq) s2.rotateCanvas(90 * qq); s2.activeLayer.isBackgroundLayer = false; rots[k] = s2;
        }
        sheet = app.documents.add(UnitValue(SW, "px"), UnitValue(SH, "px"), 300, undefined, NewDocumentMode.RGB, DocumentFill.WHITE, 1, BitsPerChannelType.EIGHT, "sRGB IEC61966-2.1");
        for (var j = 0; j < cells.length; j++) {
            var cl = cells[j], rd = rots[cl.k + "|" + cl.q]; if (!rd) continue; app.activeDocument = rd;
            rd.activeLayer.duplicate(sheet, ElementPlacement.PLACEATBEGINNING);
            app.activeDocument = sheet; sheet.activeLayer = sheet.layers[0]; var t = sheet.activeLayer, b = t.bounds;
            t.translate(UnitValue(cl.x - b[0].as("px"), "px"), UnitValue(cl.y - b[1].as("px"), "px"));
            if (sw > 0 && cl.k.charAt(0) != "l") {   // 로고만 칸은 선 없음
                var s1 = new ActionDescriptor(), rr = new ActionReference(), tr = new ActionReference();
                rr.putProperty(charIDToTypeID("Chnl"), charIDToTypeID("fsel")); s1.putReference(charIDToTypeID("null"), rr);
                tr.putEnumerated(charIDToTypeID("Chnl"), charIDToTypeID("Chnl"), charIDToTypeID("Trsp")); s1.putReference(charIDToTypeID("T   "), tr);
                executeAction(charIDToTypeID("setd"), s1, DialogModes.NO);
                if (pad > 0) { var ex = new ActionDescriptor(); ex.putUnitDouble(charIDToTypeID("By  "), charIDToTypeID("#Pxl"), pad); ex.putBoolean(stringIDToTypeID("selectionModifyEffectAtCanvasBounds"), false); executeAction(charIDToTypeID("Expn"), ex, DialogModes.NO); }
                var st = new ActionDescriptor(), col = new ActionDescriptor();
                st.putInteger(charIDToTypeID("Wdth"), sw); st.putEnumerated(charIDToTypeID("Lctn"), charIDToTypeID("StrL"), charIDToTypeID("Insd"));
                st.putUnitDouble(charIDToTypeID("Opct"), charIDToTypeID("#Prc"), 100); st.putEnumerated(charIDToTypeID("Md  "), charIDToTypeID("BlnM"), charIDToTypeID("Nrml"));
                col.putDouble(charIDToTypeID("Rd  "), gray); col.putDouble(charIDToTypeID("Grn "), gray); col.putDouble(charIDToTypeID("Bl  "), gray);
                st.putObject(charIDToTypeID("Clr "), charIDToTypeID("RGBC"), col);
                executeAction(charIDToTypeID("Strk"), st, DialogModes.NO);
                sheet.selection.deselect();
            }
        }
        if (sheet.layers.length > 2) { var bg = sheet.backgroundLayer; bg.visible = false; sheet.mergeVisibleLayers(); bg.visible = true; }   // 칸 한 장이면 합칠 것 없음
        sheet.activeLayer = sheet.layers[0];
    } catch (e) {
        if (sheet) { try { sheet.close(SaveOptions.DONOTSAVECHANGES); } catch (e2) {} }
        throw e;
    } finally { for (var r in rots) YDOT.closeQuiet(rots[r]); for (var dk in itemDocs) YDOT.closeQuiet(itemDocs[dk]); if (sigFile && sigFile.exists) { try { sigFile.remove(); } catch (eR) {} } if (dir && dir.exists) YDOT.cleanup(dir); }
    app.activeDocument = sheet;
    return sheet;
};
YDOT.closeQuiet = function (d) { if (d) { try { d.close(SaveOptions.DONOTSAVECHANGES); } catch (e) {} } };
YDOT.saveJPG = function (d, file) {   // JPG 12 Baseline 저장 (⌘⇧S와 같음). 이미 8비트 RGB 한 장이면 바로, 아니면 8비트 복사본으로
    var o = new JPEGSaveOptions(); o.quality = 12; o.embedColorProfile = true; o.formatOptions = FormatOptions.STANDARDBASELINE;
    var simple = d.bitsPerChannel == BitsPerChannelType.EIGHT && d.mode == DocumentMode.RGB && d.layers.length == 1;
    if (simple) d.saveAs(file, o, true, Extension.LOWERCASE);
    else { var c = d.duplicate("ydot_jpg", true); try { c.flatten(); if (c.mode != DocumentMode.RGB) c.changeMode(ChangeMode.RGB); if (c.bitsPerChannel != BitsPerChannelType.EIGHT) c.bitsPerChannel = BitsPerChannelType.EIGHT; c.saveAs(file, o, true, Extension.LOWERCASE); } finally { YDOT.closeQuiet(c); } }
    app.activeDocument = d;
    if (!file.exists) throw new Error(file.name + "을 저장하지 못했어요.");
};
YDOT.statePath = function () { var f = Folder(Folder.userData.fsName + "/cc"); if (!f.exists) f.create(); return f.fsName + "/ydot_ps_state.txt"; };
YDOT.docKey = function (doc) { var k = doc.name; try { k = doc.fullName.fsName; } catch (e) {} return k + "|" + Math.round(doc.width.as("px")) + "x" + Math.round(doc.height.as("px")); };
YDOT.saveState = function (o) {
    var f = File(YDOT.statePath()); f.encoding = "UTF-8"; f.lineFeed = "Unix"; if (!f.open("w")) return;
    for (var k in o) f.writeln(k + "=" + o[k]); f.close();
};
// 규격 고르기 + 자를 자리 (Shift Convert 카드 패널). 반환: 결과 객체 (ok=1) / 취소면 null
// 이름 규칙 (Shift Convert와 같음, 2026-11-05): original · 고화질 · 저화질, 겹치면 세트 전체에 같은 꼬리 _1, _2 … (세 이름이 모두 비어 있는 가장 작은 꼬리)
YDOT.nextSfx = function (names) {
    for (var k = 0; k < 100000; k++) { var t = k == 0 ? "" : "_" + k, ok = true;
        for (var i = 0; i < names.length; i++) if (File(Folder.desktop.fsName + "/" + names[i] + t + ".jpg").exists) ok = false;
        if (ok) return t; }
    return "_" + k;
};
// Custom 인화지 (2026-11-05): Shift Convert의 Sheet와 같은 규칙 — 바꿀 땐 두 곳(Donut.swift Sheet · 여기)을 같이
// 5×7in 300ppi. 위 = 폴라로이드 2장(짧은 변 = 사진 폭 413px, 사진 4.5cm 위·좌·우 꽉 + 아래 로고 띠 63px(로고 35 + 위아래 14), 반시계 90° 돌림, 두 장 가운데)
// 아래 = 작은 사진 6장(3.5×4.5cm + 사방 10px 흰 여백), 칸마다 1px 회색(204) 선(안쪽), 칸끼리 맞붙여 가운데
YDOT.customSheet = function (c1, c2, o) {   // o = ydot 결과 (설정 › 시그니처: logoFile · polStrip · logoH · logoMargin · logoAlign). 없으면 예전과 같음
    function num(v, d) { var n = Number(v); return (v === undefined || v === "" || isNaN(n)) ? d : n; }
    o = o || {}; var STRIP = num(o.polStrip, 63), LH = Math.min(num(o.logoH, 35), STRIP), MR = num(o.logoMargin, 24), ALIGN = o.logoAlign || "right";
    var SW = 1500, SH = 2100, pw = 413, ph = 531, cw = pw + 20, ch = ph + 20, gw = cw * 3, strip = STRIP, polL = [ph + strip, ph + strip];   // 로고 띠 = 로고 35 + 위아래 14px, 사진 3.5×4.5 그대로 (2026-11-05)
    var left = Math.floor((SW - gw) / 2), top = Math.floor((SH - (pw + ch * 2)) / 2), tmp = [], sheet = null;
    function px(v) { return UnitValue(v, "px"); }
    function prep(src) {   // 복제 → 8비트 sRGB → 413×531 (비율이 다르면 가운데로 꽉 채워 자름)
        app.activeDocument = src; var d = src.duplicate("ydot tmp", true); tmp.push(d); app.activeDocument = d; d.flatten();
        if (d.mode != DocumentMode.RGB) d.changeMode(ChangeMode.RGB);
        if (d.bitsPerChannel != BitsPerChannelType.EIGHT) d.bitsPerChannel = BitsPerChannelType.EIGHT;
        try { d.convertProfile("sRGB IEC61966-2.1", Intent.RELATIVECOLORIMETRIC, true, false); } catch (e) {}
        var w = d.width.as("px"), h = d.height.as("px"), k = Math.max(pw / w, ph / h);
        d.resizeImage(px(Math.max(pw, Math.round(w * k))), px(Math.max(ph, Math.round(h * k))), 300, ResampleMethod.BICUBIC);
        var W = d.width.as("px"), H = d.height.as("px"), x = Math.round((W - pw) / 2), y = Math.round((H - ph) / 2);
        d.crop([px(x), px(y), px(x + pw), px(y + ph)]); d.activeLayer.isBackgroundLayer = false; return d;
    }
    function moveTo(layer, x, y) { var b = layer.bounds; layer.translate(px(x - b[0].as("px")), px(y - b[1].as("px"))); }
    function copyInto(srcDoc, dst, x, y) { app.activeDocument = srcDoc; var l = srcDoc.activeLayer.duplicate(dst, ElementPlacement.PLACEATBEGINNING); app.activeDocument = dst; moveTo(dst.activeLayer = dst.layers[0], x, y); return dst.layers[0]; }
    function strokeRect(doc, x, y, w, h) {   // 1px 회색(204) 안쪽 선
        app.activeDocument = doc; doc.selection.select([[x, y], [x + w, y], [x + w, y + h], [x, y + h]]);
        var st = new ActionDescriptor(), col = new ActionDescriptor();
        st.putInteger(charIDToTypeID("Wdth"), 1); st.putEnumerated(charIDToTypeID("Lctn"), charIDToTypeID("StrL"), charIDToTypeID("Insd"));
        st.putUnitDouble(charIDToTypeID("Opct"), charIDToTypeID("#Prc"), 100); st.putEnumerated(charIDToTypeID("Md  "), charIDToTypeID("BlnM"), charIDToTypeID("Nrml"));
        col.putDouble(charIDToTypeID("Rd  "), 204); col.putDouble(charIDToTypeID("Grn "), 204); col.putDouble(charIDToTypeID("Bl  "), 204);
        st.putObject(charIDToTypeID("Clr "), charIDToTypeID("RGBC"), col);
        executeAction(charIDToTypeID("Strk"), st, DialogModes.NO); doc.selection.deselect();
    }
    try {
        var P = prep(c1), S = prep(c2), logo = null;
        var donut = YDOT.findDonut(), lf = null;
        if (o.logoFile == "none" || STRIP <= 0) lf = null;
        else if (o.logoFile) lf = File(o.logoFile);
        else lf = donut ? File(donut.replace(/MacOS\/Donut$/, "Resources/logo.ai")) : null;
        if (lf && lf.exists) {   // 로고: 그림 있는 자리만 열어 높이 LH(기본 0.3cm = 35px)로. ai·pdf = 벡터로 열기, 그 밖(png·jpg) = 그림
            if (/\.(ai|pdf)$/i.test(lf.name)) { var po = new PDFOpenOptions(); po.cropPage = CropToType.BOUNDINGBOX; po.resolution = 1200; po.mode = OpenDocumentMode.RGB; po.antiAlias = true; po.suppressWarnings = true; logo = app.open(lf, po); }
            else logo = app.open(lf);
            tmp.push(logo); app.activeDocument = logo;
            if (logo.mode != DocumentMode.RGB) logo.changeMode(ChangeMode.RGB);
            try { logo.trim(TrimType.TRANSPARENT); } catch (e) { try { logo.trim(TrimType.TOPLEFT); } catch (e2) {} }
            var lw = logo.width.as("px"), lh = logo.height.as("px");
            logo.resizeImage(px(Math.max(1, Math.round(lw * LH / lh))), px(LH), 300, ResampleMethod.BICUBIC); logo.flatten(); logo.activeLayer.isBackgroundLayer = false;
        }
        sheet = app.documents.add(px(SW), px(SH), 300, undefined, NewDocumentMode.RGB, DocumentFill.WHITE, 1, BitsPerChannelType.EIGHT, "sRGB IEC61966-2.1");   // 이름 없이 → Untitled-N
        var x = Math.floor((SW - polL[0] - polL[1]) / 2);   // 폴라로이드 두 장은 가운데로
        for (var i = 0; i < 2; i++) {   // 폴라로이드: 세운 모양(413 × L)을 만들고 반시계 90° → 사진 위가 왼쪽, 로고 띠가 오른쪽
            var L = polL[i], pd = app.documents.add(px(pw), px(L), 300, "ydot polaroid", NewDocumentMode.RGB, DocumentFill.WHITE, 1, BitsPerChannelType.EIGHT, "sRGB IEC61966-2.1"); tmp.push(pd);
            copyInto(P, pd, 0, 0);
            if (logo) { var lW = logo.width.as("px"), lX = ALIGN == "left" ? MR : ALIGN == "center" ? Math.round((pw - lW) / 2) : pw - MR - lW; copyInto(logo, pd, lX, ph + Math.round((L - ph - LH) / 2)); }
            app.activeDocument = pd; pd.flatten(); pd.rotateCanvas(-90); pd.activeLayer.isBackgroundLayer = false;
            copyInto(pd, sheet, x, top); strokeRect(sheet, x, top, L, pw); x += L;
        }
        for (var r = 0; r < 2; r++) for (var c = 0; c < 3; c++) {   // 작은 사진 6장
            var cx = left + c * cw, cy = top + pw + r * ch;
            copyInto(S, sheet, cx + 10, cy + 10); strokeRect(sheet, cx, cy, cw, ch);
        }
        app.activeDocument = sheet; var bg = sheet.backgroundLayer; bg.visible = false; sheet.mergeVisibleLayers(); bg.visible = true; sheet.activeLayer = sheet.layers[0];
    } catch (e) {
        if (sheet) { try { sheet.close(SaveOptions.DONOTSAVECHANGES); } catch (e2) {} }
        for (var t = 0; t < tmp.length; t++) YDOT.closeQuiet(tmp[t]);
        throw e;
    }
    for (var t2 = 0; t2 < tmp.length; t2++) YDOT.closeQuiet(tmp[t2]);
    app.activeDocument = sheet;
    return sheet;
};
YDOT.pick = function (doc, preset, allowCustom) {   // preset = {spec, head, top} 이면 그 규격 조절 화면으로 바로 (← 뒤로 = 다른 규격). allowCustom = 카드에 Custom도 (인화만)
    var donut = YDOT.findDonut();
    if (!donut) YDOT.fail("ydot이 설치돼 있지 않아요.\nydot을 설치한 뒤 다시 해 주세요.");
    var t = YDOT.tmp(), img = File(t.fsName + "/guide.jpg"), out = t.fsName + "/guide.txt", r, scale;
    try {
        scale = YDOT.exportFlat(doc, img, 2400);
        var pre = preset ? " " + YDOT.q(preset.spec) + " " + YDOT.q(preset.head) + " " + YDOT.q(preset.top) : "";
        app.system((allowCustom ? "DONUT_PS_CUSTOM=1 " : "") + YDOT.q(donut) + " --psguide " + YDOT.q(img.fsName) + " " + YDOT.q(out) + pre + " >/dev/null 2>&1");
        r = YDOT.readResult(out);
    } finally { YDOT.cleanup(t); }
    if (!r) YDOT.fail("Shift Convert에서 결과를 받지 못했어요.\n다시 해 주세요.");
    if (r.ok != "1") { if (r.reason == "cancel") return null; YDOT.fail("사용불가\n\n" + r.reason + "\n얼굴이 하나만 또렷하게 나온 세로 사진이어야 해요."); }
    r.scale = scale; return r;
};

YDOT.run(function () {
    if (app.documents.length == 0) YDOT.fail("열린 사진이 없어요.");
    var doc = app.activeDocument, units = app.preferences.rulerUnits;
    try {
        app.preferences.rulerUnits = Units.PIXELS;
        var r = YDOT.pick(doc, null); if (!r) return;   // 취소. 가이드는 항상 카드(규격 고르기)부터 (사용자 2026-11-04)
        var s = r.scale, x = Number(r.x) / s, y = Number(r.y) / s, w = Number(r.w) / s, h = Number(r.h) / s;
        // 지난번 ydot 안내선만 지움 (사용자가 직접 만든 안내선은 그대로)
        var st = YDOT.readResult(YDOT.statePath());
        if (st && st.doc == YDOT.docKey(doc) && st.gx) {
            var old = [Number(st.gx), Number(st.gx) + Number(st.gw), Number(st.gy), Number(st.gy) + Number(st.gh)];
            for (var i = doc.guides.length - 1; i >= 0; i--) {
                var g = doc.guides[i], c = g.coordinate.as("px"), vert = g.direction == Direction.VERTICAL;
                for (var j = 0; j < 4; j++) if ((j < 2) == vert && Math.abs(c - old[j]) < 0.6) { g.remove(); break; }
            }
        }
        doc.guides.add(Direction.VERTICAL, UnitValue(x, "px")); doc.guides.add(Direction.VERTICAL, UnitValue(x + w, "px"));
        doc.guides.add(Direction.HORIZONTAL, UnitValue(y, "px")); doc.guides.add(Direction.HORIZONTAL, UnitValue(y + h, "px"));
        YDOT.saveState({ doc: YDOT.docKey(doc), spec: r.spec, head: r.head, top: r.top, gx: x, gy: y, gw: w, gh: h });
    } finally { app.preferences.rulerUnits = units; }
});
