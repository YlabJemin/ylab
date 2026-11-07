#!/bin/zsh
# 더블클릭: '펑 캐릭터' 플러그인을 Stream Deck 플러그인 폴더에 복사(새 폴더 추가만)하고 Stream Deck을 다시 켬
cd "${0:A:h}"
DST="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins/com.cc.poofchar.sdPlugin"
osascript -e 'tell application "Elgato Stream Deck" to quit' 2>/dev/null; sleep 3
rm -rf "$DST" 2>/dev/null   # 예전에 설치한 '펑 캐릭터'만 (다른 플러그인 안 건드림)
cp -R "com.cc.poofchar.sdPlugin" "$DST"
open -a "Elgato Stream Deck"
echo; echo "설치했어요. Stream Deck 오른쪽 목록 맨 아래 'cc' → '펑 캐릭터'를 첫 번째 칸으로 끌어다 놓으세요."
