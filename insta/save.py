# 크롬에 띄운 인스타 게시물 사진을 인스타에 있는 가장 큰 원본 그대로(다시 압축 안 함) 바탕화면에 저장
# 여러 장 게시물: '다음'을 차례로 눌러 모든 장을 받고, 끝나면 원래 보던 장으로 되돌아감
#   (인스타는 첫 장만 1440px까지 있고 나머지 장은 보통 1080px이 가장 큼)
# 필요: 크롬 '보기 > 개발자 > Apple Events의 자바스크립트 허용'
# 사용법: python3 save.py [--one] [--again] [--check]   (--one: 지금 보이는 장만)  → ~/Desktop/인스타_<계정>_<게시물ID>[_번호].jpg  (같은 이름 있으면 덮지 않고 건너뜀)
import json, subprocess, os, re, sys, time, urllib.request
ONE = '--one' in sys.argv
AGAIN = '--again' in sys.argv      # 이미 받은 게시물 다시 받기: 기존 파일은 그대로 두고 ' (2)' 붙여 새로 저장
CHECK = '--check' in sys.argv      # 이 게시물을 이미 받았는지만 확인 (받은 파일 수 출력)

# 지금 보이는 장 1개의 가장 큰 주소 + 다음 버튼 유무
CUR = r'''(()=>{const d=document.querySelector("div[role=dialog]")||document.querySelector("main")||document;
let vis=[...d.querySelectorAll("img")].filter(i=>{const r=i.getBoundingClientRect();return i.naturalWidth>300&&r.width>200&&r.left>=-5&&r.right<=innerWidth+5&&r.bottom>0&&r.top<innerHeight});
const row=vis.filter(i=>Math.abs(i.getBoundingClientRect().top-vis[0].getBoundingClientRect().top)<5&&Math.abs(i.getBoundingClientRect().width-vis[0].getBoundingClientRect().width)<5);
if(row.length>1)vis=[row.sort((a,b)=>a.getBoundingClientRect().left-b.getBoundingClientRect().left)[0]];
const k=vis.length?(vis[0].src.match(/\/(\d+_\d+_\d+)_n\./)||[])[1]:null;
let best=null;
if(k)for(const i of document.querySelectorAll("img")){if(!i.src.includes(k))continue;
 for(const [u,w] of (i.srcset||"").split(",").map(x=>x.trim().split(" ")).filter(a=>a[0])){const n=parseInt(w||0);if(!best||n>best.w)best={w:n,u:u}}
 if(!best||i.naturalWidth>best.w)best={w:i.naturalWidth,u:i.src}}
const user=(document.querySelector("header a[href^='/'][role=link] span, header h2")||{}).textContent||"";
const nx=!!d.querySelector("button[aria-label='다음'],button[aria-label='Next']");
return JSON.stringify({url:location.href,user:user,key:k,img:best,next:nx})})()'''
NEXT = r'''(()=>{const d=document.querySelector("div[role=dialog]")||document;const b=d.querySelector("button[aria-label='다음'],button[aria-label='Next']");if(b){b.click();return "ok"}return "none"})()'''
PREV = r'''(()=>{const d=document.querySelector("div[role=dialog]")||document;const b=d.querySelector("button[aria-label='돌아가기'],button[aria-label='이전'],button[aria-label='Go back'],button[aria-label='Previous']");if(b){b.click();return "ok"}return "none"})()'''


def js(code):
    r = subprocess.run(['osascript', '-e', 'tell application "Google Chrome" to execute active tab of front window javascript ' + json.dumps(code, ensure_ascii=False)],
                       capture_output=True, text=True)
    if r.returncode: raise SystemExit(r.stderr.strip())
    return r.stdout.strip()


first = json.loads(js(CUR))
if not re.search(r'/(p|reel)/', first['url']): raise SystemExit('인스타 게시물을 열어 둔 상태에서 실행해 주세요')
if not first['img']: raise SystemExit('사진을 못 찾음: ' + first['url'])
pid = (re.search(r'/(?:p|reel)/([^/?]+)', first['url']) or [None, 'post'])[1]
user = re.sub(r'[^\w.가-힣-]', '', first.get('user') or '') or 'insta'
if CHECK:
    import glob
    print(len(glob.glob(os.path.expanduser(f'~/Desktop/인스타_*_{pid}*.jpg')))); sys.exit(0)

# 여러 장이면 처음 장으로 되감은 뒤 끝까지 넘기며 모음
imgs, moved, idx = [], 0, None
if ONE:                                                   # 지금 장만: 여러 장 게시물이면 몇 번째 장인지 이름에 붙임
    imgs = [first['img']]
    m = re.search(r'img_index=(\d+)', first['url'])
    if m or first['next']: idx = int(m.group(1)) if m else 1
elif first['next'] or 'img_index=' in first['url']:
    for _ in range(30):
        if js(PREV) != 'ok': break
        moved -= 1; time.sleep(0.6)
    seen = set()
    for _ in range(30):
        time.sleep(0.6)
        c = json.loads(js(CUR))
        if c['key'] and c['key'] not in seen: seen.add(c['key']); imgs.append(c['img'])
        if not c['next']: break
        js(NEXT); moved += 1
    for _ in range(moved): js(PREV); time.sleep(0.3)   # 원래 보던 장으로
else:
    imgs = [first['img']]

saved = 0
for n, x in enumerate(imgs, 1):
    num = idx if idx else (n if len(imgs) > 1 else None)
    dst = os.path.expanduser(f'~/Desktop/인스타_{user}_{pid}' + (f'_{num}' if num else '') + '.jpg')
    if os.path.exists(dst):
        if not AGAIN: print('이미 있음(건너뜀):', os.path.basename(dst)); continue
        k = 2
        while os.path.exists(dst[:-4] + f' ({k}).jpg'): k += 1
        dst = dst[:-4] + f' ({k}).jpg'
    req = urllib.request.Request(x['u'], headers={'User-Agent': 'Mozilla/5.0'})
    open(dst, 'wb').write(urllib.request.urlopen(req).read())
    w, h = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', dst], capture_output=True, text=True).stdout.split()[-3::2]
    print(f'저장: {os.path.basename(dst)} ({w}×{h})'); saved += 1
print(f'Saved · {saved} photo' + ('s' if saved > 1 else '') if saved else 'Already saved')
