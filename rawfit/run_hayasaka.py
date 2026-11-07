# 하야사카1·2 RAW 프리셋 전체 제작 (중단해도 끝난 단계는 건너뛰고 이어서 함)
#  0) 하야사카1 JPG용 23개  1) Sony_클래식 크롬 학습  2) 하야사카2 Sony_  3) 하야사카2 Fuji_
#  4) 하야사카1 Sony_  5) 하야사카1 Fuji_
# RAW 프리셋: WB 설정 없음(중립으로 맞춘 WB 유지), 이름 끝에 작가 WB 조정을 RAW 값으로 바꾼 숫자 (_색온도_색조)
import sys, os, json, glob, subprocess, datetime, re
T = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, T)
from fitlib import *

SP = sys.argv[1]                                   # 임시 작업 폴더
ST = os.path.expanduser('~/Library/Application Support/Adobe/CameraRaw/Settings')
H1, H2 = ST + '/하야사카1', ST + '/하야사카2'
DNG1 = '/Users/jeminyun/Desktop/Vault/하야사카 프리셋/하야사카 프리셋1'
PROF = '/Library/Application Support/Adobe/CameraRaw/Settings/Adobe/Profiles/Camera/Fujifilm/Fujifilm X-T5'
CN_PROFILE = PROF + '/Fujifilm X-T5 Camera CLASSIC Neg.xmp'
CC_NAME = 'Camera CLASSIC CHROME'
SONY_CN = H1 + '/Sony_클래식 네거티브.xmp'; SONY_CC = H1 + '/Sony_클래식 크롬.xmp'
SONY = {os.path.splitext(f)[0]: f'{SP}/sonycn/src/{f}' for f in os.listdir(f'{SP}/sonycn/src') if f.endswith('.ARW')}
FUJI = {os.path.splitext(f)[0]: f'{SP}/fuji2/src/{f}' for f in os.listdir(f'{SP}/fuji2/src') if f.endswith('.RAF')}
WB = {c: json.load(open(f'{T}/wb/wb_{c}.json'))['table'] for c in ('sony', 'fuji')}
log = lambda s: print(datetime.datetime.now().strftime('[%H:%M] ') + s, flush=True)

# 하야사카1: 확정 순서·이름·필름 (원본 DNG 번호)
H1_LIST = [('3701', '하레노히(맑은 날)', 'cn'), ('3680', '산포(산책)', 'cn'), ('3717', '요아케(새벽)', 'cn'), ('3696', '모리노 오쿠(깊은 숲)', 'cn'),
           ('3693', '아오카게(푸른 그림자)', 'cn'), ('3694', '쿠모리조라(흐린 하늘)', 'cn'), ('3683', '하이이로(잿빛)', 'cn'), ('3718', '유야케(저녁노을)', 'cn'),
           ('3688', '라벤다(라벤더)', 'cn'), ('3682', '하루가스미(봄 안개)', 'cn'), ('3687', '바라이로(장밋빛)', 'cn'), ('3710', '니치조(일상)', 'cn'),
           ('3715', '히다마리(볕 드는 곳)', 'cn'), ('3690', '코모레비(나뭇잎 햇살)', 'cn'), ('3700', '나츠노 오와리(여름의 끝)', 'cn'),
           ('3689', '시즈카나 요루(고요한 밤)', 'cn'), ('3711', '오모이데(추억)', 'cn'),
           ('3706', '나츠조라(여름 하늘)', 'cc'), ('3686', '미즈이로(연한 하늘색)', 'cc'), ('3685', '아사기리(아침 안개)', 'cc'),
           ('3697', '나츠카시(그리운)', 'cc'), ('3708', '신카이(깊은 바다)', 'cc'), ('3716', '코카게(나무 그늘)', 'cc')]
H1P = [dict(key=f'{i:02d}', title=f'{i:02d}_{n}', src=f'{DNG1}/IMG_{d}.DNG', film=fm) for i, (d, n, fm) in enumerate(H1_LIST, 1)]

def render(lst, out, le=0):
    open(out + '.txt', 'w').write('\n'.join(lst) + '\n')
    subprocess.run([T + '/render.sh', out + '.txt', out, str(le)], capture_output=True)

def suffix(cam, wb):
    v = WB[cam].get(f'{wb[0]},{wb[1]}')
    if v is None: raise SystemExit(f'WB 변환표에 없는 조합 {wb}')
    f = lambda n: '0' if n == 0 else '%+d' % n
    return f'_{f(v["K"])}_{f(v["tint"])}'

def run_job(name, cfg):
    W = f'{SP}/jobs/{name}'; cfg['work'] = W; os.makedirs(W, exist_ok=True)
    if os.path.exists(W + '/result.json'): return json.load(open(W + '/result.json')), W
    json.dump(cfg, open(W + '.json', 'w'), ensure_ascii=False)
    log(f'== {name} 시작 ==')
    r = subprocess.run([sys.executable, T + '/job_fit.py', W + '.json'])
    if r.returncode: raise SystemExit(f'{name} 실패')
    return json.load(open(W + '/result.json')), W

def write_raw(presets, W, cam, prefix, folder, group, look_of):
    final = json.load(open(W + '/state_final.json')); out = []
    for p in presets:
        s = load_settings(p['src']); st = final[p['key']]
        attrs = add_hsl(no_wb(s['attrs']), st['hsl']); look, prof = look_of(p)
        if prof: attrs.append(('CameraProfile', prof))
        title = prefix + p['title'] + suffix(cam, s['wb'])
        open(f'{folder}/{title}.xmp', 'w', encoding='utf-8').write(make_preset(title, group, attrs, st['curves'], s['other'], look))
        out.append(title)
    return out

os.makedirs(SP + '/jobs', exist_ok=True)
cn_look = look_xml(CN_PROFILE)

# 0) 하야사카1 JPG용 23개 (원본 그대로, WB 포함)
if not glob.glob(H1 + '/[0-9][0-9]_*.xmp'):
    for p in H1P:
        s = load_settings(p['src'])
        open(f'{H1}/{p["title"]}.xmp', 'w', encoding='utf-8').write(make_preset(p['title'], '하야사카1', s['attrs'], s['curves'], s['other']))
    log('하야사카1 JPG용 23개 저장')

# 1) Sony_클래식 크롬: 후지 RAF(Adobe 색상) → 후지 RAF + Camera CLASSIC CHROME 렌더를 목표로 학습
if not os.path.exists(SONY_CC):
    bdir = f'{SP}/fuji2/base_cc'
    if len(glob.glob(bdir + '/*.jpg')) < len(FUJI):
        os.makedirs(bdir + '_in', exist_ok=True); lst = []
        for ph, raw in FUJI.items():
            b = f'{bdir}_in/{ph}'; subprocess.run(['cp', '-c', raw, b + '.RAF']) if not os.path.exists(b + '.RAF') else None
            open(b + '.xmp', 'w').write(settings_xmp([('Version', '17.4'), ('ProcessVersion', '15.4'), ('CameraProfile', CC_NAME), ('HasSettings', 'True')], {c: [(0, 0), (255, 255)] for c in CURVES}))
            lst.append(b + '.RAF')
        log('후지 클래식 크롬 베이스 렌더링'); render(lst, bdir, 2400)
    res, W = run_job('cc_train', dict(raw_ext='.RAF', photos=FUJI, bases={'cc': {ph: f'{bdir}/{ph}.jpg' for ph in FUJI}},
                                     iters=8, sat_lim=90, hue_lim=70, presets=[dict(key='CC', src='identity', base='cc', init='preset')]))
    st = json.load(open(W + '/state_final.json'))['CC']
    for kind in ('Hue', 'Saturation'):      # 빨강은 학습 사진에 적어 틀어지기 쉬움 (클래식 네거티브 때와 같은 처리)
        if abs(st['hsl'][kind].get('Red', 0)) > 25: log(f'빨강 {kind} {st["hsl"][kind]["Red"]:.0f} → 제외'); st['hsl'][kind].pop('Red')
    s = identity_settings()
    open(SONY_CC, 'w', encoding='utf-8').write(make_preset('Sony_클래식 크롬', '하야사카1', add_hsl(s['attrs'], st['hsl']), st['curves']))
    log('Sony_클래식 크롬 저장 (학습 색차 %.2f → %.2f)' % (res['start_err']['CC'], res['final_err']['CC']))

# 소니 클래식 크롬 베이스 JPG (하야사카1 크롬 프리셋 목표용)
SB = {'cn': {ph: f'{SP}/sonycn/base/{ph}.jpg' for ph in SONY}, 'cc': {ph: f'{SP}/sony_cc_base/{ph}.jpg' for ph in SONY}}
if len(glob.glob(f'{SP}/sony_cc_base/*.jpg')) < len(SONY):
    s = load_settings(SONY_CC); x = settings_xmp(s['attrs'] + [('HasSettings', 'True')], s['curves'])
    os.makedirs(f'{SP}/sony_cc_base_in', exist_ok=True); lst = []
    for ph, raw in SONY.items():
        b = f'{SP}/sony_cc_base_in/{ph}'; subprocess.run(['cp', '-c', raw, b + '.ARW']) if not os.path.exists(b + '.ARW') else None
        open(b + '.xmp', 'w').write(x); lst.append(b + '.ARW')
    log('소니 클래식 크롬 베이스 렌더링'); render(lst, f'{SP}/sony_cc_base', 2400)
FB = {'cn': {ph: f'{SP}/fuji2/base_cn/{ph}.jpg' for ph in FUJI}, 'cc': {ph: f'{SP}/fuji2/base_cc/{ph}.jpg' for ph in FUJI}}

# 하야사카2 원본 (JPG용 19개)
H2P = [dict(key=os.path.basename(f)[:2], title=os.path.basename(f)[:-4], src=f, film='cn') for f in sorted(glob.glob(H2 + '/[0-9][0-9]_*.xmp'))]

def sony_cfg(presets):
    return dict(raw_ext='.ARW', photos=SONY, bases=SB, iters=4, presets=[
        dict(key=p['key'], src=p['src'], base=p['film'], init='compose', compose_with=SONY_CN if p['film'] == 'cn' else SONY_CC) for p in presets])

def fuji_cfg(presets):
    return dict(raw_ext='.RAF', photos=FUJI, bases=FB, align_bases=['cn'], iters=4, presets=[
        dict(key=p['key'], src=p['src'], base=p['film'], init='preset', **({'profile': CN_PROFILE} if p['film'] == 'cn' else {'profile_name': CC_NAME})) for p in presets])

fuji_look = lambda p: cn_look if p['film'] == 'cn' else ('', CC_NAME)
sony_look = lambda p: ('', None)

# 2)~5)
for tag, presets, cam, cfgf, folder, group, lookf, old in (
        ('h2_sony', H2P, 'sony', sony_cfg, H2, '하야사카2', sony_look, 'Sony_[0-9]*.xmp'),
        ('h2_fuji', H2P, 'fuji', fuji_cfg, H2, '하야사카2', fuji_look, 'Fuji_[0-9]*.xmp'),
        ('h1_sony', H1P, 'sony', sony_cfg, H1, '하야사카1', sony_look, 'Sony_[0-9]*.xmp'),
        ('h1_fuji', H1P, 'fuji', fuji_cfg, H1, '하야사카1', fuji_look, 'Fuji_[0-9]*.xmp')):
    done = f'{SP}/jobs/{tag}.written'
    if os.path.exists(done): continue
    res, W = run_job(tag, cfgf(presets))
    for f in glob.glob(f'{folder}/{old}'): os.remove(f)          # 예전 버전 (백업 있음)
    names = write_raw(presets, W, cam, 'Sony_' if cam == 'sony' else 'Fuji_', folder, group, lookf)
    open(done, 'w').write('\n'.join(names))
    log(f'{tag} 저장 {len(names)}개 | 색차 %.2f → %.2f' % (sum(res['start_err'].values()) / len(names), sum(res['final_err'].values()) / len(names)))
log('전체 완료')
