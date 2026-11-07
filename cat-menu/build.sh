#!/bin/zsh
# yap 앱(스크립트 메뉴, 예전 ydot의 스크립트 부분 — 2026-11-05 앱 나누기) 빌드 → /Applications/yap.app → 로그인 시 자동 실행 등록
set -e
SRC="${0:A:h}"
APP="/Applications/yap.app"
OLD="/Applications/ydot.app"; [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$OLD/Contents/Info.plist" 2>/dev/null)" = "com.cc.scriptmenu" ] && { pkill -f cc-scriptmenu 2>/dev/null; rm -rf "$OLD"; }   # 예전 한 몸 ydot(이 앱의 옛 모습) 정리 → 새 ydot은 donut/build.sh

mkdir -p "$APP/Contents/MacOS"
# 유니버설(인텔+애플실리콘) · 최소 macOS 13 으로 컴파일 (배포용, 2026-11-04). 사용: swift_build <출력> <소스>
swift_build() { swiftc -O -target arm64-apple-macos13.0 "$2" -o "$1.arm64" && swiftc -O -target x86_64-apple-macos13.0 "$2" -o "$1.x86_64" && lipo -create "$1.arm64" "$1.x86_64" -output "$1" && rm -f "$1.arm64" "$1.x86_64"; }
swift_build "$APP/Contents/MacOS/cc-scriptmenu" "$SRC/main.swift"
VER=$(date +%Y%m%d.%H%M)
sed "s#<string>BUILDVER</string>#<string>$VER</string>#" "$SRC/Info.plist" > "$APP/Contents/Info.plist"   # CFBundleVersion = 빌드 시각 → ydot이 켤 때 도우미·스크립트 새로 설치할지 판단
mkdir -p "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$SRC/yap.icns" "$APP/Contents/Resources/yap.icns"   # 앱 아이콘 (검정 yap.)
# 도우미 프로그램 (스크립트들이 ~/Library/Application Support/cc/ 에서 씀. ydot이 켤 때 거기로 복사)
T="$HOME/Desktop/cc/tools"
for pair in "cctool:$SRC/cctool.swift" "rotate:$T/rotate/rotate.swift" "airdropsend:$T/airdrop/airdropsend.swift" "psexportui:$T/psexport/psexportui.swift" "exportui:$T/c1scripts/exportui.swift" "rawjpg:$T/c1scripts/rawjpg.swift" "sessionui:$T/c1scripts/sessionui.swift"; do
  name="${pair%%:*}"; src="${pair#*:}"
  if [ ! -f "$APP/Contents/Helpers/$name" ] || [ "$src" -nt "$APP/Contents/Helpers/$name" ]; then swift_build "$APP/Contents/Helpers/$name" "$src" 2>&1 | grep -E "error:" || true; fi
done
# 실행 파일이 아닌 스크립트는 Resources에 (Helpers에 두면 서명이 파일 속성에 붙어 압축·전송 때 사라짐 → "손상됨")
find "$APP/Contents/Helpers" -maxdepth 1 \( -name "*.jsx" -o -name "*.sh" \) -delete
rm -rf "$APP/Contents/Resources/helpers" "$APP/Contents/Resources/photoshop" "$APP/Contents/Resources/ydot.icns"; mkdir -p "$APP/Contents/Resources/helpers"
cp "$T/c1scripts/c1job.sh" "$T/psexport/export.jsx" "$T/psexport/info.jsx" "$APP/Contents/Resources/helpers/"
# 스크립트 (cc 스크립트는 .applescript 그대로, 캡쳐원 메뉴용은 .scpt로 컴파일)
rm -rf "$APP/Contents/Resources/scripts"; mkdir -p "$APP/Contents/Resources/scripts/ccscripts/Photoshop" "$APP/Contents/Resources/scripts/Capture One Scripts"
cp "$SRC/scripts/ccscripts/"*.applescript "$APP/Contents/Resources/scripts/ccscripts/"
cp "$SRC/scripts/ccscripts/Photoshop/"*.applescript "$APP/Contents/Resources/scripts/ccscripts/Photoshop/"
for f in "$SRC/scripts/Capture One Scripts/"*.applescript; do n="$(basename "$f" .applescript)"; [ "$n" = "Pick" ] && continue; osacompile -o "$APP/Contents/Resources/scripts/Capture One Scripts/$n.scpt" "$f"; done
cp "$SRC/com.cc.scriptmenu.plist" "$APP/Contents/Resources/com.cc.scriptmenu.plist"   # 설치 앱이 여기서 꺼내 자동 실행 등록
rm -rf "$APP/Contents/Helpers/Shift Convert.app"   # Shift Convert은 이제 ydot 앱 (2026-11-05)
codesign --force --deep --sign "cc-codesign" "$APP"   # 고정 인증서 → 다시 빌드해도 권한 유지 (~/Desktop/cc/signing)

cp "$SRC/com.cc.scriptmenu.plist" "$HOME/Library/LaunchAgents/com.cc.scriptmenu.plist"
launchctl bootout gui/$(id -u)/com.cc.scriptmenu 2>/dev/null || true; launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.cc.scriptmenu.plist" 2>/dev/null || true

pkill -f "cc-scriptmenu" 2>/dev/null || true; sleep 0.5
[ -n "$NO_OPEN" ] || open "$APP"
echo "설치 완료: $APP"
"$SRC/share.sh" >/dev/null && echo "배포 묶음 갱신: ~/Desktop/ylab/app/yap"
