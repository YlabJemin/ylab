#!/bin/zsh
# 더블클릭: 타임트리 로그인(이메일·비밀번호는 이 창에 직접 입력, 어디에도 저장 안 함) → 고른 캘린더를 .ics 파일로 저장
# 캘린더가 여러 개면 한 번 더 실행해서 다른 캘린더를 고르면 됨 (파일 이름에 시간이 붙어서 덮어쓰지 않음)
cd "${0:A:h}"
export PYTHONWARNINGS=ignore
OUT="$HOME/Desktop/cc/작업중/timetree/타임트리_$(date +%Y%m%d_%H%M%S).ics"
echo "타임트리 이메일과 비밀번호를 입력하세요. (비밀번호는 화면에 * 로 보여요)"; echo
./venv/bin/python -m timetree_exporter -o "$OUT" && { echo; echo "저장됨: $OUT"; open -R "$OUT"; } || echo "실패했어요. 이 창 내용을 cc에게 알려주세요."
echo; echo "이 창은 닫아도 돼요."
