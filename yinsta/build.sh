#!/bin/zsh
# yinsta 앱 빌드 → /Applications/yinsta.app → 켜기 → 배포 묶음(~/Desktop/ylab/yinsta) 갱신.  NO_OPEN=1 이면 안 켬
set -e
SRC="${0:A:h}"
APP="/Applications/yinsta.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 아이콘 (icon.swift 가 바뀐 경우에만 다시 그림)
if [ ! -f "$SRC/yinsta.icns" ] || [ ! -f "$SRC/ui/applogo.png" ] || [ "$SRC/icon.swift" -nt "$SRC/yinsta.icns" ]; then
  T=$(mktemp -d); swiftc -O -o "$T/icon" "$SRC/icon.swift"; mkdir -p "$T/yinsta.iconset"; "$T/icon" "$T/yinsta.iconset" "$SRC/ui/applogo.png" 0.04   # y. 를 4% 내림 (3%→4%, 사용자 2026-11-04)
  iconutil -c icns "$T/yinsta.iconset" -o "$SRC/yinsta.icns"; cp "$T/yinsta.iconset/icon_512x512.png" "$SRC/icon_512.png"; rm -rf "$T"
fi
# 배포 앱 규칙: 유니버설(arm64+x86_64) · 최소 macOS 13.0
swift_build() { swiftc -O -target arm64-apple-macos13.0 "$2" -o "$1.arm64" && swiftc -O -target x86_64-apple-macos13.0 "$2" -o "$1.x86_64" && lipo -create "$1.arm64" "$1.x86_64" -output "$1" && rm -f "$1.arm64" "$1.x86_64"; }
swift_build "$APP/Contents/MacOS/yinsta" "$SRC/yinsta.swift"
rm -rf "$APP/Contents/Resources/ui"; cp -R "$SRC/ui" "$APP/Contents/Resources/ui"
cp "$SRC/yinsta.icns" "$APP/Contents/Resources/yinsta.icns"
mkdir -p "$APP/Contents/Resources/ko.lproj"   # 한국어 앱으로 인식
VER=$(date +%Y%m%d.%H%M)
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.cc.yinsta</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>CFBundleLocalizations</key><array><string>ko</string></array>
  <key>CFBundleName</key><string>yinsta</string>
  <key>CFBundleDisplayName</key><string>yinsta</string>
  <key>CFBundleExecutable</key><string>yinsta</string>
  <key>CFBundleIconFile</key><string>yinsta</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$VER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>y.</string>
</dict></plist>
PL
codesign --force --deep -s "cc-codesign" "$APP" 2>/dev/null || codesign --force --deep -s - "$APP"   # 고정 인증서(없으면 임시 서명)
# 브라우저로도 열어 볼 수 있게 복사 (~/Desktop/cc/작업중/yinsta/index.html)
mkdir -p "$HOME/Desktop/cc/작업중/yinsta"; rm -rf "$HOME/Desktop/cc/작업중/yinsta/lib"; cp -R "$SRC/ui/." "$HOME/Desktop/cc/작업중/yinsta/"
if [ -z "$NO_OPEN" ]; then pkill -x yinsta 2>/dev/null; sleep 0.4; open "$APP"; fi
echo "빌드 완료: $APP"
"$SRC/share.sh" >/dev/null && echo "배포 묶음 갱신: ~/Desktop/ylab/yinsta"
