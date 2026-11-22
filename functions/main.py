"""민트앤프렌즈 Cloud Functions (Blaze 요금제, Python). 배포: .github/workflows/functions.yml

- login(provider, token): 카카오 액세스 토큰을 카카오 서버에서 확인하고 Firebase 커스텀 토큰을 돌려준다.
    uid = "kakao:<카카오 회원번호>". KAKAO_APP_ID 가 설정돼 있으면 다른 카카오 앱이 받은 토큰은 거부한다.
- deleteAccount(): 로그인한 사용자의 게임 저장(users/{uid}) · 친구 데이터와 Firebase 계정을 지운다 (Play 정책: 앱 안 계정 삭제).
- sendGift(to, day): 친구에게 하루 한 번 선물 (에너지 5). 친구 관계 · 하루 한 번(쌍마다) · 하루 최대 50개를
    트랜잭션으로 확인하고 받는 사람의 inbox/{to}/items 에 넣는다. day = 보내는 기기의 날짜 'YYYY-MM-DD'.
"""
import datetime
import json
import os
import re
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
    db = firestore.client()
    try:
        _delete_social(db, uid)
    except Exception as e:  # 친구 데이터 정리가 실패해도 계정 삭제는 진행한다
        print(f'deleteAccount: social cleanup failed: {type(e).__name__}')
    db.collection('users').document(uid).delete()
    auth.delete_user(uid)
    return {'ok': True}


def _delete_social(db, uid: str) -> None:
    """공개 프로필 · 친구 코드 · 친구 목록 · 받은 선물함을 지운다."""
    profile = db.collection('profiles').document(uid)
    snap = profile.get()
    code = (snap.to_dict() or {}).get('code') if snap.exists else None
    if isinstance(code, str) and code:
        code_ref = db.collection('codes').document(code)
        code_snap = code_ref.get()
        if code_snap.exists and (code_snap.to_dict() or {}).get('uid') == uid:
            code_ref.delete()
    profile.delete()
    for col in (db.collection('users').document(uid).collection('friends'),
                db.collection('inbox').document(uid).collection('items')):
        for doc in col.list_documents(page_size=200):
            doc.delete()


# ---------------------------------------------------------------- 친구 선물

GIFT_REWARD = {'e': 5}
GIFT_DAILY_MAX = 3  # 한 사람이 하루에 보낼 수 있는 선물 수 (앱 SocialConfig.giftsPerDay 와 같게)
_DAY = re.compile(r'^\d{4}-\d{2}-\d{2}$')


def _check_day(day) -> str:
    """기기 날짜를 쓰되 서버 UTC 날짜와 하루 넘게 차이 나면 거부 (시간대 ±14시간 허용)."""
    if not isinstance(day, str) or not _DAY.match(day):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, 'day must be YYYY-MM-DD')
    try:
        d = datetime.date.fromisoformat(day)
    except ValueError as e:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, 'bad day') from e
    today = datetime.datetime.now(datetime.timezone.utc).date()
    if abs((d - today).days) > 1:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, 'day out of range')
    return day


@firestore.transactional
def _gift_txn(txn, db, sender: str, to: str, day: str, from_name: str) -> None:
    gift_ref = db.collection('gifts').document(f'{sender}_{to}_{day}')
    count_ref = db.collection('giftCounts').document(f'{sender}_{day}')
    friend_ref = db.collection('users').document(sender).collection('friends').document(to)
    # 트랜잭션에서는 읽기를 모두 먼저
    gift = gift_ref.get(transaction=txn)
    count = count_ref.get(transaction=txn)
    friend = friend_ref.get(transaction=txn)
    if not friend.exists:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.FAILED_PRECONDITION, 'not a friend')
    if gift.exists:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.ALREADY_EXISTS, 'already sent today')
    n = int((count.to_dict() or {}).get('n', 0)) if count.exists else 0
    if n >= GIFT_DAILY_MAX:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.RESOURCE_EXHAUSTED, 'daily gift limit')
    # 기록은 며칠 뒤 필요 없다: Firestore TTL 정책(expireAt)을 켜 두면 자동으로 지워진다
    expire = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=3)
    txn.set(gift_ref, {'from': sender, 'to': to, 'day': day, 'at': firestore.SERVER_TIMESTAMP, 'expireAt': expire})
    txn.set(count_ref, {'n': n + 1, 'expireAt': expire})
    txn.set(db.collection('inbox').document(to).collection('items').document(), {
        'kind': 'gift',
        'fromUid': sender,
        'fromName': from_name,
        'reward': GIFT_REWARD,
        'at': firestore.SERVER_TIMESTAMP,
    })
    txn.set(friend_ref, {'lastGiftSentDay': day}, merge=True)


@https_fn.on_call(region=REGION, max_instances=10)
def sendGift(req: https_fn.CallableRequest) -> dict:  # noqa: N802 (앱에서 부르는 이름)
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, 'login required')
    sender = req.auth.uid
    data = req.data if isinstance(req.data, dict) else {}
    to = data.get('to')
    if not isinstance(to, str) or not to or len(to) > 128 or '/' in to or to == sender:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, 'bad recipient')
    day = _check_day(data.get('day'))
    db = firestore.client()
    if not db.collection('profiles').document(to).get().exists:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.NOT_FOUND, 'no such player')
    me = db.collection('profiles').document(sender).get()
    from_name = str((me.to_dict() or {}).get('name') or '')[:24] if me.exists else ''
    _gift_txn(db.transaction(), db, sender, to, day, from_name)
    return {'ok': True, 'day': day, 'reward': GIFT_REWARD}
