// 포토샵 일괄 렌더링: 목록의 파일을 Camera Raw 설정대로 열어 sRGB 8비트 JPG로 저장
app.displayDialogs = DialogModes.NO;
var lf = new File(LISTFILE); lf.encoding = "UTF-8"; lf.open("r");
var lines = lf.read().split("\n"); lf.close();
var outDir = OUTDIR, longEdge = LONGEDGE, log = [];
for (var i = 0; i < lines.length; i++) {
    var p = lines[i]; if (!p) continue;
    var base = p.substring(p.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
    try {
        var doc = app.open(new File(p));
        doc.bitsPerChannel = BitsPerChannelType.EIGHT;
        doc.convertProfile("sRGB IEC61966-2.1", Intent.RELATIVECOLORIMETRIC, true, false);
        if (longEdge > 0) {
            if (doc.width.as("px") >= doc.height.as("px")) doc.resizeImage(UnitValue(longEdge, "px"), null, 72, ResampleMethod.BICUBIC);
            else doc.resizeImage(null, UnitValue(longEdge, "px"), 72, ResampleMethod.BICUBIC);
        } else doc.resizeImage(UnitValue(480, "px"), UnitValue(320, "px"), 72, ResampleMethod.BICUBIC);
        var o = new JPEGSaveOptions(); o.quality = 12; o.embedColorProfile = true;
        doc.saveAs(new File(outDir + "/" + base + ".jpg"), o, true);
        doc.close(SaveOptions.DONOTSAVECHANGES);
    } catch (e) { log.push(base + " ERR " + e); }
}
"done " + lines.length + " " + log.join(" | ");
