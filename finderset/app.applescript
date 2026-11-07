set r to POSIX path of (path to me) & "Contents/Resources/"
display dialog "이 맥의 Finder 설정을 ylab 설정으로 바꿀까요?" & return & return & "• 새 창 = 데스크탑, 폴더는 새 창으로 열기" & return & "• 경로 막대·상태 막대 보이기, 폴더를 위로 정렬" & return & "• 검색 = 현재 폴더, 아이콘 보기 크기, 도구 막대 버튼" & return & return & "Finder 창이 잠깐 닫혔다가 다시 열립니다." buttons {"취소", "적용"} default button "적용" cancel button "취소" with title "Finder 설정" with icon note
try
	do shell script "/bin/bash " & quoted form of (r & "apply.sh") & " " & quoted form of (r & "finder.plist")
on error e
	display dialog "적용하지 못했습니다." & return & e buttons {"확인"} default button "확인" with title "Finder 설정" with icon stop
	return
end try
display dialog "적용했습니다." & return & "(원래 설정은 ~/Library/Application Support/ylab에 백업해 두었어요)" buttons {"확인"} default button "확인" with title "Finder 설정"
