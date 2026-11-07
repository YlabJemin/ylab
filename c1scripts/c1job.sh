#!/bin/zsh
# 셀렉 내보내기 뒷일 (백그라운드): 원본 변환 → 보정본 다 써질 때까지 기다림 → 카톡용 줄이기 → 진짜 끝나면 완료 알림
# 사용: c1job.sh <저장 폴더> <RAW 목록 파일|""> <보정본 장수> <처리 전 폴더 목록 파일|""> <카톡 0|1> <RAW 복사 장수>
#   원본: 이름_원본.jpg (있으면 _원본_1 …), rawjpg로 변환
#   보정본: 처리 전에 없던 JPG(_원본 제외)가 장수만큼 생기고, 크기가 안 바뀌고, JPG 끝 표시(FFD9)까지 써지면 끝난 것 (최대 1시간)
#   카톡용: 19.5MB 넘는 JPG만 sips로 품질 95→90→…→40 낮춰 다시 저장 (해상도 그대로)
# 시험할 땐 CCDIR로 rawjpg·exportui 위치를 바꿔 씀
setopt extendedglob
dest="$1"; list="$2"; editN="$3"; before="$4"; kakao="$5"; rawN="$6"
cc="${CCDIR:-$HOME/Library/Application Support/cc}"
cache="$HOME/Library/Caches/cc"; mkdir -p "$cache"
LIMIT=19500000
WAIT=${CC_WAIT:-3600}

shrink() {   # 카톡용: 넘을 때만 화질 낮춤
  local f="$1" q=95 tmp
  [ $(stat -f%z "$f") -le $LIMIT ] && return 0
  tmp=$(mktemp "$cache/kakao.XXXXXX"); rm -f "$tmp"; tmp="$tmp.jpg"   # 빈 임시 파일 안 남게
  while [ $q -ge 40 ]; do
    sips -s format jpeg -s formatOptions $q "$f" --out "$tmp" >/dev/null 2>&1 || break
    if [ $(stat -f%z "$tmp") -le $LIMIT ]; then mv -f "$tmp" "$f"; return 0; fi
    q=$((q-5))
  done
  [ -e "$tmp" ] && mv -f "$tmp" "$f"
}

parts=()
[ "$rawN" -gt 0 ] && parts+=("RAW $rawN")

# 1) 원본
if [ -n "$list" ]; then
  ok=0; bad=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    b="${f:t:r}"; t="$dest/${b}_원본.jpg"; i=1
    while [ -e "$t" ]; do t="$dest/${b}_원본_$i.jpg"; i=$((i+1)); done
    if "$cc/rawjpg" "$f" "$t"; then ok=$((ok+1)); [ "$kakao" = 1 ] && shrink "$t"; else bad=$((bad+1)); fi
  done < "$list"
  rm -f "$list"
  p="원본 $ok"; [ $bad -gt 0 ] && p="$p (실패 $bad)"; parts+=("$p")
fi

# 2) 보정본: 캡쳐원이 다 쓸 때까지
late=""
if [ "$editN" -gt 0 ]; then
  newfiles() {
    new=()
    for f in "$dest"/*.(#i)jpg(N); do
      b="${f:t}"
      [[ "$b" == *_원본.jpg || "$b" == *_원본_<->.jpg ]] && continue
      [ -n "$before" ] && grep -qxF -- "$b" "$before" && continue
      new+=("$f")
    done
  }
  complete() {   # 모두 크기 그대로 + JPG 끝 표시
    local s1 s2 f
    s1=$(stat -f%z "${new[@]}"); sleep 2; s2=$(stat -f%z "${new[@]}")
    [ "$s1" = "$s2" ] || return 1
    for f in "${new[@]}"; do [ "$(tail -c 2 "$f" | xxd -p)" = "ffd9" ] || return 1; done
  }
  end=$((SECONDS + WAIT))
  while :; do
    newfiles
    if [ ${#new} -ge "$editN" ] && complete; then break; fi
    if [ $SECONDS -ge $end ]; then late=1; break; fi
    sleep 3
  done
  [ -n "$before" ] && rm -f "$before"
  if [ "$kakao" = 1 ]; then for f in "${new[@]}"; do shrink "$f"; done; fi
  if [ -n "$late" ]; then parts+=("보정본 ${#new}/$editN"); else parts+=("보정본 ${#new}"); fi
fi

head="내보내기 완료"; [ -n "$late" ] && head="1시간 기다렸는데 보정본이 다 안 나왔어요"
msg="$head · ${(j: · :)parts}"
[ "$kakao" = 1 ] && msg="$msg (카톡용)"
"$cc/exportui" done "$msg" "$dest"
