# 반복을 중간에 끝내고 Sony_ 19개 저장: 렌더된 회차 중 최선 → 톤커브 다듬기 → 프리셋 덮어쓰기
# 사용법: python3 finalize_sonycn.py 작업폴더 마지막회차
import sys, os, json, re, uuid, glob, subprocess
T = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, T)
from fitlib import *

J, last = sys.argv[1], int(sys.argv[2]); os.chdir(J)
D = os.path.expanduser('~/Library/Application Support/Adobe/CameraRaw/Settings/하야사카')
PH = sorted(os.path.splitext(f)[0] for f in os.listdir('src') if f.endswith('.ARW'))
PRE = sorted(os.path.basename(f)[:-4] for f in glob.glob(D + '/[0-9][0-9]_*.xmp'))
if not os.path.isdir(f'px_raw{last}'):
    subprocess.run([T + '/dump', f'raw{last}', f'px_raw{last}'], check=True)

def err(k, p):
    pr = []
    for ph in PH:
        a = blocks(load_px(f'px_raw{k}/i_{p[:2]}_{ph}.rgb')); t = blocks(load_px(f'px_tgt/t{p[:2]}_{ph}.rgb'))
        pr += [(x, y, 1.0) for x, y in zip(a, t)]
    return delta_e(pr)

errs = {k: {p: err(k, p) for p in PRE} for k in range(last + 1)}
for k in errs: print(f'{k}회차 평균 색차 %.2f' % (sum(errs[k].values()) / 19))
best = {p: min(errs, key=lambda k: errs[k][p]) for p in PRE}

made = []
for p in PRE:
    st = json.load(open(f'state_i{best[p]}.json'))[p]
    t = open(f'{D}/{p}.xmp', encoding='utf-8').read()
    t = re.sub(r'\n\s*crs:Incremental(Temperature|Tint)="[^"]*"', '', t).replace('crs:WhiteBalance="Custom"', 'crs:WhiteBalance="As Shot"')
    for kind in ('Saturation', 'Hue'):
        for color, off in st['hsl'][kind].items():
            key = f'crs:{kind}Adjustment{color}'; m = re.search(key + r'="([^"]*)"', t)
            if m:
                v = max(-100, min(100, round(float(m.group(1)) + off)))
                t = t.replace(m.group(0), f'{key}="{v:+d}"' if v else f'{key}="0"')
    cur = {'ToneCurvePV2012': [(0, 0), (255, 255)]}
    cur.update({c: smooth_curve(st['curves'][c]) for c in CHANNELS})
    for c in CURVES:
        t = re.sub(r'\s*<crs:%s>.*?</crs:%s>\n?' % (c, c), '\n' + curve_xml(c, cur[c]), t, flags=re.S)
    t = re.sub(r'crs:ToneCurveName2012="[^"]*"', 'crs:ToneCurveName2012="Custom"', t)
    t = re.sub(r'crs:UUID="[^"]*"', f'crs:UUID="{uuid.uuid4().hex.upper()}"', t, count=1)
    title = 'Sony_' + p
    t = re.sub(r'(<crs:Name>\s*<rdf:Alt>\s*<rdf:li xml:lang="x-default">)[^<]*(</rdf:li>)', lambda m: m.group(1) + title + m.group(2), t)
    open(f'{D}/{title}.xmp', 'w', encoding='utf-8').write(t); made.append(title)
json.dump({'best': best, 'errs': errs}, open('result.json', 'w'), ensure_ascii=False)
print(len(made), '개 저장 | 회차별 선택:', {k: sum(1 for v in best.values() if v == k) for k in errs})
print('완료')
