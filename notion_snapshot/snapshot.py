#!/usr/bin/env python3
"""노션 블록(토글 등) 내용을 노션 비슷한 모양의 PNG 한 장으로 저장 (노션은 읽기만 함).

  python3 snapshot.py <블록ID> <저장할 png 경로>
"""
import html, os, re, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.expanduser("~/Desktop/cc/tools/notion_toggle"))
import toggle

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH = 900
TXT = {"gray": "#787774", "brown": "#9F6B53", "orange": "#D9730D", "yellow": "#CB912F", "green": "#448361",
       "blue": "#337EA9", "purple": "#9065B0", "pink": "#C14C8A", "red": "#D44C47"}
BG = {"gray": "#F1F1EF", "brown": "#F4EEEE", "orange": "#FBECDD", "yellow": "#FBF3DB", "green": "#EDF3EC",
      "blue": "#E7F3F8", "purple": "#F6F3F9", "pink": "#FAF1F5", "red": "#FDEBEC"}


def color_css(c):
    if not c or c == "default":
        return ""
    if c.endswith("_background"):
        return f"background:{BG.get(c[:-11], '')};border-radius:3px;padding:0 2px;"
    return f"color:{TXT.get(c, '')};"


def rich(rt):
    out = []
    for a in rt:
        s = html.escape(a["plain_text"]).replace("\n", "<br>")
        an = a["annotations"]
        st = color_css(an["color"])
        if an["bold"]: st += "font-weight:600;"
        if an["italic"]: st += "font-style:italic;"
        if an["strikethrough"]: st += "text-decoration:line-through;"
        if an["underline"]: st += "text-decoration:underline;"
        if an["code"]: st += "font-family:Menlo,monospace;background:#F1F1EF;color:#EB5757;padding:0 3px;border-radius:3px;"
        if a.get("href"): s = f'<a href="{html.escape(a["href"])}">{s}</a>'
        out.append(f'<span style="{st}">{s}</span>' if st else s)
    return "".join(out)


def render(blocks):
    out, num = [], 0
    for b in blocks:
        t = b["type"]; d = b.get(t, {})
        num = num + 1 if t == "numbered_list_item" else 0
        kids = render(toggle.children(b["id"])) if b.get("has_children") else ""
        body = rich(d.get("rich_text", []))
        blk = color_css(d.get("color"))
        if t == "heading_1": out.append(f'<h1 style="{blk}">{body}</h1>{kids}')
        elif t == "heading_2": out.append(f'<h2 style="{blk}">{body}</h2>{kids}')
        elif t == "heading_3": out.append(f'<h3 style="{blk}">{body}</h3>{kids}')
        elif t == "divider": out.append('<hr>')
        elif t == "bulleted_list_item": out.append(f'<div class="li" style="{blk}"><span class="m">•</span><div>{body}{kids}</div></div>')
        elif t == "numbered_list_item": out.append(f'<div class="li" style="{blk}"><span class="m n">{num}.</span><div>{body}{kids}</div></div>')
        elif t == "toggle": out.append(f'<div class="li"><span class="m">▾</span><div>{body}{kids}</div></div>')
        elif t == "to_do": out.append(f'<div class="li"><span class="m">{"☑" if d.get("checked") else "☐"}</span><div>{body}{kids}</div></div>')
        elif t == "bookmark": out.append(f'<p><a href="{html.escape(d.get("url",""))}">{html.escape(d.get("url",""))}</a></p>')
        else: out.append(f'<p style="{blk}">{body or "&nbsp;"}</p>{kids}')
    return "".join(out)


def page(title, inner):
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
body{{margin:0;background:#fff;color:#37352F;font:16px/1.6 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif;-webkit-font-smoothing:antialiased}}
#w{{width:{WIDTH - 96}px;padding:40px 48px 48px}}
.top{{font-size:20px;font-weight:600;margin-bottom:6px}} .top .m{{color:#9B9A97;margin-right:8px}}
.in{{padding-left:28px}}
h1{{font-size:30px;font-weight:700;margin:28px 0 2px;line-height:1.3}} h2{{font-size:23px;font-weight:600;margin:4px 0 8px;line-height:1.3}}
h3{{font-size:19px;font-weight:600;margin:16px 0 4px}}
p{{margin:2px 0}} hr{{border:0;border-top:1px solid #E9E9E7;margin:22px 0 4px}}
.li{{display:flex;margin:3px 0}} .li>.m{{flex:0 0 24px;text-align:left}} .li>.n{{flex-basis:26px}} .li>div{{flex:1;min-width:0;word-break:break-all}}
a{{color:inherit;text-decoration:underline;text-decoration-color:#C7C6C4}}
</style></head><body><div id="w"><div class="top"><span class="m">▾</span>{html.escape(title)}</div><div class="in">{inner}</div></div>
<script>document.title='H'+document.getElementById('w').getBoundingClientRect().height</script></body></html>"""


def main(bid, png):
    b = toggle.req("GET", f"/blocks/{bid}")
    title = "".join(a["plain_text"] for a in b[b["type"]].get("rich_text", []))
    doc = page(title, render(toggle.children(bid)))
    tmp = tempfile.mkdtemp()
    f = os.path.join(tmp, "p.html"); open(f, "w").write(doc)
    common = ["--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={tmp}/prof"]
    dom = subprocess.run([CHROME, *common, f"--window-size={WIDTH},2000", "--dump-dom", "file://" + f],
                         capture_output=True, text=True, timeout=120).stdout
    h = int(float(re.search(r"<title>H([\d.]+)</title>", dom).group(1))) + 4
    subprocess.run([CHROME, *common, f"--window-size={WIDTH},{h}", "--force-device-scale-factor=2",
                    f"--screenshot={png}", "file://" + f], capture_output=True, timeout=120)
    shutil.rmtree(tmp, ignore_errors=True)   # Chrome 임시 폴더 정리
    print(png, f"{WIDTH}x{h} (x2)")
    return doc


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
