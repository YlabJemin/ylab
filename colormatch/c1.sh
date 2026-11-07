#!/bin/zsh
# 캡쳐원 공용 함수: render <변형> <접미사> → 미리보기 파일 경로 출력
T=~/Desktop/cc/tools/colormatch
OUT="/Users/jeminyun/Desktop/캡쳐원 전용/cc/Output/cc 미리보기"
render() {  # 레시피 "cc preview"(1600px)로 뽑고 파일 생길 때까지 기다림
  local f="$OUT/$1$2.jpg"; rm -f "$f"
  osascript -e "tell application \"Capture One\"
    set d to document 1
    set output name format of recipe \"ccprev\" of d to \"[이미지 이름]$2\"
    process (first variant of d whose name is \"$1\") recipe \"ccprev\"
  end tell" >/dev/null
  for i in {1..60}; do [ -f "$f" ] && break; sleep 1; done; sleep 1.5; [ -f "$f" ] && echo "$f" || echo "렌더 실패" >&2
}
c1set() {  # c1set <변형> "applescript 문장들 (adjustments of v 기준)"
  osascript -e "tell application \"Capture One\"
    set v to first variant of document 1 whose name is \"$1\"
    tell adjustments of v
    $2
    end tell
  end tell"
}
c1get() { osascript -e "tell application \"Capture One\" to get $2 of adjustments of (first variant of document 1 whose name is \"$1\")"; }
