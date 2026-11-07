#!/bin/zsh
# apply.sh <변형> <스타일이름> : 이미지 레이어에 스타일 적용
osascript -e "tell application \"Capture One\"
set v to first variant of document 1 whose name is \"$1\"
apply style (first layer of v whose kind is background) named \"$2\"
end tell"
