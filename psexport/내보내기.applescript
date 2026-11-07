-- 포토샵 내보내기 (고양이 메뉴 Photoshop 묶음, ~/Library/Scripts/cc 스크립트/Photoshop/): 열린 문서에서 원하는 문서·레이어를 골라 JPG로 내보냄 (현재 레이어 / 원본(맨 아래) / 직접 고른 레이어, 각각 따로)
-- 실제 작업: ~/Desktop/cc/tools/psexport/run.py (창: ~/Library/Application Support/cc/psexportui)
try
	set r to do shell script "/usr/bin/python3 " & quoted form of (POSIX path of (path to home folder) & "Desktop/cc/tools/psexport/run.py") & " 2>&1"
	if r is "" then return ""
	return last paragraph of r
on error e
	return "error:" & e
end try
