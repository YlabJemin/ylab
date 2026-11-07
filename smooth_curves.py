# 프리셋의 빨강·초록·파랑 톤커브를 부드럽게: 촘촘한 곡선 → 가우시안 평활 → 6점 곡선
# 사용법: python3 smooth_curves.py 프리셋.xmp [--write]
import re, sys, math

def spline(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]; n = len(xs)
    if n < 3:
        return lambda x: ys[0] + (ys[-1] - ys[0]) * (x - xs[0]) / (xs[-1] - xs[0])
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]; al = [0] * n
    for i in range(1, n - 1):
        al[i] = 3 / h[i] * (ys[i + 1] - ys[i]) - 3 / h[i - 1] * (ys[i] - ys[i - 1])
    l = [1] + [0] * (n - 1); mu = [0] * n; z = [0] * n
    for i in range(1, n - 1):
        l[i] = 2 * (xs[i + 1] - xs[i - 1]) - h[i - 1] * mu[i - 1]; mu[i] = h[i] / l[i]; z[i] = (al[i] - h[i - 1] * z[i - 1]) / l[i]
    c = [0] * n; b = [0] * (n - 1); d = [0] * (n - 1)
    for j in range(n - 2, -1, -1):
        c[j] = z[j] - mu[j] * c[j + 1]; b[j] = (ys[j + 1] - ys[j]) / h[j] - h[j] * (c[j + 1] + 2 * c[j]) / 3; d[j] = (c[j + 1] - c[j]) / (3 * h[j])
    def ev(x):
        x = min(max(x, xs[0]), xs[-1]); j = n - 2
        for i in range(n - 1):
            if xs[i] <= x < xs[i + 1]: j = i; break
        t = x - xs[j]; return min(255, max(0, ys[j] + b[j] * t + c[j] * t * t + d[j] * t ** 3))
    return ev

KNOTS = [0, 51, 102, 153, 204, 255]
def smooth(pts, sigma=18):
    f = spline(pts); dense = [f(x) for x in range(256)]
    # 가장자리는 기울기를 이어서 연장한 뒤 평활 (끝점 왜곡 방지)
    ext = lambda x: dense[0] + (dense[8] - dense[0]) / 8 * x if x < 0 else (dense[255] + (dense[255] - dense[247]) / 8 * (x - 255) if x > 255 else dense[x])
    sm = []
    for x in range(256):
        w = [(math.exp(-((k) ** 2) / (2 * sigma * sigma)), ext(x + k)) for k in range(-3 * sigma, 3 * sigma + 1)]
        sm.append(sum(a * v for a, v in w) / sum(a for a, _ in w))
    sm[0], sm[255] = dense[0], dense[255]
    out = []; prev = -1
    for x in KNOTS:
        y = int(round(min(255, max(0, sm[x])))); y = max(y, prev); out.append((x, y)); prev = y
    g = spline(out)
    dev = max(abs(g(x) - dense[x]) for x in range(256))
    return out, dev

path = sys.argv[1]; t = open(path, encoding='utf-8').read()
for c in ('ToneCurvePV2012Red', 'ToneCurvePV2012Green', 'ToneCurvePV2012Blue'):
    blk = re.search(r'<crs:%s>.*?</crs:%s>' % (c, c), t, re.S).group(0)
    pts = [tuple(map(int, x.split(','))) for x in re.findall(r'<rdf:li>([^<]*)</rdf:li>', blk)]
    if len(pts) <= 6: continue
    new, dev = smooth(pts)
    print(f'{c[15:]:5s} {len(pts)}점 → {len(new)}점 {[y for _, y in new]} | 원래 곡선과 최대 차이 {dev:.1f}')
    nb = '<crs:%s>\n    <rdf:Seq>\n%s    </rdf:Seq>\n   </crs:%s>' % (c, ''.join('     <rdf:li>%d, %d</rdf:li>\n' % p for p in new), c)
    t = t.replace(blk, nb)
if '--write' in sys.argv:
    open(path, 'w', encoding='utf-8').write(t); print('저장함')
