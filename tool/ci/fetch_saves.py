"""CI 전용: Firestore users/* 의 저장 JSON 만 꺼내 파일로 (계정 id 는 버린다). 화면에 아무것도 출력하지 않는다."""
import json, os, sys, urllib.request

P, T = os.environ['PROJECT'], os.environ['ACCESS_TOKEN']
H = {'Authorization': f'Bearer {T}', 'x-goog-user-project': P}
out, tok = [], ''
while True:
    u = f'https://firestore.googleapis.com/v1/projects/{P}/databases/(default)/documents/users?pageSize=300' + (f'&pageToken={tok}' if tok else '')
    with urllib.request.urlopen(urllib.request.Request(u, headers=H)) as r:
        d = json.load(r)
    for doc in d.get('documents', []):
        raw = doc.get('fields', {}).get('data', {}).get('stringValue')
        if raw:
            out.append(raw)
    tok = d.get('nextPageToken')
    if not tok:
        break
json.dump(out, open(sys.argv[1], 'w'))
print(f'saves: {len(out)}')
