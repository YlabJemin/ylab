#!/usr/bin/env python3
# 컬러에디터 스타일(.costyle) 만들기
# mkstyle.py <스타일이름> <json 설정>
#  json: {"basic": {"orange": [색상, 채도, 밝기], ...},
#         "skin": [색상, 채도, 밝기, R, G, B, 색상범위시작, 끝, 채도범위시작, 끝, 부드러움, f15, f16, f17, f18],
#         "extra": {"Exposure": "0.5", ...}}   ← 다른 키도 그대로 넣음
import sys, json, uuid, os
BASIC = [  # 캡쳐원 저장 순서 (기준색 RGB, 색상 범위)
 ("pink",   "255,0,168.909881591797,-7.11462593078613,7.11462593078613"),
 ("purple", "170.93928527832,0,255,-17.8928756713867,17.8928756713867"),
 ("blue",   "0,64.2907180786133,255,-22.4273700714111,22.4273700714111"),
 ("cyan",   "0,255,236.14192199707,-11.8545951843262,11.8545951843262"),
 ("green",  "45.498851776123,255,0,-39.3857116699219,39.3857116699219"),
 ("yellow", "255,211.99267578125,0,-5,5"),
 ("orange", "255,101.301910400391,0,-6.01692199707031,6.01692199707031"),
 ("red",    "255,0,31.4708557128906,-10.195873260498,10.195873260498"),
]
name, cfg = sys.argv[1], json.loads(sys.argv[2])
ents = []
for n, rng in BASIC:
    h, s, l = cfg.get("basic", {}).get(n, [0, 0, 0])
    ents.append(f"1,1,1,{h},{s},{l},{rng},-100,100,15,0,0,0,0")
ents.append("0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0")
if "skin" in cfg:
    ents.append("1,1,2," + ",".join(str(x) for x in cfg["skin"]))
kv = {"ColorCorrections": ";".join(ents), "Name": name, "StyleSource": "Styles", "UUID": str(uuid.uuid4()).upper()}
kv.update(cfg.get("extra", {}))
p = os.path.expanduser(f"~/Library/Application Support/Capture One/Styles/{name}.costyle")
with open(p, "w") as f:
    f.write('<?xml version="1.0"?>\n<SL Engine="1300">\n')
    for k in sorted(kv): f.write(f'\t<E K="{k}" V="{kv[k]}" />\n')
    f.write('</SL>\n')
print(p)
