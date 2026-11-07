#!/bin/zsh
# ydot 앱 빌드 (2026-11-05 앱 나누기: Shift Convert = ydot) → /Applications/ydot.app → 로그인 시 자동 실행 → 배포 묶음  (소스: Donut.swift)
set -e
SRC=~/Desktop/cc/tools/donut
APP="/Applications/ydot.app"
T="$HOME/Desktop/cc/tools"
pkill -x Donut 2>/dev/null || true
for i in {1..50}; do pgrep -x Donut >/dev/null || break; sleep 0.1; done   # 예전 ydot이 완전히 꺼질 때까지 (안 그러면 마지막 open이 꺼지는 앱으로 가서 안 켜질 때가 있음, 2026-11-05)
if [ -d "$APP" ] && [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null)" != "com.cc.donut" ]; then rm -rf "$APP"; fi   # 예전 ydot(스크립트 메뉴 = 이제 yap)이면 지움
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/MacOS"
# 유니버설(인텔+애플실리콘) · 최소 macOS 13 으로 컴파일 (배포용, 2026-11-04). 사용: swift_build <출력> <소스>
swift_build() { swiftc -O -target arm64-apple-macos13.0 "$2" -o "$1.arm64" && swiftc -O -target x86_64-apple-macos13.0 "$2" -o "$1.x86_64" && lipo -create "$1.arm64" "$1.x86_64" -output "$1" && rm -f "$1.arm64" "$1.x86_64"; }
swift_build "$APP/Contents/MacOS/Donut" "$SRC/Donut.swift"
swift_build "$APP/Contents/MacOS/airdropsend" "$T/airdrop/airdropsend.swift"   # 도넛 AirDrop 칸용 (yap 없이도)
cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.cc.donut</string>
  <key>CFBundleName</key><string>ydot</string>
  <key>CFBundleDisplayName</key><string>ydot</string>
  <key>CFBundleIconFile</key><string>ydot</string>
  <key>CFBundleExecutable</key><string>Donut</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>CFBundleLocalizations</key><array><string>ko</string></array>
  <key>CFBundleAllowMixedLocalizations</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>도넛을 연 파인더 창의 폴더를 찾고, 변환 파일을 데스크톱의 그 자리에 놓고, Custom 인화지를 포토샵 새 문서로 열기 위해 필요해요.</string>
  <key>NSDesktopFolderUsageDescription</key><string>데스크톱의 사진을 읽고 변환 파일을 저장하기 위해 필요해요.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>문서 폴더의 사진을 읽고 변환 파일을 저장하기 위해 필요해요.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>다운로드 폴더의 사진을 읽고 변환 파일을 저장하기 위해 필요해요.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>외장 디스크의 사진을 읽고 변환 파일을 저장하기 위해 필요해요.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>네트워크 드라이브의 사진을 읽고 변환 파일을 저장하기 위해 필요해요.</string>
</dict></plist>
PL
rm -rf "$APP/Contents/Resources" "$APP/Contents/Helpers"; mkdir -p "$APP/Contents/Resources/photoshop" "$APP/Contents/Resources/ko.lproj"; printf '/* 한국어 */\n' > "$APP/Contents/Resources/ko.lproj/InfoPlist.strings";   # 열기·저장 창 같은 맥 기본 창도 한국어로 (사용자 2026-11-07)
 cp "$SRC/res/logo.ai" "$APP/Contents/Resources/logo.ai"; cp "$SRC/res/ydot.icns" "$APP/Contents/Resources/ydot.icns"
"$T/psproduct/build.sh" >/dev/null && cp "$T/psproduct/build/ydot_guide.jsx" "$APP/Contents/Resources/photoshop/guide.jsx" && cp "$T/psproduct/build/ydot_print.jsx" "$APP/Contents/Resources/photoshop/print.jsx"   # 포토샵 가이드·인화 (설치 앱이 포토샵 폴더에 넣음)
cp "$SRC/com.cc.donut.plist" "$APP/Contents/Resources/com.cc.donut.plist"   # 로그인 자동 실행 (설치 앱이 꺼내 등록)   # Custom 인화지 폴라로이드 로고 (보통사진관스티커.ai). 2026-11-05 명조체는 안 씀(애플 기본 글씨)
codesign --force --deep -s "cc-codesign" "$APP"   # 고정 인증서 → 다시 빌드해도 권한 유지
echo "빌드 완료: $APP"
cp "$SRC/com.cc.donut.plist" "$HOME/Library/LaunchAgents/com.cc.donut.plist"
launchctl bootout gui/$(id -u)/com.cc.donut 2>/dev/null || true; launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.cc.donut.plist" 2>/dev/null || true
pkill -x Donut 2>/dev/null || true; for i in {1..50}; do pgrep -x Donut >/dev/null || break; sleep 0.1; done   # 빌드하는 동안 예전 ydot이 다시 켜졌으면 한 번 더 끔 (안 그러면 예전 것이 계속 돎, 2026-11-07)
[ -n "$NO_OPEN" ] || { open "$APP" --args --login; for i in {1..30}; do pgrep -x Donut >/dev/null && break; sleep 0.2; done; pgrep -x Donut >/dev/null || { sleep 1; open "$APP" --args --login; }; }   # 켜졌는지 확인, 안 켜졌으면 한 번 더
echo "설치 완료: $APP"
"$SRC/share.sh" >/dev/null && echo "배포 묶음 갱신: ~/Desktop/ylab/app/ydot"
