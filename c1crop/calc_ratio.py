# 여러 장을 같은 인물 크기·위치로 지정 비율 크롭 (캡쳐원 crop = 중심x, 중심y(아래에서부터), 너비, 높이)
import sys, json
spec = json.loads(sys.argv[1])  # {"ratio":[7,9], "eye_y":0.30, "full":[5464,8192], "items":{name:[W,H,cx,cy,d]}}
rw, rh = spec["ratio"]; e = spec["eye_y"]; FW, FH = spec["full"]
best = None
for name, (W, H, cx, cy, d) in spec["items"].items():
    ox, oy = (FW - W) / 2, (FH - H) / 2           # 캡쳐원 화면(보정 후)과 원본 전체의 차이
    ex, ey = cx * FW - ox, cy * FH - oy           # 캡쳐원 기준 눈 중심(위에서부터)
    D = d * FW                                    # 눈 사이 거리(px)
    lim = [2 * ex / D, 2 * (W - ex) / D,          # k = 크롭너비 / 눈거리
           ey / (e * D * rh / rw), (H - ey) / ((1 - e) * D * rh / rw)]
    best = min(best or 1e9, *lim)
k = best * 0.995
for name, (W, H, cx, cy, d) in spec["items"].items():
    ox, oy = (FW - W) / 2, (FH - H) / 2
    ex, ey = cx * FW - ox, cy * FH - oy
    cw = k * d * FW; ch = cw * rh / rw
    top = ey - e * ch
    print(f"{name}|{ex:.1f}|{H - (top + ch / 2):.1f}|{cw:.1f}|{ch:.1f}")
