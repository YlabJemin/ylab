-- Pick 설치 (이 파일이 있는 폴더의 Pick.app·Pick.scpt를 이 맥에 깔아 줌). 우클릭 → 열기 한 번이면 끝
on run
	set here to POSIX path of (path to me)
	if here does not end with "/" then set here to here & "/"
	set here to here & "Contents/Resources/payload/" -- 앱·스크립트 파일은 이 설치 앱 안에 들어 있음 -- Pick.app · Pick.scpt 는 이 설치 앱 안에 들어 있음
	set appSrc to here & "Pick.app"
	set scptSrc to here & "Pick.scpt"
	try
		do shell script "test -d " & quoted form of appSrc
	on error
		activate
		display dialog "설치 파일이 손상됐어요." & return & "Pick 폴더를 다시 받아 주세요." with title "Pick 설치" buttons {"확인"} default button 1 with icon stop
		return
	end try
	set home to POSIX path of (path to home folder)
	-- 1) 앱: /Applications/Pick.app (있으면 덮어씀 = 업데이트). 안 되면 사용자 Applications 폴더. 다운로드 표시(격리) 제거 → 경고 없이 열림
	set dest to "/Applications/Pick.app"
	try
		do shell script "rm -rf /Applications/Pick.app && ditto " & quoted form of appSrc & " /Applications/Pick.app"
	on error
		set dest to home & "Applications/Pick.app"
		do shell script "mkdir -p " & quoted form of (home & "Applications") & " && rm -rf " & quoted form of dest & " && ditto " & quoted form of appSrc & " " & quoted form of dest
	end try
	do shell script "xattr -dr com.apple.quarantine " & quoted form of dest & " 2>/dev/null; if [ " & quoted form of dest & " = /Applications/Pick.app ]; then rm -rf " & quoted form of (home & "Applications/Pick.app") & "; fi; true"
	-- 2) 캡쳐원 스크립트 메뉴용 Pick
	do shell script "mkdir -p " & quoted form of (home & "Library/Scripts/Capture One Scripts") & " && cp " & quoted form of scptSrc & " " & quoted form of (home & "Library/Scripts/Capture One Scripts/Pick.scpt")
	-- 3) 세션 폴더(아이콘은 픽이 켜질 때 입힘)
	do shell script "mkdir -p " & quoted form of (home & "Desktop/세션")
	-- 4) 실행 중이면 껐다 켜서 새 버전으로
	-- (tell application "Pick"은 아직 설치 안 된 맥에서 '응용 프로그램 선택' 창을 띄우므로 쓰지 않음)
	do shell script "pkill -x Pick 2>/dev/null; true"
	delay 1
	activate   -- 알림을 맨 앞으로 (2026-11-05)
	display dialog "Pick 설치가 끝났어요." & return & return & "설치된 곳" & return & "• 응용 프로그램 폴더 › Pick" & return & "• 캡쳐원 스크립트 메뉴 › Pick" & return & "• 데스크톱 › 세션 폴더" & return & return & "열기를 누르면 Pick이 켜져요." & return & "권한을 묻는 창이 뜨면 허용을 눌러 주세요." with title "Pick 설치" buttons {"열기"} default button 1 with icon note
	do shell script "open " & quoted form of dest
end run
