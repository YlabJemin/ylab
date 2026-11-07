# 하야사카 → 캡쳐원 스타일: 학습 재료·목표 이미지 준비 (Photoshop 렌더)
# 사용법: python3 prep.py <작업폴더>   (작업폴더/raw/*.CR3, 작업폴더/canonjpg/*.jpg 가 있어야 함)
# 만드는 것:
#   charts/        색 차트 JPG 2장 (30×20칸 = 비교 칸과 정확히 맞음)
#   jpg_in/        JPG 학습 입력: 캐논 카메라 JPG(긴 변 2400) + 색 차트
#   base_cn|cc/    RAW 베이스: CR3 + Sony_클래식 네거티브/크롬 (Adobe 색공간 변환이라 카메라 무관) 긴 변 2400
#   tgt_raw/       RAW 목표: 베이스 + 하야사카 JPG 프리셋(작가 WB 조정 제외)  → px_tgt_raw/ (120×80 픽셀)
#   tgt_jpg/       JPG 목표: 캐논 JPG·차트 + 하야사카 JPG 프리셋(WB 포함)     → px_tgt_jpg/
#   looks.json     색감 목록 (키, 그룹, 이름, 필름, 프리셋 경로, WB 조정값)
# 중단해도 끝난 단계는 건너뛰고 이어서 함
import sys, os, json, glob, subprocess, zlib, struct, colorsys, datetime, re
RF = os.path.expanduser('~/Desktop/cc/tools/rawfit'); sys.path.insert(0, RF)
from fitlib import load_settings, settings_xmp, embed_xmp_jpeg, no_wb

W = sys.argv[1]
ST = os.path.expanduser('~/Library/Application Support/Adobe/CameraRaw/Settings')
H1, H2 = ST + '/하야사카1', ST + '/하야사카2'
SONY_CN, SONY_CC = H1 + '/Sony_클래식 네거티브.xmp', H1 + '/Sony_클래식 크롬.xmp'
CHROME = ('나츠조라', '미즈이로', '아사기리', '나츠카시', '신카이', '코카게')   # 하야사카1 클래식 크롬 계열
log = lambda s: print(datetime.datetime.now().strftime('[%H:%M] ') + s, flush=True)

def render(lst, out, le):
    open(out + '.txt', 'w').write('\n'.join(lst) + '\n')
    r = subprocess.run([RF + '/render.sh', out + '.txt', out, str(le)], capture_output=True, text=True)
    if 'ERR' in (r.stdout or ''): log('렌더 오류: ' + r.stdout[-300:])

def dump(src, dst):
    subprocess.run([RF + '/dump', src, dst], check=True)

# ---------- 색감 목록 ----------
def looks():
    out = []
    for gi, (gdir, gname) in enumerate(((H1, '하야사카1'), (H2, '하야사카2')), 1):
        for f in sorted(glob.glob(gdir + '/[0-9][0-9]_*.xmp')):
            title = os.path.basename(f)[:-4]; num = title[:2]
            sony = glob.glob(f'{gdir}/Sony_{num}_*.xmp')
            m = re.search(r'_([-+]?\d+)_([-+]?\d+)\.xmp$', sony[0]) if sony else None
            wb = f'_{m.group(1)}_{m.group(2)}' if m else '_0_0'
            film = 'cc' if gi == 1 and any(c in title for c in CHROME) else 'cn'
            out.append(dict(key=f'h{gi}_{num}', group=gname, title=title, film=film, src=f, wb=wb))
    return out

# ---------- 색 차트 (PNG로 만들고 sips로 JPG) ----------
def png(path, w, h, cells, cw):
    raw = b''
    for y in range(h):
        row = b'\x00'
        for x in range(w):
            r, g, b = cells[(y // cw) * (w // cw) + x // cw]; row += bytes((r, g, b))
        raw += row
    ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))

def charts():
    os.makedirs(W + '/charts', exist_ok=True)
    if len(glob.glob(W + '/charts/*.jpg')) >= 2: return
    to = lambda h, s, v: tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))
    sv = [(1, 1), (.75, 1), (.5, 1), (.3, 1), (.15, 1), (1, .8), (.7, .8), (.45, .8), (.25, .8), (1, .6), (.7, .6), (.45, .6),
          (.25, .6), (.9, .45), (.6, .45), (.35, .45), (.8, .3), (.5, .3), (.3, .9), (.6, .9), (.85, .7), (.55, .7), (.35, .7), (.2, .5), (.5, .55)]
    c1 = [to(h / 24, s, v) for s, v in sv for h in range(24)]                 # 24색상 × 25단계 = 600칸
    c2 = []                                                                   # 피부·따뜻한 중간색 520 + 회색 80
    for i in range(520):
        h = (5 + (i * 7) % 45) / 360; s = .08 + ((i * 13) % 52) / 100; v = .3 + ((i * 17) % 70) / 100
        c2.append(to(h, s, v))
    c2 += [(round(k * 255 / 79),) * 3 for k in range(80)]
    for n, cells in (('chart1', c1), ('chart2', c2)):
        p = f'{W}/charts/{n}.png'; png(p, 1500, 1000, cells, 50)
        subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '95', p, '--out', f'{W}/charts/{n}.jpg'], capture_output=True)
    log('색 차트 2장')

# ---------- 준비 ----------
charts()
L = looks(); json.dump(L, open(W + '/looks.json', 'w'), ensure_ascii=False, indent=1)
log(f'색감 {len(L)}개 (하야사카1 {sum(l["group"] == "하야사카1" for l in L)}, 하야사카2 {sum(l["group"] == "하야사카2" for l in L)})')
RAW = sorted(glob.glob(W + '/raw/*.CR3')); IDS = [os.path.basename(r)[:-4] for r in RAW]

# JPG 학습 입력
os.makedirs(W + '/jpg_in', exist_ok=True)
for i in IDS:
    d = f'{W}/jpg_in/{i}.jpg'
    if not os.path.exists(d): subprocess.run(['sips', '-Z', '2400', f'{W}/canonjpg/{i}.jpg', '--out', d], capture_output=True)
for n in ('chart1', 'chart2'):
    d = f'{W}/jpg_in/{n}.jpg'
    if not os.path.exists(d): subprocess.run(['cp', f'{W}/charts/{n}.jpg', d])
JIDS = IDS + ['chart1', 'chart2']

# RAW 베이스
for film, pre in (('cn', SONY_CN), ('cc', SONY_CC)):
    bdir = f'{W}/base_{film}'
    if len(glob.glob(bdir + '/*.jpg')) >= len(IDS): continue
    s = load_settings(pre); x = settings_xmp(s['attrs'] + [('HasSettings', 'True')], s['curves'], s['other'])
    os.makedirs(bdir + '_in', exist_ok=True); lst = []
    for r, i in zip(RAW, IDS):
        b = f'{bdir}_in/{i}'
        if not os.path.exists(b + '.CR3'): subprocess.run(['cp', '-c', r, b + '.CR3'])
        open(b + '.xmp', 'w').write(x); lst.append(b + '.CR3')
    log(f'RAW 베이스 렌더 ({film}, {len(lst)}장)'); render(lst, bdir, 2400)

# 목표
for kind in ('raw', 'jpg'):
    out = f'{W}/tgt_{kind}'; os.makedirs(out + '_in', exist_ok=True)
    ids = IDS if kind == 'raw' else JIDS
    need = [l for l in L if len(glob.glob(f'{out}/{l["key"]}__*.jpg')) < len(ids)]
    if not need: continue
    lst = []
    for l in need:
        s = load_settings(l['src'])
        attrs = (no_wb(s['attrs']) if kind == 'raw' else s['attrs']) + [('HasSettings', 'True'), ('AlreadyApplied', 'False')]
        x = settings_xmp(attrs, s['curves'], s['other'])
        for i in ids:
            src = f'{W}/base_{l["film"]}/{i}.jpg' if kind == 'raw' else f'{W}/jpg_in/{i}.jpg'
            dst = f'{out}_in/{l["key"]}__{i}.jpg'; embed_xmp_jpeg(src, dst, x); lst.append(dst)
    log(f'{kind.upper()} 목표 렌더 ({len(lst)}장)')
    for k in range(0, len(lst), 200): render(lst[k:k + 200], out, 0)       # 200장씩 (Photoshop 한 번에 너무 길지 않게)
    dump(out, f'{W}/px_tgt_{kind}')
log('준비 완료')
