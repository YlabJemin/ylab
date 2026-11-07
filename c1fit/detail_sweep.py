# 질감 조합 시험: 학습 세션 c01에 색감 값 + (클래리티·스트럭처·그레인) 조합을 넣고 원본 크기로 처리 → 목표(tgt_full)와 질감 수치 비교
# 사용법: python3 detail_sweep.py <작업폴더> <키> '<조합 JSON 목록>'   조합 = {"sh":샤프닝(기본 180),"cl":클래리티,"st":스트럭처,"gt":"soft","gi":세기,"gg":입자크기}
import sys, os, json, subprocess, time, glob
W, key, combos = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
sys.argv = [sys.argv[0], W, '--none']
exec(open(os.path.expanduser('~/Desktop/cc/tools/c1fit/c1fit.py')).read().split("L = {l['key']")[0])
P = json.load(open(f'{W}/fit/{key}.json'))['best']['raw']['params']
cv = P['curves']; args = ', '.join(aslist(cv[c]) for c in ('red', 'green', 'blue')) + ', ' + aslist(P['ce'])
DT = os.path.expanduser('~/Desktop/cc/tools/c1fit/detail')
def meas(f):
    r = []
    for sc in ('2400', '8192'):
        o = subprocess.run([DT, f], capture_output=True, text=True, env=dict(os.environ, CROP='1', SCALE=sc, CY='0.3')).stdout.split()
        r += [float(x) for x in o[1:]]
    return r
T = meas(f'{W}/tgt_full/{key}_g.jpg'); print('목표', [round(x, 2) for x in T], flush=True)
for c in combos:
    tag = f'sh{c.get("sh",180)}_cl{c.get("cl",0)}_st{c.get("st",0)}_{c.get("gt","none").replace(" ","")}{c.get("gi",0)}_{c.get("gg",0)}'
    d = f'{W}/dsweep/{key}/{tag}'; os.makedirs(d, exist_ok=True)
    for f in glob.glob(d + '/*.jpg'): os.remove(f)
    g = f'''set film grain type of a to {c["gt"]}
	set film grain impact of a to {c["gi"]}
	set film grain granularity of a to {c["gg"]}''' if c.get('gt') else 'set film grain impact of a to 0'
    s = AS_HEAD + f'''
tell application "Capture One"
	set d to document "{DOC}"
	set v to first variant of d whose name is "c01"
	my ccApply(v, {args})
	set a to adjustments of v
	set clarity method of a to natural
	set clarity amount of a to {c.get("cl", 0)}
	set clarity structure of a to {c.get("st", 0)}
	set sharpening amount of a to {c.get("sh", 180)}
	{g}
	if not (exists recipe "ccfitfull" of d) then make new recipe at d with properties {{name:"ccfitfull"}}
	set j to recipe "ccfitfull" of d
	set output format of j to JPEG
	set JPEG quality of j to 95
	set color profile of j to "sRGB Color Space Profile"
	set scaling method of j to Fixed
	set scaling unit of j to percent
	set primary scaling value of j to 100
	set existing files of j to overwrite
	set enabled of j to false
	set root folder location of j to (POSIX file "{d}")
	set root folder type of j to custom location
	if (root folder type of j) is not custom location then error "recipe location"
	process {{v}} recipe "ccfitfull"
end tell'''
    open(d + '.applescript', 'w').write(s); r = subprocess.run(['osascript', d + '.applescript'], capture_output=True, text=True)
    if r.returncode: print(r.stderr); break
    for _ in range(120):
        fs = glob.glob(d + '/*.jpg')
        if fs:
            time.sleep(1); s1 = os.path.getsize(fs[0]); time.sleep(1.5)
            if os.path.getsize(fs[0]) == s1: break
        time.sleep(1)
    m = meas(d + '/c01.jpg'); err = sum(abs(a - b) / max(b, 0.3) for a, b in zip(m, T))
    print(tag, [round(x, 2) for x in m], '차이', round(err, 2), flush=True)
