# 하야사카 → 캡쳐원: 학습 세션에서 커브(R·G·B 9점) + 컬러에디터 8색을 목표(Photoshop 렌더)에 맞춤
# 사용법: python3 c1fit.py <작업폴더> <색감키...> [--it 6]
# 전제: 캡쳐원에 학습 세션 cc_fit.cosessiondb 가 열려 있고, 사진마다 임시 스타일 ccfitbase(커브 9점)가 적용돼 있음
#       레시피 ccfit (JPEG · sRGB · 긴 변 480) 이 세션 안에 있음. 사용자 세션은 건드리지 않음 (문서 이름으로만 지정)
# 결과: 작업폴더/fit/<키>.json  (raw·jpg 각각 최적 값, 색차 before/after, 반복 기록)
import sys, os, json, glob, math, subprocess, time, colorsys, datetime
RF = os.path.expanduser('~/Desktop/cc/tools/rawfit'); sys.path.insert(0, RF)
from fitlib import load_px, blocks, lab, warp

W = sys.argv[1]; args = sys.argv[2:]
IT = 10
if '--it' in args: i = args.index('--it'); IT = int(args[i + 1]); del args[i:i + 2]
DOC = 'cc_fit.cosessiondb'
RAW_IDS = ['c01', 'c02', 'c04', 'c05', 'c07', 'c08', 'c10', 'c12', 'c13', 'c15', 'c17', 'c19']
JPG_IDS = ['c01', 'c03', 'c05', 'c07', 'c09', 'c11', 'c13', 'c15', 'c17', 'c19', 'chart1', 'chart2']
ALIGN = dict(s=0.97, k=-0.02, dx=0.5, dy=0.0)          # 캡쳐원 RAW가 Photoshop보다 약 3% 넓게 나옴
CE = ['red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'pink']
CE_C = [0, 30, 60, 120, 180, 240, 280, 320]             # 색 중심(도, HSV)
XK = [i * 12.5 for i in range(9)]                        # 커브 점 가로 위치 (0~100)
log = lambda s: print(datetime.datetime.now().strftime('[%H:%M:%S] ') + s, flush=True)


def detail_of(src):
    """프리셋 텍스처·클래리티·그레인 → 캡쳐원 스트럭처·클래리티·silver rich 그레인 (원본 크기·2400px 비교로 정한 근사)"""
    import re
    t = open(src, encoding='utf-8').read()
    g = lambda k, d=0: float((re.search(rf'crs:{k}="([^"]*)"', t) or [0, d])[1])
    amt, size = g('GrainAmount'), g('GrainSize', 25)
    return {'st': max(-60, min(60, round(g('Texture') * 1.5))), 'cl': max(-50, min(50, round(g('Clarity2012') * 0.5))),
            'gi': min(100, round(amt * 1.25)) if amt > 0 else 0, 'gg': min(100, round(size * 1.6))}


def ident():
    return {'curves': {c: list(XK) for c in ('red', 'green', 'blue')}, 'ce': [[0.0, 0.0, 0.0] for _ in CE]}


# ---------- 캡쳐원 ----------
AS_HEAD = '''
on ccApply(v, rc, gc, bc, ce)
	tell application "Capture One"
		set a to adjustments of v
		repeat with i from 1 to 9
			set amount of curve point i of red curve of a to item i of rc
			set amount of curve point i of green curve of a to item i of gc
			set amount of curve point i of blue curve of a to item i of bc
		end repeat
		set ces to color editor settings of a
		set nm to {"red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"}
		repeat with i from 1 to 8
			-- 번호로 지정하면 전체(all) 칸에 덮어써짐 → 색 이름으로 지정
			set hue change of basic color correction (item i of nm) of ces to item 1 of item i of ce
			set saturation change of basic color correction (item i of nm) of ces to item 2 of item i of ce
		end repeat
		set hue change of basic color correction "all" of ces to 0
		set saturation change of basic color correction "all" of ces to 0
	end tell
end ccApply

on ccDetail(v, pSt, pCl, pGi, pGg)
	tell application "Capture One"
		set a to adjustments of v
		set clarity method of a to natural
		set clarity amount of a to pCl
		set clarity structure of a to pSt
		if pGi > 0 then
			set film grain type of a to silver rich
			set film grain impact of a to pGi
			set film grain granularity of a to pGg
		else
			set film grain impact of a to 0
		end if
	end tell
end ccDetail
'''


def aslist(x):
    if isinstance(x, list): return '{' + ', '.join(aslist(i) for i in x) + '}'
    return f'{x:.4f}'


def c1_render(params, out, det=None):
    """params: {'raw': P, 'jpg': P} → 학습 사진에 설정하고 out 폴더로 처리, 끝날 때까지 기다림"""
    os.makedirs(out, exist_ok=True)
    for f in glob.glob(out + '/*.jpg'): os.remove(f)      # 이 반복 전용 임시 폴더 (작업폴더 안)
    lines = [AS_HEAD, 'tell application "Capture One"', f'set d to document "{DOC}"', 'set vs to {}']
    for kind, ids in (('raw', RAW_IDS), ('jpg', JPG_IDS)):
        P = params[kind]; cv = P['curves']
        args = ', '.join(aslist(cv[c]) for c in ('red', 'green', 'blue')) + ', ' + aslist(P['ce'])
        for i in ids:
            n = i if kind == 'raw' else 'j_' + i
            lines += [f'set v to first variant of d whose name is "{n}"', f'my ccApply(v, {args})', 'set end of vs to v']
            if det: lines.append(f'my ccDetail(v, {det["st"]}, {det["cl"]}, {det["gi"]}, {det["gg"]})')
    lines += ['set j to recipe "ccfit" of d', f'set root folder location of j to (POSIX file "{out}")',
              'set root folder type of j to custom location',
              'if (root folder type of j) is not custom location then error "recipe location"',
              'process vs recipe "ccfit"', 'end tell']
    sp = out + '.applescript'; open(sp, 'w').write('\n'.join(lines))
    r = subprocess.run(['osascript', sp], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr)
    n = len(RAW_IDS) + len(JPG_IDS); t0 = time.time(); last = None
    while time.time() - t0 < 300:
        fs = glob.glob(out + '/*.jpg')
        if len(fs) >= n:
            sz = sum(os.path.getsize(f) for f in fs)
            if sz == last: break
            last = sz
        time.sleep(1)
    else:
        raise RuntimeError('처리 시간 초과')
    subprocess.run([RF + '/dump', out, out + '_px'], check=True)


# ---------- 비교·보정 ----------
def pairs_of(key, out, kind):
    ps = []
    for i in (RAW_IDS if kind == 'raw' else JPG_IDS):
        n = i if kind == 'raw' else 'j_' + i
        a = load_px(f'{out}_px/{n}.rgb')
        if kind == 'raw': a = warp(a, **ALIGN)
        t = load_px(f'{W}/px_tgt_{kind}/{key}__{i}.rgb')
        w = {'chart1': 1.0, 'chart2': 3.0}.get(i, 1.0)
        fb = FACES.get(f'{kind}/{i}')
        for k, (x, y) in enumerate(zip(blocks(a), blocks(t))):
            ps.append((x, y, w * (FACE_W if fb and in_face(k, fb) else 1.0)))
    return ps


FACES = json.load(open(W + '/faces.json')) if os.path.exists(W + '/faces.json') else {}   # 얼굴 영역 (목표 화면 기준 0~1)
FACE_W = 10.0                                                                            # 얼굴 피부 칸 가중치


def in_face(k, fb):
    """비교 칸 k(28×18)가 얼굴 안쪽(볼·코·입, 눈썹 위·가장자리 뺌)에 있는지"""
    bx, by = k % 28 + 1, k // 28 + 1; cx, cy = (bx * 4 + 2) / 120, (by * 4 + 2) / 80
    x0, y0, x1, y1 = fb; w, h = x1 - x0, y1 - y0
    return x0 + 0.15 * w <= cx <= x1 - 0.15 * w and y0 + 0.35 * h <= cy <= y1 - 0.02 * h


def is_skin(px):
    """목표 색이 피부색 범위(주황 계열, 채도 낮음~중간, 중간 밝기)인지"""
    h, s_, v = colorsys.rgb_to_hsv(*(c / 255 for c in px))
    return (h * 360 <= 50 or h * 360 >= 340) and 0.08 <= s_ <= 0.6 and 0.35 <= v <= 0.97


def de(ps):
    return sum(math.dist(lab(a), lab(t)) * w for a, t, w in ps) / sum(w for _, _, w in ps)


def mix(A, B, t):
    return {'curves': {c: [a + (b - a) * t for a, b in zip(A['curves'][c], B['curves'][c])] for c in A['curves']},
            'ce': [[a + (b - a) * t for a, b in zip(x, y)] for x, y in zip(A['ce'], B['ce'])]}


def step(ps, P, damp=0.8, ce_on=True):
    N = {'curves': {}, 'ce': [list(c) for c in P['ce']]}
    # 채널 커브: 출력값 구간별 (목표 − 현재) 평균 → 점의 출력 높이를 그만큼 옮김
    for ci, cn in enumerate(('red', 'green', 'blue')):
        nb = 32; s = [0.0] * nb; cnt = [0.0] * nb
        for a, t, w in ps:
            b = min(nb - 1, a[ci] // 8); s[b] += (t[ci] - a[ci]) * w; cnt[b] += w
        cen = [i * 8 + 4 for i in range(nb)]; valid = [i for i in range(nb) if cnt[i] >= 6]
        dl = {i: s[i] / cnt[i] for i in valid}; sm = {}
        for i in valid:
            ws = [(cnt[j], dl[j]) for j in (i - 1, i, i + 1) if j in dl]
            sm[i] = sum(a * b for a, b in ws) / sum(a for a, _ in ws)
        def delta(x):
            if not valid: return 0
            lo, hi = valid[0], valid[-1]
            if x <= cen[lo]: return sm[lo]
            if x >= cen[hi]: return sm[hi]
            j = max(i for i in valid if cen[i] <= x); jn = min(i for i in valid if cen[i] >= x)
            return sm[j] if j == jn else sm[j] + (sm[jn] - sm[j]) * (x - cen[j]) / (cen[jn] - cen[j])
        ys = []; prev = 0
        for y in P['curves'][cn]:
            y2 = y + damp * delta(y * 2.55) / 2.55; y2 = max(prev, min(100, max(0, y2))); ys.append(y2); prev = y2
        N['curves'][cn] = ys
    # 컬러에디터(색조 ±30·채도, 밝기는 AppleScript로 설정 불가): 현재 색(캡쳐원 출력) 기준 8색 구간별 채도비·색상차·밝기차
    acc = [[0.0] * 6 for _ in CE]
    for a, t, w in ps:
        h, s_, v = colorsys.rgb_to_hsv(*(c / 255 for c in a))
        face = w >= FACE_W                                   # 얼굴 피부는 창백해도(채도 낮아도) 반영
        if (s_ < 0.15 and not (face and s_ >= 0.03)) or v < 0.15: continue
        d = [min(abs(h * 360 - c), 360 - abs(h * 360 - c)) for c in CE_C]; bi = d.index(min(d))
        la, lt = lab(a), lab(t); ca, ct = math.hypot(la[1], la[2]), math.hypot(lt[1], lt[2])
        if ca < (2 if face else 8): continue
        dh = (math.degrees(math.atan2(lt[2], lt[1]) - math.atan2(la[2], la[1])) + 540) % 360 - 180
        A = acc[bi]; A[0] += ct * w; A[1] += ca * w; A[2] += dh * w * ca; A[3] += w * ca; A[4] += (lt[0] - la[0]) * w; A[5] += w
    for bi in range(len(CE)):
        A = acc[bi]
        if not ce_on or A[5] < 40: continue
        c = N['ce'][bi]
        c[1] = max(-60, min(60, c[1] + 0.4 * (A[0] / max(A[1], 1e-6) - 1) * 100))
        c[0] = max(-30, min(30, c[0] + 0.35 * A[2] / A[3]))
    return N


def fit(look):
    key = look['key']; res_path = f'{W}/fit/{key}.json'; os.makedirs(W + '/fit', exist_ok=True)
    P = {'raw': ident(), 'jpg': ident()}; best = {}; hist = []; det = detail_of(look['src'])
    for it in range(IT + 1):
        out = f'{W}/c1out/{key}'
        c1_render(P, out, det)
        new = {}
        for kind in ('raw', 'jpg'):
            ps = pairs_of(key, out, kind); e = de(ps)
            if kind not in best or e < best[kind]['de']: best[kind] = dict(best.get(kind, {}), de=e, params=P[kind], it=it)
            if it == 0: best[kind]['de0'] = e
            hist.append((kind, it, round(e, 2)))
            if best[kind]['it'] == it:
                new[kind] = step(ps, P[kind], damp=0.8 if it < 3 else 0.6, ce_on=it >= 1)
            else:                                   # 나빠짐 → 최적 값과 이번 값의 중간으로 되돌림
                new[kind] = mix(best[kind]['params'], P[kind], 0.5)
        log(f'{key} {it}회: RAW ΔE {hist[-2][2]} · JPG ΔE {hist[-1][2]}')
        P = new
    # 최적 값으로 다시 처리해 비교 이미지용 결과 남김
    c1_render({'raw': best['raw']['params'], 'jpg': best['jpg']['params']}, f'{W}/c1out/{key}_best', det)
    json.dump({'look': look, 'best': best, 'hist': hist, 'detail': det}, open(res_path, 'w'), ensure_ascii=False, indent=1)
    log(f'{key} 끝: RAW {best["raw"]["de0"]:.2f}→{best["raw"]["de"]:.2f}  JPG {best["jpg"]["de0"]:.2f}→{best["jpg"]["de"]:.2f}')


L = {l['key']: l for l in json.load(open(W + '/looks.json'))}
for k in (args or list(L)):
    if os.path.exists(f'{W}/fit/{k}.json') and not args: continue
    fit(L[k])
