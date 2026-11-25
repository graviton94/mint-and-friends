#!/usr/bin/env python3
"""환불(취소)된 결제를 찾아 그 사람에게 회수 표시를 남긴다 (D-066).

Play 'voidedpurchases' 목록 → purchases/{orderId} (앱이 결제 때 남긴 기록: uid · 상품) →
revocations/{uid}/items/{orderId} 를 만든다. 앱은 다음 접속 때 이것을 읽고 지급한 것을 되돌린다.
마지막으로 본 시각은 meta/refunds.lastMs 에 둔다. 서비스 계정 = FIREBASE_SERVICE_ACCOUNT (Play 권한 있음).
"""
import json, os, sys, time
import google.auth
from google.auth.transport.requests import AuthorizedSession

PKG = 'io.github.graviton94.mintandfriends'
cred, project = google.auth.default(scopes=[
    'https://www.googleapis.com/auth/androidpublisher',
    'https://www.googleapis.com/auth/datastore',
])
project = os.environ.get('PROJECT') or project
s = AuthorizedSession(cred)
FS = f'https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/documents'


def get(path):
    r = s.get(f'{FS}/{path}')
    if r.status_code == 404:
        return None
    r.raise_for_status()
    return r.json().get('fields', {})


def put(path, fields):
    r = s.patch(f'{FS}/{path}', json={'fields': fields})
    r.raise_for_status()


def sv(v):
    return {'stringValue': str(v)}


def main():
    meta = get('meta/refunds') or {}
    # 처음에는 30일 전부터 (Play 는 최대 30일까지 보여 준다)
    last = int(meta.get('lastMs', {}).get('integerValue', 0)) or int((time.time() - 30 * 86400) * 1000)
    now = int(time.time() * 1000)
    url = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}/purchases/voidedpurchases'
    params = {'startTime': str(last), 'endTime': str(now), 'type': '0', 'maxResults': '1000'}
    voided = []
    while True:
        r = s.get(url, params=params)
        r.raise_for_status()
        j = r.json()
        voided += j.get('voidedPurchases', [])
        tok = j.get('tokenPagination', {}).get('nextPageToken')
        if not tok:
            break
        params['token'] = tok
    print(f'voided since {time.strftime("%Y-%m-%d %H:%M", time.gmtime(last / 1000))}: {len(voided)}')
    done = 0
    for v in voided:
        oid = v.get('orderId', '')
        rec = get(f'purchases/{oid}') if oid else None
        if not rec:
            print(f'  {oid}: no purchase record (bought before 1.0.12 or not signed in)')
            continue
        uid = rec['uid']['stringValue']
        product = rec['product']['stringValue']
        gems = rec.get('gems', {}).get('integerValue', '0')
        put(f'revocations/{uid}/items/{oid}', {
            'product': sv(product),
            'gems': {'integerValue': str(gems)},
            'reason': {'integerValue': str(v.get('voidedReason', 0))},
            'at': {'integerValue': str(v.get('voidedTimeMillis', now))},
        })
        done += 1
        print(f'  {oid}: {product} -> revoke for {uid[:6]}…')
    put('meta/refunds', {'lastMs': {'integerValue': str(now)}})
    print(f'revocations written: {done}')


if __name__ == '__main__':
    main()
