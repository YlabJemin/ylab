-- 수동 설치 보조: ydot.app을 직접 응용 프로그램 폴더에 넣은 경우, 설치 앱이 해 주던 나머지(로그인 때 자동 실행)를 채움
on run
	set home to POSIX path of (path to home folder)
	set found to ""
	repeat with p in {"/Applications/ydot.app", home & "Applications/ydot.app"}
		try
			do shell script "test -d " & quoted form of p
			set found to p
			exit repeat
		end try
	end repeat
	if found is "" then
		display dialog "ydot.app이 응용 프로그램 폴더에 없어요. 옆의 ydot.app을 먼저 응용 프로그램 폴더로 옮긴 뒤 다시 열어 주세요." buttons {"확인"} default button 1 with icon stop
		return
	end if
	set plist to "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict><key>Label</key><string>com.cc.scriptmenu</string><key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>" & found & "</string></array><key>RunAtLoad</key><true/></dict></plist>"
	do shell script "mkdir -p " & quoted form of (home & "Library/LaunchAgents") & " && printf '%s' " & quoted form of plist & " > " & quoted form of (home & "Library/LaunchAgents/com.cc.scriptmenu.plist") & "; launchctl bootout gui/$(id -u)/com.cc.scriptmenu 2>/dev/null; launchctl bootstrap gui/$(id -u) " & quoted form of (home & "Library/LaunchAgents/com.cc.scriptmenu.plist") & " 2>/dev/null; xattr -dr com.apple.quarantine " & quoted form of found & " 2>/dev/null; open " & quoted form of found
	display dialog "로그인할 때 ydot이 자동으로 켜지도록 등록했고 지금 켰어요." & return & "메뉴 막대 오른쪽 위에 y. 아이콘이 보이면 끝이에요." buttons {"확인"} default button 1 with icon note
end run
