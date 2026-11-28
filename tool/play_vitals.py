"""Play Vitals 요약 (읽기만): 최근 비정상 종료율 · ANR 률 · 주요 오류 묶음.
python3 tool/play_vitals.py [days]
서비스 계정이 Play Console 에서 앱 정보 보기 권한이 있어야 한다. Play Developer Reporting API 사용."""
import datetime as dt
import sys

import google.auth
import google.auth.transport.requests

PKG = 'io.github.graviton94.mintandfriends'
R = f'https://playdeveloperreporting.googleapis.com/v1beta1/apps/{PKG}'
days = int(sys.argv[1]) if len(sys.argv) > 1 else 14
cred, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/playdeveloperreporting'])
s = google.auth.transport.requests.AuthorizedSession(cred)


def day(d):
    return {'year': d.year, 'month': d.month, 'day': d.day, 'timeZone': {'id': 'America/Los_Angeles'}}


# 지표는 하루 이틀 늦게 쌓인다
end = dt.date.today() - dt.timedelta(days=2)
start = end - dt.timedelta(days=days)
for metric_set, metrics in (('crashRateMetricSet', ['crashRate', 'userPerceivedCrashRate', 'distinctUsers']),
                            ('anrRateMetricSet', ['anrRate', 'userPerceivedAnrRate', 'distinctUsers'])):
    r = s.post(f'{R}/{metric_set}:query', json={
        'timelineSpec': {'aggregationPeriod': 'DAILY', 'startTime': day(start), 'endTime': day(end)},
        'metrics': metrics})
    print(f'== {metric_set} ({start}..{end}) HTTP {r.status_code}')
    if r.status_code != 200:
        print(r.text[:600])
        continue
    for row in r.json().get('rows', []):
        d = row['startTime']
        vals = {m['metric']: (m.get('decimalValue') or {}).get('value', '-') for m in row.get('metrics', [])}
        print(f"{d['year']}-{d['month']:02}-{d['day']:02}", ' '.join(f'{k}={v}' for k, v in vals.items()))

r = s.get(f'{R}/errorIssues:search', params={
    'interval.startTime.year': start.year, 'interval.startTime.month': start.month, 'interval.startTime.day': start.day,
    'interval.endTime.year': end.year, 'interval.endTime.month': end.month, 'interval.endTime.day': end.day,
    'pageSize': 20})
print(f'== errorIssues HTTP {r.status_code}')
if r.status_code != 200:
    print(r.text[:600])
else:
    for it in r.json().get('errorIssues', []):
        print(f"- {it.get('type')} x{it.get('errorReportCount')} users={it.get('distinctUsers')} "
              f"ver={it.get('lastAppVersion', {}).get('versionCode')} :: {it.get('cause', '')[:140]} @ {it.get('location', '')[:120]}")
