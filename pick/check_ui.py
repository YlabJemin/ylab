# 빌드 때 ui/index.html 스크립트 문법 검사 (JavaScriptCore). 오류면 빌드 실패로 알림
import re, subprocess, os, sys, tempfile
h = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui/index.html"), encoding="utf-8").read()
bad = False
for m in re.finditer(r"<script>(.*?)</script>", h, re.S):
    line = h[:m.start()].count("\n") + 1
    p = tempfile.mktemp(suffix=".js"); open(p, "w", encoding="utf-8").write(m.group(1))
    r = subprocess.run(["osascript", "-l", "JavaScript", "-e", f"ObjC.import('Foundation'); var s=$.NSString.stringWithContentsOfFileEncodingError('{p}',4,null).js; var o='ok'; try{{ new Function(s) }}catch(e){{ o='ERR '+e }} o"], capture_output=True, text=True)
    os.unlink(p)
    if r.stdout.strip() != "ok": bad = True; print(f"화면 코드 문법 오류 (index.html {line}줄부터 스크립트): {r.stdout.strip() or r.stderr.strip()[:200]}")
sys.exit(1 if bad else 0)
