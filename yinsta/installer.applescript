-- yinsta 설치 (이 설치 앱 안에 든 yinsta.app 을 응용 프로그램 폴더에 넣고 켬)
on run
	set here to POSIX path of (path to me)
	if here does not end with "/" then set here to here & "/"
	set here to here & "Contents/Resources/payload/"
	try
		do shell script "test -d " & quoted form of (here & "yinsta.app")
	on error
		activate
		display dialog "설치 파일이 손상됐어요." & return & "yinsta 폴더를 다시 받아 주세요." with title "yinsta 설치" buttons {"확인"} default button 1 with icon stop
		return
	end try
	set home to POSIX path of (path to home folder)
	set appDir to "/Applications/"
	try
		do shell script "test -w /Applications"
	on error
		set appDir to home & "Applications/"
		do shell script "mkdir -p " & quoted form of appDir
	end try
	do shell script "pkill -x yinsta 2>/dev/null; true"
	delay 0.5
	do shell script "rm -rf " & quoted form of (appDir & "yinsta.app") & " && ditto " & quoted form of (here & "yinsta.app") & " " & quoted form of (appDir & "yinsta.app") & " && xattr -dr com.apple.quarantine " & quoted form of (appDir & "yinsta.app") & " 2>/dev/null; true"
	do shell script "open " & quoted form of (appDir & "yinsta.app")
	delay 1   -- 켜진 yinsta 뒤로 알림이 숨지 않게 (2026-11-05)
	activate
	display dialog "yinsta 설치가 끝났어요." & return & return & "쓰는 법" & return & "• 아래 ＋ 또는 창에 끌어다 놓기로 사진을 넣어요" & return & "• 테두리를 잡고 끌면 창이 움직여요" & return & "• ⌘+ / ⌘− 로 크기를 바꿔요" & return & "• 사진은 이 맥 안에만 저장돼요" with title "yinsta 설치" buttons {"확인"} default button 1 with icon note
end run
