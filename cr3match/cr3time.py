# CR3 촬영 시각(DateTimeOriginal + SubSecTimeOriginal)을 CMT2(Exif IFD) 박스에서 직접 읽기 (exiftool 없이)
import struct, sys, os
def cr3_time(path):
    with open(path, 'rb') as f: data = f.read(400_000)
    i = data.find(b'CMT2')
    if i < 0: return None
    t = data[i+4:]
    bo = '<' if t[:2] == b'II' else '>'
    off = struct.unpack(bo+'I', t[4:8])[0]
    n = struct.unpack(bo+'H', t[off:off+2])[0]
    vals = {}
    for k in range(n):
        e = t[off+2+12*k: off+14+12*k]
        tag, typ, cnt = struct.unpack(bo+'HHI', e[:8])
        if tag in (0x9003, 0x9291):
            if cnt <= 4: raw = e[8:8+cnt]
            else:
                vo = struct.unpack(bo+'I', e[8:12])[0]; raw = t[vo:vo+cnt]
            vals[tag] = raw.split(b'\0')[0].decode(errors='ignore')
    return (vals.get(0x9003, ''), vals.get(0x9291, ''))
if __name__ == '__main__':
    for p in sys.argv[1:]: print(cr3_time(p), os.path.basename(p))
