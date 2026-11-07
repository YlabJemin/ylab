-- Install yap (2026-11-05 앱 나누기: yap = 스크립트 메뉴. 예전 ydot의 스크립트 부분. Shift Convert는 ydot 앱)
on run
	set here to POSIX path of (path to me)
	if here does not end with "/" then set here to here & "/"
	set here to here & "Contents/Resources/payload/"
	try
		do shell script "test -d " & quoted form of (here & "yap.app")
	on error
		activate
		display dialog "설치 파일이 손상됐어요." & return & "yap을 다시 받아 주세요." with title "yap 설치" buttons {"확인"} default button 1 with icon stop
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
	do shell script "pkill -f cc-scriptmenu 2>/dev/null; true"
	delay 1
	-- 예전 ydot(스크립트 메뉴 + Shift Convert 한 몸)이 있으면 지움 (스크립트 메뉴는 yap이 이어받음). 새 ydot(Shift Convert)은 그대로 둠
	set hadOld to false
	repeat with d in {"/Applications/", home & "Applications/"}
		set oid to do shell script "/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' " & quoted form of ((d as text) & "ydot.app/Contents/Info.plist") & " 2>/dev/null || true"
		if oid is "com.cc.scriptmenu" then
			set hadOld to true
			do shell script "pkill -x Donut 2>/dev/null; rm -rf " & quoted form of ((d as text) & "ydot.app") & "; true"
		end if
	end repeat
	do shell script "rm -rf " & quoted form of (appDir & "yap.app") & " && ditto " & quoted form of (here & "yap.app") & " " & quoted form of (appDir & "yap.app") & " && xattr -dr com.apple.quarantine " & quoted form of (appDir & "yap.app") & " 2>/dev/null; true"
	-- 로그인 때 yap 자동 실행 (예전 ydot과 같은 이름표라 겹치지 않음)
	do shell script "mkdir -p " & quoted form of (home & "Library/LaunchAgents") & " && sed 's#/Applications/yap.app#" & appDir & "yap.app#' " & quoted form of (appDir & "yap.app/Contents/Resources/com.cc.scriptmenu.plist") & " > " & quoted form of (home & "Library/LaunchAgents/com.cc.scriptmenu.plist") & "; launchctl bootout gui/$(id -u)/com.cc.scriptmenu 2>/dev/null; launchctl bootstrap gui/$(id -u) " & quoted form of (home & "Library/LaunchAgents/com.cc.scriptmenu.plist") & " 2>/dev/null; true"
	do shell script "open " & quoted form of (appDir & "yap.app")
	set ydotMsg to ""
	if hadOld then
		set hasNew to (do shell script "test -d /Applications/ydot.app -o -d " & quoted form of (home & "Applications/ydot.app") & " && echo y || echo n") is "y"
		if not hasNew then set ydotMsg to return & return & "예전 ydot을 쓰셨다면" & return & "• 예전 ydot을 yap으로 바꿨어요" & return & "• Shift 변환 패널을 쓰시려면 ydot도 설치해 주세요"
	end if
	delay 1   -- 켜진 yap 뒤로 알림이 숨지 않게 (2026-11-05)
	activate
	display dialog "yap 설치가 끝났어요." & return & return & "메뉴 막대 오른쪽 위 검정 yap. 아이콘" & return & "• AirDrop · 인스타 저장(⌘⇧6)" & return & "• 포토샵 내보내기 · 캡쳐원 스크립트" & return & "• 로그인하면 자동으로 켜져요" & ydotMsg with title "yap 설치" buttons {"확인"} default button 1 with icon note
end run
