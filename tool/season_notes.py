"""계절 배포 패치노트를 4개 언어에 넣는다 (D-103). 사용: season_notes.py <버전> <계절>
그 버전의 노트가 이미 있으면 맨 앞에 계절 줄만 더한다."""
import collections, json, sys

v, season = sys.argv[1], sys.argv[2]
LINE = {
    'ko': {'spring': '• 봄이 왔어요! 시작 화면 · 계절 장식 · 친구 의상이 봄으로 바뀌었어요',
           'summer': '• 여름이 왔어요! 시작 화면 · 계절 장식 · 친구 의상이 여름으로 바뀌었어요',
           'autumn': '• 가을이 왔어요! 시작 화면 · 계절 장식 · 친구 의상이 가을로 바뀌었어요',
           'winter': '• 겨울이 왔어요! 시작 화면 · 계절 장식 · 친구 의상이 겨울로 바뀌었어요'},
    'en': {'spring': '• Spring is here! The title screen, seasonal decor and outfits are now spring-themed',
           'summer': '• Summer is here! The title screen, seasonal decor and outfits are now summer-themed',
           'autumn': '• Autumn is here! The title screen, seasonal decor and outfits are now autumn-themed',
           'winter': '• Winter is here! The title screen, seasonal decor and outfits are now winter-themed'},
    'ja': {'spring': '• 春が来たよ！タイトル画面・季節の飾り・友だちの衣装が春に',
           'summer': '• 夏が来たよ！タイトル画面・季節の飾り・友だちの衣装が夏に',
           'autumn': '• 秋が来たよ！タイトル画面・季節の飾り・友だちの衣装が秋に',
           'winter': '• 冬が来たよ！タイトル画面・季節の飾り・友だちの衣装が冬に'},
    'es': {'spring': '• ¡Llegó la primavera! Pantalla de inicio, decoración y trajes de temporada de primavera',
           'summer': '• ¡Llegó el verano! Pantalla de inicio, decoración y trajes de temporada de verano',
           'autumn': '• ¡Llegó el otoño! Pantalla de inicio, decoración y trajes de temporada de otoño',
           'winter': '• ¡Llegó el invierno! Pantalla de inicio, decoración y trajes de temporada de invierno'},
}
GIFT = {'ko': '업데이트 선물로 에너지를 보내요!', 'en': "Here's some energy as an update gift!",
        'ja': 'アップデートのお礼にエネルギーをどうぞ！', 'es': '¡Te enviamos energía como regalo!'}
for l in LINE:
    p = f'assets/i18n/{l}.json'
    d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
    k = f'patch.{v}'
    line = LINE[l][season]
    cur = d.get(k)
    if cur and line not in cur:
        d[k] = line + '\n' + cur
    elif not cur:
        d[k] = line + '\n\n' + GIFT[l]
    json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
    open(p, 'a').write('\n')
print('patch notes', v, season)
