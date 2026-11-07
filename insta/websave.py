# 크롬에 띄운 웹페이지(인스타 말고)에서 지금 보고 있는 사진 한 장을 가장 큰 원본으로 바탕화면에 저장
#   - 사진 주소를 직접 연 탭: 그 사진
#   - 페이지 안(같은 사이트 iframe 포함): 화면에 보이는 사진 중 크게 보이는 것, 사진 보기 화면처럼 나란히 있으면 가운데 것
#   - 네이버(pstatic.net): 블로그에 올라간 원본(blogfiles, 크기 지정 없음) → 안 되면 type=w3840
#   - 그 밖: srcset 중 가장 큰 것
# 필요: 크롬 '보기 > 개발자 > Apple Events의 자바스크립트 허용'
# 사용법: python3 websave.py  → ~/Desktop/웹_<사이트>_<파일이름>.jpg (같은 이름 있으면 ' (2)' 붙임, 덮어쓰지 않음)
import json, subprocess, os, re, urllib.request, urllib.parse

JS = r'''(()=>{
if((document.contentType||"").startsWith("image/"))return JSON.stringify({page:location.href,src:location.href});
const docs=[document];for(const f of document.querySelectorAll("iframe")){try{if(f.contentDocument)docs.push(f.contentDocument)}catch(e){}}
let c=[];
for(const d of docs){const w=d.defaultView,vw=w.innerWidth,vh=w.innerHeight;
 for(const i of d.images){const r=i.getBoundingClientRect();if(i.naturalWidth<150||r.width<120||r.bottom<=0||r.top>=vh||r.right<=0||r.left>=vw)continue;
  const vis=(Math.min(r.right,vw)-Math.max(r.left,0))*(Math.min(r.bottom,vh)-Math.max(r.top,0));
  let best=i.currentSrc||i.src,bw=i.naturalWidth;
  for(const [u,s] of (i.srcset||"").split(",").map(x=>x.trim().split(" ")).filter(a=>a[0])){const n=parseInt(s||0);if(n>bw){bw=n;best=u}}
  c.push({src:new URL(best,d.baseURI).href,vis:vis,dc:Math.abs((r.left+r.right)/2-vw/2)+Math.abs((r.top+r.bottom)/2-vh/2)})}}
if(!c.length)return JSON.stringify({page:location.href,src:null});
const mx=Math.max(...c.map(x=>x.vis));const big=c.filter(x=>x.vis>=mx*0.6);big.sort((a,b)=>a.dc-b.dc);
return JSON.stringify({page:location.href,src:big[0].src})})()'''

r = subprocess.run(['osascript', '-e', 'tell application "Google Chrome" to execute active tab of front window javascript ' + json.dumps(JS, ensure_ascii=False)],
                   capture_output=True, text=True)
if r.returncode: raise SystemExit(r.stderr.strip())
d = json.loads(r.stdout)
if not d['src']: raise SystemExit('이 페이지에서 사진을 못 찾았어요')
page, src = d['page'], d['src']

cands = []
if 'pstatic.net' in src:                                   # 네이버: 원본 → 큰 크기
    base = src.split('?')[0]
    cands += [base.replace('postfiles.pstatic.net', 'blogfiles.pstatic.net'), base + '?type=w3840']
cands.append(src)

data = None
for u in cands:
    try:
        req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0', 'Referer': page})
        b = urllib.request.urlopen(req, timeout=30).read()
        if len(b) > 5000: data = b; break                   # 아주 작은 응답(오류용 썸네일)은 버림
    except Exception:
        continue
if not data: raise SystemExit('사진을 받지 못했어요: ' + src[:100])

site = re.sub(r'^www\.|^m\.', '', urllib.parse.urlparse(page).hostname or 'web').split('.')[0]
name = os.path.basename(urllib.parse.urlparse(src).path) or 'image'
name = re.sub(r'[^\w.가-힣-]', '_', urllib.parse.unquote(name))
stem, ext = os.path.splitext(name)
if not ext:
    ext = '.png' if data[:4] == b'\x89PNG' else '.webp' if data[8:12] == b'WEBP' else '.jpg'
dst = os.path.expanduser(f'~/Desktop/웹_{site}_{stem}{ext}')
k = 2
while os.path.exists(dst):
    dst = os.path.expanduser(f'~/Desktop/웹_{site}_{stem} ({k}){ext}'); k += 1
open(dst, 'wb').write(data)
w, h = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', dst], capture_output=True, text=True).stdout.split()[-3::2]
print(f'저장: {os.path.basename(dst)} ({w}×{h})')
print(f'Saved · {w}×{h}')
