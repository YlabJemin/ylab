#!/usr/bin/env python3
"""노션 하위 페이지 → 토글 변환.

  python3 toggle.py scan                 # 조회만 (바꾸지 않음), 목록·문제 블록 보고
  python3 toggle.py backup               # 전체 블록 JSON + 파일을 backup/notion_toggle/에 저장
  python3 toggle.py convert <페이지ID>    # 하위 페이지 하나를 부모 안의 토글로 바꾸고 원본은 휴지통
  python3 toggle.py all                  # 변환 가능한 하위 페이지 전부 (안쪽부터)
"""
import json, os, subprocess, sys, time, urllib.request, urllib.error, mimetypes

CC = os.path.expanduser("~/Desktop/cc")
TOKEN = open(f"{CC}/notion_token").read().strip()
BACKUP = f"{CC}/backup/notion_toggle"
API = "https://api.notion.com/v1"
VER = "2022-06-28"

CANT_COPY = {"child_database", "unsupported", "template", "synced_block", "link_preview",
             "ai_block", "transcription", "meeting_notes", "tab"}


def req(method, path, data=None):
    url = path if path.startswith("http") else API + path
    for attempt in range(8):
        r = urllib.request.Request(url, method=method,
                                   data=json.dumps(data).encode() if data is not None else None,
                                   headers={"Authorization": "Bearer " + TOKEN, "Notion-Version": VER,
                                            "Content-Type": "application/json"})
        try:
            return json.load(urllib.request.urlopen(r, timeout=60))
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            if e.code in (429, 500, 502, 503, 504) and attempt < 7:
                time.sleep(float(e.headers.get("Retry-After") or 2 ** attempt))
                continue
            raise RuntimeError(f"{method} {path} → {e.code} {body}")
        except urllib.error.URLError:
            if attempt < 7:
                time.sleep(2 ** attempt)
                continue
            raise


def children(block_id):
    out, cur = [], None
    while True:
        d = req("GET", f"/blocks/{block_id}/children?page_size=100" + (f"&start_cursor={cur}" if cur else ""))
        out += d["results"]
        if not d["has_more"]:
            return out
        cur = d["next_cursor"]


def tree(block_id):
    """블록 목록 + 각 블록의 _children (child_page 안은 들어가지 않음)."""
    out = children(block_id)
    for b in out:
        if b["has_children"] and b["type"] not in ("child_page", "child_database"):
            b["_children"] = tree(b["id"])
    return out


def walk(blocks):
    for b in blocks:
        yield b
        yield from walk(b.get("_children", []))


def page_title(page):
    for v in page["properties"].values():
        if v["type"] == "title":
            return v["title"]
    return []


def plain(rt):
    return "".join(t["plain_text"] for t in rt)


def top_pages():
    pages, cur = [], None
    while True:
        b = {"page_size": 100, "filter": {"property": "object", "value": "page"}}
        if cur:
            b["start_cursor"] = cur
        d = req("POST", "/search", b)
        pages += d["results"]
        if not d["has_more"]:
            break
        cur = d["next_cursor"]
    return [p for p in pages if p["parent"]["type"] == "workspace" and not p.get("in_trash")]


# ---------- 조회 ----------

def collect(page_id, depth=0, path=""):
    """페이지 안의 모든 child_page를 (안쪽 먼저) 모은다."""
    blocks = tree(page_id)
    found = []
    for b in walk(blocks):
        if b["type"] == "child_page":
            sub_path = f"{path} > {b['child_page']['title']}"
            found += collect(b["id"], depth + 1, sub_path)
            found.append({"id": b["id"], "title": b["child_page"]["title"], "path": sub_path,
                          "parent_block": b["parent"], "depth": depth + 1})
    return found


def inspect(page_id):
    blocks = tree(page_id)
    types = {}
    problems, files, subpages = [], 0, []
    for b in walk(blocks):
        t = b["type"]
        types[t] = types.get(t, 0) + 1
        if t in ("child_page", "child_database"):
            subpages.append(t)
        elif t in CANT_COPY:
            problems.append(t)
        payload = b.get(t, {})
        if isinstance(payload, dict) and payload.get("type") == "file":
            files += 1
        if t == "callout" and (payload.get("icon") or {}).get("type") not in (None, "emoji", "external"):
            problems.append("callout 아이콘(" + payload["icon"]["type"] + ")")
    return blocks, sum(types.values()), problems, files, subpages


def cmd_scan():
    tops = top_pages()
    print(f"최상위 페이지 {len(tops)}개")
    total = 0
    for p in tops:
        name = plain(page_title(p)) or "(제목 없음)"
        subs = collect(p["id"], 0, name)
        print(f"\n■ {name}  (하위 페이지 {len(subs)}개)")
        for s in subs:
            _, n, probs, files, nested = inspect(s["id"])
            loc = "" if s["parent_block"]["type"] == "page_id" else f" [위치: {s['parent_block']['type']} 안]"
            note = []
            if nested:
                note.append(f"안에 하위 {len(nested)}개 → 먼저 변환")
            if probs:
                note.append("복사 못 함: " + ", ".join(sorted(set(probs))))
            if files:
                note.append(f"파일 {files}개 재업로드")
            print(f"  {'  ' * (s['depth'] - 1)}- {s['title'] or '(제목 없음)'}: 블록 {n}{loc}"
                  + (f"  ⚠ {' / '.join(note)}" if note else ""))
            total += 1
    print(f"\n하위 페이지 합계 {total}개")


# ---------- 백업 ----------

def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    urllib.request.urlretrieve(url, dest)


def cmd_backup():
    stamp = time.strftime("%Y%m%d_%H%M%S")
    root = f"{BACKUP}/{stamp}"
    os.makedirs(root, exist_ok=True)

    def dump(pid, name):
        page = req("GET", f"/pages/{pid}")
        blocks = tree(pid)
        safe = "".join(c if c not in '/:' else '_' for c in name)[:60] or "제목없음"
        with open(f"{root}/{safe}_{pid[:8]}.json", "w") as f:
            json.dump({"page": page, "blocks": blocks}, f, ensure_ascii=False, indent=1)
        for b in walk(blocks):
            pl = b.get(b["type"], {})
            if isinstance(pl, dict) and pl.get("type") == "file":
                fname = urllib.parse.unquote(pl["file"]["url"].split("?")[0].split("/")[-1])
                download(pl["file"]["url"], f"{root}/files/{b['id']}_{fname}")
            if b["type"] == "child_page":
                dump(b["id"], name + "__" + b["child_page"]["title"])

    for p in top_pages():
        dump(p["id"], plain(page_title(p)) or "제목없음")
    print("백업:", root)


# ---------- 변환 ----------

def clean_rt(rt):
    out = []
    for t in rt:
        item = {"type": t["type"], "annotations": t["annotations"]}
        if t["type"] == "mention" and t["mention"]["type"] in ("page", "database", "date", "user"):
            m = t["mention"]
            item["mention"] = {m["type"]: m[m["type"]]}
        elif t["type"] == "equation":
            item["equation"] = t["equation"]
        else:  # text, 그리고 링크 미리보기 등 다른 멘션은 링크 달린 글자로
            item = {"type": "text", "annotations": t["annotations"],
                    "text": {"content": t["plain_text"], "link": {"url": t["href"]} if t.get("href") else None}}
            if t["type"] == "text":
                item["text"]["link"] = t["text"].get("link")
        out.append(item)
    return out


def upload_file(url, name):
    tmp = f"/tmp/cc_notion_{int(time.time() * 1000)}_{name}"
    download(url, tmp)
    ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
    fu = req("POST", "/file_uploads", {"filename": name, "content_type": ctype})
    r = subprocess.run(["curl", "-s", "-X", "POST", fu["upload_url"],
                        "-H", "Authorization: Bearer " + TOKEN, "-H", "Notion-Version: " + VER,
                        "-F", f"file=@{tmp};type={ctype}"], capture_output=True, text=True)
    os.remove(tmp)
    res = json.loads(r.stdout)
    if res.get("status") != "uploaded":
        raise RuntimeError("파일 업로드 실패: " + r.stdout)
    return fu["id"]


def build(b, skipped):
    """원본 블록 → 새로 만들 블록(자식 없이). 복사 못 하면 안내 문단."""
    t = b["type"]
    if t in CANT_COPY or t == "child_page":
        skipped.append(t)
        return {"type": "paragraph", "paragraph": {"rich_text": [
            {"type": "text", "text": {"content": f"[복사 못 한 블록: {t}]"}}]}}
    pl = {k: v for k, v in json.loads(json.dumps(b[t])).items() if v is not None}
    for k in ("rich_text", "caption"):
        if k in pl:
            pl[k] = clean_rt(pl[k])
    if t == "table_row":
        pl["cells"] = [clean_rt(c) for c in pl["cells"]]
    if pl.get("type") == "file":
        name = urllib.parse.unquote(pl["file"]["url"].split("?")[0].split("/")[-1])
        pl.pop("file")
        pl["type"] = "file_upload"
        pl["file_upload"] = {"id": upload_file(b[t]["file"]["url"], name)}
    if t == "callout":
        icon = pl.get("icon")
        if icon and icon["type"] not in ("emoji", "external"):
            pl.pop("icon")
    if t == "link_to_page" and pl.get("type") == "database_id":
        pass
    return {"type": t, t: pl}


def new_only(res, after, n):
    """응답에서 새로 만든 블록만 (응답이 부모 전체를 줄 때도 대비)."""
    ids = [r["id"] for r in res]
    if after is None:  # 끝에 붙인 경우: 마지막 n개
        return res[-n:]
    if after in ids:
        i = ids.index(after)
        return res[i + 1: i + 1 + n]
    return res[:n]  # after 뒤부터 오는 경우


def create(parent_id, src, skipped, after=None):
    """src 블록들을 parent_id 안에 복사 (끝에 추가, after 있으면 그 뒤에). 만든 블록 수 반환."""
    made = 0
    for i in range(0, len(src), 100):
        chunk = src[i:i + 100]
        payload = []
        for b in chunk:
            nb = build(b, skipped)
            if b["type"] == "table":
                nb["table"]["children"] = [build(r, skipped) for r in b.get("_children", [])]
            elif b["type"] == "column_list":
                nb["column_list"]["children"] = [
                    {"type": "column", "column": {"children": [build(x, skipped) for x in col.get("_children", [])]}}
                    for col in b.get("_children", [])]
            payload.append(nb)
        body = {"children": payload}
        if after:
            body["after"] = after
        res = req("PATCH", f"/blocks/{parent_id}/children", body)["results"]
        res = new_only(res, after, len(chunk))
        after = res[-1]["id"] if after else None
        for b, nb in zip(chunk, res):
            made += 1
            kids = b.get("_children", [])
            if b["type"] == "table":
                made += len(kids)
            elif b["type"] == "column_list":
                cols = children(nb["id"])
                for col_src, col_new in zip(kids, cols):
                    made += 1
                    new_kids = children(col_new["id"])
                    for x_src, x_new in zip(col_src.get("_children", []), new_kids):
                        made += 1
                        if x_src.get("_children") and x_src["type"] not in CANT_COPY:
                            made += create(x_new["id"], x_src["_children"], skipped)
            elif kids and b["type"] not in CANT_COPY:
                made += create(nb["id"], kids, skipped)
    return made


def count(blocks):
    return sum(1 for _ in walk(blocks))


def convert(page_id):
    page = req("GET", f"/pages/{page_id}")
    blk = req("GET", f"/blocks/{page_id}")
    parent = blk["parent"]
    parent_id = parent.get("block_id") or parent.get("page_id")
    if not parent_id:
        raise RuntimeError("부모가 페이지/블록이 아님: " + json.dumps(parent))
    src = tree(page_id)
    if any(b["type"] in ("child_page", "child_database") for b in walk(src)):
        print("  건너뜀 (안에 하위 페이지/데이터베이스가 남아 있음):", plain(page_title(page)))
        return False
    title = clean_rt(page_title(page))
    icon = page.get("icon")
    if icon and icon["type"] == "emoji":
        title = [{"type": "text", "text": {"content": icon["emoji"] + " "}}] + title
    if not title:
        title = [{"type": "text", "text": {"content": "(제목 없음)"}}]
    res = req("PATCH", f"/blocks/{parent_id}/children",
              {"children": [{"type": "toggle", "toggle": {"rich_text": title}}], "after": page_id})["results"]
    toggle_id = new_only(res, page_id, 1)[0]["id"]
    skipped = []
    create(toggle_id, src, skipped)
    got = count(tree(toggle_id))
    want = count(src)
    print(f"  {plain(page_title(page)) or '(제목 없음)'}: 원본 블록 {want} → 토글 안 {got}"
          + (f", 복사 못 함 {skipped}" if skipped else ""))
    if got != want:
        print("  ⚠ 블록 수가 달라서 원본을 남겨둠. 토글:", toggle_id)
        return False
    req("PATCH", f"/pages/{page_id}", {"archived": True})
    return True


def cmd_all():
    for p in top_pages():
        name = plain(page_title(p)) or "(제목 없음)"
        subs = collect(p["id"], 0, name)
        if subs:
            print("■", name)
        for s in subs:  # collect가 안쪽 먼저 모으므로 순서대로 하면 됨
            convert(s["id"])


if __name__ == "__main__":
    import urllib.parse
    cmd = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if cmd == "scan":
        cmd_scan()
    elif cmd == "backup":
        cmd_backup()
    elif cmd == "convert":
        convert(sys.argv[2])
    elif cmd == "all":
        cmd_all()
