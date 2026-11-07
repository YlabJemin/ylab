# 고양이 메뉴 "포토샵 내보내기" 실행부: 포토샵 정보 읽기 → 창(psexportui) → 내보내기(export.jsx)
# 마지막 줄을 고양이 앱이 읽음: "toast:문구" / "error:문구" / 빈 줄(취소)
import json, os, re, subprocess, sys, tempfile, time
HERE = os.path.dirname(os.path.abspath(__file__))
UI = os.path.expanduser("~/Library/Application Support/cc/psexportui")
TEST_DEST = os.environ.get("PSX_TEST_DEST")      # 시험용: 창 없이 이 폴더로
TEST_SEL = os.environ.get("PSX_TEST_SEL")        # 시험용: 창 대신 이 JSON 선택값

def ps(js):
    # 기본 2분 제한이 있으면 사진이 많을 때 끝나기 전에 끊김 → 2시간까지 기다림
    r = subprocess.run(["osascript", "-e", "with timeout of 7200 seconds",
                        "-e", 'tell application id "com.adobe.Photoshop" to do javascript ' + json.dumps(js, ensure_ascii=False),
                        "-e", "end timeout"], capture_output=True, text=True)
    if r.returncode: raise SystemExit("error:" + r.stderr.strip())
    return r.stdout.strip()

running = subprocess.run(["osascript", "-e", 'application id "com.adobe.Photoshop" is running'], capture_output=True, text=True).stdout.strip()
if running != "true": print("toast:포토샵이 켜져 있지 않아요"); sys.exit()
info = json.loads(ps(open(os.path.join(HERE, "info.jsx")).read()))
if not info["docs"]: print("toast:열린 문서가 없어요"); sys.exit()

if TEST_SEL:
    sel = json.loads(TEST_SEL)
else:
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False); json.dump(info, f, ensure_ascii=False); f.close()
    r = subprocess.run([UI, f.name], capture_output=True, text=True); os.unlink(f.name)
    if r.returncode != 0 or not r.stdout.strip(): print(""); sys.exit()
    sel = json.loads(r.stdout.strip().splitlines()[-1])

dest = TEST_DEST or (os.path.join(sel["path"], sel["folder"]) if sel["folder"] else sel["path"])
os.makedirs(dest, exist_ok=True)
before = set(os.listdir(dest))
clean = lambda s: re.sub(r'[/:\\]', '_', s).strip() or "레이어"
jobs, total = [], 0
for d in info["docs"]:
    if d["i"] not in sel["docs"]: continue
    want = {}                                          # 레이어 번호 → 이름 뒤 붙일 말 (먼저 정한 것 우선)
    if sel["current"] and d["active"] >= 0: want.setdefault(d["active"], "_최종")
    if sel["original"] and d["layers"]: want.setdefault(len(d["layers"]) - 1, "_원본")
    for k, n in enumerate(d["layers"]):
        if n in sel["pick"]: want.setdefault(k, "_" + clean(n))
    if want:
        jobs.append({"i": d["i"], "layers": [{"k": k, "suffix": s} for k, s in sorted(want.items())]}); total += len(want)
if not jobs: print("toast:내보낼 레이어가 없어요"); sys.exit()
spec = {"dest": dest, "jobs": jobs, "limit": 19500000 if sel.get("kakao") else 0}   # 카톡용: 19.5MB 안으로
out = ps("var SPEC=" + json.dumps(spec, ensure_ascii=False) + ";\n" + open(os.path.join(HERE, "export.jsx")).read())
n, _, errs = out.partition("|")

# 진짜 끝났는지 확인: 새로 생긴 JPG 크기가 더 안 바뀔 때까지 (최대 2분)
def sizes():
    return {f: os.path.getsize(os.path.join(dest, f)) for f in os.listdir(dest) if f not in before and f.lower().endswith(".jpg")}
last, t0 = sizes(), time.time()
while time.time() - t0 < 120:
    time.sleep(1); cur = sizes()
    if cur == last and all(v > 0 for v in cur.values()): break
    last = cur
if errs: print("error:" + n + "개 저장, 실패: " + errs); sys.exit()

print(f"toast:내보내기 완료 · {n}장")
