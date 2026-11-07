#!/bin/bash
# Finder Settings.app → ~/Desktop/ylab/Finder Settings (유니버설, 최소 macOS 13, cc-codesign). 영어 이름 2026-11-05
set -e; S="$(cd "$(dirname "$0")" && pwd)"; O="$HOME/Desktop/ylab/Finder Settings"; A="$O/Finder Settings.app"
[ -d "$O" ] || { [ -d "$HOME/Desktop/ylab/Finder 설정" ] && mv "$HOME/Desktop/ylab/Finder 설정" "$O"; }   # 예전 이름에서 옮김
mkdir -p "$O"; rm -rf "$A" "$O/Finder 설정.app" "$O/읽어보기.txt"
osacompile -o "$A" "$S/app.applescript"
python3 "$S/make_fragment.py" "$A/Contents/Resources/finder.plist" >/dev/null
cp "$S/apply.sh" "$A/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 13.0" "$A/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$A/Contents/Info.plist"
M="$A/Contents/MacOS/applet"; vtool -set-build-version macos 13.0 "$(sw_vers -productVersion | cut -d. -f1).0" -replace -output "$M.new" "$M" && mv "$M.new" "$M" && chmod +x "$M"
T="$(mktemp -d)"; I="$T/y.iconset"; mkdir -p "$I"; for s in 16 32 128 256; do sips -z $s $s "$S/../cat-menu/yfolder.png" --out "$I/icon_${s}x${s}.png" >/dev/null; sips -z $((s*2)) $((s*2)) "$S/../cat-menu/yfolder.png" --out "$I/icon_${s}x${s}@2x.png" >/dev/null; done; iconutil -c icns "$I" -o "$A/Contents/Resources/applet.icns"; rm -rf "$T"; rm -f "$A/Contents/Resources/Assets.car"; /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$A/Contents/Info.plist" 2>/dev/null; touch "$A"   # ylab 폴더 아이콘 (Assets.car가 가려서 지움)
codesign --force --deep -s "cc-codesign" "$A"
cat > "$O/README.txt" <<'TXT'
Finder Settings

1. 'Finder Settings.app'을 두 번 클릭 → '적용'.
   → "확인할 수 없어 열 수 없습니다" 창이 뜨면 '완료'를 누르고,
     시스템 설정 › 개인정보 보호 및 보안 › 아래로 내려 "그래도 열기" › 열기.  (처음 한 번만)
2. Finder 창이 잠깐 닫혔다 다시 열리면 끝.

바뀌는 것: 새 창 = 데스크탑, 폴더는 새 창으로 열기, 경로 막대·상태 막대 보이기, 이름순일 때 폴더를 위로,
           검색 범위 = 현재 폴더, 아이콘 보기 크기·간격, 목록 보기 정렬, 도구 막대 버튼, 열기·저장 창 목록 정렬.
안 바뀌는 것: 사이드바, 창 위치·크기, 최근 기록, iCloud.
원래 설정은 처음 적용할 때 ~/Library/Application Support/ylab/Finder 원래 설정.plist 로 백업됩니다.
TXT
echo "만듦: $A"
