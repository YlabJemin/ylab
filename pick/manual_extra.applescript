-- 수동 설치 보조: Pick.app을 직접 응용 프로그램 폴더에 넣은 경우, 설치 앱이 해 주던 나머지를 채움
--   · 캡쳐원 스크립트 메뉴에 Pick 항목 (Pick.scpt → ~/Library/Scripts/Capture One Scripts/)
--   · 데스크톱에 '세션' 폴더
on run
	set here to POSIX path of (path to me)
	if here does not end with "/" then set here to here & "/"
	set scptSrc to here & "Contents/Resources/Pick.scpt"
	set home to POSIX path of (path to home folder)
	do shell script "mkdir -p " & quoted form of (home & "Library/Scripts/Capture One Scripts") & " && cp " & quoted form of scptSrc & " " & quoted form of (home & "Library/Scripts/Capture One Scripts/Pick.scpt") & " && mkdir -p " & quoted form of (home & "Desktop/세션")
	set found to ""
	repeat with p in {"/Applications/Pick.app", home & "Applications/Pick.app"}
		try
			do shell script "test -d " & quoted form of p
			set found to p
			exit repeat
		end try
	end repeat
	if found is "" then
		display dialog "캡쳐원 스크립트 메뉴에 Pick을 넣고 데스크톱에 '세션' 폴더를 만들었어요." & return & return & "Pick.app은 아직 응용 프로그램 폴더에 없어요. 옆의 Pick.app을 응용 프로그램 폴더로 옮겨 주세요." buttons {"확인"} default button 1 with icon note
	else
		display dialog "캡쳐원 스크립트 메뉴에 Pick을 넣고 데스크톱에 '세션' 폴더를 만들었어요." & return & return & "Pick: " & found buttons {"확인"} default button 1 with icon note
	end if
end run
