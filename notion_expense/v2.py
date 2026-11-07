"""노션 API 2026-03-11 (보기 API) 호출 도우미."""
import json, os, time, urllib.request, urllib.error
TOKEN = open(os.path.expanduser("~/Desktop/cc/notion_token")).read().strip()
def req(method, path, data=None):
    for a in range(6):
        r = urllib.request.Request("https://api.notion.com/v1" + path, method=method,
            data=json.dumps(data).encode() if data is not None else None,
            headers={"Authorization": "Bearer " + TOKEN, "Notion-Version": "2026-03-11", "Content-Type": "application/json"})
        try:
            return json.load(urllib.request.urlopen(r, timeout=60))
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            if e.code in (429, 500, 502, 503) and a < 5:
                time.sleep(2 ** a); continue
            raise RuntimeError(f"{method} {path} → {e.code} {body}")
