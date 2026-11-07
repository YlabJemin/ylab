"""크롬(사용자 로그인 상태)에서 cc 전용 새 창을 열어 페이지 글을 읽는 도우미. 읽기만 함."""
import json, subprocess, sys, time
def osa(script):
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr.strip())
    return r.stdout.strip()
def new_window(url):
    return osa(f'''tell application "Google Chrome"
set w to make new window
set URL of active tab of w to "{url}"
return id of w
end tell''')
def add_tab(wid, url):
    return osa(f'''tell application "Google Chrome"
tell window id {wid} to make new tab with properties {{URL:"{url}"}}
end tell''')
def js(wid, idx, code):
    return osa(f'tell application "Google Chrome" to execute tab {idx} of window id {wid} javascript {json.dumps(code, ensure_ascii=False)}')
def wait(wid, idx, t=15):
    for _ in range(t*2):
        try:
            if js(wid, idx, "document.readyState") == "complete": return
        except Exception: pass
        time.sleep(0.5)
def text(wid, idx, n=6000):
    return js(wid, idx, "document.body.innerText")[:n]
def url(wid, idx):
    return osa(f'tell application "Google Chrome" to get URL of tab {idx} of window id {wid}')
if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "open":
        wid = new_window(sys.argv[2])
        for u in sys.argv[3:]: add_tab(wid, u)
        print(wid)
    elif cmd == "text":
        wid, idx = sys.argv[2], int(sys.argv[3]); wait(wid, idx)
        print("URL:", url(wid, idx)); print(text(wid, idx, int(sys.argv[4]) if len(sys.argv) > 4 else 6000))
    elif cmd == "js":
        print(js(sys.argv[2], int(sys.argv[3]), sys.argv[4]))
    elif cmd == "goto":
        osa(f'tell application "Google Chrome" to set URL of tab {int(sys.argv[3])} of window id {sys.argv[2]} to "{sys.argv[4]}"')
    elif cmd == "close":
        osa(f'tell application "Google Chrome" to close window id {sys.argv[2]}')
