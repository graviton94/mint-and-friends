"""민트앤프렌즈 Cloud Functions (Blaze 요금제, Python). 배포: .github/workflows/functions.yml

- login(provider, token): 카카오 액세스 토큰을 카카오 서버에서 확인하고 Firebase 커스텀 토큰을 돌려준다.
    uid = "kakao:<카카오 회원번호>". KAKAO_APP_ID 가 설정돼 있으면 다른 카카오 앱이 받은 토큰은 거부한다.
- deleteAccount(): 로그인한 사용자의 게임 저장(users/{uid})과 Firebase 계정을 지운다 (Play 정책: 앱 안 계정 삭제).
"""
import json
import os
import urllib.error
import urllib.request

from firebase_admin import auth, firestore, initialize_app
from firebase_functions import https_fn

initialize_app()

REGION = 'us-central1'

# 우리 카카오 앱의 숫자 ID (카카오 디벨로퍼스 → 앱 → 앱 ID). functions/.env 로 들어온다.
KAKAO_APP_ID = (os.environ.get('KAKAO_APP_ID') or '').strip()
if KAKAO_APP_ID and not KAKAO_APP_ID.isdigit():
    print('KAKAO_APP_ID is not numeric: ignoring it')
    KAKAO_APP_ID = ''

_PROFILE_URLS = {'kakao': 'https://kapi.kakao.com/v2/user/me'}


class _NotOurToken(Exception):
    pass


def _get(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.load(r)


def _kakao_is_ours(token: str) -> None:
    if not KAKAO_APP_ID:
        return
    info = _get('https://kapi.kakao.com/v1/user/access_token_info', token)
    if str(info.get('app_id')) != KAKAO_APP_ID:
        raise _NotOurToken()


def _profile(provider: str, token: str) -> tuple[str, str | None, str | None]:
    """(제공자 회원 id, 닉네임, 사진 URL). 토큰이 틀리면 예외."""
    if provider == 'kakao':
        _kakao_is_ours(token)
    body = _get(_PROFILE_URLS[provider], token)
    profile = (body.get('kakao_account') or {}).get('profile') or {}
    props = body.get('properties') or {}
    return (str(body['id']), profile.get('nickname') or props.get('nickname'),
            profile.get('profile_image_url') or props.get('profile_image'))


@https_fn.on_call(region=REGION, max_instances=10)
def login(req: https_fn.CallableRequest) -> dict:
    data = req.data if isinstance(req.data, dict) else {}
    provider, token = data.get('provider'), data.get('token')
    if provider not in _PROFILE_URLS or not isinstance(token, str) or not token or len(token) > 4096:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, 'provider and token required')
    try:
        pid, name, photo = _profile(provider, token)
    except _NotOurToken as e:
        print('login: a kakao token made for another app')
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, 'token not accepted') from e
    except urllib.error.HTTPError as e:
        print(f'login: {provider} refused the token ({e.code})')
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, 'token not accepted') from e
    except Exception as e:
        print(f'login: {provider} check failed: {type(e).__name__}')
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAVAILABLE, 'could not check the token') from e

    uid = f'{provider}:{pid}'[:128]
    fields = {'display_name': (name or '')[:100] or None}
    if photo and photo.startswith('http://'):
        photo = 'https://' + photo[len('http://'):]
    if photo and photo.startswith('https://'):
        fields['photo_url'] = photo
    try:
        auth.update_user(uid, **fields)
    except auth.UserNotFoundError:
        auth.create_user(uid=uid, **fields)
    return {'token': auth.create_custom_token(uid, {'provider': provider}).decode()}


@https_fn.on_call(region=REGION, max_instances=10)
def deleteAccount(req: https_fn.CallableRequest) -> dict:  # noqa: N802 (앱에서 부르는 이름)
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, 'login required')
    uid = req.auth.uid
    firestore.client().collection('users').document(uid).delete()
    auth.delete_user(uid)
    return {'ok': True}
