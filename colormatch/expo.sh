#!/bin/zsh
# expo.sh <변형> <접미사> <목표 볼 L> : 얼굴 자동 인식 → 볼 피부 밝기가 목표가 되게 노출 반복 조정
source ~/Desktop/cc/tools/colormatch/c1.sh
V="$1"; S="$2"; TL="$3"
f=$(render "$V" "$S"); CH=(${=$($T/face "$f" 2>/dev/null)}); CH=(${CH[1]} ${CH[2]})
[ "${CH[1]}" = "NOFACE" ] && { echo "  얼굴 못 찾음"; exit 1; }
for it in 1 2 3 4 5; do
  L=$($T/measure m "$f" "${CH[@]}" | awk 'NR>1{L+=$7;n++} END{printf "%.2f", L/n}')
  e=$(c1get "$V" exposure); echo "  노출 $e → 볼 L $L"
  (( ${$(( L - TL ))#-} < 0.6 )) && break
  c1set "$V" "set exposure to $(( e + (TL - L) / 11.0 ))" >/dev/null
  f=$(render "$V" "$S")
done
