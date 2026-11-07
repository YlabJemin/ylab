#!/usr/bin/env python3
# 포토샵 액션 파일(.atn / Actions Palette.psp) 읽기 → 사람이 읽을 수 있는 단계 목록 (읽기 전용)
import struct, sys
class R:
    def __init__(s, b): s.b, s.p = b, 0
    def u8(s): v = s.b[s.p]; s.p += 1; return v
    def i16(s): v = struct.unpack('>h', s.b[s.p:s.p+2])[0]; s.p += 2; return v
    def i32(s): v = struct.unpack('>i', s.b[s.p:s.p+4])[0]; s.p += 4; return v
    def f64(s): v = struct.unpack('>d', s.b[s.p:s.p+8])[0]; s.p += 8; return v
    def raw(s, n): v = s.b[s.p:s.p+n]; s.p += n; return v
    def uni(s): n = s.i32(); v = s.raw(n*2).decode('utf-16-be', 'replace').rstrip('\x00'); return v
    def pas(s): n = s.i32(); return s.raw(n).decode('latin-1')
    def cid(s): n = s.i32(); return s.raw(4 if n == 0 else n).decode('latin-1')
def desc(r):
    name = r.uni(); cls = r.cid(); n = r.i32(); d = {'_class': cls}
    for _ in range(n): k = r.cid(); d[k] = val(r)
    return d
def ref(r):
    n = r.i32(); out = []
    for _ in range(n):
        t = r.raw(4).decode('latin-1')
        if t == 'prop': out.append(('prop', r.uni(), r.cid(), r.cid()))
        elif t == 'Clss': out.append(('class', r.uni(), r.cid()))
        elif t == 'Enmr': out.append(('enum', r.uni(), r.cid(), r.cid(), r.cid()))
        elif t == 'rele': out.append(('rel', r.uni(), r.cid(), r.i32()))
        elif t == 'Idnt': out.append(('id', r.uni(), r.cid(), r.i32()))
        elif t == 'indx': out.append(('index', r.uni(), r.cid(), r.i32()))
        elif t == 'name': out.append(('name', r.uni(), r.cid(), r.uni()))
        else: raise ValueError('ref type ' + t)
    return out
def val(r):
    t = r.raw(4).decode('latin-1')
    if t in ('Objc', 'GlbO'): return desc(r)
    if t == 'VlLs': n = r.i32(); return [val(r) for _ in range(n)]
    if t == 'doub': return r.f64()
    if t == 'UntF': u = r.raw(4).decode('latin-1'); return (r.f64(), u)
    if t == 'TEXT': return r.uni()
    if t == 'enum': return ('enum', r.cid(), r.cid())
    if t == 'long': return r.i32()
    if t == 'comp': return struct.unpack('>q', r.raw(8))[0]
    if t == 'bool': return bool(r.u8())
    if t in ('type', 'GlbC'): return ('class', r.uni(), r.cid())
    if t in ('alis', 'tdta', 'Pth '): n = r.i32(); return ('<%s %d bytes>' % (t, n), r.raw(n))[0]
    if t == 'obj ': return ('ref', ref(r))
    raise ValueError('type %r at %d' % (t, r.p))
def item(r):
    exp, en, dlg, opt = r.u8(), r.u8(), r.u8(), r.u8()
    kind = r.raw(4).decode('latin-1')
    ev = r.raw(4).decode('latin-1') if kind == 'long' else r.pas()
    name = r.pas(); has = r.i32()
    d = desc(r) if has == -1 else None
    return {'event': ev, 'name': name, 'enabled': bool(en), 'dialog': dlg, 'desc': d}
def action(r):
    idx = r.i16(); sh = r.u8(); cm = r.u8(); col = r.i16(); name = r.uni(); exp = r.u8(); n = r.i32()
    return {'name': name, 'items': [item(r) for _ in range(n)]}
def aset(r):
    name = r.uni(); exp = r.u8(); n = r.i32()
    return {'name': name, 'actions': [action(r) for _ in range(n)]}
def load(path):
    b = open(path, 'rb').read(); r = R(b); ver = r.i32()
    if path.endswith('.psp'): n = r.i32(); return [aset(r) for _ in range(n)]
    return [aset(r)]
def show(v, ind=6):
    if isinstance(v, dict):
        for k, x in v.items():
            if k == '_class': continue
            if isinstance(x, (dict, list)): print(' ' * ind + k + ':'); show(x, ind + 2)
            else: print(' ' * ind + '%s = %r' % (k, x))
    elif isinstance(v, list):
        for x in v: show(x, ind)
    else: print(' ' * ind + repr(v))
if __name__ == '__main__':
    for s in load(sys.argv[1]):
        print('== 세트:', s['name'])
        for a in s['actions']:
            if len(sys.argv) > 2 and sys.argv[2] not in a['name']: continue
            print('  -- 액션:', a['name'], '(%d단계)' % len(a['items']))
            for i, it in enumerate(a['items']):
                print('   %2d. %s [%s]%s' % (i + 1, it['name'], it['event'], '' if it['enabled'] else ' (꺼짐)'))
                if it['desc'] and (len(sys.argv) > 3): show(it['desc'])
