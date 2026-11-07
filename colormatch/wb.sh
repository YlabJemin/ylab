#!/bin/zsh
# 배경으로 화이트밸런스 잡기: wb.sh <변형> <배경영역1> [배경영역2 ...]
# 배경 평균 a·b가 0에 가까워질 때까지 틴트·색온도 반복 조정 (스포이드와 같은 효과)
source ~/Desktop/cc/tools/colormatch/c1.sh
V="$1"; shift
for it in 1 2 3 4 5 6; do
  f=$(render "$V" "_wb")
  read a b L <<< $($T/measure m "$f" "$@" | awk 'NR>1{L+=$7;a+=$8;b+=$9;n++} END{printf "%.2f %.2f %.1f", a/n, b/n, L/n}')
  temp=$(c1get "$V" temperature); tint=$(c1get "$V" tint)
  echo "  [$it] 색온도 $temp 틴트 $tint → 배경 L $L a $a b $b"
  if (( ${a#-} < 0.35 && ${b#-} < 0.35 )); then break; fi
  nt=$(( tint - a * 0.9 )); nk=$(( temp - b * 70 ))
  c1set "$V" "set tint to $nt
  set temperature to $nk" >/dev/null
done
