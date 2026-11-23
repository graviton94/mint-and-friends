"""Google Play Developer API (CI 전용). 서비스 계정: GOOGLE_APPLICATION_CREDENTIALS.
사용: play_api.py check | upload <aab> <track> <versionName> [status] [fraction]
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
            out.append({'language': code, 'text': t.split('\n\n')[0][:500]})
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


if __name__ == '__main__':
    if sys.argv[1] == 'check':
        check()
    else:
        upload(*sys.argv[2:])
