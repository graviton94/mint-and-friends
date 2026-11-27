import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/i18n/l10n.dart';

/// 일본어 줄바꿈은 말 덩어리 사이에서만 (D-105).
void main() {
  String show(String s) => jaPhrases(s).replaceAll('⁠', '');

  test('글자는 그대로 (줄 바꾸지 않음 기호만 끼운다)', () {
    for (final s in ['アカウントとデータを削除', 'クラウドに保存済み 16:09', '[[star]]×3 もらえるよ！']) {
      expect(show(s), s);
    }
  });

  test('낱말 안에서는 줄을 바꾸지 않는다', () {
    expect(_split(jaPhrases('アカウントとデータを削除')), ['アカウントと', 'データを', '削除']);
    expect(_split(jaPhrases('問題を知らせる')), ['問題を', '知らせる']);
    expect(_split(jaPhrases('エネルギー・プレゼント・友だち')), ['エネルギー・', 'プレゼント・', '友だち']);
  });

  test('숫자와 일본어는 붙여 두고, 영문 · 숫자끼리는 그대로', () {
    expect(_split(jaPhrases('新しい庭師さん限定・1回だけ！')).contains('1回だけ！'), isTrue);
    expect(jaPhrases('https://example.com/a?b=1'), 'https://example.com/a?b=1');
  });

  test('아이콘 토큰은 통째로', () {
    expect(jaPhrases('[[diamond]]ダイヤ').startsWith('[[diamond]]'), isTrue);
  });
}

/// 줄을 바꿀 수 있는 자리(= U+2060 이 없는 글자 사이)로 나눈다.
List<String> _split(String s) {
  final out = <String>[];
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '⁠') continue;
    if (b.isNotEmpty && (i == 0 || s[i - 1] != '⁠')) {
      out.add(b.toString());
      b.clear();
    }
    b.write(ch);
  }
  if (b.isNotEmpty) out.add(b.toString());
  return out;
}
