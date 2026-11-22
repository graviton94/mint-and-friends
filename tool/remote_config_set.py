#!/usr/bin/env python3
"""Firebase 원격 설정 값 바꾸기 (CI 의 remote-config.yml 이 부른다).

사용: ACCESS_TOKEN=... PROJECT=... python3 tool/remote_config_set.py latest_version_code=1023 [키=값 ...]
- 앱이 아는 키(lib/game/tuning.dart)만 받는다. 기존 조건부 값 · 다른 키는 그대로 둔다.
- 바꾸기 전 값과 바꾼 뒤 값을 찍는다 (비밀 아님).
"""
import json
import os
import sys
import urllib.request

ALLOWED = {
    'latest_version_code', 'min_version_code', 'order_quota_per_friend',
    'energy_regen_seconds', 'energy_ad_amount', 'refill_base', 'refill_step', 'refill_max',
    'rescue_chance', 'easy_order_chance', 'market_price_base', 'area_star_scale',
    'coin_scale', 'seed_income', 'seed_coin_base',
}

token, project = os.environ['ACCESS_TOKEN'], os.environ['PROJECT']
url = f'https://firebaseremoteconfig.googleapis.com/v1/projects/{project}/remoteConfig'
pairs = {}
for a in sys.argv[1:]:
    k, _, v = a.partition('=')
    if k not in ALLOWED:
        sys.exit(f'unknown key: {k}')
    float(v)  # 숫자만
    pairs[k] = v

req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}', 'Accept-Encoding': 'identity'})
with urllib.request.urlopen(req) as r:
    etag = r.headers.get('ETag') or '*'  # 아직 게시한 적 없으면 ETag 가 없다
    tpl = json.load(r)
params = tpl.setdefault('parameters', {})
for k, v in pairs.items():
    old = params.get(k, {}).get('defaultValue', {}).get('value')
    p = params.setdefault(k, {})
    p['defaultValue'] = {'value': v}
    p['valueType'] = 'NUMBER'
    print(f'{k}: {old} -> {v}')
body = json.dumps(tpl).encode()
put = urllib.request.Request(url, data=body, method='PUT', headers={
    'Authorization': f'Bearer {token}',
    'Content-Type': 'application/json; UTF-8',
    'If-Match': etag,
})
with urllib.request.urlopen(put) as r:
    print('published version', json.load(r).get('version', {}).get('versionNumber'))
