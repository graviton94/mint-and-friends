import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mint_and_friends/i18n/l10n.dart';
import 'package:mint_and_friends/ui/theme.dart';
import 'package:mint_and_friends/ui/widgets/prose_text.dart';

/// D-125 사용자 규칙: 이야기 · 편지 본문은 ① 문장 끝에서 줄바꿈 ② 한 문장이 길면 고르게 나눠
/// 마지막 줄에 낱말 하나만 넘어가지 않게 ③ 계산한 줄 말고 저절로 더 꺾이지 않게.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prefixes = ['story.', 'diary.p', 'diary.intro', 'ep.', 'event.story.'];

  Future<void> fonts() async {
    for (final (family, file) in [
      ('Jua', 'assets/fonts/Jua.ttf'),
      ('MochiyPop', 'assets/fonts/MochiyPopOne-ja.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(file))).load();
    }
  }

  for (final lang in ['ko', 'en', 'es', 'ja']) {
    testWidgets('본문 줄바꿈: $lang', (tester) async {
      await tester.runAsync(() async {
        await fonts();
        await L10n.instance.init();
        await L10n.instance.setLanguage(lang);
      });
      final all =
          (jsonDecode(File('assets/i18n/$lang.json').readAsStringSync())
                  as Map<String, dynamic>)
              .entries
              .where(
                (e) =>
                    prefixes.any(e.key.startsWith) &&
                    !e.key.endsWith('Title') &&
                    !e.key.endsWith('.t') &&
                    e.key != 'diary.intro.go' &&
                    (e.value as String).length > 20,
              )
              .toList();
      const style = TextStyle(fontSize: 15, height: 1.5);
      final bad = <String>[];
      for (final width in [250.0, 300.0, 340.0]) {
        for (final e in all) {
          final text = tr(e.key);
          final laid = proseLayout(
            text,
            appFontStyle(style),
            width,
            TextScaler.noScaling,
          );
          // ① 문장 끝 뒤에 같은 줄로 이어지는 글자가 없다
          if (RegExp(r'[.!?。！？][ \t]+\S').hasMatch(laid)) {
            bad.add('${e.key}@$width 문장 뒤 이어짐');
          }
          // ② 여러 줄로 나눈 문장의 마지막 줄이 낱말 하나뿐이면 안 된다 (빈칸 있는 언어)
          for (final para in splitSentences(text).split('\n')) {
            final lines = proseLayout(
              para,
              appFontStyle(style),
              width,
              TextScaler.noScaling,
            ).split('\n');
            if (lines.length > 1 &&
                para.contains(' ') &&
                !lines.last.trim().contains(' ')) {
              bad.add('${e.key}@$width 꼬리 한 낱말: «${lines.last}»');
            }
          }
          // ③ 실제로 그렸을 때 계산한 줄 수보다 더 꺾이지 않는다 (빈칸 있는 언어만)
          if (lang != 'ja') {
            await tester.pumpWidget(
              MaterialApp(
                theme: buildTheme(),
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: width,
                      child: ProseText(text, style: style),
                    ),
                  ),
                ),
              ),
            );
            final rp = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.byType(ProseText),
                matching: find.byType(RichText),
              ),
            );
            final want = rp.text.toPlainText().split('\n').length;
            // 실제 줄 수: 글자 상자들의 줄 위치가 몇 가지인지
            final tops = <int>{
              for (final b in rp.getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: rp.text.toPlainText().length,
                ),
              ))
                ((b.top + b.bottom) / 2 / (15 * 1.5)).floor(),
            };
            final got = tops.length;
            if (got > want) bad.add('${e.key}@$width 저절로 더 꺾임 $got>$want');
          }
        }
      }
      // ignore: avoid_print
      print('== $lang: ${bad.length}\n${bad.take(30).join('\n')}');
      expect(bad, isEmpty);
    });
  }
}
