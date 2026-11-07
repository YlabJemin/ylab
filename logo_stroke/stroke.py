# 로고 원본 이미지의 획을 얇게 / 끝을 뾰족하게 / 꼬리를 짧게 가공
import sys, json
from collections import deque
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage.morphology import skeletonize

src, outdir = sys.argv[1], sys.argv[2]
S = 3  # 업스케일 배율
im = Image.open(src).convert("RGB")
im = im.resize((im.width * S, im.height * S), Image.LANCZOS)
a = np.asarray(im).astype(float) / 255
lum = a.mean(axis=2)
soft = ndi.gaussian_filter(lum, 1.2)
soft2 = ndi.gaussian_filter(lum, 3.5)
mask = soft < 0.6
color = np.median(a[mask & (lum < 0.45)], axis=0)
bg = np.array([1.0, 1.0, 1.0])

lab, n = ndi.label(mask)
sizes = ndi.sum(mask, lab, range(1, n + 1))
mask = np.isin(lab, np.where(sizes > 300 * S)[0] + 1)
lab, n = ndi.label(mask)
H, W = mask.shape
# 별표: 오른쪽 위에 있는 작은 덩어리
star = np.zeros_like(mask)
for i in range(1, n + 1):
    ys, xs = np.where(lab == i)
    if ys.mean() < H * 0.42 and xs.mean() > W * 0.68 and len(ys) < mask.sum() * 0.06:
        star |= lab == i
text = mask & ~star

text_s = (soft2 < 0.6) & ndi.binary_dilation(text, iterations=6) & ~ndi.binary_dilation(star, iterations=3)
text_s = ndi.binary_opening(text_s, iterations=2)
dt = ndi.distance_transform_edt(text_s)
sk = skeletonize(text_s)
R = np.median(dt[sk])
print("획 반지름(px)", round(R, 1), "별 픽셀", int(star.sum()))

nb = np.array([[1, 1, 1], [1, 0, 1], [1, 1, 1]])
def endpoints(s):
    c = ndi.convolve(s.astype(int), nb, mode="constant")
    return s & (c == 1)
def nbrs(s, y, x):
    out = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            yy, xx = y + dy, x + dx
            if (dy or dx) and 0 <= yy < H and 0 <= xx < W and s[yy, xx]:
                out.append((yy, xx, 1.414 if dy and dx else 1))
    return out
def branches(s):
    """끝점에서 갈림길 전까지의 가지 목록: [(점들, 누적거리들, 갈림길에서 끝났는지)]"""
    res = []
    for y, x in zip(*np.where(endpoints(s))):
        pts, ds, seen, cur, acc, junc = [(y, x)], [0.0], {(y, x)}, (y, x), 0.0, False
        while True:
            nb_ = [p for p in nbrs(s, *cur) if (p[0], p[1]) not in seen]
            allnb = nbrs(s, *cur)
            if len(allnb) >= 3 and len(pts) > 1:
                junc = True; pts.pop(); ds.pop(); break
            if not nb_:
                break
            yy, xx, w = nb_[0]
            acc += w; cur = (yy, xx); seen.add(cur); pts.append(cur); ds.append(acc)
        res.append((pts, ds, junc))
    return res
def prune(s, L):
    for _ in range(3):
        for pts, ds, junc in branches(s):
            if junc and ds and ds[-1] < L:
                for p in pts: s[p] = False
        s = skeletonize(s)
    return s
sk = prune(sk, 1.6 * R)
MINLEN = 3.0
def geo(s):
    """긴 끝 가지(꼬리)만: 끝점에서의 거리"""
    d = np.full(s.shape, np.inf)
    for pts, ds, junc in branches(s):
        if ds and ds[-1] >= MINLEN * R:
            for p, v in zip(pts, ds):
                d[p] = min(d[p], v)
    return d

def render(thin, taper, tmin, trim):
    s = sk.copy()
    if trim > 0:
        s &= ~(geo(s) < trim * R)
    d = geo(s)
    F = np.full((H, W), -1e9)
    ys, xs = np.where(s)
    for y, x in zip(ys, xs):
        r = R * thin
        if taper > 0 and np.isfinite(d[y, x]):
            t = min(1.0, d[y, x] / (taper * R))
            r *= tmin + (1 - tmin) * t ** 0.7
        k = int(r) + 2
        y0, y1, x0, x1 = max(0, y - k), min(H, y + k + 1), max(0, x - k), min(W, x + k + 1)
        gy, gx = np.mgrid[y0:y1, x0:x1]
        v = r - np.hypot(gy - y, gx - x)
        F[y0:y1, x0:x1] = np.maximum(F[y0:y1, x0:x1], v)
    return np.clip(F + 0.5, 0, 1)

def thin_only(thin):
    return np.clip(dt - (1 - thin) * R + 0.5, 0, 1) * text

star_a = np.clip((0.6 - soft) / 0.15, 0, 1) * star
V = json.loads(sys.argv[3])
for name, p in V.items():
    alpha = thin_only(p["thin"]) if p["taper"] == 0 and p["trim"] == 0 else render(p["thin"], p["taper"], p["tmin"], p["trim"])
    a2 = ndi.gaussian_filter(alpha, 0.16 * R)  # 윤곽 매끈하게
    alpha = np.clip((a2 - 0.5) * 3.0 + 0.5, 0, 1)
    alpha = np.maximum(alpha, star_a)
    rgb = bg * (1 - alpha[..., None]) + color * alpha[..., None]
    Image.fromarray((rgb * 255).round().astype(np.uint8)).save(f"{outdir}/{name}.png")
    print("저장", name)
