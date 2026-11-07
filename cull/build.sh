#!/bin/zsh
# 셀렉 휠 앱 빌드 → ~/Library/Application Support/cc/셀렉 휠.app
set -e
SRC=~/Desktop/cc/tools/cull
APP="$HOME/Library/Application Support/cc/셀렉 휠.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O "$SRC/CullWheel.swift" -o "$APP/Contents/MacOS/cullwheel"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.cc.cullwheel</string>
  <key>CFBundleName</key><string>셀렉 휠</string>
  <key>CFBundleDisplayName</key><string>셀렉 휠</string>
  <key>CFBundleExecutable</key><string>cullwheel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>캡쳐원에서 별점·색상 태그를 읽고 쓰고, 미리보기를 만들기 위해 필요해요.</string>
  <key>NSDesktopFolderUsageDescription</key><string>데스크탑의 캡쳐원 세션 폴더에서 보정 반영 썸네일을 읽기 위해 필요해요.</string>
</dict></plist>
EOF
codesign --force -s "cc-codesign" "$APP"   # 고정 인증서로 서명 → 다시 빌드해도 권한 유지 (~/Desktop/cc/signing)
echo "빌드 완료: $APP"
