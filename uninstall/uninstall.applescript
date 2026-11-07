-- ylab 제거 앱 (Pick · ydot · yap · yinsta — 2026-11-05 앱 나누기: ydot = Shift Convert, yap = 스크립트 메뉴). 이 소스 하나에서 @@TARGETS@@·@@TITLE@@만 바꿔 4개를 만든다 (build.sh)
-- 원칙 (2026-11-05 사용자 "이상한거 지우면 안되는거다"):
--   · 우리 앱이 넣은 것만. 이름과 표시(번들 ID · 안의 파일 · 스크립트 안 글자)가 맞을 때만 휴지통으로
--   · 폴더째 버리는 건 우리 전용 폴더뿐. 같이 쓰는 폴더(Application Support/cc, 스크립트 폴더)는 우리 파일만 고르고, 비면 폴더도
--   · 데스크톱 '세션' 폴더·사진·ylab 폴더·Finder 설정은 건드리지 않음
--   · Pick.scpt(캡쳐원 Pick 항목)는 Pick 몫, rawjpg는 Pick 앱 안에도 따로 있음 → 서로 안 기댐
-- 시험: test.sh가 이 파일을 .scpt로 컴파일해 uninstallIn()을 가짜 홈·가짜 루트·가짜 휴지통으로만 부름.
--       시험 모드는 경로가 ~/Desktop/cc/작업중/시험/ 아래가 아니면 멈추고, 앱 종료·launchctl·defaults·tccutil·관리자 암호를 하지 않음
-- 상태는 property/global에 두지 않음 (애플릿이 끝날 때 저장하려 해서 서명이 깨짐)
use AppleScript version "2.5"
use framework "Foundation"
use framework "AppKit"
use scripting additions

on run
	uninstallIn("@@TARGETS@@", POSIX path of (path to home folder), "", "", false)
end run

on appTitle()
	return "@@TITLE@@"
end appTitle

-- tg: "pick" "ydot" "yap" "yinsta"를 쉼표로 · home: 끝이 / · root: 실제는 "" (시험은 가짜 루트) · fakeTrash: 시험 때 옮길 폴더
on uninstallIn(tg, home, root, fakeTrash, testMode)
	if home does not end with "/" then set home to home & "/"
	if testMode then
		set guard to "/Desktop/cc/작업중/시험/"
		if home does not contain guard or root does not contain guard or fakeTrash does not contain guard then error "시험 경로가 아니에요: " & home
	else
		if root is not "" or fakeTrash is not "" then error "실제 실행에는 가짜 경로를 쓸 수 없어요"
	end if
	set wantPick to (tg contains "pick")
	set wantYdot to (tg contains "ydot")
	set wantYap to (tg contains "yap")
	set wantInsta to (tg contains "yinsta")
	set apps to root & "/Applications/"
	set uapps to home & "Applications/"
	set L to home & "Library/"
	set its_ to {} -- 휴지통으로 옮길 것
	set adminIts to {} -- 관리자 권한으로 지울 것 (포토샵 앱 폴더)
	set emptyDirs to {} -- 비면 지울 폴더 (안쪽부터)
	set ids to {}
	set appIDs to {}
	set c1 to L & "Scripts/Capture One Scripts/"
	set oldPS to {"ydot 가이드.jsx", "ydot 인화.jsx", "ydot 원래대로.jsx"}

	-- Pick
	if wantPick then
		repeat with d in {apps, uapps}
			my addApp(its_, (d as text) & "Pick.app", "com.cc.pick")
		end repeat
		if my exists_(L & "Application Support/Pick/ratings.json") then my add(its_, L & "Application Support/Pick")
		my add(its_, L & "Caches/Pick") -- 미리보기 캐시 (다시 만들 수 있는 것만 있음)
		set end of ids to "com.cc.pick"
		set end of appIDs to "com.cc.pick"
	end if
	-- Pick.scpt (캡쳐원 메뉴 Pick 항목): Pick 몫
	if wantPick then
		set p to c1 & "Pick.scpt"
		if my hasMarker(p, {"com.cc.pick", "pick://"}) then my add(its_, p)
	end if

	set cc to L & "Application Support/cc/"
	-- ydot (= Shift Convert. 새 ydot.app은 com.cc.donut, 예전 한 몸 ydot은 com.cc.scriptmenu, 더 옛날 Shift Convert.app)
	if wantYdot then
		repeat with d in {apps, uapps}
			my addApp(its_, (d as text) & "ydot.app", "com.cc.donut")
			my addApp(its_, (d as text) & "Shift Convert.app", "com.cc.donut")
			if not wantYap then my addApp(its_, (d as text) & "ydot.app", "com.cc.scriptmenu") -- 예전 한 몸 ydot (yap을 같이 지울 땐 아래에서)
		end repeat
		my add(its_, L & "LaunchAgents/com.cc.donut.plist")
		repeat with n in {"ydot_guide.jsx", "ydot_print.jsx", "ydot_ps_state.txt"} & oldPS
			my add(its_, cc & (n as text))
		end repeat
		set end of emptyDirs to cc
		-- 옛 버전이 사용자 포토샵 폴더에 넣던 스크립트
		set adobe to L & "Application Support/Adobe/"
		repeat with v in my children(adobe)
			if (v as text) starts with "Adobe Photoshop" then
				repeat with n in oldPS
					my add(its_, adobe & v & "/Presets/Scripts/" & n)
				end repeat
			end if
		end repeat
		-- 포토샵 앱 폴더 스크립트 (관리자 권한)
		repeat with v in my children(apps)
			if (v as text) starts with "Adobe Photoshop" then
				repeat with n in {"ydot_guide.jsx", "ydot_print.jsx"} & oldPS
					my add(adminIts, apps & v & "/Presets/Scripts/" & n)
				end repeat
			end if
		end repeat
		set ids to ids & {"com.cc.donut", "com.cc.ydot-shared"}
		set end of appIDs to "com.cc.donut"
	end if

	-- yap (= 스크립트 메뉴. 예전 한 몸 ydot도 이 번들 ID)
	if wantYap then
		repeat with d in {apps, uapps}
			my addApp(its_, (d as text) & "yap.app", "com.cc.scriptmenu")
			my addApp(its_, (d as text) & "ydot.app", "com.cc.scriptmenu")
		end repeat
		my add(its_, L & "LaunchAgents/com.cc.scriptmenu.plist")
		-- 캡쳐원 스크립트: 우리 도우미(Application Support/cc)를 부르는 것만 (New Session · Delete Session · Export · 옛 이름). Pick.scpt는 Pick 몫
		repeat with n in my children(c1)
			set n to n as text
			if n is not "Pick.scpt" and (n ends with ".scpt" or n ends with ".applescript") then
				if my hasMarker(c1 & n, {"Application Support/cc"}) then my add(its_, c1 & n)
			end if
		end repeat
		-- 스크립트 메뉴 폴더 (지금 yap_scripts, 옛 ydot_scripts · cc 스크립트): 우리 스크립트만, 사용자가 넣은 건 남김
		repeat with sd in {"yap_scripts", "ydot_scripts", "cc 스크립트"}
			set base to L & "Scripts/" & sd & "/"
			repeat with sub in {"Photoshop/", ""}
				set dd to base & sub
				repeat with n in my children(dd)
					set n to n as text
					if n ends with ".scpt" or n ends with ".applescript" then
						if my hasMarker(dd & n, {"Application Support/cc"}) then my add(its_, dd & n)
					end if
				end repeat
			end repeat
			set end of emptyDirs to base & "Photoshop"
			set end of emptyDirs to base
		end repeat
		-- 도우미 폴더: yap 파일만 (같은 폴더를 다른 프로그램이 쓸 수 있음)
		repeat with n in {"airdropsend", "cctool", "exportui", "psexportui", "rawjpg", "rotate", "sessionui", "c1job.sh", "export.jsx", "info.jsx", "yap-version", "ydot-version"}
			my add(its_, cc & (n as text))
		end repeat
		set end of emptyDirs to cc
		set end of ids to "com.cc.scriptmenu"
		set end of appIDs to "com.cc.scriptmenu"
	end if

	-- yinsta
	if wantInsta then
		repeat with d in {apps, uapps}
			my addApp(its_, (d as text) & "yinsta.app", "com.cc.yinsta")
		end repeat
		set ys to L & "Application Support/yinsta"
		if (my exists_(ys & "/posts.json")) or (my exists_(ys & "/settings.json")) then my add(its_, ys)
		set end of ids to "com.cc.yinsta"
		set end of appIDs to "com.cc.yinsta"
	end if

	-- 번들 ID 이름으로 된 것 (설정 · 캐시 · 웹 저장소 · 창 상태)
	repeat with i in ids
		set i to i as text
		repeat with p in {"Preferences/" & i & ".plist", "Caches/" & i, "WebKit/" & i, "HTTPStorages/" & i, "HTTPStorages/" & i & ".binarycookies", "Saved Application State/" & i & ".savedState"}
			my add(its_, L & p)
		end repeat
	end repeat

	-- 확인
	set nameT to appTitle()
	if testMode then set nameT to tg
	if (count of its_) + (count of adminIts) is 0 then
		if testMode then return "없음"
		display dialog "이 맥에는 지울 " & nameT & " 파일이 없어요." buttons {"확인"} default button 1 with title nameT & " 제거" with icon note
		return
	end if
	if not testMode then
		set msg to "아래 " & ((count of its_) + (count of adminIts)) & "개를 지워요. 휴지통으로 옮기니 필요하면 꺼낼 수 있어요." & return & return
		repeat with p in its_
			set msg to msg & "• " & my shortPath(p as text, home) & return
		end repeat
		repeat with p in adminIts
			set msg to msg & "• " & my shortPath(p as text, home) & "  (암호를 받아 바로 지움)" & return
		end repeat
		if wantPick then set msg to msg & return & "데스크톱 '세션' 폴더와 사진은 그대로 둬요."
		display dialog msg buttons {"취소", "제거"} default button "제거" cancel button "취소" with title nameT & " 제거" with icon caution
	end if

	set logT to ""
	-- 1) 앱 끄기 · 로그인 자동 실행 해제
	if testMode then
		set logT to logT & "(건너뜀) 앱 끄기 " & my joinT(appIDs) & linefeed
		if wantYap then set logT to logT & "(건너뜀) launchctl bootout com.cc.scriptmenu" & linefeed
		if wantYdot then set logT to logT & "(건너뜀) launchctl bootout com.cc.donut" & linefeed
	else
		repeat with i in appIDs
			my quitApp(i as text)
		end repeat
		if wantYap then do shell script "launchctl bootout gui/$(id -u)/com.cc.scriptmenu 2>/dev/null; true"
		if wantYdot then do shell script "launchctl bootout gui/$(id -u)/com.cc.donut 2>/dev/null; true"
		repeat with i in ids
			do shell script "defaults delete " & quoted form of (i as text) & " 2>/dev/null; true"
		end repeat
	end if
	-- 2) 휴지통으로
	set fm to current application's NSFileManager's defaultManager()
	set failed to {}
	set k to 0
	repeat with p in its_
		set p to p as text
		set k to k + 1
		if testMode then
			set dst to fakeTrash & k & "_" & (do shell script "basename " & quoted form of p)
			set {ok, e} to fm's moveItemAtPath:p toPath:dst |error|:(reference)
			if ok then set logT to logT & "휴지통 " & p & linefeed
		else
			set {ok, e} to fm's trashItemAtURL:(current application's NSURL's fileURLWithPath:p) resultingItemURL:(missing value) |error|:(reference)
		end if
		if not ok then set end of failed to p
	end repeat
	-- 3) 포토샵 앱 폴더 (관리자)
	set adminNote to ""
	if (count of adminIts) > 0 then
		if testMode then
			repeat with p in adminIts
				set k to k + 1
				fm's moveItemAtPath:(p as text) toPath:(fakeTrash & k & "_admin_" & (do shell script "basename " & quoted form of (p as text))) |error|:(missing value)
				set logT to logT & "관리자 지움 " & p & linefeed
			end repeat
		else
			set cmd to "rm -f"
			repeat with p in adminIts
				set cmd to cmd & " " & quoted form of (p as text)
			end repeat
			try
				do shell script cmd with prompt nameT & " 제거: 포토샵 스크립트 메뉴의 ydot 스크립트를 지우려고 해요." with administrator privileges
			on error
				set adminNote to return & "포토샵 스크립트는 암호를 취소해서 남아 있어요. 다시 열면 지울 수 있어요."
			end try
		end if
	end if
	-- 4) 비어 있게 된 폴더 (안에 .DS_Store만 있어도 빈 것으로)
	repeat with d in emptyDirs
		set d to d as text
		if my exists_(d) then
			set kids to my children(d)
			if kids is {} or kids is {".DS_Store"} then
				fm's removeItemAtPath:d |error|:(missing value)
				set logT to logT & "빈 폴더 지움 " & d & linefeed
			end if
		end if
	end repeat
	-- 5) 권한 목록
	if testMode then
		set logT to logT & "(건너뜀) tccutil reset " & my joinT(appIDs) & linefeed
	else
		repeat with i in appIDs
			do shell script "tccutil reset All " & quoted form of (i as text) & " >/dev/null 2>&1; true"
		end repeat
	end if

	if testMode then
		repeat with p in failed
			set logT to logT & "실패 " & p & linefeed
		end repeat
		return logT
	end if
	set doneMsg to nameT & "을(를) 지웠어요."
	if (count of failed) > 0 then
		set doneMsg to doneMsg & return & return & "옮기지 못한 것:" & return
		repeat with p in failed
			set doneMsg to doneMsg & "• " & my shortPath(p as text, home) & return
		end repeat
	end if
	display dialog doneMsg & adminNote & return & return & "휴지통을 비우면 완전히 없어져요." buttons {"확인"} default button 1 with title nameT & " 제거" with icon note
end uninstallIn

-- ── 도우미 ──
on exists_(p)
	return (current application's NSFileManager's defaultManager()'s fileExistsAtPath:p) as boolean
end exists_

on add(lst, p)
	set p to p as text
	if p ends with "/" then set p to text 1 thru -2 of p
	if my exists_(p) and lst does not contain {p} then set end of lst to p
end add

-- .app은 번들 ID가 맞을 때만 (같은 이름의 다른 앱은 안 건드림)
on isOurApp(p, bid)
	set d to current application's NSDictionary's dictionaryWithContentsOfFile:(p & "/Contents/Info.plist")
	if d is missing value then return false
	set v to d's objectForKey:"CFBundleIdentifier"
	if v is missing value then return false
	return (v as text) is bid
end isOurApp

on addApp(lst, p, bid)
	if my isOurApp(p, bid) then my add(lst, p)
end addApp

on children(d)
	set r to (current application's NSFileManager's defaultManager()'s contentsOfDirectoryAtPath:d |error|:(missing value))
	if r is missing value then return {}
	return r as list
end children

-- 스크립트 안에 우리 표시 글자가 있는지 (.scpt는 풀어서 읽음)
on hasMarker(p, marks)
	if not my exists_(p) then return false
	set t to ""
	try
		if p ends with ".scpt" then
			set t to do shell script "osadecompile " & quoted form of p
		else
			set s to current application's NSString's stringWithContentsOfFile:p encoding:4 |error|:(missing value)
			if s is not missing value then set t to s as text
		end if
	end try
	repeat with m in marks
		if t contains (m as text) then return true
	end repeat
	return false
end hasMarker

on quitApp(bid)
	set ra to current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:bid
	if (count of (ra as list)) is 0 then return
	repeat with a in (ra as list)
		a's terminate()
	end repeat
	repeat 20 times
		if (count of ((current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:bid) as list)) is 0 then return
		delay 0.1
	end repeat
	repeat with a in ((current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:bid) as list)
		a's forceTerminate()
	end repeat
	delay 0.3
end quitApp

on shortPath(p, home)
	if p starts with home then return "~/" & text ((length of home) + 1) thru -1 of p
	return p
end shortPath

on joinT(lst)
	set AppleScript's text item delimiters to ", "
	set t to lst as text
	set AppleScript's text item delimiters to ""
	return t
end joinT
