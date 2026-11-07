#!/bin/zsh
# Pick 앱 빌드 → /Applications/Pick.app (관리자 사용자는 비밀번호 없이 쓸 수 있는 폴더)  (소스: Pick.swift + ui/)
set -e
python3 "$(dirname "$0")/check_ui.py" || { echo "빌드 중단: 화면 코드 문법 오류"; exit 1; }
SRC=~/Desktop/cc/tools/pick
APP="/Applications/Pick.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 유니버설(인텔+애플실리콘) · 최소 macOS 13 으로 컴파일 (배포용, 2026-11-04). 사용: swift_build <출력> <소스>
swift_build() { swiftc -O -target arm64-apple-macos13.0 "$2" -o "$1.arm64" && swiftc -O -target x86_64-apple-macos13.0 "$2" -o "$1.x86_64" && lipo -create "$1.arm64" "$1.x86_64" -output "$1" && rm -f "$1.arm64" "$1.x86_64"; }
swift_build "$APP/Contents/MacOS/Pick" "$SRC/Pick.swift"
swift_build "$APP/Contents/MacOS/rawjpg" "$SRC/../c1scripts/rawjpg.swift"   # 내보내기 '원본'용 도우미를 앱 안에 (2026-11-05, 예전엔 ydot이 깔아 줌)
rm -rf "$APP/Contents/Resources/ui"; cp -R "$SRC/ui" "$APP/Contents/Resources/ui"
[ -f "$SRC/Pick.icns" ] && cp "$SRC/Pick.icns" "$APP/Contents/Resources/Pick.icns"
[ -f "$SRC/c1folder.png" ] && cp "$SRC/c1folder.png" "$APP/Contents/Resources/c1folder.png"   # '캡쳐원 전용' 폴더 아이콘 (흰 폴더 + 캡쳐원 고리)
mkdir -p "$APP/Contents/Resources/ko.lproj"   # 한국어 앱으로 인식 → 데스크톱·사용자 같은 폴더 표시 이름이 한국어로
cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.cc.pick</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>CFBundleLocalizations</key><array><string>ko</string></array>
  <key>CFBundleName</key><string>Pick</string>
  <key>CFBundleDisplayName</key><string>Pick</string>
  <key>CFBundleExecutable</key><string>Pick</string>
  <key>CFBundleIconFile</key><string>Pick</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Folder</string><key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array></dict></array>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Pick</string><key>CFBundleURLSchemes</key><array><string>pick</string></array></dict></array>
  <key>NSAppleEventsUsageDescription</key><string>캡쳐원 세션의 사진 목록·별점·조정값을 읽고, 별점을 넣고, 보정 반영 미리보기를 만들기 위해 필요해요.</string>
  <key>NSDesktopFolderUsageDescription</key><string>데스크톱에 있는 캡쳐원 세션의 사진과 썸네일을 읽기 위해 필요해요.</string>
</dict></plist>
PL
codesign --force --deep -s "cc-codesign" "$APP"   # 고정 인증서 → 다시 빌드해도 권한 유지
echo "빌드 완료: $APP"
"$SRC/share.sh" >/dev/null && echo "배포 묶음 갱신: ~/Desktop/ylab/Pick"   # 배포 폴더를 항상 최신으로
