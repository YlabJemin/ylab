# 인스타(보정·크롭된) 사진과 같은 컷을 원본 폴더에서 찾기: 작은 흑백 썸네일에서 여러 배율로 템플릿 매칭
import sys, os, numpy as np
from PIL import Image
from skimage.feature import match_template
insta, folder = sys.argv[1], sys.argv[2]
TW = 90
def gray(im, w):
    im = im.convert("L"); h = round(im.height * w / im.width)
    a = np.asarray(im.resize((w, h), Image.BILINEAR), float)
    return (a - a.mean()) / (a.std() + 1e-6)
ins = Image.open(insta)
res = []
files = sorted(f for f in os.listdir(folder) if f.lower().endswith(".jpg"))
for f in files:
    im = Image.open(os.path.join(folder, f)); im.draft("RGB", (im.width // 8, im.height // 8))
    o = gray(im, TW)
    best = -1
    for s in (1.0, 0.93, 0.86, 0.79, 0.72, 0.65):
        t = gray(ins, max(20, round(TW * s)))
        if t.shape[0] > o.shape[0] or t.shape[1] > o.shape[1]: continue
        best = max(best, match_template(o, t).max())
    res.append((best, f))
res.sort(reverse=True)
for b, f in res[:8]: print(round(b, 3), f)
