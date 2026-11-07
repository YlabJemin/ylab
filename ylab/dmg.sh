#!/bin/zsh
# 앱별 디스크 이미지 → ~/Desktop/ylab/{Pick,ydot,yap,yinsta}.dmg  (안: Install · Uninstall · README, 원본은 ylab/app/<이름>/)
# 각 share.sh 끝(제거 앱 빌드 뒤)에서 자동으로 불림 → 묶음이 바뀌면 dmg도 늘 최신 (사용자 2026-11-05)
set -e
Y=~/Desktop/ylab
for n in Pick ydot yap yinsta; do
  src="$Y/app/$n"; [ -d "$src" ] || continue
  tmp=$(mktemp -d)/"$n.dmg"
  hdiutil create -quiet -volname "$n" -srcfolder "$src" -fs HFS+ -format UDZO -ov "$tmp"   # HFS+ = 예전 맥에서도 열림
  mv -f "$tmp" "$Y/$n.dmg"; rmdir "${tmp:h}" 2>/dev/null || true
  echo "dmg: $Y/$n.dmg"
done
