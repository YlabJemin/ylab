#!/bin/zsh
# ydot 배포 묶음 갱신 → ~/Desktop/ylab/app/ydot/ (Install ydot · Uninstall ydot · README) + 밖에 ydot.dmg  (2026-11-05 앱 나누기: ydot = Shift Convert)
set -e
SRC="${0:A:h}"
OUT=~/Desktop/ylab/app/ydot
mkdir -p "$OUT"
rm -rf "$OUT/Install ydot.app" "$OUT/Install ydot.scptd" "$OUT/ydot 설치.app" "$OUT/ydot 제거.app" "$OUT/읽어보기.txt" "$OUT/수동 설치"
fix_applet() { local a="$1/Contents/MacOS/applet"; [ -f "$a" ] || return 0; rm -f "$1/Contents/Resources/Assets.car"; /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$1/Contents/Info.plist" 2>/dev/null;  # 기본 아이콘 묶음이 applet.icns를 가려서 지움
  vtool -set-build-version macos 13.0 "$(sw_vers -productVersion | cut -d. -f1).0" -replace -output "$a.new" "$a" 2>/dev/null && mv "$a.new" "$a" && chmod +x "$a"; codesign --force --deep -s "cc-codesign" "$1" 2>/dev/null || true; }
osacompile -o "$OUT/Install ydot.app" "$SRC/installer.applescript"
PAY="$OUT/Install ydot.app/Contents/Resources/payload"; mkdir -p "$PAY"; ditto /Applications/ydot.app "$PAY/ydot.app"
cp "$SRC/res/ydot.icns" "$OUT/Install ydot.app/Contents/Resources/applet.icns"; touch "$OUT/Install ydot.app"
fix_applet "$OUT/Install ydot.app"
VER=$(date +%Y-%m-%d)
cat > "$OUT/README.txt" <<TXT
ydot 설치 안내  (묶음 날짜: $VER)

ydot: 사진을 집은 채 쉬프트를 누르면 변환 메뉴(도넛)가 펼쳐져요. 증명사진(Product)·Custom 인화, 포토샵 가이드·인화 스크립트.
(AirDrop·인스타 저장·캡쳐원 스크립트 메뉴는 'yap' 앱이에요. 따로 설치해요)

■ 처음 설치
 1. 'Install ydot'를 두 번 클릭합니다.
    → "확인할 수 없어 열 수 없습니다" 창이 뜨면 '완료'를 누르고,
      시스템 설정 › 개인정보 보호 및 보안 › 아래로 내려 "그래도 열기" › 열기.  (처음 한 번만)
    (예전 맥(macOS 14 이하)은 'Install ydot'를 마우스 오른쪽 클릭 → 열기 → 열기로도 됩니다)
 2. 끝. 메뉴 막대 오른쪽 위에 y. 아이콘이 생깁니다. 권한을 묻는 창이 뜨면 '허용'을 누릅니다.

■ 포토샵 스크립트 (ydot_guide · ydot_print)
 • 'Install ydot' 중에 맥 암호를 한 번 묻습니다. 입력하면 포토샵 스크립트 메뉴에 들어갑니다 (포토샵이 꺼져 있어도 돼요).
 • 포토샵이 켜져 있었다면 한 번 껐다 켜면 파일 › 스크립트에 'ydot_guide', 'ydot_print'가 나타납니다.
 • 포토샵을 ydot보다 나중에 깔았으면 'Install ydot'를 한 번 더 실행하세요.

■ 지우기
 • 'Uninstall ydot'를 두 번 클릭 → 지울 목록을 보여 주고, '제거'를 누르면 휴지통으로 옮깁니다.
 • 전부 한 번에 지우려면 ylab 폴더의 'Uninstall ylab'.

■ 문제가 생기면
 • 'Install ydot'가 안 열림: 시스템 설정 › 개인정보 보호 및 보안 › 아래쪽 "그래도 열기".
 • y. 아이콘이 안 보임: 응용 프로그램 › ydot을 한 번 열기.
TXT
echo "갱신: $OUT"
~/Desktop/cc/tools/uninstall/build.sh
~/Desktop/cc/tools/ylab/dmg.sh
