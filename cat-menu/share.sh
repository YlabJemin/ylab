#!/bin/zsh
# yap 배포 묶음 갱신 → ~/Desktop/ylab/app/yap/ (Install yap · Uninstall yap · README) + 밖에 yap.dmg  (2026-11-05 앱 나누기)
set -e
SRC="${0:A:h}"
OUT=~/Desktop/ylab/app/yap
mkdir -p "$OUT"
rm -rf "$OUT/Install yap.app" "$OUT/Install yap.scptd"
fix_applet() { local a="$1/Contents/MacOS/applet"; [ -f "$a" ] || return 0; rm -f "$1/Contents/Resources/Assets.car"; /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$1/Contents/Info.plist" 2>/dev/null;  # 기본 아이콘 묶음이 applet.icns를 가려서 지움
  vtool -set-build-version macos 13.0 "$(sw_vers -productVersion | cut -d. -f1).0" -replace -output "$a.new" "$a" 2>/dev/null && mv "$a.new" "$a" && chmod +x "$a"; codesign --force --deep -s "cc-codesign" "$1" 2>/dev/null || true; }
osacompile -o "$OUT/Install yap.app" "$SRC/installer.applescript"
PAY="$OUT/Install yap.app/Contents/Resources/payload"; mkdir -p "$PAY"; ditto /Applications/yap.app "$PAY/yap.app"
cp "$SRC/yap.icns" "$OUT/Install yap.app/Contents/Resources/applet.icns"; touch "$OUT/Install yap.app"
fix_applet "$OUT/Install yap.app"
VER=$(date +%Y-%m-%d)
cat > "$OUT/README.txt" <<TXT
yap 설치 안내  (묶음 날짜: $VER)

yap: 메뉴 막대 검정 yap. 아이콘의 스크립트 모음 — AirDrop · Rotate Photo · Save Instagram Photos(⌘⇧6) · Photoshop Export · 캡쳐원 New Session · Delete Session · Export.
(쉬프트 변환 메뉴·증명사진 인화는 'ydot' 앱이에요. 따로 설치해요)

■ 처음 설치
 1. 'Install yap'를 두 번 클릭합니다.
    → "확인할 수 없어 열 수 없습니다" 창이 뜨면 '완료'를 누르고,
      시스템 설정 › 개인정보 보호 및 보안 › 아래로 내려 "그래도 열기" › 열기.  (처음 한 번만)
 2. 끝. 메뉴 막대 오른쪽 위에 검정 yap. 아이콘이 생깁니다. 권한을 묻는 창이 뜨면 '허용'을 누릅니다.

■ 내 스크립트 넣기
 • yap 메뉴 › Open Scripts Folder → 캡쳐원 스크립트 폴더가 열려요. 여기에 넣은 스크립트가 메뉴에 나와요.

■ 지우기
 • 'Uninstall yap'를 두 번 클릭 → 지울 목록을 보여 주고, '제거'를 누르면 휴지통으로 옮깁니다.
 • 전부 한 번에 지우려면 ylab 폴더의 'Uninstall ylab'.

■ 문제가 생기면
 • 'Install yap'가 안 열림: 시스템 설정 › 개인정보 보호 및 보안 › 아래쪽 "그래도 열기".
 • yap. 아이콘이 안 보임: 응용 프로그램 › yap을 한 번 열기.
TXT
echo "갱신: $OUT"
~/Desktop/cc/tools/uninstall/build.sh
~/Desktop/cc/tools/ylab/dmg.sh
