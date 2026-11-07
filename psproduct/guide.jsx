// ydot 가이드: 규격을 고르면(Shift Convert 카드 패널) ydot 기본값(또는 조절한 값)으로 잘릴 자리를 안내선 4개로 표시. 문서 내용은 바꾸지 않음
#target photoshop
//@include-common
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
