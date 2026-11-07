# 그레인 대응표 만들기: 학습 세션 c01에 색감 값 + 캡쳐원 그레인(종류·세기·입자크기)을 바꿔가며 2400px로 처리 → 원본 크기 입자 측정
import sys, os, json, subprocess, time, glob, itertools
sys.argv = [sys.argv[0], sys.argv[1], '--none'] + sys.argv[2:]
exec(open(os.path.expanduser('~/Desktop/cc/tools/c1fit/c1fit.py')).read().split("L = {l['key']")[0])
key = sys.argv[3]; P = json.load(open(f'{W}/fit/{key}.json'))['best']['raw']['params']
out = f'{W}/grain/{key}'; os.makedirs(out, exist_ok=True)
cv = P['curves']; args = ', '.join(aslist(cv[c]) for c in ('red', 'green', 'blue')) + ', ' + aslist(P['ce'])
res = []
for gt, imp, gran in itertools.product(sys.argv[4].split(','), [float(x) for x in sys.argv[5].split(',')], [float(x) for x in sys.argv[6].split(',')]):
    tag = f'{gt.replace(" ", "")}_{imp:g}_{gran:g}'; d = f'{out}/{tag}'; os.makedirs(d, exist_ok=True)
    for f in glob.glob(d + '/*.jpg'): os.remove(f)
    s = AS_HEAD + f'''
tell application "Capture One"
	set d to document "{DOC}"
	set v to first variant of d whose name is "c01"
	my ccApply(v, {args})
	set a to adjustments of v
	set film grain type of a to {gt}
	set film grain impact of a to {imp}
	set film grain granularity of a to {gran}
	if not (exists recipe "ccfit2400" of d) then make new recipe at d with properties {{name:"ccfit2400"}}
	set j to recipe "ccfit2400" of d
	set output format of j to JPEG
	set JPEG quality of j to 95
	set color profile of j to "sRGB Color Space Profile"
	set scaling method of j to Long_Edge
	set scaling unit of j to pixels
	set primary scaling value of j to 2400
	set existing files of j to overwrite
	set enabled of j to false
	set root folder location of j to (POSIX file "{d}")
	set root folder type of j to custom location
	if (root folder type of j) is not custom location then error "recipe location"
	process {{v}} recipe "ccfit2400"
end tell'''
    open(d + '.applescript', 'w').write(s); r = subprocess.run(['osascript', d + '.applescript'], capture_output=True, text=True)
    if r.returncode: print(r.stderr); break
    for _ in range(60):
        if glob.glob(d + '/*.jpg'): time.sleep(1.5); break
        time.sleep(1)
    m = subprocess.run([os.path.expanduser('~/Desktop/cc/tools/c1fit/detail'), d + '/c01.jpg'], capture_output=True, text=True, env=dict(os.environ, CROP='1')).stdout.split()
    print(tag, m[1:], flush=True)
