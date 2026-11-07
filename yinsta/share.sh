#!/bin/zsh
# yinsta 배포 묶음 갱신 → ~/Desktop/ylab/app/yinsta/  ('Install yinsta' 앱 안에 yinsta.app 이 들어 있음 + README) + 밖에 yinsta.dmg
set -e
SRC="${0:A:h}"
OUT=~/Desktop/ylab/app/yinsta   # 예비용 폴더 (사용자 2026-11-05: 밖에는 yinsta.dmg)
[ -d "$OUT" ] || { mkdir -p ~/Desktop/ylab/app; [ -d ~/Desktop/ylab/yinsta ] && mv ~/Desktop/ylab/yinsta "$OUT"; mkdir -p "$OUT"; }   # 예전 위치에서 옮김
rm -rf "$OUT/yinsta 설치.app" "$OUT/yinsta 제거.app" "$OUT/읽어보기.txt"   # 예전 한글 이름 정리
mkdir -p "$OUT"
rm -rf "$OUT/Install yinsta.app" "$OUT/Install yinsta.scptd"
fix_applet() { local a="$1/Contents/MacOS/applet"; [ -f "$a" ] || return 0; rm -f "$1/Contents/Resources/Assets.car"; /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$1/Contents/Info.plist" 2>/dev/null;  # 기본 아이콘 묶음(Assets.car)이 applet.icns를 가려서 지움 (2026-11-05)
  vtool -set-build-version macos 13.0 "$(sw_vers -productVersion | cut -d. -f1).0" -replace -output "$a.new" "$a" 2>/dev/null && mv "$a.new" "$a" && chmod +x "$a"; codesign --force --deep -s "cc-codesign" "$1" 2>/dev/null || true; }   # 설치 앱 최소 OS 낮추기
osacompile -o "$OUT/Install yinsta.app" "$SRC/installer.applescript"
PAY="$OUT/Install yinsta.app/Contents/Resources/payload"; mkdir -p "$PAY"; ditto /Applications/yinsta.app "$PAY/yinsta.app"
cp "$SRC/yinsta.icns" "$OUT/Install yinsta.app/Contents/Resources/applet.icns"; touch "$OUT/Install yinsta.app"   # 설치 앱도 yinsta 아이콘으로
fix_applet "$OUT/Install yinsta.app"
rm -rf "$OUT/수동 설치"   # 수동 설치는 없앰 (사용자 2026-11-05: 설치 앱 안에 같은 앱이 있음)
VER=$(date +%Y-%m-%d)
cat > "$OUT/README.txt" <<TXT
yinsta 설치 안내  (묶음 날짜: $VER)

yinsta = 가상 인스타그램. 내 사진을 넣으면 피드·프로필 격자에 올린 것처럼 보여 주는 시뮬레이터예요.
사진은 이 맥 안(~/Library/Application Support/yinsta)에만 저장되고 어디로도 올라가지 않아요.

■ 처음 설치
 1. 이 yinsta 폴더를 통째로 새 맥에 옮깁니다 (AirDrop · USB · 압축 파일 모두 됩니다).
 2. 'Install yinsta'를 두 번 클릭합니다.
    → "확인할 수 없어 열 수 없습니다" 창이 뜨면 '완료'를 누르고,
      시스템 설정 › 개인정보 보호 및 보안 › 아래로 내려 "그래도 열기" › 열기.  (처음 한 번만)
    (예전 맥(macOS 14 이하)은 'Install yinsta'를 마우스 오른쪽 클릭 → 열기 → 열기로도 됩니다)
 3. 끝. 아이폰 모양 창으로 yinsta가 켜집니다.

■ 쓰는 법
 • 사진 넣기: 프로필 화면 왼쪽 위 ＋ 를 누르거나, 사진 파일을 창에 끌어다 놓기 (여러 장이면 파일 이름순으로 게시)
 • 순서 바꾸기: 프로필 탭 격자에서 사진을 끌어 옮기기. 지우기: 격자 칸의 ✕
 • 글자 고치기: 이름·소개·팔로워·스토리 닉네임·문구·좋아요 수·시간·시계를 눌러서 바로 수정
 • 프로필 편집: 프로필 탭의 '프로필 편집'. 프로필 공유: 지금 화면을 그림으로 복사 → 카톡 등에 붙여넣기(⌘V)
 • 아이폰 왼쪽에 떠 있는 ‹ 버튼(또는 프로필의 ☰, 크롬 창의 ⚙): 왼쪽에 설정 패널 — 사진 비율(4:5 / 1:1), 창 크기 슬라이더(5단계), 사진 소스 패널, 화면 캡처 복사, 피드 비우기(사진은 소스로 돌아감)
 • 사진 소스 패널(설정 아래에 붙음): 사진을 미리 모아 두고, 격자의 원하는 자리로 끌어 놓으면 그 자리에 게시 (두 번 클릭 = 맨 위에 게시)
 • 아이폰 아래 V: 휴대폰을 길게 펼쳐 한눈에 보기(창을 넓게·길게 마음대로).  아이폰 위 ^: 인스타 PC(웹) 화면으로 보기 (창 자체가 크롬 창: 탭 줄을 잡고 옮기기 · 탭 줄 더블클릭 = 화면 가득 ↔ 원래 크기 · 창 가장자리를 끌면 크기 조절 · 탭 줄 왼쪽 ⚙ = 설정 패널, 휴대폰 아이콘 = 휴대폰으로)
 • 창 옮기기: 아이폰 테두리나 패널 머리를 잡고 끌기.  크기: 창 가장자리 끌기, ⌘+ / ⌘− / ⌘0.  종료: ⌘Q 또는 오른쪽 옆 버튼

■ 지우기
 • 'Uninstall yinsta'를 두 번 클릭 → 지울 목록을 보여 주고, '제거'를 누르면 휴지통으로 옮깁니다.
 • Pick · ydot · yinsta를 한 번에 지우려면 ylab 폴더의 'Uninstall ylab'.

■ 문제가 생기면
 • 'Install yinsta'가 안 열림: 시스템 설정 › 개인정보 보호 및 보안 › 아래쪽 "그래도 열기" (두 번 클릭해서 경고를 한 번 띄운 뒤에 나타납니다).
 • 사진이 사라짐: 보기 메뉴 › '저장 폴더 보기'로 저장 폴더를 확인해 보세요.
TXT
echo "갱신: $OUT"
~/Desktop/cc/tools/uninstall/build.sh   # 제거 앱 (Pick·ydot·yinsta 각자 + ylab 전체)
~/Desktop/cc/tools/ylab/dmg.sh   # 앱별 dmg (늘 최신)
