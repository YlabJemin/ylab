# 질감 맞춤용 목표: 하야사카 프리셋에서 그레인만 뺀 렌더 (RAW c01·c07, JPG c05·c11) → 작업폴더/tgt_ng/<키>__<r|j>_<id>.jpg
import sys, os, json, subprocess
RF = os.path.expanduser('~/Desktop/cc/tools/rawfit'); sys.path.insert(0, RF)
from fitlib import load_settings, settings_xmp, embed_xmp_jpeg, no_wb
W = sys.argv[1]; L = json.load(open(W + '/looks.json'))
out = W + '/tgt_ng'; os.makedirs(out + '_in', exist_ok=True); lst = []
for l in L:
    s = load_settings(l['src'])
    for kind, ids in (('r', ('c01', 'c07')), ('j', ('c05', 'c11'))):
        a = [(k, v) for k, v in (no_wb(s['attrs']) if kind == 'r' else s['attrs']) if not k.startswith('Grain')]
        x = settings_xmp(a + [('GrainAmount', '0'), ('HasSettings', 'True'), ('AlreadyApplied', 'False')], s['curves'], s['other'])
        for i in ids:
            src = f'{W}/base_{l["film"]}/{i}.jpg' if kind == 'r' else f'{W}/jpg_in/{i}.jpg'
            d = f'{out}_in/{l["key"]}__{kind}_{i}.jpg'; embed_xmp_jpeg(src, d, x); lst.append(d)
open(out + '.txt', 'w').write('\n'.join(lst) + '\n')
r = subprocess.run([RF + '/render.sh', out + '.txt', out, '0'], capture_output=True, text=True)
print(len(lst), 'ERR' in (r.stdout or ''), (r.stdout or '')[-200:])
