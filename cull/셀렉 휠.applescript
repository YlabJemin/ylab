-- 캡쳐원 셀렉 휠 실행 스크립트: 앱을 띄우기만 하고 바로 끝남 (캡쳐원을 붙잡지 않음)
-- 앱: ~/Library/Application Support/cc/셀렉 휠.app (소스 ~/Desktop/cc/tools/cull/CullWheel.swift)
set appPath to POSIX path of (path to application support folder from user domain) & "cc/셀렉 휠.app"
do shell script "open " & quoted form of appPath
