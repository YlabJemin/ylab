#!/bin/zsh
# 더블클릭: Stream Deck을 잠깐 끄고 → '제민' 프로필 버튼 7개를 토글 앱으로 바꾸고 → 다시 켬 (아이콘 그대로, 원본은 자동 백업)
cd "${0:A:h}"
osascript -e 'tell application "Elgato Stream Deck" to quit' 2>/dev/null; sleep 3
python3 apply_streamdeck.py
open -a "Elgato Stream Deck"
echo; echo "끝났어요. 이 창은 닫아도 돼요."
