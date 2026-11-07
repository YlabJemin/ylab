# 공용: RAW 한 장 + 프리셋 하나 = "베이스 JPG + 원래 프리셋(WB 제외)" 이 되도록 맞춤
# 사용법: python3 job_fit.py 설정.json
# 설정.json:
#   work: 작업 폴더, raw_ext: ".ARW"/".RAF", photos: {사진ID: RAW경로}
#   bases: {베이스이름: {사진ID: 베이스 JPG 경로}}  — 목표 = 이 JPG + 원래 프리셋(WB 제외)
#   align_bases: [위치 맞추기가 필요한 베이스 이름]  (실제 카메라 JPG일 때)
#   weights: {사진ID: 가중치}, iters: 반복 횟수, sat_lim/hue_lim: 색상혼합 한계
#   presets: [{key, src(프리셋 XMP·DNG 경로 또는 "identity"), base, init("compose"|"preset"),
#              compose_with(베이스 프리셋 XMP, init=compose일 때), profile(색표형 프로필 파일) 또는 profile_name(내장 프로필 이름)}]
import sys, os, json, subprocess, math, datetime
T = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, T)
from fitlib import *

C = json.load(open(sys.argv[1])); os.makedirs(C['work'], exist_ok=True); os.chdir(C['work'])
PH = sorted(C['photos']); EXT = C['raw_ext']; WT = C.get('weights', {}); N = C.get('iters', 4)
SAT, HUE = C.get('sat_lim', 90), C.get('hue_lim', 70)
log = lambda s: print(datetime.datetime.now().strftime('[%H:%M] ') + s, flush=True)

def render(lst, out):
    open(out + '.txt', 'w').write('\n'.join(os.path.abspath(x) for x in lst) + '\n')
    r = subprocess.run([T + '/render.sh', os.path.abspath(out + '.txt'), os.path.abspath(out), '0'], capture_output=True, text=True)
    if 'ERR' in r.stdout: log('렌더 오류: ' + r.stdout[-400:])
    subprocess.run([T + '/dump', out, 'px_' + out], check=True)

def clone(ph, dst):
    if not os.path.exists(dst): subprocess.run(['cp', '-c', C['photos'][ph], dst], check=True)

P = {}
for p in C['presets']:
    s = identity_settings() if p['src'] == 'identity' else load_settings(p['src'])
    look, prof = look_xml(p['profile']) if p.get('profile') else ('', p.get('profile_name'))   # 색표형(파일) 또는 내장 프로필 이름
    P[p['key']] = dict(cfg=p, s=s, look=look, prof=prof)
KEYS = [p['key'] for p in C['presets']]

# 1) 목표 렌더: 베이스 JPG + 원래 프리셋(WB 제외)
if not os.path.isdir('px_tgt'):
    log(f'목표 렌더링 ({len(KEYS) * len(PH)}장)'); os.makedirs('tgt_in', exist_ok=True); lst = []
    for k in KEYS:
        s = P[k]['s']; x = settings_xmp(no_wb(s['attrs']) + [('HasSettings', 'True'), ('AlreadyApplied', 'False')], s['curves'], s['other'])
        for ph in PH:
            dst = f'tgt_in/t{k}_{ph}.jpg'; embed_xmp_jpeg(C['bases'][P[k]['cfg']['base']][ph], dst, x); lst.append(dst)
    render(lst, 'tgt')

# 2) 출발 상태
if not os.path.exists('state_i0.json'):
    st = {}
    for k in KEYS:
        s = P[k]['s']; cfg = P[k]['cfg']
        if cfg.get('init') == 'compose':
            b = load_settings(cfg['compose_with']); M = spline(s['curves']['ToneCurvePV2012']); cur = {'ToneCurvePV2012': [(0, 0), (255, 255)]}
            for c in CHANNELS:
                Pc = spline(s['curves'][c]); Bc = spline(b['curves'][c]); xs = list(range(0, 256, 16)) + [255]; ys = []; prev = 0
                for x in xs:
                    y = max(int(round(Pc(M(Bc(x))))), prev); ys.append(y); prev = y
                cur[c] = list(zip(xs, ys))
            bh = dict(b['attrs']); hsl = {kind: {c: float(bh.get(f'{kind}Adjustment{c}', 0)) for c in BANDS if float(bh.get(f'{kind}Adjustment{c}', 0))} for kind in ('Saturation', 'Hue')}
        else:
            cur = {c: list(v) for c, v in s['curves'].items()}; hsl = {'Saturation': {}, 'Hue': {}}
        st[k] = {'curves': cur, 'hsl': hsl}
    json.dump(st, open('state_i0.json', 'w'))

def raw_xmp(k, st):
    s = P[k]['s']; attrs = add_hsl(no_wb(s['attrs']), st['hsl'])
    if P[k]['prof']: attrs.append(('CameraProfile', P[k]['prof']))
    return settings_xmp(attrs + [('HasSettings', 'True')], st['curves'], s['other'] + ([P[k]['look']] if P[k]['look'] else []))

def render_state(tag, st):
    lst = []; os.makedirs(f'raw_in{tag}', exist_ok=True)
    for k in KEYS:
        x = raw_xmp(k, st[k])
        for ph in PH:
            b = f'raw_in{tag}/i_{k}_{ph}'; clone(ph, b + EXT); open(b + '.xmp', 'w').write(x); lst.append(b + EXT)
    render(lst, f'raw{tag}')

ALIGN = json.load(open('align.json')) if os.path.exists('align.json') else None
def pairs_for(tag, k):
    base = P[k]['cfg']['base']; out = []
    for ph in PH:
        a = load_px(f'px_raw{tag}/i_{k}_{ph}.rgb')
        if ALIGN and base in ALIGN and ph in ALIGN[base]:
            g = ALIGN[base][ph]; a = warp(a, g['s'], g['k'], g['dx'], g['dy'])
        t = load_px(f'px_tgt/t{k}_{ph}.rgb'); w = WT.get(ph, 1.0)
        out += [(x, y, w) for x, y in zip(blocks(a), blocks(t))]
    return out

errs = json.load(open('errs.json')) if os.path.exists('errs.json') else {}
for it in range(N + 1):
    st = json.load(open(f'state_i{it}.json'))
    if not os.path.isdir(f'px_raw{it}'):
        log(f'{it + 1}/{N + 1}회차 RAW 렌더링 ({len(KEYS) * len(PH)}장)'); render_state(it, st)
    if ALIGN is None and C.get('align_bases'):
        ALIGN = {}
        for base in C['align_bases']:
            ks = [k for k in KEYS if P[k]['cfg']['base'] == base][:3]
            if not ks: continue
            ALIGN[base] = {}
            for ph in PH:
                ALIGN[base][ph] = find_align([(load_px(f'px_raw{it}/i_{k}_{ph}.rgb'), load_px(f'px_tgt/t{k}_{ph}.rgb')) for k in ks])
                g = ALIGN[base][ph]; log(f'위치 맞추기 {base} {ph}: 확대 {g["s"]:.3f} 왜곡 {g["k"]:+.3f} 이동({g["dx"]:+.1f},{g["dy"]:+.1f}) 차이 {g["before"]:.1f}→{g["after"]:.1f}')
        json.dump(ALIGN, open('align.json', 'w'))
    if str(it) not in errs or it < N and not os.path.exists(f'state_i{it + 1}.json'):
        errs[str(it)] = {}; nxt = {}
        for k in KEYS:
            pr = pairs_for(it, k); errs[str(it)][k] = delta_e(pr)
            if it < N:
                c, h = fit_step(pr, st[k]['curves'], st[k]['hsl'], sat_lim=SAT, hue_lim=HUE); nxt[k] = {'curves': c, 'hsl': h}
        json.dump(errs, open('errs.json', 'w'))
        if it < N: json.dump(nxt, open(f'state_i{it + 1}.json', 'w'))
        log(f'{it}회차 평균 색차 %.2f' % (sum(errs[str(it)].values()) / len(KEYS)))

# 3) 프리셋별 최선 회차 → 채널 톤커브 평활화 → 최종 확인
best = {k: min(range(N + 1), key=lambda i: errs[str(i)][k]) for k in KEYS}
final = {}
for k in KEYS:
    s = json.load(open(f'state_i{best[k]}.json'))[k]
    s['curves'] = {c: (smooth_curve(v) if c in CHANNELS else v) for c, v in s['curves'].items()}; final[k] = s
json.dump(final, open('state_final.json', 'w'))
if not os.path.isdir('px_rawF'):
    log('다듬은 톤커브로 최종 확인 렌더링'); render_state('F', final)
fe = {k: delta_e(pairs_for('F', k)) for k in KEYS}
json.dump({'best': best, 'final_err': fe, 'start_err': errs['0']}, open('result.json', 'w'))
log('처음 평균 %.2f → 최종(다듬은 뒤) 평균 %.2f' % (sum(errs['0'].values()) / len(KEYS), sum(fe.values()) / len(KEYS)))
log('완료')
