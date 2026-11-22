"""데이터 보안 CSV 만들기: 빈 템플릿 + 앱 프로필(JSON) → Play Console 가져오기용 CSV.

  python3 make_data_safety_csv.py profile.json out.csv

템플릿은 Play Console(데이터 보안 → 내보내기)에서 받은 형식 그대로다. 질문 ID 가 바뀌면
콘솔에서 빈 CSV 를 새로 내보내 data_safety_template.csv 를 바꾸면 된다.
"""
import csv, json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
prof = json.load(open(sys.argv[1], encoding='utf-8'))
types = prof['types']
rows = list(csv.reader(open(os.path.join(here, 'data_safety_template.csv'), encoding='utf-8')))
out = [rows[0]]
for r in rows[1:]:
    q, resp = r[0], r[1]
    v = ''
    if q == 'PSL_DATA_COLLECTION_COLLECTS_PERSONAL_DATA':
        v = str(prof['collects']).lower()
    elif q == 'PSL_DATA_COLLECTION_ENCRYPTED_IN_TRANSIT':
        v = str(prof['encrypted_in_transit']).lower()
    elif q == 'PSL_SUPPORTED_ACCOUNT_CREATION_METHODS':
        v = 'true' if resp in prof['account_methods'] else ''
    elif q == 'PSL_ACCOUNT_DELETION_URL':
        v = prof.get('account_deletion_url', '')
    elif q == 'PSL_SUPPORT_DATA_DELETION_BY_USER':
        v = 'true' if resp == 'DATA_DELETION_YES' and prof.get('data_deletion_url') else ''
    elif q == 'PSL_DATA_DELETION_URL':
        v = prof.get('data_deletion_url', '')
    elif q.startswith('PSL_DATA_TYPES_'):
        v = 'true' if resp in types and types[resp]['cat'] == q else ''
    elif q.startswith('PSL_DATA_USAGE_RESPONSES:'):
        _, t, sub = q.split(':')
        d = types.get(t)
        if d:
            if sub == 'PSL_DATA_USAGE_COLLECTION_AND_SHARING':
                v = 'true' if resp == 'PSL_DATA_USAGE_ONLY_COLLECTED' or (resp == 'PSL_DATA_USAGE_ONLY_SHARED' and d['shared']) else ''
            elif sub == 'PSL_DATA_USAGE_EPHEMERAL':
                v = str(d.get('ephemeral', False)).lower()
            elif sub == 'DATA_USAGE_USER_CONTROL':
                want = 'PSL_DATA_USAGE_USER_CONTROL_OPTIONAL' if d['optional'] else 'PSL_DATA_USAGE_USER_CONTROL_REQUIRED'
                v = 'true' if resp == want else ''
            elif sub == 'DATA_USAGE_COLLECTION_PURPOSE':
                v = 'true' if resp in d['collect'] else ''
            elif sub == 'DATA_USAGE_SHARING_PURPOSE':
                v = 'true' if resp in d['share'] else ''
    # PSL_HAS_OUTSIDE_APP_ACCOUNTS · PSL_INDEPENDENTLY_VALIDATED 등은 비워 둔다 (OAuth 고르면 답할 수 없음)
    r = r[:]
    r[2] = v
    out.append(r)
csv.writer(open(sys.argv[2], 'w', encoding='utf-8', newline='')).writerows(out)
print('ok', sum(1 for r in out[1:] if r[2]), 'answers')
