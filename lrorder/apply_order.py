# 라이트룸 카탈로그에서 한 폴더의 '사용자 순서'를 order.json 순서로 바꿈 (보정 값은 건드리지 않음)
# 사용법: python3 apply_order.py <카탈로그.lrcat> <폴더 id_local> <order.json> [--dry]
# 바꾸는 것: Adobe_images.positionInFolder (그 폴더 사진만), AgFolderContent 정렬 방식 → user / ascending
# 안전장치: 라이트룸이 열려 있으면(.lock 파일) 중단, 한 트랜잭션, 바꾸기 전후 보정·메타데이터 해시 비교(다르면 되돌림)
import sys, os, json, sqlite3, hashlib

cat, folder, order_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
DRY = '--dry' in sys.argv
if os.path.exists(cat + '.lock'): raise SystemExit('라이트룸이 이 카탈로그를 열고 있어요(.lock 있음). 라이트룸을 끄고 다시 실행하세요.')
order = json.load(open(order_path))['order']

# 라이트룸 정렬 문자열 알파벳 (WFSortOrderStrings lex64, 글자 순서 = 정렬 순서)
AL = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz'
def pos(i, n):                       # 0..n-1 → 'z'(기본값)보다 앞에 고르게 퍼진 두 글자
    v = (i + 1) * (62 * 64) // (n + 1)
    return AL[v // 64] + AL[v % 64]

def fingerprint(db, ids):
    """사진 보정·메타데이터 관련 테이블의 그 사진 행 해시 (positionInFolder 제외)"""
    h = hashlib.sha256()
    cols = [r[1] for r in db.execute('pragma table_info(Adobe_images)') if r[1] != 'positionInFolder']
    for t, key, cs in (('Adobe_images', 'id_local', cols), ('Adobe_imageDevelopSettings', 'image', None),
                       ('Adobe_AdditionalMetadata', 'image', None), ('AgLibraryIPTC', 'image', None)):
        try:
            sel = ','.join(f'"{c}"' for c in cs) if cs else '*'
            for r in db.execute(f'select {sel} from {t} where {key} in ({",".join("?" * len(ids))}) order by {key}', ids):
                h.update(repr(r).encode())
        except sqlite3.OperationalError:
            pass
    return h.hexdigest()

db = sqlite3.connect(cat)
rows = db.execute('select lf.baseName, i.id_local from AgLibraryFile lf join Adobe_images i on i.rootFile = lf.id_local where lf.folder = ?', (folder,)).fetchall()
idmap = dict(rows)
if sorted(idmap) != sorted(order): raise SystemExit(f'폴더 사진({len(idmap)})과 순서 목록({len(order)})이 달라요: ' + str(set(idmap) ^ set(order)))
ids = [idmap[n] for n in order]
before = fingerprint(db, ids)
print('바꾸기 전 정렬:', db.execute("select content from AgFolderContent where containingFolder=? and owningModule='com.adobe.ag.library.sortType'", (folder,)).fetchall())
try:
    db.execute('begin')
    for i, iid in enumerate(ids):
        db.execute('update Adobe_images set positionInFolder = ? where id_local = ?', (pos(i, len(ids)), iid))
    n = db.execute("update AgFolderContent set content = 'user' where containingFolder = ? and owningModule = 'com.adobe.ag.library.sortType'", (folder,)).rowcount
    db.execute("update AgFolderContent set content = 'ascending' where containingFolder = ? and owningModule = 'com.adobe.ag.library.sortDirection'", (folder,))
    after = fingerprint(db, ids)
    if after != before: raise RuntimeError('보정·메타데이터 해시가 달라짐 → 되돌림')
    got = [r[0] for r in db.execute('select lf.baseName from AgLibraryFile lf join Adobe_images i on i.rootFile = lf.id_local where lf.folder = ? order by i.positionInFolder', (folder,))]
    if got != order: raise RuntimeError('정렬 결과가 순서 목록과 다름 → 되돌림')
    if DRY: raise RuntimeError('시험 실행(--dry) → 되돌림')
    db.commit()
    print(f'완료: {len(ids)}장 순서 저장, 정렬 방식 user ({n}행), 보정·메타데이터 해시 같음')
except Exception as e:
    db.rollback(); print('변경 없음:', e)
    if 'dry' not in str(e): sys.exit(1)
finally:
    print('무결성 검사:', db.execute('pragma quick_check').fetchone()[0]); db.close()
