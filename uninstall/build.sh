#!/bin/zsh
# 제거 앱 5개 만들기 → ~/Desktop/ylab/app/{Pick,ydot,yap,yinsta}/Uninstall <이름>.app , ~/Desktop/ylab/Uninstall ylab.app (영어 이름, 2026-11-05)
# 소스는 uninstall.applescript 하나 (@@TARGETS@@·@@TITLE@@만 바꿈). 각 share.sh 끝에서도 불림
# 시험은 test.sh (가짜 맥 폴더에서만). 만든 제거 앱은 시험 목적이라도 직접 실행하지 않기
set -e
SRC=${0:A:h}
T=~/Desktop/cc/tools
Y=~/Desktop/ylab
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# osacompile 앱의 최소 macOS를 13.0으로 낮추고 서명 (share.sh와 같음)
fix_applet() { local a="$1/Contents/MacOS/applet"; [ -f "$a" ] || return 0; rm -f "$1/Contents/Resources/Assets.car"; /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$1/Contents/Info.plist" 2>/dev/null;  # 기본 아이콘 묶음(Assets.car)이 applet.icns를 가려서 지움 (2026-11-05)
  vtool -set-build-version macos 13.0 "$(sw_vers -productVersion | cut -d. -f1).0" -replace -output "$a.new" "$a" 2>/dev/null && mv "$a.new" "$a" && chmod +x "$a"; codesign --force --deep -s "cc-codesign" "$1" 2>/dev/null || true; }
# 폴더 아이콘(yfolder.png) → icns (전체 제거 앱용)
YI="$TMP/y.iconset"; mkdir -p "$YI"
for s in 16 32 128 256; do sips -z $s $s "$T/cat-menu/yfolder.png" --out "$YI/icon_${s}x${s}.png" >/dev/null; sips -z $((s*2)) $((s*2)) "$T/cat-menu/yfolder.png" --out "$YI/icon_${s}x${s}@2x.png" >/dev/null; done
iconutil -c icns "$YI" -o "$TMP/y.icns"
one() {   # $1 대상, $2 제목, $3 나올 앱 경로, $4 아이콘
  [ -d "${3:h}" ] || return 0
  sed -e "s/@@TARGETS@@/$1/g" -e "s/@@TITLE@@/$2/g" "$SRC/uninstall.applescript" > "$TMP/u.applescript"
  rm -rf "$3"; osacompile -o "$3" "$TMP/u.applescript"
  cp "$4" "$3/Contents/Resources/applet.icns"; touch "$3"
  fix_applet "$3"
  echo "제거 앱: $3"
}
rm -rf "$Y/ylab 전체 제거.app" "$Y/app/Pick/Pick 제거.app" "$Y/app/ydot/ydot 제거.app" "$Y/app/yinsta/yinsta 제거.app"   # 예전 한글 이름 정리 (2026-11-05)
one pick Pick "$Y/app/Pick/Uninstall Pick.app" "$T/pick/Pick.icns"
one ydot ydot "$Y/app/ydot/Uninstall ydot.app" "$T/donut/res/ydot.icns"
one yap yap "$Y/app/yap/Uninstall yap.app" "$T/cat-menu/yap.icns"
one yinsta yinsta "$Y/app/yinsta/Uninstall yinsta.app" "$T/yinsta/yinsta.icns"
one "pick,ydot,yap,yinsta" "Pick · ydot · yap · yinsta" "$Y/Uninstall ylab.app" "$TMP/y.icns"
