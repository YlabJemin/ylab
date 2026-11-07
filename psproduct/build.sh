#!/bin/zsh
# ydot 포토샵 스크립트 만들기: 공통 부분을 붙여 build/ 에 "ydot_guide.jsx" · "ydot_print.jsx" (프로그램이 쓰는 파일 이름은 영어만, 2026-11-05) (ydot 빌드가 Helpers로 가져감)
set -e
SRC=~/Desktop/cc/tools/psproduct; mkdir -p "$SRC/build"
rm -f "$SRC/build/"*.jsx
for pair in "guide.jsx:ydot_guide.jsx" "print.jsx:ydot_print.jsx"; do
  s="${pair%%:*}"; d="${pair#*:}"
  python3 - "$SRC/$s" "$SRC/common.jsxinc" "$SRC/build/$d" <<'PY'
import sys; s=open(sys.argv[1],encoding='utf-8').read(); c=open(sys.argv[2],encoding='utf-8').read()
open(sys.argv[3],'w',encoding='utf-8').write('﻿'+s.replace('//@include-common', c))
PY
done
ls "$SRC/build"
