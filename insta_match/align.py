# 인스타 사진을 원본에 정밀 정렬(ORB 특징점 + RANSAC 닮음변환) → 정렬 정확도 비교, --out이면 원본 크기 캔버스(검정 여백)에 배치해 저장
import sys, os, numpy as np
from PIL import Image
from skimage.feature import ORB, match_descriptors
from skimage.measure import ransac
from skimage.transform import SimilarityTransform
insta, folder = sys.argv[1], sys.argv[2]; cands = sys.argv[3].split(","); out = sys.argv[4] if len(sys.argv) > 4 else None
D = 4  # 원본 축소 배율
ins = Image.open(insta).convert("RGB")
gi = np.asarray(ins.convert("L"), float) / 255
def feats(g):
    o = ORB(n_keypoints=3000, fast_threshold=0.05); o.detect_and_extract(g); return o.keypoints, o.descriptors
ki, di = feats(gi)
best = None
for c in cands:
    im = Image.open(os.path.join(folder, c)); W, H = im.size
    im.draft("RGB", (W // D, H // D)); im = im.convert("RGB")
    s = W / im.width
    go = np.asarray(im.convert("L"), float) / 255
    ko, do = feats(go)
    m = match_descriptors(di, do, cross_check=True, max_ratio=0.85)
    src = ki[m[:, 0]][:, ::-1]; dst = ko[m[:, 1]][:, ::-1]   # (x,y)
    model, inl = ransac((src, dst), SimilarityTransform, min_samples=3, residual_threshold=2, max_trials=3000)
    # 정렬 후 겹치는 영역 상관도
    T = SimilarityTransform(scale=model.scale * s, rotation=model.rotation, translation=model.translation * s)
    small = ins.resize((ins.width // 2, ins.height // 2))
    Ts = SimilarityTransform(scale=T.scale * 2 / D * 1, rotation=T.rotation, translation=T.translation / (s))
    inv = np.linalg.inv(SimilarityTransform(scale=model.scale * 2, rotation=model.rotation, translation=model.translation).params)
    warped = np.asarray(small.convert("L").transform(im.size, Image.AFFINE, tuple(inv[:2].ravel()), Image.BILINEAR, fillcolor=None), float)
    mask = np.asarray(Image.new("L", small.size, 255).transform(im.size, Image.AFFINE, tuple(inv[:2].ravel()), Image.NEAREST), bool)
    a = warped[mask]; b = go[mask] * 255
    ncc = np.corrcoef(a, b)[0, 1]
    print(f"{c} 일치점 {inl.sum()}/{len(m)} 배율 {T.scale:.3f} 회전 {np.degrees(T.rotation):.2f}° 위치 ({T.translation[0]:.0f},{T.translation[1]:.0f}) 상관 {ncc:.4f}")
    if best is None or inl.sum() > best[0]: best = (inl.sum(), c, T, W, H)
print("가장 잘 맞음:", best[1])
if out:
    n, c, T, W, H = best
    inv = np.linalg.inv(T.params)
    res = ins.transform((W, H), Image.AFFINE, tuple(inv[:2].ravel()), Image.BICUBIC, fillcolor=(0, 0, 0))
    res.save(out, quality=100, subsampling=0)
    print("저장", out, res.size)
