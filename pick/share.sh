#!/bin/zsh
# 배포 묶음 갱신 → ~/Desktop/ylab/Pick/  (Pick만. ydot·Shift 파일변환은 tools/cat-menu/share.sh)
set -e
SRC=~/Desktop/cc/tools/pick
OUT=~/Desktop/ylab/app/Pick   # 예비용 폴더 (사용자 2026-11-05: 밖에는 Pick.dmg)
[ -d "$OUT" ] || { mkdir -p ~/Desktop/ylab/app; [ -d ~/Desktop/ylab/Pick ] && mv ~/Desktop/ylab/Pick "$OUT"; mkdir -p "$OUT"; }   # 예전 위치에서 옮김
rm -rf "$OUT/Pick 설치.app" "$OUT/Pick 제거.app" "$OUT/읽어보기.txt"   # 예전 한글 이름 정리
mkdir -p "$OUT"
rm -rf "$OUT/Pick.app" "$OUT/Pick.scpt" "$OUT/Install Pick.app" "$OUT/Install Pick.scptd"   # 예전 묶음 흔적 정리 (지금은 설치 앱 하나에 다 들어 있음)
# osacompile 로 만든 앱은 최소 macOS가 이 맥 버전(27)으로 박혀 예전 맥에서 안 열림 → 13.0으로 낮추고 서명 (2026-11-04)
fix_applet() { local a="$1/Contents/MacOS/applet"; [ -f "$a" ] || return 0; rm -f "$1/Contents/Resources/Assets.car"; /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$1/Contents/Info.plist" 2>/dev/null;  # 기본 아이콘 묶음(Assets.car)이 applet.icns를 가려서 지움 (2026-11-05)
  vtool -set-build-version macos 13.0 "$(sw_vers -productVersion | cut -d. -f1).0" -replace -output "$a.new" "$a" 2>/dev/null && mv "$a.new" "$a" && chmod +x "$a"; codesign --force --deep -s "cc-codesign" "$1" 2>/dev/null || true; }
osacompile -o "$OUT/Install Pick.app" "$SRC/installer.applescript"
PAY="$OUT/Install Pick.app/Contents/Resources/payload"; mkdir -p "$PAY"
ditto /Applications/Pick.app "$PAY/Pick.app"; osacompile -o "$PAY/Pick.scpt" "$SRC/Pick.applescript"
[ -f "$SRC/Pick.icns" ] && cp "$SRC/Pick.icns" "$OUT/Install Pick.app/Contents/Resources/applet.icns" && touch "$OUT/Install Pick.app"   # 설치 앱도 픽 아이콘으로
fix_applet "$OUT/Install Pick.app"
rm -rf "$OUT/수동 설치"   # 수동 설치는 없앰 (사용자 2026-11-05: 설치 앱 안에 같은 앱이 있음)
VER=$(date +%Y-%m-%d)
cat > "$OUT/README.txt" <<TXT
Pick 설치 안내  (묶음 날짜: $VER)

■ 처음 설치
 1. 이 Pick 폴더를 통째로 새 맥에 옮깁니다 (AirDrop · USB · 압축 파일 모두 됩니다).
 2. 'Install Pick'를 두 번 클릭합니다.
    → "확인할 수 없어 열 수 없습니다" 창이 뜨면 '완료'를 누르고,
      시스템 설정 › 개인정보 보호 및 보안 › 아래로 내려 "그래도 열기" › 열기.  (처음 한 번만)
    (예전 맥(macOS 14 이하)은 'Install Pick'를 마우스 오른쪽 클릭 → 열기 → 열기로도 됩니다)
 3. 끝. Pick이 켜지면서 권한을 묻는 창이 뜨면 전부 '허용'을 누릅니다.
    (캡쳐원 제어 · 데스크톱 폴더 접근, 두 가지)

■ 지우기
 • 'Uninstall Pick'를 두 번 클릭 → 지울 목록을 보여 주고, '제거'를 누르면 휴지통으로 옮깁니다.
 • 데스크톱 '세션' 폴더와 사진은 지우지 않습니다.
 • Pick · ydot · yinsta를 한 번에 지우려면 ylab 폴더의 'Uninstall ylab'.

■ 문제가 생기면
 • 'Install Pick'가 안 열림: 시스템 설정 › 개인정보 보호 및 보안 › 아래쪽 "그래도 열기"가 보이는지 확인 (두 번 클릭해서 경고를 한 번 띄운 뒤에 나타납니다).
 • 캡쳐원 스크립트 메뉴에 Pick이 없음: 캡쳐원을 껐다 켜기.
 • 세션이 안 열림: 캡쳐원이 켜져 있는지 확인.
TXT
echo "갱신: $OUT"
~/Desktop/cc/tools/uninstall/build.sh   # 제거 앱 (Pick·ydot·yinsta 각자 + ylab 전체)
~/Desktop/cc/tools/ylab/dmg.sh   # 앱별 dmg (늘 최신)
