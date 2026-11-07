# 프리셋 번호 바꾸기: 폴더 안의 NN_…, Sony_NN_…, Fuji_NN_… 파일 이름과 라이트룸 표시 이름을 새 번호로
# 사용법: python3 renumber.py 폴더 "옛번호1 옛번호2 ..."   (새 순서대로 옛 번호 나열 → 01, 02, … 로 바뀜)
import sys, os, re, glob
folder, order = sys.argv[1], sys.argv[2].split()
new = {old: f'{i:02d}' for i, old in enumerate(order, 1)}
files = [f for f in glob.glob(folder + '/*.xmp') if re.match(r'^(Sony_|Fuji_)?\d\d_', os.path.basename(f))]
olds = {re.match(r'^(?:Sony_|Fuji_)?(\d\d)_', os.path.basename(f)).group(1) for f in files}
assert olds == set(order) and len(order) == len(set(order)), (sorted(olds), order)
plan = []
for f in files:
    b = os.path.basename(f)[:-4]; m = re.match(r'^(Sony_|Fuji_)?(\d\d)_(.*)$', b)
    title = (m.group(1) or '') + new[m.group(2)] + '_' + m.group(3)
    t = open(f, encoding='utf-8').read()
    look = re.search(r'<crs:Look>.*?</crs:Look>', t, re.S); body = t.replace(look.group(0), '@@LOOK@@') if look else t
    body, n = re.subn(r'(<crs:Name>\s*<rdf:Alt>\s*<rdf:li xml:lang="x-default">)[^<]*(</rdf:li>)', lambda mm: mm.group(1) + title + mm.group(2), body)
    assert n == 1, f
    if look: body = body.replace('@@LOOK@@', look.group(0))
    plan.append((f, os.path.join(folder, title + '.xmp'), body))
for old, dst, body in plan: open(dst + '.tmp', 'w', encoding='utf-8').write(body)   # 이름 겹침 없게 두 단계로
for old, dst, body in plan: os.remove(old)
for old, dst, body in plan: os.rename(dst + '.tmp', dst)
print(len(plan), '개 번호 변경')
