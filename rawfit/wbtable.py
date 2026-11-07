# 작가의 JPG용 WB 조정(색온도·색조 상대값) → RAW 슬라이더 값(K, 색조) 변환표 만들기
# 사용법: python3 wbtable.py 작업폴더 카메라이름 RAW파일
# 방법: RAW를 5500K·색조0으로 JPG 렌더(기준) → JPG에 작가 WB 조정 적용 시 색 변화 측정
#       → RAW 색온도·색조를 바꿔가며 같은 색 변화가 나는 값을 찾음
import sys, os, re, glob, json, math, subprocess
T = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, T)
from fitlib import *

W, CAM, RAW = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(W, exist_ok=True); os.chdir(W)
ext = os.path.splitext(RAW)[1]
BASE_K = 5500
KMIN = int(os.environ.get('WB_KMIN', '-1200'))
DK = list(range(KMIN, 1201, 300)); DT = list(range(-30, 31, 10))
V = [('Version', '17.4'), ('ProcessVersion', '15.4')]

def render(lst, out, le=0):
    open(out + '.txt', 'w').write('\n'.join(os.path.abspath(x) for x in lst) + '\n')
    subprocess.run([T + '/render.sh', os.path.abspath(out + '.txt'), os.path.abspath(out), str(le)], capture_output=True)
    subprocess.run([T + '/dump', out, 'px_' + out], check=True)

def raw_file(name, k, t):
    b = f'raw_in/{name}'; os.makedirs('raw_in', exist_ok=True)
    if not os.path.exists(b + ext): subprocess.run(['cp', '-c', RAW, b + ext], check=True)
    ident = {c: [(0, 0), (255, 255)] for c in CURVES}
    open(b + '.xmp', 'w').write(settings_xmp(V + [('WhiteBalance', 'Custom'), ('Temperature', str(k)), ('Tint', '%+d' % t), ('HasSettings', 'True')], ident))
    return b + ext

# 작가 WB 조합 모으기 (하야사카1·2 원본)
def wb_of(text):
    g = lambda k: (re.search(r'crs:' + k + r'="([^"]*)"', text) or [0, '0'])[1]
    return int(float(g('IncrementalTemperature'))), int(float(g('IncrementalTint')))
pairs = set()
for f in glob.glob(os.path.expanduser('~/Library/Application Support/Adobe/CameraRaw/Settings/하야사카2/[0-9][0-9]_*.xmp')):
    pairs.add(wb_of(open(f, encoding='utf-8').read()))
for f in glob.glob('/Users/jeminyun/Desktop/Vault/하야사카 프리셋/하야사카 프리셋1/*.DNG'):
    d = open(f, 'rb').read(); i = d.find(b'<x:xmpmeta'); x = d[i:d.find(b'</x:xmpmeta>', i)].decode('utf8', 'replace')
    pairs.add(wb_of(re.sub(r'<crs:Preset>.*?</crs:Preset>', '', x, flags=re.S)))
pairs = sorted(pairs | {(0, 0)})

# 1) 기준 JPG (RAW 5500K·색조0)
if not os.path.isdir('px_base'):
    render([raw_file('base', BASE_K, 0)], 'base', 1600)
# 2) 기준 JPG에 작가 WB 조정 적용
if not os.path.isdir('px_jpg'):
    os.makedirs('jpg_in', exist_ok=True); lst = []
    ident = {c: [(0, 0), (255, 255)] for c in CURVES}
    for (t, ti) in pairs:
        dst = f'jpg_in/j_{t}_{ti}.jpg'
        embed_xmp_jpeg('base/base.jpg', dst, settings_xmp(V + [('WhiteBalance', 'Custom'), ('IncrementalTemperature', '%+d' % t), ('IncrementalTint', '%+d' % ti), ('HasSettings', 'True'), ('AlreadyApplied', 'False')], ident))
        lst.append(dst)
    render(lst, 'jpg')
# 3) RAW 색온도·색조 격자
GD = 'grid' if KMIN == -1200 else f'grid{-KMIN}'
if not os.path.isdir('px_' + GD):
    render([raw_file(f'g_{dk}_{dt}', BASE_K + dk, dt) for dk in DK for dt in DT], GD)

def feat(path):
    """중간 밝기 픽셀의 평균 선형 RGB → (log R/G, log B/G)"""
    s = [0.0, 0.0, 0.0]; n = 0
    for p in load_px(path):
        l = [LUT[c] for c in p]; y = 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        if 0.02 < y < 0.8 and max(p) < 250:
            for i in range(3): s[i] += l[i]
            n += 1
    return (math.log(s[0] / s[1]), math.log(s[2] / s[1]))

J0 = feat('px_jpg/j_0_0.rgb')
G = {(dk, dt): feat(f'px_{GD}/g_{dk}_{dt}.rgb') for dk in DK for dt in DT}
R0 = G[(0, 0)]
def grid_at(dk, dt):   # 격자 사이 값은 양선형 보간
    i = min(len(DK) - 2, max(0, int((dk - DK[0]) // 300))); j = min(len(DT) - 2, max(0, int((dt - DT[0]) // 10)))
    fx = (dk - DK[i]) / 300; fy = (dt - DT[j]) / 10
    a, b, c, d = G[(DK[i], DT[j])], G[(DK[i + 1], DT[j])], G[(DK[i], DT[j + 1])], G[(DK[i + 1], DT[j + 1])]
    return tuple(a[m] * (1 - fx) * (1 - fy) + b[m] * fx * (1 - fy) + c[m] * (1 - fx) * fy + d[m] * fx * fy for m in range(2))

table = {}
for (t, ti) in pairs:
    jf = feat(f'px_jpg/j_{t}_{ti}.rgb'); target = (jf[0] - J0[0], jf[1] - J0[1])
    best = None
    for dk in range(KMIN, 1201, 10):
        for dt10 in range(-300, 301, 5):
            dt = dt10 / 10; g = grid_at(dk, dt)
            e = (g[0] - R0[0] - target[0]) ** 2 + (g[1] - R0[1] - target[1]) ** 2
            if best is None or e < best[0]: best = (e, dk, dt)
    table[f'{t},{ti}'] = {'K': int(round(best[1] / 50.0) * 50), 'tint': int(round(best[2])), 'err': round(math.sqrt(best[0]) * 100, 2)}
json.dump({'camera': CAM, 'base_K': BASE_K, 'table': table}, open(f'wb_{CAM}.json', 'w'), ensure_ascii=False, indent=1)
for k, v in sorted(table.items(), key=lambda kv: tuple(map(int, kv[0].split(',')))):
    print(f'{CAM} JPG 색온도·색조 {k:>8} → RAW {v["K"]:+5d}K, 색조 {v["tint"]:+3d}  (오차 {v["err"]})')
