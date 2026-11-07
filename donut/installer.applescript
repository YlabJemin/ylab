-- Install ydot (2026-11-05 앱 나누기: ydot = Shift Convert. 스크립트 메뉴는 yap 앱)
on run
	set here to POSIX path of (path to me)
	if here does not end with "/" then set here to here & "/"
	set here to here & "Contents/Resources/payload/"
	try
		do shell script "test -d " & quoted form of (here & "ydot.app")
	on error
		activate
		display dialog "설치 파일이 손상됐어요." & return & "ydot을 다시 받아 주세요." with title "ydot 설치" buttons {"확인"} default button 1 with icon stop
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
	-- 예전 ydot(스크립트 메뉴 + Shift Convert 한 몸)이 있으면: 그 앱과 로그인 자동 실행을 정리 (스크립트 파일·도우미는 그대로 → yap을 깔면 다시 메뉴로)
	set hadOld to false
	set oldID to do shell script "/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' " & quoted form of (appDir & "ydot.app/Contents/Info.plist") & " 2>/dev/null || true"
	if oldID is "com.cc.scriptmenu" then set hadOld to true
	set yapHere to (do shell script "test -d /Applications/yap.app -o -d " & quoted form of (home & "Applications/yap.app") & " && echo y || echo n") is "y"
	do shell script "pkill -x Donut 2>/dev/null; pkill -f cc-scriptmenu 2>/dev/null; true"
	delay 1
	if hadOld and not yapHere then do shell script "launchctl bootout gui/$(id -u)/com.cc.scriptmenu 2>/dev/null; rm -f " & quoted form of (home & "Library/LaunchAgents/com.cc.scriptmenu.plist") & "; true"
	do shell script "rm -rf " & quoted form of (appDir & "ydot.app") & " " & quoted form of (appDir & "Shift Convert.app") & " && ditto " & quoted form of (here & "ydot.app") & " " & quoted form of (appDir & "ydot.app") & " && xattr -dr com.apple.quarantine " & quoted form of (appDir & "ydot.app") & " 2>/dev/null; true"
	-- 로그인 때 ydot 자동 실행
	do shell script "mkdir -p " & quoted form of (home & "Library/LaunchAgents") & " && sed 's#/Applications/ydot.app#" & appDir & "ydot.app#' " & quoted form of (appDir & "ydot.app/Contents/Resources/com.cc.donut.plist") & " > " & quoted form of (home & "Library/LaunchAgents/com.cc.donut.plist") & "; launchctl bootout gui/$(id -u)/com.cc.donut 2>/dev/null; launchctl bootstrap gui/$(id -u) " & quoted form of (home & "Library/LaunchAgents/com.cc.donut.plist") & " 2>/dev/null; true"
	-- 포토샵 스크립트(가이드·인화) → 설치된 포토샵마다 앱 폴더의 Presets/Scripts (관리자 암호 한 번). 포토샵이 없으면 건너뜀. 포토샵은 꺼져 있어도 됨
	set psMsg to ""
	set psDirs to do shell script "ls -d /Applications/Adobe\\ Photoshop*/Presets/Scripts 2>/dev/null || true"
	if psDirs is not "" then
		set h to appDir & "ydot.app/Contents/Resources/photoshop/"
		set cmd to ""
		repeat with d in paragraphs of psDirs
			set cmd to cmd & "rm -f " & quoted form of ((d as text) & "/ydot 가이드.jsx") & " " & quoted form of ((d as text) & "/ydot 인화.jsx") & "; cp " & quoted form of (h & "guide.jsx") & " " & quoted form of ((d as text) & "/ydot_guide.jsx") & " && cp " & quoted form of (h & "print.jsx") & " " & quoted form of ((d as text) & "/ydot_print.jsx") & " && chmod 644 " & quoted form of ((d as text) & "/ydot_guide.jsx") & " " & quoted form of ((d as text) & "/ydot_print.jsx") & "; "
		end repeat
		try
			activate   -- 암호 창이 다른 창 뒤에 숨지 않게
			do shell script cmd with prompt "ydot 가이드·인화 스크립트를 포토샵 스크립트 메뉴에 넣으려고 해요." with administrator privileges
			set psMsg to return & return & "포토샵" & return & "• 파일 › 스크립트에 ydot_guide · ydot_print가 생겨요" & return & "• 포토샵이 켜져 있었다면 한 번 껐다 켜 주세요"
		on error
			set psMsg to return & return & "포토샵" & return & "• 스크립트는 넣지 않았어요 (암호 취소)" & return & "• 설치를 다시 하면 넣을 수 있어요"
		end try
	end if
	do shell script "open " & quoted form of (appDir & "ydot.app") & " --args --login"   -- 설치 뒤엔 조용히 (창은 앱을 누르면)
	set yapMsg to ""
	if hadOld and not yapHere then set yapMsg to return & return & "예전 ydot을 쓰셨다면" & return & "• AirDrop · 인스타 저장 · 캡쳐원 스크립트 메뉴는 이제 yap 앱이에요" & return & "• 쓰시려면 yap도 설치해 주세요"
	delay 1   -- 켜진 ydot 뒤로 알림이 숨지 않게: 잠깐 기다렸다가 이 창을 맨 앞으로 (2026-11-05)
	activate
	display dialog "ydot 설치가 끝났어요." & return & return & "메뉴 막대 오른쪽 위 y. 아이콘" & return & "• 사진을 집은 채 Shift를 누르면 변환 패널이 열려요" & return & "• 설정: y. › Settings… (⌘,)" & return & "• 로그인하면 자동으로 켜져요" & psMsg & yapMsg with title "ydot 설치" buttons {"확인"} default button 1 with icon note
end run
