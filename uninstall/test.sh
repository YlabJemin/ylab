#!/bin/zsh
# 제거 앱 시험 — 가짜 맥(~/Desktop/cc/작업중/시험/제거시험/)에서만. 실제 경로는 절대 안 씀
# 시나리오마다 가짜 설치 흔적 + "지우면 안 되는 것"을 새로 만들고 uninstallIn(시험 모드)를 부른 뒤 남은 것을 검사
set -u
SRC=${0:A:h}
T=~/Desktop/cc/작업중/시험/제거시험
SCPT=$T/_u.scpt
YB=/Applications/yap.app/Contents/Resources/scripts   # 진짜 스크립트를 '복사'해서 씀 (원본은 읽기만)
rm -rf "$T"; mkdir -p "$T"
osacompile -o "$SCPT" "$SRC/uninstall.applescript" || exit 1
fail=0

mkapp() { mkdir -p "$1/Contents"; cat > "$1/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$2</string></dict></plist>
P
}
fixture() {   # $1 = 시나리오 폴더
  local R=$1/root H=$1/home/
  rm -rf "$1"; mkdir -p "$R/Applications" "$H" "$1/trash/"
  mkapp "$R/Applications/Pick.app" com.cc.pick
  mkapp "$R/Applications/ydot.app" com.cc.donut
  mkapp "$R/Applications/yap.app" com.cc.scriptmenu
  mkapp "$R/Applications/Shift Convert.app" com.cc.donut
  mkapp "$H/Applications/yinsta.app" com.cc.yinsta            # 사용자 Applications에 깔린 경우
  mkapp "$H/Applications/Pick.app" com.someone.pick            # [남아야 함] 같은 이름 다른 앱
  mkapp "$R/Applications/Other.app" com.other.app              # [남아야 함]
  local PS="$R/Applications/Adobe Photoshop 2026/Presets/Scripts"; mkdir -p "$PS"
  touch "$PS/ydot_guide.jsx" "$PS/ydot_print.jsx" "$PS/ydot 인화.jsx" "$PS/Other Script.jsx"   # Other Script [남아야 함]
  local L=$H/Library C1="$H/Library/Scripts/Capture One Scripts"
  mkdir -p "$C1/Background Scripts" "$L/Scripts/yap_scripts/Photoshop" "$L/Scripts/cc 스크립트" "$L/LaunchAgents" "$L/Preferences" \
    "$L/Application Support/cc/셀렉 휠.app" "$L/Application Support/Pick" "$L/Application Support/yinsta/posts" "$L/Application Support/Other" \
    "$L/Caches/Pick/folders" "$L/Caches/com.cc.pick" "$L/WebKit/com.cc.yinsta" "$L/Saved Application State/com.cc.pick.savedState" \
    "$L/Application Support/Adobe/Adobe Photoshop 2026/Presets/Scripts" "$H/Desktop/세션/0101_시험세션"
  cp "$YB/Capture One Scripts/"*.scpt "$C1/"
  osacompile -o "$C1/Pick.scpt" "$SRC/../pick/Pick.applescript"   # Pick 몫 (yap 묶음엔 없음)
  osacompile -o "$C1/My Own.scpt" -e 'display dialog "mine"'           # [남아야 함] 사용자 스크립트
  osacompile -o "$C1/Background Scripts/bg.scpt" -e 'return 1'         # [남아야 함]
  cp "$YB/ccscripts/"*.applescript "$L/Scripts/yap_scripts/"; cp "$YB/ccscripts/Photoshop/"*.applescript "$L/Scripts/yap_scripts/Photoshop/"
  echo 'display dialog "my script"' > "$L/Scripts/yap_scripts/Mine.applescript"   # [남아야 함] 사용자가 넣은 것
  cp "$YB/ccscripts/AirDrop.applescript" "$L/Scripts/cc 스크립트/"                # 옛 폴더 (비면 폴더도 지워져야 함)
  for n in airdropsend cctool exportui psexportui rawjpg rotate sessionui c1job.sh export.jsx info.jsx ydot-version yap-version ydot_guide.jsx ydot_print.jsx ydot_ps_state.txt "ydot 가이드.jsx"; do touch "$L/Application Support/cc/$n"; done
  touch "$L/Application Support/cc/wacom-scroll"                       # [남아야 함] 다른 프로그램
  echo '{}' > "$L/Application Support/Pick/ratings.json"
  echo '[]' > "$L/Application Support/yinsta/posts.json"
  touch "$L/Application Support/Other/x" "$L/Caches/Pick/folders/a_s.jpg"
  touch "$L/Application Support/Adobe/Adobe Photoshop 2026/Presets/Scripts/ydot 가이드.jsx" "$L/Application Support/Adobe/Adobe Photoshop 2026/Presets/Scripts/Mine.jsx"
  touch "$L/LaunchAgents/com.cc.scriptmenu.plist" "$L/LaunchAgents/com.cc.donut.plist" "$L/LaunchAgents/com.other.agent.plist"
  for i in com.cc.pick com.cc.scriptmenu com.cc.donut com.cc.ydot-shared com.cc.yinsta com.apple.finder; do touch "$L/Preferences/$i.plist"; done
  touch "$H/Desktop/세션/0101_시험세션/photo.cr3"
}
run() {   # $1 시나리오 이름, $2 대상
  local S=$T/$1; fixture "$S"
  echo "━━ $1 ($2)"
  osascript -e "on run a
    set u to load script (POSIX file (item 1 of a))
    tell u to return uninstallIn(item 2 of a, item 3 of a, item 4 of a, item 5 of a, true)
  end run" "$SCPT" "$2" "$S/home/" "$S/root" "$S/trash/" | sed 's#'"$S"'#…#g'
  LEFT=$(cd "$S" && find root home -mindepth 1 | sort)
}
must()  { for p in "$@"; do print -r -- "$LEFT" | grep -qxF -- "$p" || { echo "  ✗ 지워지면 안 되는데 없음: $p"; fail=1; }; done; }
gone()  { for p in "$@"; do print -r -- "$LEFT" | grep -qxF -- "$p" && { echo "  ✗ 남아 있음: $p"; fail=1; }; done; return 0; }

ALWAYS=( "home/Applications/Pick.app" "root/Applications/Other.app" "root/Applications/Adobe Photoshop 2026/Presets/Scripts/Other Script.jsx"
  "home/Library/Scripts/Capture One Scripts/My Own.scpt" "home/Library/Scripts/Capture One Scripts/Background Scripts/bg.scpt"
  "home/Library/Scripts/yap_scripts/Mine.applescript" "home/Library/Application Support/cc/wacom-scroll" "home/Library/Application Support/cc/셀렉 휠.app"
  "home/Library/Application Support/Other/x" "home/Library/Application Support/Adobe/Adobe Photoshop 2026/Presets/Scripts/Mine.jsx"
  "home/Library/LaunchAgents/com.other.agent.plist" "home/Library/Preferences/com.apple.finder.plist" "home/Desktop/세션/0101_시험세션/photo.cr3" )
C1="home/Library/Scripts/Capture One Scripts"; AS="home/Library/Application Support"
PICK=( "root/Applications/Pick.app" "$AS/Pick" "home/Library/Caches/Pick" "home/Library/Caches/com.cc.pick" "home/Library/Saved Application State/com.cc.pick.savedState" "home/Library/Preferences/com.cc.pick.plist" )
YDOT=( "root/Applications/ydot.app" "root/Applications/Shift Convert.app" "home/Library/LaunchAgents/com.cc.donut.plist" "$AS/cc/ydot_guide.jsx" "$AS/cc/ydot 가이드.jsx"
  "root/Applications/Adobe Photoshop 2026/Presets/Scripts/ydot_guide.jsx" "root/Applications/Adobe Photoshop 2026/Presets/Scripts/ydot 인화.jsx"
  "$AS/Adobe/Adobe Photoshop 2026/Presets/Scripts/ydot 가이드.jsx" "home/Library/Preferences/com.cc.donut.plist" "home/Library/Preferences/com.cc.ydot-shared.plist" )
YAP=( "root/Applications/yap.app" "home/Library/LaunchAgents/com.cc.scriptmenu.plist" "$C1/New Session.scpt" "$C1/Delete Session.scpt" "$C1/Export.scpt"
  "home/Library/Scripts/yap_scripts/AirDrop.applescript" "home/Library/Scripts/yap_scripts/Photoshop" "home/Library/Scripts/cc 스크립트" "$AS/cc/cctool" "$AS/cc/rawjpg" "$AS/cc/yap-version" "$AS/cc/ydot-version"
  "home/Library/Preferences/com.cc.scriptmenu.plist" )
INSTA=( "home/Applications/yinsta.app" "$AS/yinsta" "home/Library/WebKit/com.cc.yinsta" "home/Library/Preferences/com.cc.yinsta.plist" )

run ydot만 ydot;             gone $YDOT; must $ALWAYS $PICK $YAP "$C1/Pick.scpt" $INSTA "home/Library/Scripts/yap_scripts"
run yap만 yap;               gone $YAP; must $ALWAYS $PICK $YDOT "$C1/Pick.scpt" $INSTA
run Pick만 pick;            gone $PICK "$C1/Pick.scpt"; must $ALWAYS $YDOT $YAP $INSTA
run yinsta만 yinsta;        gone $INSTA; must $ALWAYS $PICK $YDOT $YAP "$C1/Pick.scpt"
run 전체 "pick,ydot,yap,yinsta"; gone $PICK $YDOT $YAP $INSTA "$C1/Pick.scpt"; must $ALWAYS
echo "  남은 것:"; print -r -- "$LEFT" | sed 's/^/    /'
# 시험 경로 지킴: 가짜 경로가 아니면 멈춰야 함
echo "━━ 경로 지킴"
osascript -e "on run a
  set u to load script (POSIX file (item 1 of a))
  tell u to return uninstallIn(\"pick\", \"/Users/nobody/\", \"\", \"\", true)
end run" "$SCPT" 2>&1 | grep -q "시험 경로가 아니에요" && echo "  ✓ 진짜 경로 거부" || { echo "  ✗ 진짜 경로를 거부하지 않음"; fail=1; }
[ $fail = 0 ] && echo "모두 통과" || echo "실패 있음"
rm -rf "$T"
exit $fail
