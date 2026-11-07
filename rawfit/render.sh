#!/bin/zsh
# 사용법: render.sh 목록파일 출력폴더 [긴변픽셀(0이면 480x320)]
T=${0:A:h}; mkdir -p "$2"
sed -e "s|LISTFILE|\"$1\"|" -e "s|OUTDIR|\"$2\"|" -e "s|LONGEDGE|${3:-0}|" $T/render_tpl.jsx > "$2/_run.jsx"
osascript -e "set js to read (POSIX file \"$2/_run.jsx\") as «class utf8»" -e "with timeout of 3000 seconds" -e "tell application \"Adobe Photoshop 2026\" to do javascript js" -e "end timeout"
