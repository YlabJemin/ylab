#!/bin/zsh
# wacom-scroll 빌드·서명·설치 (cc-codesign 서명이라 다시 빌드해도 권한 유지)
cd "$(dirname "$0")"
swiftc -O wacom-scroll.swift -o wacom-scroll || exit 1
codesign -f -s cc-codesign -i com.cc.wacom-scroll wacom-scroll || exit 1
cp wacom-scroll ~/Library/Application\ Support/cc/
launchctl kickstart -k gui/$(id -u)/com.cc.wacom-scroll
