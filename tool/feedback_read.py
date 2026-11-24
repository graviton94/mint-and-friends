"""최근 '문제 알리기' 글 읽기 (CI, ACCESS_TOKEN · PROJECT). 계정 id 는 앞 6자리만."""
import json, os, urllib.request
P, T = os.environ['PROJECT'], os.environ['ACCESS_TOKEN']
body = {'structuredQuery': {'from': [{'collectionId': 'feedback'}],
                            'orderBy': [{'field': {'fieldPath': 'at'}, 'direction': 'DESCENDING'}], 'limit': 50}}
req = urllib.request.Request(f'https://firestore.googleapis.com/v1/projects/{P}/databases/(default)/documents:runQuery',
                             data=json.dumps(body).encode(), headers={'Authorization': f'Bearer {T}', 'Content-Type': 'application/json'})
rows = [r['document']['fields'] for r in json.load(urllib.request.urlopen(req)) if 'document' in r]
print(f'== 문제 알리기 {len(rows)}건 (최근 순)')
for f in rows:
    g = lambda k: f.get(k, {}).get('stringValue') or f.get(k, {}).get('timestampValue', '')
    print(f"- {g('at')[:16]} [{g('from')[:6]}] {g('text')}\n    {g('diag')}")
