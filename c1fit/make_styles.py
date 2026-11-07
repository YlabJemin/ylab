# c1fit.py 결과(fit/<키>.json) → 캡쳐원 스타일(.costyle)
# 사용법: python3 make_styles.py <작업폴더> <출력 Styles 폴더> [키...]
#   RAW: <출력>/<그룹> RAW/Canon_<이름>_<WB조정>.costyle   JPG: <출력>/<그룹> JPG/<이름>.costyle
# 내용: R·G·B 커브(9점), 컬러에디터 8색(색조·채도), 클래리티·스트럭처, silver rich 필름 그레인 (c1fit.py detail_of 값)
import sys, os, json, glob, re, uuid

W, OUT = sys.argv[1], sys.argv[2]; keys = sys.argv[3:]
# 캡쳐원 기본 컬러에디터 문자열 (칸 순서: 핑크·보라·파랑·시안·초록·노랑·주황·빨강·전체), 4·5번째 값 = 색조·채도
CC_DEFAULT = ('1,1,1,0,0,0,255,0,168.909881591797,-7.11462593078613,7.11462593078613,-100,100,15,0,0,0,0;'
              '1,1,1,0,0,0,170.93928527832,0,255,-17.8928756713867,17.8928756713867,-100,100,15,0,0,0,0;'
              '1,1,1,0,0,0,0,64.2907180786133,255,-22.4273700714111,22.4273700714111,-100,100,15,0,0,0,0;'
              '1,1,1,0,0,0,0,255,236.14192199707,-11.8545951843262,11.8545951843262,-100,100,15,0,0,0,0;'
              '1,1,1,0,0,0,45.498851776123,255,0,-39.3857116699219,39.3857116699219,-100,100,15,0,0,0,0;'
              '1,1,1,0,0,0,255,211.99267578125,0,-5,5,-100,100,15,0,0,0,0;'
              '1,1,1,0,0,0,255,101.301910400391,0,-6.01692199707031,6.01692199707031,-100,100,15,0,0,0,0;'
              '1,1,1,0,0,0,255,0,31.4708557128906,-10.195873260498,10.195873260498,-100,100,15,0,0,0,0;'
              '0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0')
XK = [i * 12.5 for i in range(9)]


def curve(ys):
    return ';'.join(f'{x / 100:g},{min(1, max(0, y / 100)):.6f}' for x, y in zip(XK, ys))


def colors(ce):          # ce: red…pink 순서 [색조, 채도] → 파일 칸 순서(pink…red)로 넣음
    slots = [s.split(',') for s in CC_DEFAULT.split(';')]
    for i, (h, s, *_) in enumerate(ce):
        f = slots[7 - i]; f[3] = f'{h:.4f}'; f[4] = f'{s:.4f}'
    return ';'.join(','.join(f) for f in slots)


def grain(src):
    t = open(src, encoding='utf-8').read()
    g = lambda k, d: float((re.search(rf'crs:{k}="([^"]*)"', t) or [0, d])[1])
    amt, size = g('GrainAmount', 0), g('GrainSize', 25)
    if amt <= 0: return []
    return [('FilmGrainType', '1'), ('FilmGrainAmount', f'{amt * 0.6:.0f}'), ('FilmGrainGranularity', f'{size:.0f}')]


def write(path, name, P, extra):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kv = [('Name', name), ('UUID', str(uuid.uuid5(uuid.NAMESPACE_URL, 'cc-hayasaka/' + name)).upper()),
          ('ColorCorrections', colors(P['ce']))]
    kv += [(f'GradationCurve{c.capitalize()}', curve(P['curves'][c])) for c in ('red', 'green', 'blue')]
    kv += extra
    body = '\n'.join(f'\t<E K="{k}" V="{v}" />' for k, v in kv)
    open(path, 'w', encoding='utf-8').write(f'<?xml version="1.0"?>\n<SL Engine="1300">\n{body}\n</SL>\n')


n = 0
for f in sorted(glob.glob(W + '/fit/*.json')):
    r = json.load(open(f)); lk = r['look']
    if keys and lk['key'] not in keys: continue
    dt = r.get('detail') or {}
    gr = [('ClarityMethod', '3'), ('Clarity', str(dt.get('cl', 0))), ('ClarityStructure', str(dt.get('st', 0)))]
    if dt.get('gi'): gr += [('FilmGrainType', '1'), ('FilmGrainAmount', str(dt['gi'])), ('FilmGrainGranularity', str(dt['gg']))]   # 1 = silver rich (재시작 후 적용해서 확인할 것)
    raw_name = f'Canon_{lk["title"]}{lk["wb"]}'
    write(f'{OUT}/{lk["group"]} RAW/{raw_name}.costyle', raw_name, r['best']['raw']['params'], gr)
    write(f'{OUT}/{lk["group"]} JPG/{lk["title"]}.costyle', lk['title'], r['best']['jpg']['params'], gr)
    n += 1
print(f'{n}개 색감 → {n * 2}개 스타일: {OUT}')
