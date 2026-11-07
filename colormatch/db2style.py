#!/usr/bin/env python3
# 세션 DB(복사본)에서 사진 하나의 이미지 레이어 설정을 읽어 .costyle로 저장
# db2style.py <db> <사진이름 일부> <스타일이름> [<스타일이름2> ...]
# 노출·화이트밸런스는 사진마다 다르므로 제외
import sys, sqlite3, uuid, os
db, key, names = sys.argv[1], sys.argv[2], sys.argv[3:]
c = sqlite3.connect(db); c.row_factory = sqlite3.Row
r = c.execute("""select l.* from ZVARIANT v join ZIMAGE i on v.ZIMAGE=i.Z_PK join ZVARIANTLAYER l on l.Z_PK=v.ZADJUSTMENTLAYER
                 where i.ZDISPLAYNAME like ?""", (f"%{key}%",)).fetchone()
M = {"Contrast": "ZCONTRAST", "Brightness": "ZBRIGHTNESS", "Saturation": "ZSATURATION",
     "HighlightRecoveryEx": "ZHIGHLIGHTRECOVERY", "ShadowRecovery": "ZSHADOWRECOVERY",
     "WhiteRecovery": "ZWHITERECOVERY", "BlackRecovery": "ZBLACKRECOVERY",
     "Clarity": "ZCLARITY", "ClarityStructure": "ZCLARITYSTRUCTURE", "ClarityMethod": "ZCLARITYMETHOD",
     "Shadow": "ZLEVELSSHADOW", "Highlight": "ZLEVELSHIGHLIGHT", "Midtone": "ZMIDTONE",
     "TargetShadow": "ZLEVELSTARGETSHADOW", "TargetHighlight": "ZLEVELSTARGETHIGHLIGHT",
     "ColorBalance": "ZCOLORBALANCE", "ColorBalanceShadow": "ZCOLORBALANCESHADOW",
     "ColorBalanceMidtone": "ZCOLORBALANCEMIDTONE", "ColorBalanceHighlight": "ZCOLORBALANCEHIGHLIGHT",
     "ColorCorrections": "ZCOLORCORRECTIONS", "GradationCurve": "ZGRADATIONCURVE", "GradationCurveY": "ZGRADATIONCURVEY"}
kv = {}
for k, col in M.items():
    v = r[col]
    if v is None or v == "": continue
    if isinstance(v, float): v = f"{v:g}"
    kv[k] = str(v)
for k, v in kv.items(): print(f"  {k} = {v if k != 'ColorCorrections' else v.split(';')[-1]}")
for n in names:
    d = dict(kv, Name=n, StyleSource="Styles", UUID=str(uuid.uuid4()).upper())
    p = os.path.expanduser(f"~/Library/Application Support/Capture One/Styles/{n}.costyle")
    with open(p, "w") as f:
        f.write('<?xml version="1.0"?>\n<SL Engine="1300">\n')
        for k in sorted(d): f.write(f'\t<E K="{k}" V="{d[k]}" />\n')
        f.write('</SL>\n')
    print("→", p)
