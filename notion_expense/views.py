"""지출 표 보기 설정 (API 2026-03-11)."""
import json
from v2 import req

st = json.load(open("state.json"))
PID = st["prop_ids"]
SHOW = [("항목", 150), ("결제수단", 90), ("금액 보기", 135), ("금액", 110), ("결제일", 80),
        ("시작", 105), ("종료", 105), ("회차", 80), ("메모", 260)]
HIDE = ["남은 금액", "전체 회차", "월 합계", "합계 대상", "순서", "정렬"]
TOP = ["고정비", "할부", "정기결제", "월 합계"]
BOTTOM = ["연간", "카드실적", "생활"]


def config():
    props = []
    for n, w in SHOW:
        p = {"property_id": PID[n], "visible": True, "width": w, "wrap": n in ("항목", "금액 보기", "메모")}
        if n in ("시작", "종료"):
            p["date_format"] = "year_month_day"
        props.append(p)
    props += [{"property_id": PID[n], "visible": False} for n in HIDE]
    return {"type": "table", "properties": props, "wrap_cells": True, "show_vertical_lines": True,
            "group_by": {"type": "select", "property_id": PID["분류"], "sort": {"type": "manual"},
                         "hide_empty_groups": True}}


def body(name, groups):
    return {"name": name, "type": "table", "configuration": config(),
            "sorts": [{"property": "정렬", "direction": "ascending"}],
            "filter": {"property": "분류", "select": {"equals": groups}}}
