#!/bin/zsh
# 예진룩 적용: look.sh <변형> [배경영역1 배경영역2 ...]
# 1) 공통값  2) 배경으로 WB  3) 컬러밸런스  4) 스킨톤 스타일 + 빨강 채도  5) 배경 L 94가 되게 노출
source ~/Desktop/cc/tools/colormatch/c1.sh
V="$1"; shift
BG=("$@"); [ ${#BG} -eq 0 ] && BG=(0.04,0.14,0.14,0.26 0.86,0.14,0.96,0.26)
SKIN_STYLE=${SKIN_STYLE:-cc-look}; TARGET_L=${TARGET_L:-94}
echo "■ $V"
c1set "$V" "set exposure to 0.8
set contrast to -5
set highlight recovery to 10
set shadow recovery to 15
set color balance highlight saturation to 0" >/dev/null
$T/wb.sh "$V" "${BG[@]}" | tail -1
c1set "$V" "set color balance highlight hue to 220
set color balance highlight saturation to 0.08" >/dev/null
$T/apply.sh "$V" "$SKIN_STYLE"
osascript -e "tell application \"Capture One\"
set v to first variant of current document whose name is \"$V\"
set saturation change of (first basic color correction of color editor settings of adjustments of v whose name is \"red\") to 12
end tell"
for it in 1 2 3 4; do
  f=$(render "$V" "_look")
  L=$($T/measure m "$f" "${BG[@]}" | awk 'NR>1{L+=$7;n++} END{printf "%.2f", L/n}')
  e=$(c1get "$V" exposure)
  echo "  노출 $e → 배경 L $L"
  (( ${$(( L - TARGET_L ))#-} < 0.7 )) && break
  c1set "$V" "set exposure to $(( e + (TARGET_L - L) / 9.0 ))" >/dev/null
done
