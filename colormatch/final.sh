#!/bin/zsh
# final.sh <변형> <스타일(cc-ref1|cc-ref2)> [접미사] : 배경 WB → 스타일 → 얼굴(볼) 기준 노출 L 87
source ~/Desktop/cc/tools/colormatch/c1.sh
V="$1"; ST="$2"; SUF=${3:-_$ST}
echo "■ $V ← $ST"
[ -z "$SKIPWB" ] && { c1set "$V" "set exposure to 0.8" >/dev/null; $T/wb.sh "$V" 0.04,0.14,0.14,0.26 0.86,0.14,0.96,0.26 | tail -1; }
$T/apply.sh "$V" "$ST"
$T/expo.sh "$V" "$SUF" 87
