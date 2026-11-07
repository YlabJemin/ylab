#!/bin/zsh
# 앱 토글 껍데기 만들기 → ~/Library/Application Support/cc/토글/<이름>.app  (실행 파일 하나를 여러 껍데기에 복사)
set -e
SRC="${0:A:h}"; OUT="$HOME/Library/Application Support/cc/토글"
mkdir -p "$OUT"; swiftc -O "$SRC/main.swift" -o "$SRC/toggle"
mk() {  # mk <이름> <대상 bundle id>
  local APP="$OUT/$1.app"; mkdir -p "$APP/Contents/MacOS"; cp "$SRC/toggle" "$APP/Contents/MacOS/toggle"
  cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.cc.toggle.$3</string>
  <key>CFBundleName</key><string>$1</string>
  <key>CFBundleExecutable</key><string>toggle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSBackgroundOnly</key><true/>
  <key>CCToggleBundleID</key><string>$2</string>
</dict></plist>
P
  codesign --force -s "cc-codesign" "$APP" 2>/dev/null; echo "  $1 → $2"
}
mk "Claude 토글" com.anthropic.claudefordesktop claude
mk "Claude Code 토글" com.microsoft.VSCode vscode
mk "포토샵 토글" com.adobe.Photoshop photoshop
mk "라이트룸 토글" com.adobe.LightroomClassicCC7 lightroom
mk "이보토 토글" com.cclian.Evoto evoto
mk "캡쳐원 토글" com.captureone.captureone16 captureone
mk "카톡 토글" com.kakao.KakaoTalkMac kakaotalk
echo "완료: $OUT"
