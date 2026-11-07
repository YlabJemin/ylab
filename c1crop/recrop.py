# 확인용 출력에서 잰 눈 위치로 크롭을 다시 맞춤. 입력: 현재 크롭과 출력 측정값
import sys, json
s = json.loads(sys.argv[1]); tx, ty = s["eye"]; dt = s["d"]
for n, (cx, cyb, cw, ch, H, ex, ey, d) in s["items"].items():
    top = (H - cyb) - ch / 2; left = cx - cw / 2
    eax, eay = left + ex * cw, top + ey * ch
    cw2 = cw * d / dt; ch2 = ch * d / dt
    left2 = eax - tx * cw2; top2 = eay - ty * ch2
    print(f"{n}|{left2 + cw2/2:.1f}|{H - (top2 + ch2/2):.1f}|{cw2:.1f}|{ch2:.1f}")
