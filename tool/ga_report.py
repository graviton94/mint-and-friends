"""Google Analytics(Firebase) 지표 요약 (CI 전용, 서비스 계정 = GA 속성 뷰어).
사용: python3 tool/ga_report.py [일수=7]"""
import os, sys
import google.auth
from google.auth.transport.requests import AuthorizedSession

DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 7
cred, project = google.auth.default(scopes=['https://www.googleapis.com/auth/analytics.readonly',
                                            'https://www.googleapis.com/auth/cloud-platform'])
s = AuthorizedSession(cred)
project = os.environ.get('PROJECT') or project
r = s.get(f'https://firebase.googleapis.com/v1beta1/projects/{project}/analyticsDetails')
if not r.ok:
    print('analyticsDetails', r.status_code, r.text[:300]); sys.exit(1)
prop = r.json()['analyticsProperty']['id']
print(f'GA property {prop}, last {DAYS} days')
st = s.get(f'https://analyticsadmin.googleapis.com/v1beta/properties/{prop}/dataStreams')
print('data streams:', [(x.get('type'), x.get('displayName'), (x.get('androidAppStreamData') or {}).get('packageName')) for x in st.json().get('dataStreams', [])] if st.ok else (st.status_code, st.text[:200]))
rt = s.post(f'https://analyticsdata.googleapis.com/v1beta/properties/{prop}:runRealtimeReport',
            json={'dimensions': [{'name': 'eventName'}], 'metrics': [{'name': 'eventCount'}], 'limit': 20})
print('realtime (30 min):', [(x['dimensionValues'][0]['value'], x['metricValues'][0]['value']) for x in rt.json().get('rows', [])] if rt.ok else (rt.status_code, rt.text[:200]))
URL = f'https://analyticsdata.googleapis.com/v1beta/properties/{prop}:runReport'
RANGE = [{'startDate': f'{DAYS}daysAgo', 'endDate': 'today'}]


def report(title, dims, mets, limit=40, order=None, filt=None):
    body = {'dateRanges': RANGE, 'dimensions': [{'name': d} for d in dims],
            'metrics': [{'name': m} for m in mets], 'limit': limit}
    if order:
        body['orderBys'] = [order]
    if filt:
        body['dimensionFilter'] = filt
    r = s.post(URL, json=body)
    print(f'\n== {title}')
    if not r.ok:
        print('  error', r.status_code, r.text[:300]); return
    print('  ' + ' | '.join(dims + mets))
    for row in r.json().get('rows', []):
        print('  ' + ' | '.join([v['value'] for v in row.get('dimensionValues', [])] + [v['value'] for v in row['metricValues']]))


report('날짜별 사용자', ['date'], ['activeUsers', 'newUsers', 'sessions', 'averageSessionDuration'],
       order={'dimension': {'dimensionName': 'date'}})
report('앱 버전별 사용자', ['appVersion'], ['activeUsers'])
report('이벤트 (많은 순)', ['eventName'], ['eventCount', 'totalUsers'], limit=60,
       order={'metric': {'metricName': 'eventCount'}, 'desc': True})
report('튜토리얼 · 첫 진행 깔때기', ['eventName'], ['totalUsers'],
       filt={'filter': {'fieldName': 'eventName', 'inListFilter': {'values': [
           'first_open', 'tutorial_begin', 'tutorial_step', 'tutorial_complete', 'level_up', 'area_complete', 'orders_done']}}})
report('나라별 사용자', ['country'], ['activeUsers'], limit=15,
       order={'metric': {'metricName': 'activeUsers'}, 'desc': True})
# 재방문: 첫 접속일 묶음별 1일 · 7일 뒤
body = {'dimensions': [{'name': 'cohort'}, {'name': 'cohortNthDay'}], 'metrics': [{'name': 'cohortActiveUsers'}],
        'cohortSpec': {'cohorts': [{'name': 'all', 'dimension': 'firstSessionDate',
                                    'dateRange': {'startDate': f'{max(DAYS, 8)}daysAgo', 'endDate': 'yesterday'}}],
                       'cohortsRange': {'granularity': 'DAILY', 'startOffset': 0, 'endOffset': 7}}}
r = s.post(URL, json=body)
print('\n== 재방문 (첫 접속 이후 N일째 활성 사용자)')
if r.ok:
    rows = sorted(((int(x['dimensionValues'][1]['value']), x['metricValues'][0]['value']) for x in r.json().get('rows', [])))
    print('  ' + '  '.join(f'D{d}:{v}' for d, v in rows))
else:
    print('  error', r.status_code, r.text[:300])
