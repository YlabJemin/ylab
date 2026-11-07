#!/bin/zsh
# 사용: iter.sh 단계이름 → 현재 크롭 읽고, 출력 재서, 눈을 (0.5,0.30)·눈거리 DT로 옮긴 새 크롭 적용 후 다시 출력·측정
DT=${DT:-0.1435}; G=${G:-1}
S=/private/tmp/claude-501/-Users-jeminyun/17d18a7c-2ed7-4e40-9de3-d67b0b879c0c/scratchpad/c1rot/$1; mkdir -p "$S"
names=(1017_유림님0285 1017_유림님0310 1017_유림님0374)
osascript -e "tell application \"Capture One\" to set root folder location of recipe \"ccfit2400\" of current document to (POSIX file \"$S\")" >/dev/null
for n in $names; do osascript -e "tell application \"Capture One\" to process (first variant of current document whose name is \"$n\") recipe \"ccfit2400\"" >/dev/null; done
for i in $(seq 1 40); do [ $(ls "$S" | grep -c jpg) -ge 3 ] && break; sleep 2; done; sleep 2
for n in $names; do
  m=($(~/Desktop/cc/tools/c1crop/face_angle "$S/$n.jpg" 2>/dev/null | awk '{print $2,$5,$6,$7}'))
  c=($(osascript -e "tell application \"Capture One\" to get crop of (first variant of current document whose name is \"$n\")" | tr -d ','))
  echo "$n 각도 ${m[1]} 눈 ${m[2]} ${m[3]} 거리 ${m[4]} 크롭 ${c[*]}"
  if [ -n "$APPLY" ]; then
    new=$(python3 -c "
cx,cy,cw,ch=$c[1],$c[2],$c[3],$c[4]; ex,ey,d=${m[2]},${m[3]},${m[4]}; G=$G
cw2=cw*d/$DT; ch2=ch*d/$DT
cx2=cx+G*(ex-0.5)*cw; cy2=cy-G*(ey-0.30)*ch
print(f'{{{cx2:.1f}, {cy2:.1f}, {cw2:.1f}, {ch2:.1f}}}')")
    osascript -e "tell application \"Capture One\" to set crop of (first variant of current document whose name is \"$n\") to $new" >/dev/null
    echo "   → $new"
  fi
done
