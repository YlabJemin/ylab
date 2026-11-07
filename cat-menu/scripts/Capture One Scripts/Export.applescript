-- 캡쳐원 셀렉 내보내기 스크립트 (세션 만들기·지우기와 별개)
-- 캡쳐원 브라우저에서 선택한 사진 → 창에서 고른 종류만 내보냄 (여러 개 가능, 마지막 선택 기억)
--   RAW   : 원래 파일 그대로 복사 (같은 사진은 한 번만, 이름 겹치면 _1 _2 …)
--   원본  : 보정 없는 JPG (이름_원본.jpg) — 캡쳐원을 거치지 않고 rawjpg로 변환
--   보정본: 레시피 cc-select-jpg로 처리 요청 (캡쳐원이 백그라운드 처리, 같은 이름은 번호)
--   카톡용: 원본·보정본 JPG를 20MB 이하로 (화질만 낮춤)
-- 완료 알림: RAW만이면 바로. 원본·보정본이 있으면 c1job.sh가 백그라운드에서 파일이 진짜 다 써진 걸 확인한 뒤 띄움
--   (스크립트는 바로 끝나서 캡쳐원을 붙잡지 않음)
-- 창: exportui (위치 선택, 기본값 저장, 새 폴더 만들기, 종류 체크)
-- 캡쳐원이 꺼져 있으면 켜지 않고 안내만 함
-- 설치 위치: ~/Library/Scripts/Capture One Scripts/ (캡쳐원 스크립트 메뉴 최상위)
-- 원본 소스: ~/Desktop/cc/tools/c1scripts/셀렉 내보내기.applescript
-- 함께 쓰는 것: ~/Library/Application Support/cc/ exportui · rawjpg · c1job.sh
-- (2026-10-29 셀렉 내보내기 + 셀렉 내보내기(jpg) 합침. 이전 것: cc/backup/캡쳐원_스크립트/셀렉내보내기_통합전_*)

property oldRecipeRaw : "cc-select-raw" -- 예전 버전에서 쓰던 이름 (남아 있으면 지움)
property recipeJpg : "cc-select-jpg"

on ccDir()
	return POSIX path of (path to application support folder from user domain) & "cc/"
end ccDir

on ui(argList)
	set cmd to quoted form of (ccDir() & "exportui")
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

-- 원본 파일 복사 (이름이 겹치면 _1 _2 … 붙임, 날짜 유지)
on copyOriginal(src, dir)
	do shell script "f=" & quoted form of src & "; d=" & quoted form of dir & "; b=$(basename \"$f\"); n=\"${b%.*}\"; e=\"${b##*.}\"; t=\"$d/$b\"; i=1; while [ -e \"$t\" ]; do t=\"$d/${n}_$i.$e\"; i=$((i+1)); done; cp -p \"$f\" \"$t\""
end copyOriginal

on run
	-- 1) 캡쳐원이 켜져 있을 때만 (이 확인은 캡쳐원을 켜지 않음)
	if not (application "Capture One" is running) then
		showMessage("캡쳐원에서 사진을 선택한 뒤 실행해 주세요")
		return
	end if

	-- 2) 선택한 사진
	tell application "Capture One"
		set d to current document
		set sel to (variants of d whose selected is true)
	end tell
	set n to count of sel
	if n = 0 then
		showMessage("선택한 사진이 없어요")
		return
	end if

	-- 3) 내보내기 설정 창 (취소·✕면 조용히 끝)
	try
		set res to ui({n as text})
	on error
		return
	end try
	set basePath to paragraph 1 of res
	set folderName to ""
	if (count of paragraphs of res) > 1 then set folderName to paragraph 2 of res
	set kinds to "edit"
	if (count of paragraphs of res) > 2 then set kinds to paragraph 3 of res
	set doRaw to (kinds contains "raw")
	set doOrig to (kinds contains "orig")
	set doEdit to (kinds contains "edit")
	set kakao to "0"
	if (count of paragraphs of res) > 3 then
		if paragraph 4 of res is "kakao" then set kakao to "1"
	end if

	-- 4) 내보낼 곳
	set dest to basePath
	if folderName is not "" then set dest to basePath & "/" & folderName
	do shell script "mkdir -p " & quoted form of dest

	-- 5) 원래 파일 경로 (같은 사진의 변형이 여러 개여도 한 번만)
	set srcPaths to {}
	if doRaw or doOrig then
		tell application "Capture One"
			repeat with v in sel
				set p to path of (parent image of v)
				if srcPaths does not contain p then set end of srcPaths to p
			end repeat
		end tell
	end if
	set srcN to count of srcPaths
	set rawN to 0

	-- 6) RAW 복사
	if doRaw then
		try
			repeat with p in srcPaths
				copyOriginal(p as text, dest)
			end repeat
		on error errMsg
			showMessage("RAW를 복사하지 못했어요: " & errMsg)
			return
		end try
		set rawN to srcN
	end if
	if not (doOrig or doEdit) then
		try
			ui({"done", "내보내기 완료 · RAW " & rawN, dest})
		end try
		return
	end if

	-- 7) 보정본: 레시피로 처리 요청 (처리 전 폴더 목록을 남겨서 새로 생긴 것만 셈)
	set beforeFile to ""
	set editN to 0
	if doEdit then
		try
			set beforeFile to do shell script "mkdir -p ~/Library/Caches/cc && f=$(mktemp ~/Library/Caches/cc/before.XXXXXX) && ls -1 " & quoted form of dest & " > \"$f\" && echo \"$f\""
			tell application "Capture One"
				if exists recipe oldRecipeRaw of d then delete recipe oldRecipeRaw of d
				if not (exists recipe recipeJpg of d) then make new recipe at d with properties {name:recipeJpg}
				set j to recipe recipeJpg of d
				set output format of j to JPEG
				set JPEG quality of j to 100
				set color profile of j to "sRGB Color Space Profile"
				set scaling method of j to Fixed
				set upscale of j to false
				-- 저장 위치: 위치를 먼저 넣어야 종류가 "지정한 폴더"로 바뀜 (종류를 먼저 바꾸면 무시됨)
				set root folder location of j to (POSIX file dest)
				set root folder type of j to custom location
				set output sub folder of j to ""
				set existing files of j to add suffix
				set enabled of j to false
				-- 확인: 지정한 폴더가 아니면 처리하지 않음 (세션 Output 폴더로 새는 것 방지)
				if (root folder type of j) is not custom location then
					error "저장 위치를 설정하지 못했어요"
				end if
				process sel recipe recipeJpg
			end tell
		on error errMsg
			showMessage("보정본 내보내기를 시작하지 못했어요: " & errMsg)
			return
		end try
		set editN to n
	end if

	-- 8) 원본 목록
	set listFile to ""
	if doOrig then
		try
			set listFile to do shell script "mkdir -p ~/Library/Caches/cc && mktemp ~/Library/Caches/cc/rawlist.XXXXXX"
			set AppleScript's text item delimiters to linefeed
			set listText to (srcPaths as text)
			set AppleScript's text item delimiters to ""
			do shell script "printf '%s\\n' " & quoted form of listText & " > " & quoted form of listFile
		on error errMsg
			showMessage("원본 변환을 시작하지 못했어요: " & errMsg)
			return
		end try
	end if

	-- 9) 뒷일은 백그라운드로 (원본 변환 → 보정본 다 써질 때까지 기다림 → 카톡용 → 진짜 끝나면 완료 알림)
	try
		do shell script "nohup /bin/zsh " & quoted form of (ccDir() & "c1job.sh") & " " & quoted form of dest & " " & quoted form of listFile & " " & editN & " " & quoted form of beforeFile & " " & kakao & " " & rawN & " > /dev/null 2>&1 &"
	on error errMsg
		showMessage("내보내기 마무리를 시작하지 못했어요: " & errMsg)
	end try
end run
