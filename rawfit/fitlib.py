# RAW용 프리셋 맞추기 공용 함수
# - 프리셋 XMP 읽기/쓰기, JPG에 설정 넣기
# - 렌더 픽셀 비교 → 채널 톤커브(ProPhoto 원색 공간) + 색상혼합(채도·색조) 보정
import re, os, math, struct, colorsys, glob

CURVES = ['ToneCurvePV2012', 'ToneCurvePV2012Red', 'ToneCurvePV2012Green', 'ToneCurvePV2012Blue']
CHANNELS = {'ToneCurvePV2012Red': 0, 'ToneCurvePV2012Green': 1, 'ToneCurvePV2012Blue': 2}
BANDS = ['Red', 'Orange', 'Yellow', 'Green', 'Aqua', 'Blue', 'Purple', 'Magenta']
BAND_CENTERS = [0, 30, 60, 120, 180, 240, 270, 300]
META = re.compile(r'^(PresetType|Cluster|UUID|Supports\w+|RequiresRGBTables|CameraModelRestriction|Copyright|ContactInfo)$')


# ---------- 프리셋 XMP ----------
def load_preset(path):
    t = open(path, encoding='utf-8').read()
    head = re.search(r'<rdf:Description rdf:about=""(.*?)>', t, re.S).group(1)
    attrs = re.findall(r'crs:(\w+)="([^"]*)"', head)
    curves = {}
    for c in CURVES:
        m = re.search(r'<crs:%s>.*?</crs:%s>' % (c, c), t, re.S)
        curves[c] = [tuple(int(float(z)) for z in li.split(',')) for li in re.findall(r'<rdf:li>([^<]*)</rdf:li>', m.group(0))] if m else [(0, 0), (255, 255)]
    other = [m.group(0) for m in re.finditer(r'<crs:(PointColors|ColorVariance)>.*?</crs:\1>', t, re.S)]
    return dict(path=path, text=t, attrs=attrs, curves=curves, other=other)


def curve_xml(c, pts):
    return '   <crs:%s>\n    <rdf:Seq>\n%s    </rdf:Seq>\n   </crs:%s>\n' % (
        c, ''.join('     <rdf:li>%d, %d</rdf:li>\n' % tuple(p) for p in pts), c)


def settings_xmp(attrs, curves, other=()):
    body = '\n'.join('   crs:%s="%s"' % (a, v) for a, v in attrs)
    return ('<x:xmpmeta xmlns:x="adobe:ns:meta/">\n <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
            '  <rdf:Description rdf:about=""\n    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"\n'
            + body + '>\n' + ''.join(curve_xml(c, curves[c]) for c in CURVES) + '\n'.join(other)
            + '\n  </rdf:Description>\n </rdf:RDF>\n</x:xmpmeta>\n')


def jpeg_attrs(p):
    """JPG용: 프리셋 그대로(상대 색온도 포함) + '아직 적용 안 됨' 표시"""
    return [(a, v) for a, v in p['attrs'] if not META.match(a)] + [('AlreadyApplied', 'False')]


def raw_attrs(p, hsl=None):
    """RAW용: 상대 색온도 제거, 촬영 당시 WB, 색상혼합 보정량 더하기"""
    hsl = hsl or {'Saturation': {}, 'Hue': {}}
    out = []
    for a, v in p['attrs']:
        if META.match(a) or a in ('IncrementalTemperature', 'IncrementalTint'):
            continue
        if a == 'WhiteBalance':
            v = 'As Shot'
        for kind in ('Saturation', 'Hue'):
            pre = kind + 'Adjustment'
            if a.startswith(pre) and a[len(pre):] in hsl[kind]:
                v = '%+d' % max(-100, min(100, round(float(v) + hsl[kind][a[len(pre):]])))
        out.append((a, v))
    return out


def embed_xmp_jpeg(src, dst, xmp):
    """JPG의 기존 XMP는 지우고, 새 설정을 표준 위치(APP0/Exif 뒤)에 넣기"""
    d = open(src, 'rb').read(); assert d[:2] == b'\xff\xd8'
    segs = []; i = 2
    while d[i] == 0xFF and d[i + 1] != 0xDA:
        L = struct.unpack('>H', d[i + 2:i + 4])[0]
        seg = d[i:i + 2 + L]
        if not (d[i + 1] == 0xE1 and seg[4:33] == b'http://ns.adobe.com/xap/1.0/\x00'):
            segs.append(seg)
        i += 2 + L
    pkt = b'http://ns.adobe.com/xap/1.0/\x00' + ('<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>' + xmp + '<?xpacket end="w"?>').encode('utf-8')
    new = b'\xff\xe1' + struct.pack('>H', len(pkt) + 2) + pkt
    k = 0
    while k < len(segs) and segs[k][1] in (0xE0, 0xE1):
        k += 1
    open(dst, 'wb').write(d[:2] + b''.join(segs[:k]) + new + b''.join(segs[k:]) + d[i:])


# ---------- 색 계산 ----------
_dec = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
_enc = lambda c: 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
LUT = [_dec(i / 255) for i in range(256)]
_M = [[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]]
_B = [[1.0478112, 0.0228866, -0.0501270], [0.0295424, 0.9904844, -0.0170491], [-0.0092345, 0.0150436, 0.7521316]]
_P = [[1.3459433, -0.2556075, -0.0511118], [-0.5445989, 1.5081673, 0.0205351], [0.0, 0.0, 1.2118128]]
_mul = lambda m, v: [m[r][0] * v[0] + m[r][1] * v[1] + m[r][2] * v[2] for r in range(3)]
_MP = [[sum(_P[i][t] * sum(_B[t][u] * _M[u][j] for u in range(3)) for t in range(3)) for j in range(3)] for i in range(3)]


def to_pp(px):
    """sRGB → ProPhoto 원색(감마는 sRGB), 0~255: 라이트룸 톤커브가 작동하는 공간 근사"""
    v = _mul(_MP, [LUT[px[0]], LUT[px[1]], LUT[px[2]]])
    return [255 * _enc(min(1, max(0, c))) for c in v]


def lab(px):
    X, Y, Z = _mul(_M, [LUT[px[0]], LUT[px[1]], LUT[px[2]]])
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(X / 0.95047), f(Y), f(Z / 1.08883)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def spline(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]; n = len(xs)
    if n < 3:
        return lambda x: ys[0] + (ys[-1] - ys[0]) * (min(max(x, xs[0]), xs[-1]) - xs[0]) / (xs[-1] - xs[0])
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
            if xs[i] <= x < xs[i + 1]:
                j = i; break
        t = x - xs[j]
        return min(255, max(0, ys[j] + b[j] * t + c[j] * t * t + d[j] * t ** 3))
    return ev


def smooth_curve(pts, sigma=18, knots=(0, 51, 102, 153, 204, 255)):
    f = spline(pts); dense = [f(x) for x in range(256)]
    ext = lambda x: dense[0] + (dense[8] - dense[0]) / 8 * x if x < 0 else (
        dense[255] + (dense[255] - dense[247]) / 8 * (x - 255) if x > 255 else dense[x])
    sm = []
    for x in range(256):
        w = [(math.exp(-(k * k) / (2 * sigma * sigma)), ext(x + k)) for k in range(-3 * sigma, 3 * sigma + 1)]
        sm.append(sum(a * v for a, v in w) / sum(a for a, _ in w))
    sm[0], sm[255] = dense[0], dense[255]
    out = []; prev = -1
    for x in knots:
        y = max(int(round(min(255, max(0, sm[x])))), prev); out.append((x, y)); prev = y
    return out


# ---------- 픽셀 비교 ----------
W_, H_, BS = 120, 80, 4


def load_px(path):
    d = open(path, 'rb').read()
    return [(d[i], d[i + 1], d[i + 2]) for i in range(0, len(d), 3)]


def blocks(img):
    out = []
    for by in range(1, H_ // BS - 1):
        for bx in range(1, W_ // BS - 1):
            px = [img[(by * BS + j) * W_ + bx * BS + i] for j in range(BS) for i in range(BS)]
            out.append(tuple(round(sum(p[c] for p in px) / len(px)) for c in range(3)))
    return out


def band(px):
    hh, ss, vv = colorsys.rgb_to_hsv(*(c / 255 for c in px))
    if ss < 0.12 or vv < 0.12:
        return None
    d = [min(abs(hh * 360 - c), 360 - abs(hh * 360 - c)) for c in BAND_CENTERS]
    return d.index(min(d))


def delta_e(pairs):
    sw = sum(w for _, _, w in pairs)
    return sum(math.dist(lab(a), lab(t)) * w for a, t, w in pairs) / sw


def fit_step(pairs, curves, hsl, damp=0.8, sat_lim=90, hue_lim=70):
    """pairs: (RAW 블록, 목표 블록, 가중치). 채널 톤커브와 색상혼합 보정량을 한 단계 갱신"""
    Ap = [to_pp(a) for a, _, _ in pairs]; Tp = [to_pp(t) for _, t, _ in pairs]; Wg = [w for _, _, w in pairs]
    newc = dict(curves)
    xs_out = list(range(0, 256, 16)) + [255]
    for cname, ci in CHANNELS.items():
        nb = 32; s = [0.0] * nb; cnt = [0.0] * nb
        for a, t, w in zip(Ap, Tp, Wg):
            bi = min(nb - 1, int(a[ci] / 8)); s[bi] += (t[ci] - a[ci]) * w; cnt[bi] += w
        cen = [i * 8 + 4 for i in range(nb)]; valid = [i for i in range(nb) if cnt[i] >= 6]
        dl = [s[i] / cnt[i] if cnt[i] else 0 for i in range(nb)]; sm = {}
        for i in valid:
            ws = [(cnt[j], dl[j]) for j in (i - 1, i, i + 1) if j in valid]
            sm[i] = sum(a * b for a, b in ws) / sum(a for a, _ in ws)
        def delta(x):
            if not valid: return 0
            lo, hi = valid[0], valid[-1]
            if x <= cen[lo]: return sm[lo] * x / cen[lo]
            if x >= cen[hi]: return sm[hi] * (255 - x) / (255 - cen[hi])
            j = max(i for i in valid if cen[i] <= x); jn = min(i for i in valid if cen[i] >= x)
            return sm[j] if j == jn else sm[j] + (sm[jn] - sm[j]) * (x - cen[j]) / (cen[jn] - cen[j])
        C = spline(curves[cname]); ys = []; prev = 0
        for x in xs_out:
            y = C(x); y = int(round(min(255, max(0, y + damp * delta(y))))); y = max(y, prev); ys.append(y); prev = y
        newc[cname] = list(zip(xs_out, ys))
    acc = [[0.0] * 5 for _ in BANDS]
    for (a, t, w) in pairs:
        bi = band(t)
        if bi is None: continue
        la = lab(a); lt = lab(t); ca = math.hypot(la[1], la[2]); ct = math.hypot(lt[1], lt[2])
        if ct < 6: continue
        dh = (math.degrees(math.atan2(lt[2], lt[1])) - math.degrees(math.atan2(la[2], la[1])) + 540) % 360 - 180
        acc[bi][0] += ct * w; acc[bi][1] += ca * w; acc[bi][2] += dh * w * ct; acc[bi][3] += w * ct; acc[bi][4] += w
    ns = {'Saturation': dict(hsl['Saturation']), 'Hue': dict(hsl['Hue'])}
    for bi, bn in enumerate(BANDS):
        if acc[bi][4] < 100 or acc[bi][0] / acc[bi][4] < 12:
            continue
        ratio = acc[bi][0] / max(acc[bi][1], 1e-6); dh = acc[bi][2] / acc[bi][3]
        ns['Saturation'][bn] = max(-sat_lim, min(sat_lim, ns['Saturation'].get(bn, 0) + 0.7 * (ratio - 1) * 100))
        ns['Hue'][bn] = max(-hue_lim, min(hue_lim, ns['Hue'].get(bn, 0) + 0.5 * dh * 100 / 30))
    return newc, ns


# ---------- 원본 설정 읽기 (프리셋 XMP 또는 DNG) ----------
CLEAN = re.compile(r'^(Crop\w*|HasCrop|RawFileName|Upright\w*|Perspective\w*|Lens\w*|AutoLateralCA|Defringe\w*|VignetteAmount|'
                   r'CameraProfile\w*|UUID|AlreadyApplied|HasSettings)$')
WB_KEYS = ('WhiteBalance', 'IncrementalTemperature', 'IncrementalTint', 'Temperature', 'Tint')
HSL_KEYS = [f'{k}Adjustment{c}' for k in ('Hue', 'Saturation', 'Luminance') for c in BANDS]


def load_settings(path):
    """프리셋 XMP 또는 DNG에서 보정값만 꺼냄 (크롭·렌즈·기울기·프로필·메타데이터 제외)"""
    if path.lower().endswith('.dng'):
        d = open(path, 'rb').read(); i = d.find(b'<x:xmpmeta')
        t = d[i:d.find(b'</x:xmpmeta>', i) + 12].decode('utf8', 'replace')
    else:
        t = open(path, encoding='utf-8').read()
    t = re.sub(r'<crs:Preset>.*?</crs:Preset>', '', t, flags=re.S)
    t = re.sub(r'<crs:Look>.*?</crs:Look>', '', t, flags=re.S)
    head = re.search(r'<rdf:Description rdf:about=""(.*?)>', t, re.S).group(1)
    attrs = [(a, v) for a, v in re.findall(r'crs:(\w+)="([^"]*)"', head) if not CLEAN.match(a) and not META.match(a)]
    have = {a for a, _ in attrs}
    attrs += [(k, '0') for k in HSL_KEYS if k not in have]      # 색상혼합 보정이 항상 들어가도록
    curves = {}
    for c in CURVES:
        m = re.search(r'<crs:%s>.*?</crs:%s>' % (c, c), t, re.S)
        curves[c] = [tuple(int(float(z)) for z in li.split(',')) for li in re.findall(r'<rdf:li>([^<]*)</rdf:li>', m.group(0))] if m else [(0, 0), (255, 255)]
    other = [m.group(0) for m in re.finditer(r'<crs:(PointColors|ColorVariance)>.*?</crs:\1>', t, re.S)]
    wb = dict(attrs)
    return dict(path=path, attrs=attrs, curves=curves, other=other,
                wb=(int(float(wb.get('IncrementalTemperature', 0))), int(float(wb.get('IncrementalTint', 0)))))


def identity_settings():
    return dict(path=None, attrs=[('Version', '17.4'), ('ProcessVersion', '15.4')] + [(k, '0') for k in HSL_KEYS] + [('ToneCurveName2012', 'Custom')],
                curves={c: [(0, 0), (255, 255)] for c in CURVES}, other=[], wb=(0, 0))


def no_wb(attrs):
    return [(a, v) for a, v in attrs if a not in WB_KEYS]


def add_hsl(attrs, hsl):
    out = []
    for a, v in attrs:
        for kind in ('Saturation', 'Hue'):
            pre = kind + 'Adjustment'
            if a.startswith(pre) and a[len(pre):] in hsl.get(kind, {}):
                v = '%+d' % max(-100, min(100, round(float(v) + hsl[kind][a[len(pre):]])))
        out.append((a, v))
    return out


# ---------- 카메라 프로필 (Look) ----------
def look_xml(profile_path):
    """라이트룸 카메라 매칭 프로필 파일 → 설정에 넣을 <crs:Look> 블록과 CameraProfile 값"""
    t = open(profile_path, encoding='utf-8').read()
    g = lambda k: re.search(r'crs:' + k + r'="([^"]*)"', t).group(1)
    name = re.search(r'<crs:Name>.*?x-default">([^<]*)', t, re.S).group(1)
    xml = ('   <crs:Look>\n    <rdf:Description\n     crs:Name="%s"\n     crs:Amount="1"\n     crs:UUID="%s"\n'
           '     crs:SupportsAmount="False"\n     crs:SupportsMonochrome="False"\n     crs:SupportsOutputReferred="False"\n'
           '     crs:Copyright="%s">\n    <crs:Group>\n     <rdf:Alt>\n      <rdf:li xml:lang="x-default">Profiles</rdf:li>\n     </rdf:Alt>\n    </crs:Group>\n'
           '    <crs:Parameters>\n     <rdf:Description\n      crs:Version="%s"\n      crs:ProcessVersion="%s"\n      crs:ConvertToGrayscale="False"\n'
           '      crs:CameraProfile="%s"\n      crs:RGBTable="%s"/>\n    </crs:Parameters>\n    </rdf:Description>\n   </crs:Look>'
           % (name, g('UUID').upper(), g('Copyright'), g('Version'), g('ProcessVersion'), g('CameraProfile'), g('RGBTable')))
    return xml, g('CameraProfile')


# ---------- 프리셋 파일 만들기 ----------
def make_preset(title, group, attrs, curves, other=(), extra_xml=''):
    import uuid as _u
    alt = lambda s: '<rdf:Alt>\n     <rdf:li xml:lang="x-default">%s</rdf:li>\n    </rdf:Alt>' % s
    meta = [('PresetType', 'Normal'), ('Cluster', ''), ('UUID', _u.uuid4().hex.upper()), ('SupportsAmount', 'False'),
            ('SupportsColor', 'True'), ('SupportsMonochrome', 'True'), ('SupportsHighDynamicRange', 'True'),
            ('SupportsNormalDynamicRange', 'True'), ('SupportsSceneReferred', 'True'), ('SupportsOutputReferred', 'True'),
            ('RequiresRGBTables', 'False'), ('CameraModelRestriction', ''), ('Copyright', ''), ('ContactInfo', '')]
    body = '\n'.join('   crs:%s="%s"' % (a, v) for a, v in meta + list(attrs) + [('HasSettings', 'True')])
    return ('<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00        ">\n'
            ' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n  <rdf:Description rdf:about=""\n'
            '    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"\n' + body + '>\n'
            '   <crs:Name>\n    %s\n   </crs:Name>\n   <crs:ShortName>\n    %s\n   </crs:ShortName>\n   <crs:SortName>\n    %s\n   </crs:SortName>\n'
            '   <crs:Group>\n    %s\n   </crs:Group>\n   <crs:Description>\n    %s\n   </crs:Description>\n'
            % (alt(title), alt(''), alt(''), alt(group), alt(''))
            + ''.join(curve_xml(c, curves[c]) for c in CURVES) + '\n'.join(other) + ('\n' + extra_xml if extra_xml else '')
            + '\n  </rdf:Description>\n </rdf:RDF>\n</x:xmpmeta>\n')


# ---------- 위치 맞추기 (카메라 JPG와 RAW 렌더가 조금 다를 때) ----------
def warp(img, s=1.0, k=0.0, dx=0.0, dy=0.0):
    if s == 1.0 and k == 0.0 and dx == 0.0 and dy == 0.0:
        return img
    w, h = W_, H_; R0 = (w * w / 4 + h * h / 4) ** 0.5; out = []
    for y in range(h):
        for x in range(w):
            ux = x - w / 2; uy = y - h / 2; m = (1 + k * (ux * ux + uy * uy) / (R0 * R0)) / s
            X = min(max(ux * m + w / 2 + dx, 0), w - 1.001); Y = min(max(uy * m + h / 2 + dy, 0), h - 1.001)
            x0, y0 = int(X), int(Y); fx, fy = X - x0, Y - y0
            q = [img[y0 * w + x0], img[y0 * w + x0 + 1], img[(y0 + 1) * w + x0], img[(y0 + 1) * w + x0 + 1]]
            out.append(tuple(int(round(q[0][c] * (1 - fx) * (1 - fy) + q[1][c] * fx * (1 - fy) + q[2][c] * (1 - fx) * fy + q[3][c] * fx * fy)) for c in range(3)))
    return out


def find_align(pairs_imgs):
    """(RAW 렌더, 목표) 이미지 쌍 여러 개로 확대·왜곡·이동 찾기"""
    gray = lambda im: [0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2] for p in im]
    G = [(gray(a), gray(b)) for a, b in pairs_imgs]; w, h = W_, H_; R0 = (w * w / 4 + h * h / 4) ** 0.5
    def smp(im, X, Y):
        X = min(max(X, 0), w - 1.001); Y = min(max(Y, 0), h - 1.001); x0, y0 = int(X), int(Y); fx, fy = X - x0, Y - y0
        return im[y0 * w + x0] * (1 - fx) * (1 - fy) + im[y0 * w + x0 + 1] * fx * (1 - fy) + im[(y0 + 1) * w + x0] * (1 - fx) * fy + im[(y0 + 1) * w + x0 + 1] * fx * fy
    def err(s, k, dx, dy):
        e = n = 0
        for A, T in G:
            for y in range(6, h - 6, 3):
                for x in range(8, w - 8, 3):
                    ux = x - w / 2; uy = y - h / 2; m = (1 + k * (ux * ux + uy * uy) / (R0 * R0)) / s
                    e += abs(smp(A, ux * m + w / 2 + dx, uy * m + h / 2 + dy) - T[y * w + x]); n += 1
        return e / n
    best = (err(1, 0, 0, 0), 1.0, 0.0, 0.0, 0.0); base = best[0]
    for s in [1 + i * 0.01 for i in range(0, 9)]:
        e = err(s, 0, 0, 0)
        if e < best[0]: best = (e, s, 0.0, 0.0, 0.0)
    for _ in range(2):
        _, s0, k0, dx0, dy0 = best
        for s in [s0 + i * 0.004 for i in (-2, -1, 0, 1, 2)]:
            for k in [k0 + i * 0.01 for i in (-2, -1, 0, 1, 2)]:
                for dx in [dx0 + i * 0.5 for i in (-1, 0, 1)]:
                    for dy in [dy0 + i * 0.5 for i in (-1, 0, 1)]:
                        e = err(s, k, dx, dy)
                        if e < best[0]: best = (e, s, k, dx, dy)
    return {'s': best[1], 'k': best[2], 'dx': best[3], 'dy': best[4], 'before': base, 'after': best[0]}
