#!/bin/zsh
# ccvm 빌드 → ~/Desktop/cc/tools/ccvm/ccvm.app (가상화 권한 entitlement 서명)
set -e
SRC="${0:A:h}"; APP="$SRC/ccvm.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/ccvm" "$SRC/ccvm.swift"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.cc.ccvm</string><key>CFBundleName</key><string>새 맥</string><key>CFBundleExecutable</key><string>ccvm</string>
  <key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PL
codesign --force --entitlements "$SRC/ccvm.entitlements" -s "cc-codesign" "$APP"
echo "빌드 완료: $APP"
