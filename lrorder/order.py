# 배경 특징으로 비슷한 배경끼리 묶어 순서 제안
#   묶음: 사람을 가린 장면 특징(fp/, Vision FeaturePrint) 거리 + 배경 색(bg.tsv) 조금 (평균 연결 군집, 거리 기준 TH)
#   순서: 묶음 안은 촬영 시간순, 묶음끼리는 각 묶음의 첫 촬영 시간순 (식 흐름 유지)
# 사용법: python3 order.py <작업폴더> [TH]  → order.json (그룹·순서), 화면용 미리보기는 sheet.py
import sys, json, math, struct, os
W = sys.argv[1]; TH = float(sys.argv[2]) if len(sys.argv) > 2 else 14.0
times = {l.split('\t')[0]: l.split('\t')[1] for l in open(W + '/times.tsv').read().split('\n') if l}
F = {}
for l in open(W + '/bg.tsv').read().split('\n'):
    p = l.split('\t')
    if len(p) < 7: continue
    L, a, b, sd = map(float, p[1:5])
    grid = []
    for c in p[6].split(';'):
        grid += [float(x) for x in c.split(',')] if c != '-' else [L, a, b]
    # 전체 배경색(가중 2) + 칸별 배치 + 밝기 편차(질감)
    F[p[0]] = [L * 2, a * 4, b * 4, sd] + [v * (1 if i % 3 == 0 else 2) * 0.5 for i, v in enumerate(grid)]

names = sorted(F, key=lambda n: times.get(n, ''))
FP = {}
for n in F:
    b = open(f'{W}/fp/{n}.fp', 'rb').read(); FP[n] = struct.unpack(f'{len(b) // 4}f', b)
dc = lambda x, y: math.dist(F[x], F[y]) / math.sqrt(len(F[x])) * 2
d = lambda x, y: math.dist(FP[x], FP[y]) * 20 + dc(x, y) * 0.3   # 장면 위주, 색은 보조
# 평균 연결 군집
cl = [[n] for n in names]
def cd(A, B): return sum(d(x, y) for x in A for y in B) / (len(A) * len(B))
while True:
    best = None
    for i in range(len(cl)):
        for j in range(i + 1, len(cl)):
            v = cd(cl[i], cl[j])
            if best is None or v < best[0]: best = (v, i, j)
    if not best or best[0] > TH: break
    _, i, j = best; cl[i] += cl[j]; del cl[j]
# 다듬기 1: 사진마다 평균 거리가 가장 가까운 묶음으로 옮김 (몇 번 반복)
for _ in range(6):
    moved = 0
    for ci, c in enumerate(cl):
        for n in list(c):
            if len(c) == 1: continue
            own = sum(d(n, m) for m in c if m != n) / (len(c) - 1)
            best = min(((sum(d(n, m) for m in o) / len(o), oi) for oi, o in enumerate(cl) if oi != ci and o), default=None)
            if best and best[0] < own * 0.9:
                c.remove(n); cl[best[1]].append(n); moved += 1
    cl = [c for c in cl if c]
    if not moved: break
# 다듬기 2: 1장짜리 묶음은 가까운 묶음에 합침 (너무 멀면 그대로)
for c in [c for c in cl if len(c) == 1]:
    n = c[0]; others = [o for o in cl if o is not c and o]
    v, o = min(((sum(d(n, m) for m in o) / len(o), o) for o in others), key=lambda t: t[0])
    if v < TH * 1.25: o.append(n); c.clear()
cl = [c for c in cl if c]
for c in cl: c.sort(key=lambda n: times.get(n, ''))
cl.sort(key=lambda c: times.get(c[0], ''))
order = [n for c in cl for n in c]
json.dump({'groups': cl, 'order': order, 'th': TH}, open(W + '/order.json', 'w'), ensure_ascii=False, indent=1)
print(f'{len(cl)}개 묶음:', [len(c) for c in cl])
