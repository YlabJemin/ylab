# 이 맥 Finder 설정에서 다른 맥에 옮길 항목만 뽑아 finder.plist로 (경로·창 위치·기록·iCloud 제외)
import plistlib, subprocess, sys
cur = plistlib.loads(subprocess.run(['defaults','export','com.apple.finder','-'], capture_output=True, check=True).stdout)
KEYS = ['NewWindowTarget','FinderSpawnTab','ShowPathbar','ShowStatusBar','_FXSortFoldersFirst',
        'FXDefaultSearchScope','StandardViewSettings','NSToolbar Configuration Browser','FK_DefaultListViewSettings']
def clean(v):
    if isinstance(v, dict): return {k: clean(x) for k, x in v.items() if not k.startswith('scrollPosition') and k != 'WindowBounds'}
    if isinstance(v, list): return [clean(x) for x in v]
    return v
out = {k: clean(cur[k]) for k in KEYS if k in cur}
if out.get('NewWindowTarget') not in ('PfDe','PfHm','PfDo','PfAF','PfCm','PfID'): out.pop('NewWindowTarget', None)   # 특정 폴더 지정(경로)이면 뺌
plistlib.dump(out, open(sys.argv[1], 'wb'), fmt=plistlib.FMT_XML)
print(' '.join(out))
