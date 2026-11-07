-- 캡쳐원 세션 만들기 스크립트
-- 실행 → (캡쳐원 꺼져 있으면 켜고 로딩 끝날 때까지 대기) → 새 세션 이름 입력 창(다크 글래스, sessionui input)
--       → 데스크톱/캡쳐원 전용 안에 세션 생성 → 원래 창은 저장 후 닫아 새 세션 창 하나만 남김
-- 캡쳐원이 이미 켜져 있으면 바로 이름 입력 창
-- 이름 검사(빈 이름·/·:·이미 있는 이름)는 입력 창에서 함
-- 설치 위치: ~/Library/Scripts/Capture One Scripts/ (캡쳐원 스크립트 메뉴 최상위)
-- 원본 소스: ~/Desktop/cc/tools/c1scripts/세션 만들기.applescript

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

	-- 저장 위치 준비 + 이미 있는 이름 모으기
	tell application "Finder"
		if not (exists folder targetFolderName of desktopFolder) then
			make new folder at desktopFolder with properties {name:targetFolderName}
		end if
		set targetFolder to folder targetFolderName of desktopFolder
		set existingNames to name of every folder of targetFolder
		set targetPath to POSIX path of (targetFolder as alias)
	end tell

	-- 캡쳐원 켜기 (꺼져 있을 때만) → 스크립트 명령을 받을 수 있을 때까지 기다림
	if not (application "Capture One" is running) then
		-- 캡쳐원은 켜질 때 마지막 세션을 다시 엶. 그 세션이 휴지통에 있거나 없어졌으면
		-- "세션을 열 수 없습니다" 오류가 뜨고, 기억을 지우면 카탈로그를 새로 만들어 버림
		-- → 기억된 세션이 쓸 수 없을 때만 캡쳐원 전용의 가장 최근 세션으로 바꿔둠
		try
			do shell script "
k=com.captureone.captureone16
u=$(defaults read $k keySessionURL 2>/dev/null)
p=$(python3 -c 'import sys,urllib.parse as q; print(q.unquote(sys.argv[1]).replace(\"file://\",\"\"))' \"$u\" 2>/dev/null)
if [ -z \"$u\" ] || [ ! -e \"$p\" ] || echo \"$p\" | grep -q '/.Trash/'; then
  new=$(ls -t " & quoted form of targetPath & "*/*.cosessiondb 2>/dev/null | head -1)
  if [ -n \"$new\" ]; then
    url=$(python3 -c 'import sys,pathlib; print(pathlib.Path(sys.argv[1]).as_uri())' \"$new\")
    defaults write $k keySessionURL -string \"$url\"
    defaults write $k openedSessionURLs5 -array \"$url\"
  fi
fi"
		end try
		tell application "Capture One" to launch
		set ready to false
		repeat 300 times -- 최대 약 5분 (시작 창이 떠 있으면 닫을 때까지)
			try
				with timeout of 2 seconds
					tell application "Capture One" to count documents
				end timeout
				set ready to true
				exit repeat
			end try
			delay 1
		end repeat
		delay 1 -- 로딩 화면이 사라질 여유
		if not ready then
			showMessage("캡쳐원이 준비되지 않아서 세션을 만들지 못했어요")
			return
		end if
	end if

	-- 이름 입력 (취소·✕면 조용히 끝)
	try
		set newName to ui({"input"} & existingNames)
	on error
		return
	end try
	if newName is "" then return

	-- 새 세션 만들기
	try
		with timeout of 600 seconds
			tell application "Capture One"
				set oldDocs to every document -- 원래 열려 있던 창들
				make new document with properties {name:newName, path:(POSIX file targetPath), kind:session}
				-- 스크립트로 만들면 항상 새 창이 뜸 → 원래 창은 저장하고 닫아 새 세션 창 하나만 남김 (지우지 않음)
				repeat with d in oldDocs
					try
						save d
						close d
					end try
				end repeat
				activate
			end tell
		end timeout
	on error errMsg
		showMessage("세션을 만들지 못했어요: " & errMsg)
	end try
end run
