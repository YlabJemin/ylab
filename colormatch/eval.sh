#!/bin/zsh
# eval.sh <이미지...> : 배경 / 볼(얼굴 인식) / 입술 / 검정·흰색 / 그림자 틴트 요약
T=~/Desktop/cc/tools/colormatch
for f in "$@"; do
  P=(${=$($T/face "$f" 2>/dev/null)})
  out=$($T/measure m "$f" 0.04,0.14,0.14,0.26 0.86,0.14,0.96,0.26 ${P[1]} ${P[2]} ${P[3]})
  bg=$(echo "$out" | sed -n 2,3p | awk '{L+=$7;a+=$8;b+=$9} END{printf "배경 L%.1f a%.1f b%.1f", L/2,a/2,b/2}')
  ck=$(echo "$out" | sed -n 4,5p | awk '{L+=$7;C+=$11;h+=$13} END{printf "볼 L%.1f C%.1f h%.0f", L/2,C/2,h/2}')
  lp=$(echo "$out" | sed -n 6p | awk '{printf "입술 C%.0f", $11}')
  st=$($T/measure stats "$f" | awk 'NR==2{split($3,a,"=");split($13,b,"="); printf "검정%.0f 흰%.0f", a[2], b[2]} /L10~ 20|L20~ 30/{sa+=$5;sb+=$7;n++} END{printf " 그림자 a%.1f b%.1f", sa/n, sb/n}')
  printf "%-26s %s | %s | %s | %s\n" "$(basename "$f" .jpg | sed 's/_045A[0-9]*//')" "$bg" "$ck" "$lp" "$st"
done
