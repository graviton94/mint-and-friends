#!/usr/bin/env python3
"""운영 공지 올리기: Firestore notices/{id} 에 문서를 만든다. 앱은 시작할 때 진행 중인 공지를 쪽지함에 넣는다.

준비: pip install firebase-admin, Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → 새 비공개 키(JSON).

예)
  python3 tool/post_notice.py --key sa.json --ko "점검 보상" --en "Maintenance gift" --ja "メンテナンスのお詫び" \
      --coins 500 --energy 20 --days 7
  python3 tool/post_notice.py --key sa.json --ko "11월 점검 안내" --body-ko "11/30 02:00~04:00 점검해요.\\n점검 뒤 에너지를 보내요." --energy 30
  python3 tool/post_notice.py --key sa.json --list
  python3 tool/post_notice.py --key sa.json --delete <id>

같은 --id 로 다시 올리면 덮어쓴다. 이미 받은 사람에게는 다시 가지 않는다 (쪽지 id = notice-<id>).
"""
import argparse
import datetime
import sys


def main() -> int:
    ap = argparse.ArgumentParser(description='Post an in-game notice (mailbox) to Firestore.')
    ap.add_argument('--key', required=True, help='service account JSON path')
    ap.add_argument('--id', help='document id (default: date-based)')
    ap.add_argument('--ko', help='title (Korean, default language)')
    ap.add_argument('--en', help='title (English)')
    ap.add_argument('--ja', help='title (Japanese)')
    ap.add_argument('--es', help='title (Spanish)')
    ap.add_argument('--body', help='optional body text (all languages)')
    for l in ('ko', 'en', 'ja', 'es'):
        ap.add_argument(f'--body-{l}', dest=f'body_{l}', help=f'body text ({l}), shown in the notice detail; \\n for new lines')
    ap.add_argument('--coins', type=int, default=0)
    ap.add_argument('--energy', type=int, default=0)
    ap.add_argument('--stars', type=int, default=0)
    ap.add_argument('--gems', type=int, default=0)
    ap.add_argument('--start', help='start time, ISO (default: now, UTC if no offset)')
    ap.add_argument('--days', type=float, default=7, help='how long it stays active (default 7)')
    ap.add_argument('--list', action='store_true', help='list notices and exit')
    ap.add_argument('--delete', metavar='ID', help='delete a notice and exit')
    a = ap.parse_args()

    import firebase_admin
    from firebase_admin import credentials, firestore

    firebase_admin.initialize_app(credentials.Certificate(a.key))
    col = firestore.client().collection('notices')

    if a.list:
        for d in col.stream():
            v = d.to_dict()
            print(d.id, v.get('title_ko') or v.get('title_en'), v.get('reward'), v.get('startAt'), '→', v.get('endAt'))
        return 0
    if a.delete:
        col.document(a.delete).delete()
        print('deleted', a.delete)
        return 0

    if not a.ko:
        ap.error('--ko is required (Korean is the default language)')
    now = datetime.datetime.now(datetime.timezone.utc)
    start = datetime.datetime.fromisoformat(a.start) if a.start else now
    if start.tzinfo is None:
        start = start.replace(tzinfo=datetime.timezone.utc)
    end = start + datetime.timedelta(days=a.days)
    doc = {
        'title_ko': a.ko,
        'startAt': start,
        'endAt': end,
    }
    if a.en:
        doc['title_en'] = a.en
    if a.ja:
        doc['title_ja'] = a.ja
    if a.es:
        doc['title_es'] = a.es
    if a.body:
        doc['body'] = a.body.replace('\\n', '\n')
    for l in ('ko', 'en', 'ja', 'es'):
        b = getattr(a, f'body_{l}')
        if b:
            doc[f'body_{l}'] = b.replace('\\n', '\n')
    reward = {k: v for k, v in (('c', a.coins), ('e', a.energy), ('s', a.stars), ('g', a.gems)) if v > 0}
    if reward:
        doc['reward'] = reward
    nid = a.id or now.strftime('%Y%m%d-%H%M%S')
    col.document(nid).set(doc)
    print(f'notice {nid}: {a.ko} {reward or ""} {start.isoformat()} → {end.isoformat()}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
