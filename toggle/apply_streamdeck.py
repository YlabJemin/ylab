# Stream Deck '제민' 프로필 버튼을 토글 앱으로 바꿈 (아이콘·위치 그대로). 누르면 토글, 길게 누르기 기능 없음
# 사용법: python3 apply_streamdeck.py [프로필 폴더]   (기본: 실제 '제민' 프로필 페이지)  --undo 로 되돌리기(백업 복원)
import json, os, sys, shutil, time
PAGE = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else os.path.expanduser(
    '~/Library/Application Support/com.elgato.StreamDeck/ProfilesV3/AF7AC0EE-2F4F-4C74-9B5A-CB4696FACCB0.sdProfile/Profiles/B32BE563-838F-4E6D-8E86-125C229288D5')
T = os.path.expanduser('~/Library/Application Support/cc/토글')
MAP = {'com.anthropic.claudefordesktop': 'Claude 토글', 'com.microsoft.VSCode': 'Claude Code 토글', 'com.adobe.Photoshop': '포토샵 토글',
       'com.adobe.LightroomClassicCC7': '라이트룸 토글', 'com.cclian.Evoto': '이보토 토글', 'com.captureone.captureone16': '캡쳐원 토글',
       'com.kakao.KakaoTalkMac': '카톡 토글'}
man = os.path.join(PAGE, 'manifest.json'); bak = man + '.cc_before_toggle'
if '--undo' in sys.argv:
    shutil.copy2(bak, man); print('되돌림:', man); sys.exit()
d = json.load(open(man))
if not os.path.exists(bak): shutil.copy2(man, bak)                 # 처음 한 번만 원본 백업
n = 0
for k, v in d['Controllers'][0]['Actions'].items():
    s = v.get('Settings') or {}
    target = s.get('cc_toggle_target') or s.get('bundle_id')
    if v.get('UUID') != 'com.elgato.streamdeck.system.openapp' or target not in MAP: continue
    app = f'{T}/{MAP[target]}.app'
    # 버튼 = 토글 앱 (길게 누르기 없음)
    s.update({'cc_toggle_target': target, 'app_name': MAP[target], 'bundle_id': 'com.cc.toggle.' + target.split('.')[-1].lower(),
              'bundle_path': app, 'source': app, 'exec': f'{app}/Contents/MacOS/toggle', 'is_bundle': True,
              'bring_to_front': False, 'long_press': 'none'})
    v['Settings'] = s; n += 1; print(f'  {k}: {target} → {MAP[target]}')
json.dump(d, open(man, 'w'), ensure_ascii=False, indent=None, separators=(',', ':'))
print(f'{n}개 버튼 변경 (아이콘 그대로). 백업: {bak}')
