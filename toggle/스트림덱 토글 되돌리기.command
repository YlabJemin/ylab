#!/bin/zsh
# 더블클릭: 토글 적용 전으로 되돌림 (원래 앱 열기 + 길게 누르면 종료)
cd "${0:A:h}"
osascript -e 'tell application "Elgato Stream Deck" to quit' 2>/dev/null; sleep 3
python3 apply_streamdeck.py --undo
open -a "Elgato Stream Deck"
echo; echo "되돌렸어요. 이 창은 닫아도 돼요."
