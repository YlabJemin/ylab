#!/usr/bin/env python3
"""맥 메모(notes.json) → 노션 페이지. 메모 하나당 페이지 하나, 제목 = 메모 제목.

사용법:
  python3 upload.py --dry                 # 변환만 해보고 블록 수 보고 (노션 접속 안 함)
  python3 upload.py --parent <페이지ID> [--limit 3]   # 업로드 (progress.json 으로 이어하기)
토큰: ~/Desktop/cc/notion_token
"""
import argparse, base64, html.parser, json, os, re, subprocess, sys, tempfile, time, urllib.request, urllib.error, uuid

HOME = os.path.expanduser('~')
EXPORT = f'{HOME}/Desktop/cc/notes_export/notes.json'
PROGRESS = f'{HOME}/Desktop/cc/notes_export/progress.json'
TOKEN_FILE = f'{HOME}/Desktop/cc/notion_token'
API = 'https://api.notion.com/v1'
MAXTXT = 2000


# ---------- HTML → 블록 ----------
class Conv(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []          # 최상위 블록
        self.cur = None           # 지금 글자를 받는 블록 dict
        self.ann = []             # 서식 스택: 'bold','italic','underline',('link',url)
        self.lists = []           # 열린 ul 의 부모 li (None = 최상위)
        self.li_stack = []
        self.table = None; self.row = None; self.cell = None
        self.images = []          # (block, data_uri)

    # 블록 만들기
    def new_block(self, typ='paragraph'):
        b = {'type': typ, 'rt': [], 'children': []}
        self.cur = b
        return b

    def text(self, s):
        if self.cell is not None:
            tgt = self.cell
        else:
            if self.cur is None:
                self.blocks.append(self.new_block())
            tgt = self.cur['rt']
        a = {'bold': 'bold' in self.ann, 'italic': 'italic' in self.ann, 'underline': 'underline' in self.ann}
        link = next((x[1] for x in self.ann if isinstance(x, tuple)), None)
        if tgt and tgt[-1]['a'] == a and tgt[-1]['link'] == link:
            tgt[-1]['t'] += s
        else:
            tgt.append({'t': s, 'a': a, 'link': link})

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ('b', 'strong'): self.ann.append('bold')
        elif tag in ('i', 'em'): self.ann.append('italic')
        elif tag == 'u': self.ann.append('underline')
        elif tag == 'a':
            href = attrs.get('href', '')
            self.ann.append(('link', href) if href.startswith(('http://', 'https://')) else 'nolink')
        elif tag == 'br': self.text('\n')
        elif tag == 'div' and self.table is None and not self.li_stack:
            self.blocks.append(self.new_block())
        elif tag in ('h1', 'h2', 'h3') and self.cur is not None and self.cell is None:
            if self.cur['type'] == 'paragraph' and not ''.join(r['t'] for r in self.cur['rt']).strip():
                self.cur['type'] = {'h1': 'heading_1', 'h2': 'heading_2', 'h3': 'heading_3'}[tag]
        elif tag == 'ul':
            self.lists.append(self.li_stack[-1] if self.li_stack else None)
        elif tag == 'li':
            b = self.new_block('bulleted_list_item')
            parent = self.lists[-1] if self.lists else None
            (parent['children'] if parent else self.blocks).append(b)
            self.li_stack.append(b)
        elif tag == 'table':
            self.table = {'type': 'table', 'rows': []}
            self.blocks.append(self.table); self.cur = None
        elif tag == 'tr' and self.table is not None:
            self.row = []; self.table['rows'].append(self.row)
        elif tag == 'td' and self.row is not None:
            self.cell = []; self.row.append(self.cell)
        elif tag == 'img':
            src = attrs.get('src', '')
            b = {'type': 'image', 'src': src}
            self.blocks.append(b); self.images.append(b); self.cur = None

    def handle_endtag(self, tag):
        pop = {'b': 'bold', 'strong': 'bold', 'i': 'italic', 'em': 'italic', 'u': 'underline'}
        if tag in pop:
            if pop[tag] in self.ann: self.ann.reverse(); self.ann.remove(pop[tag]); self.ann.reverse()
        elif tag == 'a':
            for i in range(len(self.ann) - 1, -1, -1):
                if isinstance(self.ann[i], tuple) or self.ann[i] == 'nolink': del self.ann[i]; break
        elif tag == 'div' and self.table is None and not self.li_stack:
            self.cur = None
        elif tag == 'li' and self.li_stack:
            self.li_stack.pop()
            self.cur = self.li_stack[-1] if self.li_stack else None
        elif tag == 'ul' and self.lists:
            self.lists.pop(); self.cur = self.li_stack[-1] if self.li_stack else None
        elif tag == 'td': self.cell = None
        elif tag == 'tr': self.row = None
        elif tag == 'table': self.table = None

    def handle_data(self, data):
        if self.table is not None and self.cell is None:
            return  # 표 안의 줄바꿈 공백
        if self.cur is None and self.cell is None and not data.strip():
            return  # 태그 사이 줄바꿈
        self.text(data)


def rich(rt):
    """내부 조각 → 노션 rich_text (2000자 분할, 앞뒤 줄바꿈 정리)"""
    rt = [dict(r) for r in rt if r['t']]
    while rt and not rt[-1]['t'].rstrip('\n'): rt.pop()
    if rt: rt[-1]['t'] = rt[-1]['t'].rstrip('\n')
    while rt and not rt[0]['t'].lstrip('\n'): rt.pop(0)
    out = []
    for r in rt:
        t = r['t']
        for i in range(0, len(t), MAXTXT):
            o = {'type': 'text', 'text': {'content': t[i:i + MAXTXT]}}
            if r['link']: o['text']['link'] = {'url': r['link']}
            if any(r['a'].values()): o['annotations'] = r['a']
            out.append(o)
    return out


def plain(rt):
    return ''.join(r['t'] for r in rt).strip()


def to_notion(b, depth=0):
    """내부 블록 → 노션 블록 목록 (list 는 너무 깊으면 평평하게)"""
    if b['type'] == 'table':
        rows = [r for r in b['rows'] if r]
        if not rows: return []
        w = max(len(r) for r in rows)
        return [{'type': 'table', 'table': {'table_width': w, 'has_column_header': False, 'has_row_header': False,
                 'children': [{'type': 'table_row', 'table_row': {'cells': [rich(c) for c in r] + [[] for _ in range(w - len(r))]}}
                              for r in rows]}}]
    if b['type'] == 'image':
        return [{'type': 'image', '_src': b['src']}]
    typ = b['type']
    rt = rich(b['rt'])
    if len(rt) > 100:  # 노션 한도: 조각 100개 → 서식 버리고 글자만
        s = ''.join(r['text']['content'] for r in rt)
        rt = [{'type': 'text', 'text': {'content': s[i:i + MAXTXT]}} for i in range(0, len(s), MAXTXT)]
    if typ.startswith('heading') and not rt:
        typ = 'paragraph'
    nb = {'type': typ, typ: {'rich_text': rt}}
    kids = [k for c in b['children'] for k in to_notion(c, depth + 1)]
    if kids and depth < 1:
        nb[typ]['children'] = kids
        return [nb]
    return [nb] + kids


def convert(note):
    c = Conv(); c.feed(note['body']); c.close()
    out = [k for b in c.blocks for k in to_notion(b)]
    # 첫 제목이 페이지 제목과 같으면 빼기, 빈 줄 여러 개는 하나로, 앞뒤 빈 줄 제거
    def empty(b):
        return b['type'] == 'paragraph' and not b['paragraph']['rich_text']
    res = []
    for b in out:
        if empty(b) and (not res or empty(res[-1])): continue
        res.append(b)
    while res and empty(res[-1]): res.pop()
    title = note['title'].strip()
    first = next((i for i, b in enumerate(res) if b['type'].startswith('heading')), None)
    if first is not None and first <= 1:
        b = res[first]
        if ''.join(r['text']['content'] for r in b[b['type']]['rich_text']).strip() == title:
            del res[first]
            while res and empty(res[0]): res.pop(0)
    return res


# ---------- 노션 API ----------
def token():
    return open(TOKEN_FILE).read().strip()


def call(method, path, body=None, raw=None, ctype='application/json'):
    for attempt in range(6):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        req = urllib.request.Request(API + path, data=data, method=method, headers={
            'Authorization': 'Bearer ' + token(), 'Notion-Version': '2022-06-28', 'Content-Type': ctype})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                time.sleep(0.35)
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors='replace')
            if e.code in (429, 500, 502, 503, 504) and attempt < 5:
                time.sleep(float(e.headers.get('Retry-After', 2 ** attempt))); continue
            raise RuntimeError(f'{e.code} {path}: {msg}')


def upload_image(src):
    m = re.match(r'data:image/(\w+);base64,(.*)', src, re.S)
    if not m: return None
    ext, data = m.group(1), base64.b64decode(m.group(2))
    if ext != 'jpeg' and ext != 'png':  # HEIC 등 → JPEG
        with tempfile.TemporaryDirectory() as d:
            a, b = f'{d}/in.{ext}', f'{d}/out.jpg'
            open(a, 'wb').write(data)
            subprocess.run(['sips', '-s', 'format', 'jpeg', a, '--out', b], check=True, capture_output=True)
            data, ext = open(b, 'rb').read(), 'jpeg'
    name, mime = f'image.{"jpg" if ext == "jpeg" else ext}', f'image/{ext}'
    fu = call('POST', '/file_uploads', {'filename': name, 'content_type': mime})
    bd = uuid.uuid4().hex
    body = (f'--{bd}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\n'
            f'Content-Type: {mime}\r\n\r\n').encode() + data + f'\r\n--{bd}--\r\n'.encode()
    call('POST', f'/file_uploads/{fu["id"]}/send', raw=body, ctype=f'multipart/form-data; boundary={bd}')
    return fu['id']


def finalize(blocks):
    """이미지 업로드하고 노션에 보낼 형태로"""
    out = []
    for b in blocks:
        if b['type'] == 'image':
            fid = upload_image(b['_src'])
            if fid:
                out.append({'type': 'image', 'image': {'type': 'file_upload', 'file_upload': {'id': fid}}})
            else:
                out.append({'type': 'paragraph', 'paragraph': {'rich_text': [{'type': 'text', 'text': {'content': '[이미지 옮기지 못함]'}}]}})
        else:
            out.append(b)
    return out


def upload(note, parent):
    blocks = finalize(convert(note))
    page = call('POST', '/pages', {'parent': {'page_id': parent},
        'properties': {'title': {'title': [{'type': 'text', 'text': {'content': note['title'].strip()[:MAXTXT] or '제목 없음'}}]}},
        'children': blocks[:100]})
    for i in range(100, len(blocks), 100):
        call('PATCH', f'/blocks/{page["id"]}/children', {'children': blocks[i:i + 100]})
    return page['url']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry', action='store_true')
    ap.add_argument('--parent')
    ap.add_argument('--limit', type=int)
    a = ap.parse_args()
    notes = json.load(open(EXPORT))
    if a.dry:
        for n in notes:
            bl = convert(n)
            kinds = {}
            for b in bl: kinds[b['type']] = kinds.get(b['type'], 0) + 1
            print(f'{n["title"][:30]:32} {len(bl):4} {kinds}')
        return
    parent = re.sub(r'.*?([0-9a-f]{32})(\?.*)?$', r'\1', a.parent.replace('-', ''))
    prog = json.load(open(PROGRESS)) if os.path.exists(PROGRESS) else {}
    done = 0
    for n in notes:
        if n['id'] in prog: continue
        if a.limit is not None and done >= a.limit: break
        try:
            prog[n['id']] = upload(n, parent)
            print('완료', n['title'], prog[n['id']], flush=True)
        except Exception as e:
            print('실패', n['title'], e, flush=True)
        json.dump(prog, open(PROGRESS, 'w'), ensure_ascii=False, indent=1)
        done += 1
    print(f'올린 메모 {len(prog)} / {len(notes)}')


if __name__ == '__main__':
    main()
