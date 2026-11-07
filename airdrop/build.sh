#!/bin/zsh
# airdropsend 빌드·서명·설치
cd "$(dirname "$0")"
swiftc -O airdropsend.swift -o airdropsend || exit 1
codesign -f -s cc-codesign -i com.cc.airdropsend airdropsend || exit 1
cp airdropsend ~/Library/Application\ Support/cc/
