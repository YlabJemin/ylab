-- 캡쳐원 세션 삭제 스크립트
-- 대상: 데스크톱의 "캡쳐원 전용" 폴더 바로 아래에 있는 세션 폴더만 다룸 (하위 폴더 재귀 탐색 안 함)
-- 세션 판별: 폴더 안에 ".cosessiondb" 확장자 파일이 있으면 캡쳐원 세션으로 인식
-- 여러 개 선택 가능 (⌘ 또는 ⇧ 누르고 클릭)
-- 삭제 방식: 완전 삭제가 아니라 휴지통으로 이동 (복구 가능), 반드시 확인창을 거침
-- 설치 위치: ~/Library/Scripts/Capture One Scripts/ (캡쳐원 스크립트 메뉴 최상위)
-- 원본 소스: ~/Desktop/cc/tools/c1scripts/세션 삭제.applescript

property targetFolderName : "캡쳐원 전용"

on run
	set desktopFolder to path to desktop folder

	tell application "Finder"
		if not (exists folder targetFolderName of desktopFolder) then
			display dialog "'" & targetFolderName & "' 폴더가 데스크톱에 없습니다." buttons {"확인"} default button 1 with icon caution
			return
		end if

		set targetFolder to folder targetFolderName of desktopFolder
		set candidateFolders to every folder of targetFolder

		set sessionFolders to {}
		repeat with f in candidateFolders
			set dbFiles to (every file of f whose name extension is "cosessiondb")
			if (count of dbFiles) > 0 then
				set end of sessionFolders to f
			end if
		end repeat
	end tell

	if (count of sessionFolders) = 0 then
		display dialog "'" & targetFolderName & "' 안에 삭제할 수 있는 캡쳐원 세션이 없습니다." buttons {"확인"} default button 1 with icon note
		return
	end if

	set sessionNames to {}
	repeat with f in sessionFolders
		tell application "Finder" to set end of sessionNames to (name of f)
	end repeat

	set chosenList to choose from list sessionNames with title "캡쳐원 세션 삭제" with prompt "삭제할 세션을 선택하세요 (⌘ 누르고 클릭하면 여러 개 선택):" OK button name "확인" cancel button name "취소" with multiple selections allowed

	if chosenList is false then return

	-- 선택한 이름과 일치하는 실제 폴더 참조 찾기
	set targetSessions to {}
	set chosenText to ""
	repeat with chosenName in chosenList
		repeat with f in sessionFolders
			tell application "Finder"
				if (name of f) is (chosenName as text) then set end of targetSessions to f
			end tell
		end repeat
		set chosenText to chosenText & "「" & chosenName & "」" & return
	end repeat

	if (count of targetSessions) = 0 then return

	set confirmResult to display dialog "세션을 삭제하시나요?" & return & return & chosenText buttons {"취소", "확인"} default button "취소" cancel button "취소" with title "캡쳐원 세션 삭제" with icon caution

	if button returned of confirmResult is "확인" then
		tell application "Finder"
			repeat with s in targetSessions
				delete s
			end repeat
		end tell
		display dialog "세션을 삭제했습니다:)" buttons {"확인"} default button 1 with title "캡쳐원 세션 삭제" with icon note
	end if
end run
