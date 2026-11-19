import 'dart:io';

import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/art/art.dart';
import 'package:mint_and_friends/i18n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _load(String lang) =>
    L10n.parse(File('assets/i18n/$lang.json').readAsStringSync());

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  final base = _load(L10n.fallbackLang);

  for (final lang in L10n.supported.keys) {
    test('$lang: 기본 언어와 키·자리표시자가 같다', () {
      final t = _load(lang);
      final missing = base.keys.where((k) => !t.containsKey(k)).toList();
      final extra = t.keys.where((k) => !base.containsKey(k)).toList();
      expect(missing, isEmpty, reason: '빠진 키');
      expect(extra, isEmpty, reason: '기본 언어에 없는 키');
      for (final k in base.keys) {
        expect(
          _placeholders(t[k]!),
          _placeholders(base[k]!),
          reason: '자리표시자 불일치: $k',
        );
      }
    });
  }

  test('모든 콘텐츠 id 에 문구가 있다', () {
    final keys = <String>[
      for (final c in Chain.values)
        for (var l = 1; l <= GameConfig.maxLevel; l++) Chains.item(c, l).key,
      for (final f in Friends.all) ...[
        f.key('name'),
        f.key('species'),
        f.key('line'),
      ],
      for (final a in Garden.areas) ...[a.key, for (final d in a.decor) d.key],
      for (final u in Upgrades.all) ...[u.key, '${u.key}.desc'],
      for (final f in Feature.values) 'feature.${f.name}',
      for (final b in FriendBuff.values) 'buff.${b.name}',
      for (final c in Chain.values) 'chain.${c.name}',
    ];
    final missing = keys.where((k) => !base.containsKey(k)).toList();
    expect(missing, isEmpty);
  });

  test('UI 문구에 이모지 대신 아이콘 토큰만 쓴다', () {
    final emoji = RegExp(
      r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]',
      unicode: true,
    );
    final token = RegExp(r'\[\[([a-z_0-9:]+)\]\]');
    final known = {
      ...Art.iconFallback.keys,
      'coin',
      'star',
      'basket',
      'lock',
      'bubble',
      'gift',
      'visitor',
    };
    for (final lang in L10n.supported.keys) {
      for (final e in _load(lang).entries) {
        if (e.key.startsWith('item.') ||
            e.key.startsWith('decor.') ||
            e.key.startsWith('friend.') ||
            e.key.startsWith('area.')) {
          continue;
        }
        expect(
          emoji.hasMatch(e.value),
          isFalse,
          reason: '$lang ${e.key}: 이모지 대신 [[토큰]] 사용',
        );
        for (final m in token.allMatches(e.value)) {
          final t = m.group(1)!;
          final ok =
              known.contains(t) ||
              t.startsWith('item:') ||
              t.startsWith('friend:') ||
              t.startsWith('decor:');
          expect(ok, isTrue, reason: '$lang ${e.key}: 알 수 없는 토큰 $t');
        }
      }
    }
  });

  test('tr: 자리표시자 치환과 없는 키 대체', () {
    L10n.instance.debugSetTables(
      'en',
      {'a': 'Hi {n}'},
      fallback: {'a': '안녕 {n}', 'b': '기본'},
    );
    expect(L10n.instance.t('a', {'n': 3}), 'Hi 3');
    expect(L10n.instance.t('b'), '기본');
    expect(L10n.instance.t('zzz'), 'zzz');
  });
}
