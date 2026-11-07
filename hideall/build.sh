#!/bin/zsh
# 데스크톱(모두 숨기기) 앱 빌드 → ~/Library/Application Support/cc/데스크톱.app
set -e
SRC="${0:A:h}"; APP="$HOME/Library/Application Support/cc/데스크톱.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O "$SRC/main.swift" -o "$APP/Contents/MacOS/hideall"
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.cc.hideall</string>
  <key>CFBundleName</key><string>데스크톱</string>
  <key>CFBundleExecutable</key><string>hideall</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>숨기기 요청을 무시하는 앱(라이트룸·이보토 등)을 숨기려면 System Events 제어가 필요해요.</string>
</dict></plist>
P
codesign --force -s "cc-codesign" "$APP"
echo "빌드 완료: $APP"
