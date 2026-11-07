-- 사용: osascript apply_grade.applescript "변형 이름" ["미리보기 접미사"]
-- 레퍼런스 색감(밝은 무채색 배경 + 채도 낮은 핑크빛 피부)을 캡쳐원 변형 하나에 적용
-- 기본: WB 4450K / 틴트 -5 / 노출 +0.3
-- 레이어 "cc 피부"(AI 얼굴+몸 피부): 채도 -45, 노출 +0.2, 틴트 -1.5
-- 레이어 "cc 배경"(AI 사람 전체 마스크 반전): 노출 +1.0, 채도 -60, 색온도 4200
on run argv
	set vname to item 1 of argv
	tell application "Capture One"
		set d to current document
		set v to first variant of d whose name is vname
		-- 이전에 만든 cc 레이어가 있으면 지우고 다시 만듦
		repeat with L in (layers of v whose name starts with "cc ")
			delete L
		end repeat
		tell adjustments of v
			set temperature to 4450
			set tint to -5
			set exposure to 0.3
		end tell
		set sl to item 1 of (create people mask v areas {face skin, body skin} separate layers false)
		set name of sl to "cc 피부"
		tell adjustments of sl
			set saturation to -45
			set exposure to 0.2
			set tint to -1.5
		end tell
		set bl to item 1 of (create people mask v areas {body skin, face skin, eyebrows, lips, hair, iris and pupil, sclera, clothes} separate layers false)
		set name of bl to "cc 배경"
		invert mask bl
		tell adjustments of bl
			set exposure to 1.0
			set saturation to -60
			set temperature to 4200
		end tell
		if (count of argv) > 1 then
			set r to recipe "cc 미리보기" of d
			set output name format of r to "[이미지 이름]" & (item 2 of argv)
			process v recipe "cc 미리보기"
		end if
	end tell
end run
