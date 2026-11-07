#!/usr/bin/env python3
"""노션 재정 페이지 맨 아래에 '지출' 토글 + 지출 표(새 데이터베이스) 만들기.

  python3 expense.py apply     # 토글·표·줄 만들기 (state.json 있으면 멈춤 — 중복 방지)
  python3 expense.py check     # 만든 표 다시 읽어서 합계·회차·수식 결과 확인 (읽기만)
  python3 expense.py fix       # 수식만 다시 설정 (state.json의 표 대상)

기존 '현재 지출 목록' 안 표는 건드리지 않음.
"""
import json, os, sys

sys.path.insert(0, os.path.expanduser("~/Desktop/cc/tools/notion_toggle"))
from toggle import req  # noqa: E402

PAGE = "3e794c72-9eb3-8084-aa7b-f332e081d2e5"  # 재정
STATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "state.json")

# ---- 수식 (노션 수식 2.0) ----
K = '((year(now()) - year(prop("시작"))) * 12 + month(now()) - month(prop("시작")) + 1)'


def won(x):
    """숫자 → "₩1,234,567" (노션 정규식이 앞보기(?=)를 지원 안 해서 계산으로 쉼표)."""
    p3 = lambda v: f'(if({v} < 10, "00", if({v} < 100, "0", "")) + format({v}))'
    return ('lets(n, round(' + x + '), '
            'm, floor(n / 1000000), t, floor(n / 1000) % 1000, u, n % 1000, '
            '"₩" + if(n >= 1000000, format(m) + "," + ' + p3('t') + ' + "," + ' + p3('u') + ', '
            'if(n >= 1000, format(floor(n / 1000)) + "," + ' + p3('u') + ', format(n))))')


F_ROUND = f'if(empty(prop("전체 회차")) or empty(prop("시작")), "", format({K}) + "/" + format(prop("전체 회차")))'
F_LEFT = f'if(prop("분류") == "할부", prop("금액") * (prop("전체 회차") - {K} + 1), 0)'
_TOTAL = ('prop("합계 대상").filter(current.prop("분류") == "고정비" or current.prop("분류") == "할부"'
          ' or current.prop("분류") == "정기결제").map(current.prop("금액")).sum()')
_AMT = won('prop("금액")')
_LEFT = won('prop("남은 금액")')
F_VIEW = (
    f'if(prop("분류") == "월 합계", style({won(_TOTAL)}, "b"), '
    f'if(format(prop("금액")) == "", "—", '
    f'if(prop("분류") == "할부", '
    f'{_AMT} + "\\n" + style({_LEFT}, "gray")'
    f' + "\\n" + style(format(prop("전체 회차") - {K} + 1) + "회 남음", "gray"), '
    f'{_AMT})))'
)

GROUPS = [("고정비", "gray"), ("할부", "orange"), ("정기결제", "blue"), ("월 합계", "default"),
          ("연간", "brown"), ("카드실적", "green"), ("생활", "purple")]
PAYS = [("계좌이체", "gray"), ("삼성카드", "red"), ("신한카드", "blue"), ("국민체크", "yellow")]

# (분류, 항목, 결제수단, 금액, 결제일, 시작, 종료, 전체회차, 메모, 취소줄)
ROWS = [
    ("고정비", "월세 (프로렌스)", "계좌이체", 1360000, "", "2026-06-01", "2027-07-01", None, "", False),
    ("고정비", "공과금", "계좌이체", 140000, "", "", "", None, "전기 7만 · 가스 3만 · 수도 2만 · 여유분 2만", False),
    ("할부", "삼성 TV", "삼성카드", 195800, "", "2026-06-01", "2027-06-01", 12, "", False),
    ("할부", "쿠쿠 음처기", "삼성카드", 33200, "", "2026-08-01", "2027-08-01", 12, "", False),
    ("할부", "허먼밀러", "삼성카드", 153700, "", "2026-06-01", "2027-08-01", 14, "", False),
    ("할부", "이엘", "삼성카드", 584800, "", "2026-09-01", "2027-09-01", 12, "", False),
    ("정기결제", "KT 요금", "", None, "", "", "", None, "₩60,000 · 가족이 냄 · VVIP · 유튜브 프리미엄 · 밀리의 서재", True),
    ("정기결제", "어도비", "", 13200, "23일", "", "", None, "", False),
    ("정기결제", "코웨이 정수기", "신한카드", 10910, "14일", "2026-07-01", "2029-06-01", 36,
     "36개월 약정 · 34,910 − 제휴카드 11,000 − 실적 30만 13,000 (할인 약정 내내) · 2027.07부터 44,910 → 20,910원", False),
    ("정기결제", "스포티파이", "", 0, "22일", "", "", None, "12/21까지 0원 · 체크카드로 바꾸면 5,000원 할인", False),
    ("연간", "신한카드 연회비", "신한카드", 30000, "매년 6/19", "2026-06-19", "", None, "2026.06.19 개설", False),
    ("연간", "삼성카드 연회비", "삼성카드", 49000, "매년 5/28", "2024-05-28", "", None, "2024.05.28 개설", False),
    ("카드실적", "신한카드", "신한카드", 300000, "", "", "", None, "30만 이상 → 정수기 13,000원 할인", False),
    ("카드실적", "국민체크카드", "국민체크", 200000, "", "", "", None, "", False),
    ("생활", "탈모약", "", 80000, "", "", "", None, "", False),
    ("생활", "담배", "", None, "", "", "", None, "", False),
    ("생활", "정신과 진료 & 약", "", None, "", "", "", None, "", False),
    ("생활", "커피", "", None, "", "", "", None, "", False),
]


def text(s, **ann):
    return [{"type": "text", "text": {"content": s}, "annotations": ann}] if s else []


def row_props(r, total_id):
    g, name, pay, amt, day, start, end, n, memo, strike = r
    p = {
        "항목": {"title": text(name, bold=True, strikethrough=strike)},
        "분류": {"select": {"name": g}},
        "금액": {"number": amt},
        "결제일": {"rich_text": text(day)},
        "메모": {"rich_text": text(memo)},
        "월 합계": {"relation": [{"id": total_id}]},
    }
    if pay:
        p["결제수단"] = {"select": {"name": pay}}
    if start:
        p["시작"] = {"date": {"start": start}}
    if end:
        p["종료"] = {"date": {"start": end}}
    if n:
        p["전체 회차"] = {"number": n}
    return p


def set_formulas(db):
    req("PATCH", f"/databases/{db}", {"properties": {
        "회차": {"formula": {"expression": F_ROUND}},
        "남은 금액": {"formula": {"expression": F_LEFT}},
        "금액 보기": {"formula": {"expression": F_VIEW}},
    }})


def apply():
    if os.path.exists(STATE):
        sys.exit(f"이미 만든 기록이 있음: {STATE} (중복 방지로 멈춤)")
    st = {}
    tg = req("PATCH", f"/blocks/{PAGE}/children", {"children": [
        {"object": "block", "type": "toggle", "toggle": {"rich_text": text("지출")}}]})
    st["toggle"] = tg["results"][0]["id"]
    json.dump(st, open(STATE, "w"), indent=1)
    db = req("POST", "/databases", {
        "parent": {"type": "page_id", "page_id": PAGE}, "is_inline": True,
        "title": text("지출"),
        "properties": {
            "항목": {"title": {}},
            "분류": {"select": {"options": [{"name": n, "color": c} for n, c in GROUPS]}},
            "결제수단": {"select": {"options": [{"name": n, "color": c} for n, c in PAYS]}},
            "금액": {"number": {"format": "won"}},
            "결제일": {"rich_text": {}},
            "시작": {"date": {}},
            "종료": {"date": {}},
            "전체 회차": {"number": {"format": "number"}},
            "메모": {"rich_text": {}},
        }})
    st["db"] = db["id"]
    json.dump(st, open(STATE, "w"), indent=1)
    req("PATCH", f"/databases/{st['db']}", {"properties": {"월 합계": {"relation": {
        "database_id": st["db"], "type": "dual_property",
        "dual_property": {"synced_property_name": "합계 대상"}}}}})
    set_formulas(st["db"])
    tot = req("POST", "/pages", {"parent": {"database_id": st["db"]}, "properties": {
        "항목": {"title": text("월 합계", bold=True)},
        "분류": {"select": {"name": "월 합계"}},
        "메모": {"rich_text": text("고정비 + 할부 + 정기결제 (자동 계산)")}}})
    st["total_row"] = tot["id"]
    st["rows"] = []
    for r in ROWS:
        st["rows"].append(req("POST", "/pages", {"parent": {"database_id": st["db"]},
                                                 "properties": row_props(r, tot["id"])})["id"])
        json.dump(st, open(STATE, "w"), indent=1)
    print("완료:", json.dumps(st, indent=1))


def check():
    st = json.load(open(STATE))
    db = req("GET", f"/databases/{st['db']}")
    print("표:", "".join(t["plain_text"] for t in db["title"]), "| 속성:", ", ".join(db["properties"]))
    rows = req("POST", f"/databases/{st['db']}/query", {"page_size": 100})["results"]
    sums = {}
    for r in rows:
        p = r["properties"]
        g = (p["분류"]["select"] or {}).get("name")
        amt = p["금액"]["number"]
        sums[g] = sums.get(g, 0) + (amt or 0)
        f = lambda k: (p[k]["formula"].get(p[k]["formula"]["type"]) if k in p else None)
        name = "".join(t["plain_text"] for t in p["항목"]["title"])
        print(f"{g:5} {name:14} 금액={amt} 회차={f('회차')!r} 남은={f('남은 금액')!r} 보기={f('금액 보기')!r}")
    print("분류별 합계:", sums, "| 줄 수:", len(rows))


if __name__ == "__main__":
    {"apply": apply, "check": check, "fix": lambda: set_formulas(json.load(open(STATE))["db"])}[sys.argv[1]]()
