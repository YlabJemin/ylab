#!/bin/zsh
# typechar 빌드·서명·설치 (cc-codesign 서명이라 다시 빌드해도 권한 유지)
cd "$(dirname "$0")"
swiftc -O typechar.swift -o typechar || exit 1
codesign -f -s cc-codesign -i com.cc.typechar typechar || exit 1
cp typechar ~/Library/Application\ Support/cc/
