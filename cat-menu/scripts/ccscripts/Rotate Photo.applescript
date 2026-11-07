-- Finder에서 선택한 사진을 시계방향 90도 회전
-- JPG·HEIC·TIFF는 다시 압축 없이 방향 정보만 바꿈(화질 그대로), PNG 등은 픽셀 회전, RAW·기타 파일은 건너뜀
-- 실제 작업: ~/Library/Application Support/cc/rotate  (원본: ~/Desktop/cc/tools/rotate/rotate.swift)
try
	tell application "Finder" to set sel to selection as alias list
	if (count of sel) = 0 then return "toast:Select photos in Finder first"
	set args to ""
	repeat with f in sel
		set args to args & " " & quoted form of POSIX path of f
	end repeat
	set r to do shell script quoted form of (POSIX path of (path to application support folder from user domain) & "cc/rotate") & args
	return "toast:" & r
on error e number n
	if n is -128 then return ""
	return "error:" & e
end try
