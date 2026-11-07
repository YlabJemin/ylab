-- 캡쳐원 세션 지우기 스크립트
-- 대상: 데스크톱의 "캡쳐원 전용" 폴더 바로 아래에 있는 세션 폴더만 다룸 (하위 폴더 재귀 탐색 안 함)
-- 세션 판별: 폴더 안에 ".cosessiondb" 확장자 파일이 있으면 캡쳐원 세션으로 인식
-- 창: 다크모드 전용 창 프로그램(~/Library/Application Support/cc/sessionui)으로 표시
--     체크박스 목록 + 전체 선택 → "세션을 지우시겠습니까?" → "세션을 지웠습니다☺️"
-- 삭제 방식: 완전 삭제가 아니라 휴지통으로 이동 (복구 가능)
-- 설치 위치: ~/Library/Scripts/Capture One Scripts/ (캡쳐원 스크립트 메뉴 최상위)
-- 원본 소스: ~/Desktop/cc/tools/c1scripts/세션 지우기.applescript

property targetFolderName : "캡쳐원 전용"

on ui(argList)
	set uiPath to POSIX path of (path to application support folder from user domain) & "cc/sessionui"
	set cmd to quoted form of uiPath
	repeat with a in argList
		set cmd to cmd & " " & quoted form of (a as text)
	end repeat
	return do shell script cmd
end ui

on showMessage(msg)
	try
		ui({"msg", msg})
	end try
end showMessage

on run
	set desktopFolder to path to desktop folder

	tell application "Finder"
		if not (exists folder targetFolderName of desktopFolder) then
			set missingFolder to true
		else
			set missingFolder to false
			set targetFolder to folder targetFolderName of desktopFolder
			set sessionFolders to {}
			set candidateFolders to every folder of targetFolder
			repeat with f in candidateFolders
				set dbFiles to (every file of f whose name extension is "cosessiondb")
				if (count of dbFiles) > 0 then
					set end of sessionFolders to f
				end if
			end repeat
		end if
	end tell

	if missingFolder then
		showMessage("'" & targetFolderName & "' 폴더가 데스크톱에 없습니다.")
		return
	end if
	if (count of sessionFolders) = 0 then
		showMessage("'" & targetFolderName & "' 안에 지울 수 있는 캡쳐원 세션이 없습니다.")
		return
	end if

	set sessionNames to {}
	repeat with f in sessionFolders
		tell application "Finder" to set end of sessionNames to (name of f)
	end repeat

	-- 체크박스 목록 + 확인창 (취소하면 오류로 끝나므로 조용히 종료)
	try
		set picked to ui({"choose"} & sessionNames)
	on error
		return
	end try
	if picked is "" then return
	set pickedNames to paragraphs of picked

	tell application "Finder"
		repeat with f in sessionFolders
			if pickedNames contains (name of f) then delete f
		end repeat
	end tell

	try
		ui({"msg", "세션 제거 완료", "1"}) -- 1초 뒤 자동으로 닫힘
	end try
end run
