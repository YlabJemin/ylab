-- 에어드롭 보내기 (⌘⇧A): Finder에서 고른 파일을 에어드롭으로 보냄 — 공유 버튼이 여러 장에서 실패하는 문제 대신 쓰는 것
-- 실제 작업: ~/Library/Application Support/cc/airdropsend (원본 ~/Desktop/cc/tools/airdrop/airdropsend.swift)
-- 보내는 동안 고양이 메뉴가 멈추지 않게 따로 실행하고 바로 끝남. 완료·실패 알림은 airdropsend가 띄움
tell application "Finder" to set sel to selection as alias list
if sel is {} then return "toast:Finder에서 보낼 파일을 골라 주세요"
set args to ""
repeat with f in sel
	set p to POSIX path of f
	if p does not end with "/" then set args to args & " " & quoted form of p
end repeat
if args is "" then return "toast:폴더는 보낼 수 없어요 · 파일을 골라 주세요"
do shell script quoted form of (POSIX path of (path to application support folder from user domain) & "cc/airdropsend") & args & " > /dev/null 2>&1 &"
return ""
