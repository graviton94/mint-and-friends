"""비공개 테스트 접속 현황 (개인정보 없이 숫자만): Firebase Auth 마지막 접속 + Firestore 저장 진행도.
CI 에서 ACCESS_TOKEN · PROJECT 로 실행한다."""
import json, os, time, urllib.request
from collections import Counter

P, T = os.environ['PROJECT'], os.environ['ACCESS_TOKEN']
H = {'Authorization': f'Bearer {T}', 'Content-Type': 'application/json',
     'x-goog-user-project': P}

def call(url, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers=H, method='POST' if body is not None else 'GET')
    with urllib.request.urlopen(req) as r:
        return json.load(r)

now = time.time() * 1000
DAY = 86400000

# ---- Auth: 가입 · 마지막 접속 (토큰 갱신)
users, off = [], 0
while True:
    r = call(f'https://identitytoolkit.googleapis.com/v1/projects/{P}/accounts:query',
             {'returnUserInfo': True, 'limit': '500', 'offset': str(off)})
    batch = r.get('userInfo', [])
    users += batch
    off += len(batch)
    if len(batch) < 500: break
def last(u): return max(int(u.get('lastRefreshAt') and time.mktime(time.strptime(u['lastRefreshAt'][:19], '%Y-%m-%dT%H:%M:%S')) * 1000 or 0), int(u.get('lastLoginAt', 0)))
print(f'== 계정 {len(users)}명')
for d in (1, 3, 7):
    print(f'  최근 {d}일 접속: {sum(1 for u in users if now - last(u) < d * DAY)}명')
joined = Counter(time.strftime('%m-%d', time.gmtime(int(u.get('createdAt', 0)) / 1000)) for u in users)
print('  가입일별:', dict(sorted(joined.items())[-14:]))
prov = Counter((u.get('providerUserInfo') or [{}])[0].get('providerId', 'guest/custom') for u in users)
print('  로그인 방식:', dict(prov))

# ---- Firestore: 저장된 진행도
docs, tok = [], ''
while True:
    u = f'https://firestore.googleapis.com/v1/projects/{P}/databases/(default)/documents/users?pageSize=300' + (f'&pageToken={tok}' if tok else '')
    r = call(u)
    docs += r.get('documents', [])
    tok = r.get('nextPageToken')
    if not tok: break
rows = []
for d in docs:
    raw = d.get('fields', {}).get('data', {}).get('stringValue')
    if not raw: continue
    j = json.loads(raw)
    upd = time.mktime(time.strptime(d['updateTime'][:19], '%Y-%m-%dT%H:%M:%S')) * 1000
    up = j.get('up', {})
    rows.append((round((now - upd) / 3600000, 1), j.get('level'), j.get('area'), up.get('basketTier', 0),
                 up.get('teaPower', 0), j.get('hi', {}), sum(1 for x in j.get('store', []) if x)))
rows.sort()
print(f'\n== 클라우드 저장 {len(rows)}개 (최근 저장 순) : 몇시간전 | Lv | 구역 | 바구니등급 | 찻잎강화 | 체인별 최고단계 | 보관함 칸 사용')
for r in rows:
    print('  ', *r)
