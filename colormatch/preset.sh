#!/bin/zsh
# preset.sh <변형> <프리셋번호 1|2> [노출목표L]
# 배경 WB → 프리셋 값(p<n>.txt, 컬러에디터 p<n>_ce.txt) → 스킨톤 스타일(SKIN_STYLE 있으면) → 배경 L 목표로 노출
source ~/Desktop/cc/tools/colormatch/c1.sh
V="$1"; N="$2"; TL=${3:-$([ $N = 1 ] && echo 87 || echo 87)}
BG=(0.04,0.14,0.14,0.26 0.86,0.14,0.96,0.26)
echo "■ $V → 프리셋 $N (볼 목표 L $TL)"
c1set "$V" "set color balance highlight saturation to 0
set color balance shadow saturation to 0
set color balance midtone saturation to 0
set level target shadow rgb to 0
set level target highlight rgb to 255
set exposure to 0.8" >/dev/null
[ -z "$SKIPWB" ] && $T/wb.sh "$V" "${BG[@]}" | tail -1
[ -n "$SKIN_STYLE" ] && $T/apply.sh "$V" "$SKIN_STYLE"
c1set "$V" "$(cat $T/p$N.txt)" >/dev/null
while read nm h s l; do osascript -e "tell application \"Capture One\"
set v to first variant of current document whose name is \"$V\"
tell (first basic color correction of color editor settings of adjustments of v whose name is \"$nm\")
set hue change to $h
set saturation change to $s
set lightness change to $l
end tell
end tell"; done < $T/p${N}_ce.txt
$T/expo.sh "$V" "_p$N" "$TL"
