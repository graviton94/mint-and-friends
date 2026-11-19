import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 아이콘 토큰([[coin]] 등)이 든 문구를 그냥 Text 로 그리면 화면에 "[[ad]]" 같은 글자가 그대로 보인다.
/// 토큰이 든 문구 키가 Text( 바로 안에서 쓰이면 실패한다 (IconText 로 그려야 함).
void main() {
  test('토큰이 든 문구는 IconText 로만 그린다', () {
    final ko =
        jsonDecode(File('assets/i18n/ko.json').readAsStringSync()) as Map;
    final tokenKeys = {
      for (final e in ko.entries)
        if ((e.value as String).contains('[[')) e.key as String,
    };
    final rawText = RegExp(
      r"(?<![A-Za-z])Text\(\s*(?:[^()]|\([^()]*\))*?tr\('([a-zA-Z0-9_.]+)'",
    );
    final bad = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in rawText.allMatches(src)) {
        if (tokenKeys.contains(m.group(1))) bad.add('${f.path}: ${m.group(1)}');
      }
    }
    expect(bad, isEmpty);
  });
}
