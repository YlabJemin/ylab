-- 캡쳐원 스크립트 메뉴 "Pick": 셀렉 앱을 띄우기만 하고 바로 끝남 (캡쳐원을 붙잡지 않음)
-- 앱: /Applications/Pick.app (소스 ~/Desktop/cc/tools/pick). 어디에 있든 번들 ID로 찾음
-- pick://c1 → 지금 캡쳐원에 열린 세션으로 연결 (그냥 켜면 데스크톱 폴더로 시작하므로)
do shell script "open -b com.cc.pick pick://c1"
