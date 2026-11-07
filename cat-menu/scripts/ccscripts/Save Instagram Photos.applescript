-- 사진 저장 (⌘⇧6): 크롬에 띄운 사진을 원본 그대로 바탕화면에 저장
-- 인스타: 선택 창 / 그 밖의 사이트(네이버 블로그 등): 지금 보고 있는 사진 한 장 바로 저장 (websave.py)
-- 선택 창: Enter = 전체 저장(여러 장이면 전부) / 지금 장만 / Esc = 취소
-- 이미 받은 게시물이면: "다시 받을까요?" → 기존 파일은 그대로 두고 ' (2)' 붙여 새로 저장
-- 실제 작업: ~/Library/Application Support/cc/cctool instasave  (크롬 '보기 > 개발자 > Apple Events의 자바스크립트 허용' 필요. 원본 tools/cat-menu/cctool.swift)
set py to quoted form of (POSIX path of (path to application support folder from user domain) & "cc/cctool") & " instasave"
try
	tell application "Google Chrome" to set u to URL of active tab of front window
	if u does not contain "instagram.com" then
		set r to do shell script quoted form of (POSIX path of (path to application support folder from user domain) & "cc/cctool") & " websave 2>&1"
		return "toast:" & (last paragraph of r)
	end if
	set have to (do shell script py & " --check 2>&1") as integer
	activate
	if have > 0 then
		set b to button returned of (display dialog "Already saved (" & have & " photo" & (item (((have > 1) as integer) + 1) of {"", "s"}) & "). Save again?" buttons {"Cancel", "This One", "Save All Again"} default button "This One" cancel button "Cancel" with title "Instagram Save")
		set opt to " --again"
	else
		set b to button returned of (display dialog "Save Instagram photos to Desktop" buttons {"Cancel", "This One", "Save All"} default button "This One" cancel button "Cancel" with title "Instagram Save")
		set opt to ""
	end if
	if b is "This One" then set opt to opt & " --one"
	tell application "Google Chrome" to activate
	set r to do shell script py & opt & " 2>&1"
	return "toast:" & (last paragraph of r) -- 고양이 앱이 화면 위쪽에 잠깐 띄웠다 사라지게 함
on error e number n
	if n is -128 then return "" -- 취소
	return "error:" & e -- 고양이 앱이 오류 창으로 보여줌
end try
