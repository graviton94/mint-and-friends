"""GA(Firebase) 속성 준비 (D-118, CI 전용). 나중에 분석할 때 '수집이 안 되고 있었다'가 없게:
  1) 이벤트 매개변수 · 사용자 속성을 맞춤 측정기준으로 등록 (등록해야 GA 보고서에서 보인다)
  2) 이벤트 데이터 보관 기간 14개월 (기본 2개월)
  3) BigQuery 일일 내보내기 연결 (원본 이벤트 전부, 직접 쿼리용)
사용: python3 tool/ga_setup.py [--apply]  (서비스 계정이 GA 속성 '편집자'여야 바꿀 수 있다)"""
import os, sys
import google.auth
from google.auth.transport.requests import AuthorizedSession

APPLY = '--apply' in sys.argv
cred, project = google.auth.default(scopes=['https://www.googleapis.com/auth/analytics.edit',
                                            'https://www.googleapis.com/auth/cloud-platform'])
s = AuthorizedSession(cred)
project = os.environ.get('PROJECT') or project
r = s.get(f'https://firebase.googleapis.com/v1beta1/projects/{project}/analyticsDetails')
if not r.ok:
    print('analyticsDetails', r.status_code, r.text[:300]); sys.exit(1)
prop = r.json()['analyticsProperty']['id']
ADMIN = f'https://analyticsadmin.googleapis.com/v1alpha/properties/{prop}'
print('GA property', prop, 'project', project, 'apply' if APPLY else 'dry run')

# 1) 맞춤 측정기준
EVENT_PARAMS = {
    'product': '결제 상품', 'krw': '결제 원화', 'kind': '종류', 'step': '단계', 'from': '보여 준 곳',
    'id': '대상 id', 'area': '구역', 'level': '레벨', 'slot': '장식 자리', 'chain': '아이템 계열',
    'lv': '아이템 단계', 'd': '행동 상세', 'key': '열린 이유', 'event': '월간 이벤트', 'pass': '패스 여부',
    'what': '다이아 소비처', 'amount': '양', 'quests': '오늘 퀘스트 수', 'round': '재단장 회차',
    'orders': '부탁 수', 'hour': '시각', 'starter': '첫 구매 노출', 'gems': '다이아 보유', 'left': '남은 다이아',
    'code': '오류 코드', 'via': '경로', 'to': '공유 대상', 'step_name': '튜토리얼 단계',
    'event_step': '이벤트 칸', 'payer': '결제자', 'buys': '결제 횟수', 'piggy': '저금통',
    'friend': '친구', 'seeds': '씨앗', 'decor': '장식 수', 'renew': '재단장', 'coins_e': '코인 자릿수',
}
USER_PROPS = {
    'payer': '결제자', 'pass': '패스 종류', 'lang': '언어', 'renew': '재단장 회차', 'area': '지금 구역',
    'player_level': '플레이어 레벨', 'event_pass': '이벤트 패스',
}
have = set()
page = None
while True:
    r = s.get(f'{ADMIN}/customDimensions', params={'pageSize': 200, **({'pageToken': page} if page else {})})
    if not r.ok:
        print('list dims', r.status_code, r.text[:300]); break
    j = r.json()
    for d in j.get('customDimensions', []):
        have.add((d['scope'], d['parameterName']))
    page = j.get('nextPageToken')
    if not page:
        break
print('dims registered:', len(have))
todo = [('EVENT', k, v) for k, v in EVENT_PARAMS.items() if ('EVENT', k) not in have] + \
       [('USER', k, v) for k, v in USER_PROPS.items() if ('USER', k) not in have]
for scope, name, label in todo:
    print('dim', scope, name)
    if APPLY:
        r = s.post(f'{ADMIN}/customDimensions', json={
            'parameterName': name,
            # 표시 이름은 영문 · 숫자 · 밑줄 · 빈칸만 된다 (한국어 설명은 description 에)
            'displayName': (('user ' if scope == 'USER' else '') + name.replace('_', ' '))[:82],
            'scope': scope, 'description': f'{label} (D-118)'[:150]})
        print('  ->', r.status_code, '' if r.ok else r.text[:200])

# 2) 보관 기간
r = s.get(f'{ADMIN}/dataRetentionSettings')
print('retention', r.status_code, r.json() if r.ok else r.text[:200])
if APPLY and r.ok and r.json().get('eventDataRetention') != 'FOURTEEN_MONTHS':
    r = s.patch(f'{ADMIN}/dataRetentionSettings', params={'updateMask': 'eventDataRetention,resetUserDataOnNewActivity'},
                json={'eventDataRetention': 'FOURTEEN_MONTHS', 'resetUserDataOnNewActivity': True})
    print('  retention ->', r.status_code, r.text[:200])

# 3) BigQuery 내보내기
r = s.get(f'{ADMIN}/bigQueryLinks')
print('bigquery links', r.status_code, r.json() if r.ok else r.text[:300])
if APPLY and r.ok and not r.json().get('bigqueryLinks'):
    r = s.post(f'{ADMIN}/bigQueryLinks', json={
        'project': f'projects/{project}', 'dailyExportEnabled': True, 'streamingExportEnabled': False,
        'datasetLocation': 'asia-northeast3', 'includeAdvertisingId': False})
    print('  bigquery ->', r.status_code, r.text[:300])
print('done' if APPLY else 'dry run: nothing changed')
