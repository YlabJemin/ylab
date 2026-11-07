#!/bin/bash
# Finder 설정 적용: 지금 설정을 사본으로 받아 옮길 항목만 바꿔 끼우고 다시 넣음. 처음 한 번은 원래 설정을 백업.
set -e
F="$1"; D="${FINDER_DOMAIN:-com.apple.finder}"   # FINDER_DOMAIN: 시험용
B="$HOME/Library/Application Support/ylab"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$B"
defaults export "$D" "$T/cur.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Print" "$T/cur.plist" >/dev/null 2>&1 || printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n' > "$T/cur.plist"
[ -n "$FINDER_DOMAIN" ] || [ -e "$B/Finder 원래 설정.plist" ] || cp "$T/cur.plist" "$B/Finder 원래 설정.plist"
for k in NewWindowTarget NewWindowTargetPath FinderSpawnTab ShowPathbar ShowStatusBar _FXSortFoldersFirst FXDefaultSearchScope StandardViewSettings "NSToolbar Configuration Browser" FK_DefaultListViewSettings; do
  /usr/libexec/PlistBuddy -c "Delete ':$k'" "$T/cur.plist" >/dev/null 2>&1 || true
  defaults delete "$D" "$k" >/dev/null 2>&1 || true; done   # import는 없는 키를 지우지 않음
/usr/libexec/PlistBuddy -c "Merge '$F'" "$T/cur.plist" >/dev/null
defaults import "$D" "$T/cur.plist"
[ -n "$FINDER_DOMAIN" ] || killall Finder 2>/dev/null || true
