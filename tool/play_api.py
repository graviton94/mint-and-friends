"""Google Play Developer API (CI 전용). 서비스 계정: GOOGLE_APPLICATION_CREDENTIALS.
사용: play_api.py check | upload <aab> <track> <versionName> [status] [fraction]
      | feature <season> [--apply]  (docs/store/season/<season>/<lang>.png 를 언어별 그래픽 이미지로, --apply 없으면 확인만)
출시 노트는 assets/i18n/<lang>.json 의 patch.<versionName> 에서 가져온다."""
import json, sys, time
import google.auth
from google.auth.transport.requests import AuthorizedSession

PKG = 'io.github.graviton94.mintandfriends'
API = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}'
UP = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}'
cred, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/androidpublisher'])
s = AuthorizedSession(cred)


def ok(r):
    if r.status_code >= 300:
        print('HTTP', r.status_code, r.text[:800])
        sys.exit(1)
    return r.json() if r.content else {}


def check():
    e = ok(s.post(f'{API}/edits'))
    tracks = ok(s.get(f'{API}/edits/{e["id"]}/tracks'))
    for t in tracks.get('tracks', []):
        rel = [(r.get('status'), r.get('versionCodes'), r.get('userFraction')) for r in t.get('releases', [])]
        print('track', t['track'], rel)
    s.delete(f'{API}/edits/{e["id"]}')
    rv = s.get(f'{API}/reviews', params={'maxResults': 5})
    print('reviews', rv.status_code, len(rv.json().get('reviews', [])) if rv.ok else rv.text[:200])
    print('access ok')


NOTE_LANG = {'ko': 'ko-KR', 'en': 'en-US', 'ja': 'ja-JP', 'es': 'es-419'}


def notes(version):
    out = []
    for l, code in NOTE_LANG.items():
        try:
            t = json.load(open(f'assets/i18n/{l}.json')).get(f'patch.{version}')
        except Exception:
            t = None
        if t:
            t = t.split('\n\n')[0]  # 선물 안내 문단은 빼고
            while len(t) > 500 and '\n' in t:  # Play 한도 500자: 줄 단위로 줄인다
                t = t.rsplit('\n', 1)[0]
            out.append({'language': code, 'text': t[:500]})
    return out


def upload(aab, track, version, status='completed', fraction=None):
    e = ok(s.post(f'{API}/edits'))['id']
    with open(aab, 'rb') as f:
        b = ok(s.post(f'{UP}/edits/{e}/bundles', params={'uploadType': 'media'},
                      data=f, headers={'Content-Type': 'application/octet-stream'}, timeout=900))
    code = b['versionCode']
    rel = {'versionCodes': [str(code)], 'status': status, 'name': f'{version} ({code})',
           'releaseNotes': notes(version)}
    if fraction:
        rel['userFraction'] = float(fraction)
    ok(s.put(f'{API}/edits/{e}/tracks/{track}', json={'track': track, 'releases': [rel]}))
    ok(s.post(f'{API}/edits/{e}:commit'))
    print(f'released {version} ({code}) to {track} status={status}')
    open('/tmp/play_code', 'w').write(str(code))


# 앱 언어 → Play 등록정보 언어 (등록돼 있는 것만 바꾼다)
FEATURE_LANG = {'ko': ['ko-KR'], 'en': ['en-US', 'en-GB'], 'ja': ['ja-JP'], 'es': ['es-419', 'es-ES', 'es-US']}


def feature(season, apply=False):
    import os
    e = ok(s.post(f'{API}/edits'))['id']
    have = {l['language'] for l in ok(s.get(f'{API}/edits/{e}/listings')).get('listings', [])}
    print('listings:', sorted(have))
    todo = []
    for lang, codes in FEATURE_LANG.items():
        f = f'docs/store/season/{season}/{lang}.png'
        if not os.path.exists(f):
            print('missing', f); sys.exit(1)
        todo += [(c, f) for c in codes if c in have]
    for code, f in todo:
        print(('upload ' if apply else 'would upload ') + f'{f} -> {code}')
        if apply:
            ok(s.delete(f'{API}/edits/{e}/listings/{code}/featureGraphic'))
            with open(f, 'rb') as fh:
                ok(s.post(f'{UP}/edits/{e}/listings/{code}/featureGraphic', params={'uploadType': 'media'},
                          data=fh, headers={'Content-Type': 'image/png'}, timeout=300))
    # 스토어 아이콘(512): 시즌판 (홈 화면 아이콘은 앱 업데이트로, tool/launcher_icon.py)
    icon = f'docs/store/season/{season}/icon_512.png'
    if os.path.exists(icon):
        for lang, codes in FEATURE_LANG.items():
            for code in codes:
                if code not in have:
                    continue
                print(('replace ' if apply else 'would replace ') + f'icon {code}: {icon}')
                if apply:
                    ok(s.delete(f'{API}/edits/{e}/listings/{code}/icon'))
                    with open(icon, 'rb') as fh:
                        ok(s.post(f'{UP}/edits/{e}/listings/{code}/icon', params={'uploadType': 'media'},
                                  data=fh, headers={'Content-Type': 'image/png'}, timeout=300))
    # 휴대전화 스크린샷: [시즌 표지] + 기존 1~7 (8번은 뺀다)
    for lang, codes in FEATURE_LANG.items():
        # 시즌판 2~8번(docs/store/season/<시즌>/<언어>_<n>.jpg)이 있으면 그것, 없으면 기본 스크린샷 1~7
        rest = [f'docs/store/season/{season}/{lang}_{i}.jpg' for i in range(1, 8)]
        if not all(os.path.exists(f) for f in rest):
            rest = [f'docs/store/screenshots/{lang}/{i}.jpg' for i in range(1, 8)]
        shots = [f'docs/store/season/{season}/shot_{lang}.jpg'] + rest
        for f in shots:
            if not os.path.exists(f):
                print('missing', f); sys.exit(1)
        for code in codes:
            if code not in have:
                continue
            print(('replace ' if apply else 'would replace ') + f'phoneScreenshots {code}: ' + ', '.join(x.split('/')[-1] for x in shots))
            if apply:
                ok(s.delete(f'{API}/edits/{e}/listings/{code}/phoneScreenshots'))
                for f in shots:
                    with open(f, 'rb') as fh:
                        ok(s.post(f'{UP}/edits/{e}/listings/{code}/phoneScreenshots', params={'uploadType': 'media'},
                                  data=fh, headers={'Content-Type': 'image/jpeg'}, timeout=300))
    if apply:
        ok(s.post(f'{API}/edits/{e}:commit'))
        print(f'feature graphics and screenshots for {season} committed ({len(todo)} listings)')
    else:
        s.delete(f'{API}/edits/{e}')
        print('dry run: nothing changed')


def listing(apply=False):
    """docs/store/store.json 의 제목 · 짧은 설명 · 자세한 설명을 스토어 등록정보에 맞춘다 (--apply 없으면 확인만)."""
    store = json.load(open('docs/store/store.json'))
    e = ok(s.post(f'{API}/edits'))['id']
    cur = {l['language']: l for l in ok(s.get(f'{API}/edits/{e}/listings')).get('listings', [])}
    print('listings:', sorted(cur))
    changed = 0
    for L in store['langs']:
        base = L['code'].split('-')[0]
        codes = [c for c in FEATURE_LANG.get(base, [L['code']]) if c in cur] or [L['code']]
        want = {'title': L['title'], 'shortDescription': L['short'], 'fullDescription': L['full']}
        for code in codes:
            have = cur.get(code, {})
            diff = [k for k, v in want.items() if have.get(k) != v]
            if not diff:
                print(f'{code}: same')
                continue
            changed += 1
            print(f'{code}: {"update" if apply else "would update"} {diff}')
            if apply:
                ok(s.patch(f'{API}/edits/{e}/listings/{code}', json=want))
    if apply and changed:
        ok(s.post(f'{API}/edits/{e}:commit'))
        print(f'committed {changed} listings')
    else:
        s.delete(f'{API}/edits/{e}')
        print('nothing committed' if apply else 'dry run: nothing changed')


if __name__ == '__main__':
    if sys.argv[1] == 'check':
        check()
    elif sys.argv[1] == 'listing':
        listing('--apply' in sys.argv)
    elif sys.argv[1] == 'feature':
        feature(sys.argv[2], '--apply' in sys.argv)
    else:
        upload(*sys.argv[2:])
