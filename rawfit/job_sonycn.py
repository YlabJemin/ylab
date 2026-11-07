# 소니 RAW 한 장 + 프리셋 하나 = "클래식 네거티브 베이스 + 하야사카" 가 되도록 Sony_ 19개를 맞춤
# 사용법: python3 job_sonycn.py 작업폴더   (작업폴더/src/S01.ARW ... 필요)
import sys, os, json, subprocess, glob, math
T = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, T)
from fitlib import *

J = sys.argv[1]; os.chdir(J)
D = os.path.expanduser('~/Library/Application Support/Adobe/CameraRaw/Settings/하야사카')
PH = sorted(os.path.splitext(f)[0] for f in os.listdir('src') if f.endswith('.ARW'))
PRE = sorted(os.path.basename(f)[:-4] for f in glob.glob(D + '/[0-9][0-9]_*.xmp'))
assert len(PRE) == 19
ITER = 4
log = lambda s: print(time_str() + ' ' + s, flush=True)
def time_str():
    import datetime; return datetime.datetime.now().strftime('[%H:%M]')
def render(lst, out, long_edge=0):
    open(out + '.txt', 'w').write('\n'.join(os.path.abspath(x) for x in lst) + '\n')
    r = subprocess.run([T + '/render.sh', os.path.abspath(out + '.txt'), os.path.abspath(out), str(long_edge)], capture_output=True, text=True)
    if 'ERR' in r.stdout: log('렌더 오류: ' + r.stdout[-300:])
def dump(out):
    subprocess.run([T + '/dump', out, 'px_' + out], check=True)
def clone(ph, dst):
    if not os.path.exists(dst): subprocess.run(['cp', '-c', f'src/{ph}.ARW', dst], check=True)

cn = load_preset(D + '/Sony_클래식 네거티브.xmp')
cn_hsl = {'Saturation': {}, 'Hue': {}}
for a, v in cn['attrs']:
    for kind in ('Saturation', 'Hue'):
        pre = kind + 'Adjustment'
        if a.startswith(pre) and float(v): cn_hsl[kind][a[len(pre):]] = float(v)
presets = {p: load_preset(f'{D}/{p}.xmp') for p in PRE}

# 1) 클래식 네거티브 베이스 JPG
if not os.path.isdir('base') or len(os.listdir('base')) < len(PH) + 1:
    log('1단계: 클래식 네거티브 베이스 JPG 만들기')
    os.makedirs('base_in', exist_ok=True); lst = []
    for ph in PH:
        clone(ph, f'base_in/{ph}.ARW')
        open(f'base_in/{ph}.xmp', 'w').write(settings_xmp([(a, v) for a, v in cn['attrs'] if not META.match(a)], cn['curves']))
        lst.append(f'base_in/{ph}.ARW')
    render(lst, 'base', 2400)

# 2) 목표: 베이스 JPG + 원래 하야사카 프리셋
if not os.path.isdir('px_tgt'):
    log('2단계: 목표 렌더링 (%d장)' % (len(PH) * 19))
    os.makedirs('tgt_in', exist_ok=True); lst = []
    for p in PRE:
        pr = presets[p]
        for ph in PH:
            dst = f'tgt_in/t{p[:2]}_{ph}.jpg'
            embed_xmp_jpeg(f'base/{ph}.jpg', dst, settings_xmp(jpeg_attrs(pr), pr['curves'], pr['other'])); lst.append(dst)
    render(lst, 'tgt'); dump('tgt')

# 3) 출발점: 채널 톤커브 = 프리셋 채널 ∘ 프리셋 전체 ∘ 클래식 네거티브 채널, 전체 커브는 직선
state_f = 'state_i0.json'
if not os.path.exists(state_f):
    st = {}
    for p in PRE:
        pr = presets[p]; M = spline(pr['curves']['ToneCurvePV2012']); cur = {'ToneCurvePV2012': [(0, 0), (255, 255)]}
        for c in CHANNELS:
            Pc = spline(pr['curves'][c]); Cc = spline(cn['curves'][c]); xs = list(range(0, 256, 16)) + [255]; ys = []; prev = 0
            for x in xs:
                y = int(round(Pc(M(Cc(x))))); y = max(y, prev); ys.append(y); prev = y
            cur[c] = list(zip(xs, ys))
        st[p] = {'curves': cur, 'hsl': {k: dict(v) for k, v in cn_hsl.items()}}
    json.dump(st, open(state_f, 'w'))

def render_state(k, st, smooth=False):
    lst = []; os.makedirs(f'raw_in{k}', exist_ok=True)
    for p in PRE:
        cur = st[p]['curves']
        if smooth: cur = {c: (smooth_curve(v) if c in CHANNELS else v) for c, v in cur.items()}
        x = settings_xmp(raw_attrs(presets[p], st[p]['hsl']), cur, presets[p]['other'])
        for ph in PH:
            b = f'raw_in{k}/i_{p[:2]}_{ph}'; clone(ph, b + '.ARW'); open(b + '.xmp', 'w').write(x); lst.append(b + '.ARW')
    render(lst, f'raw{k}'); dump(f'raw{k}')

def pairs_for(k, p):
    out = []
    for ph in PH:
        a = blocks(load_px(f'px_raw{k}/i_{p[:2]}_{ph}.rgb')); t = blocks(load_px(f'px_tgt/t{p[:2]}_{ph}.rgb'))
        out += [(x, y, 1.0) for x, y in zip(a, t)]
    return out

# 4) 반복
errs = {}
for k in range(ITER + 1):
    st = json.load(open(f'state_i{k}.json'))
    if not os.path.isdir(f'px_raw{k}'):
        log(f'3단계: {k + 1}/{ITER + 1}회차 RAW 렌더링')
        render_state(k, st)
    errs[k] = {}; nxt = {}
    for p in PRE:
        pr = pairs_for(k, p); errs[k][p] = delta_e(pr)
        if k < ITER:
            c, h = fit_step(pr, st[p]['curves'], st[p]['hsl']); nxt[p] = {'curves': c, 'hsl': h}
    log(f'{k}회차 평균 색차 %.2f' % (sum(errs[k].values()) / 19))
    if k < ITER: json.dump(nxt, open(f'state_i{k + 1}.json', 'w'))
json.dump(errs, open('errs.json', 'w'))

# 5) 프리셋별 최선 회차 → 톤커브 다듬기 → 최종 확인 렌더링
best = {p: min(range(ITER + 1), key=lambda k: errs[k][p]) for p in PRE}
final = {p: json.load(open(f'state_i{best[p]}.json'))[p] for p in PRE}
for p in PRE:
    final[p]['curves'] = {c: (smooth_curve(v) if c in CHANNELS else v) for c, v in final[p]['curves'].items()}
json.dump(final, open('state_final.json', 'w'))
log('4단계: 다듬은 톤커브로 최종 확인 렌더링')
render_state('F', final)
fe = {p: delta_e(pairs_for('F', p)) for p in PRE}
json.dump({'best': best, 'final_err': fe}, open('result.json', 'w'), ensure_ascii=False)
log('최종(다듬은 뒤) 평균 색차 %.2f' % (sum(fe.values()) / 19))
log('완료')
