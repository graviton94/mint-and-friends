import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'icon_text.dart';

/// 이야기 · 편지 · 공지 본문 (D-125, 사용자 규칙):
/// ① 문장이 끝나면(. ! ? … 。 ！ ？) 줄을 바꾼다.
/// ② 한 문장이 한 줄을 넘으면 낱말 단위로 줄 길이를 고르게 나눈다 (마지막 줄에 '거야.' 한 낱말만 넘어가지 않게).
/// 빈칸이 없는 일본어 문장은 ①만 (낱말 묶음 줄바꿈은 L10n 이 이미 한다).
class ProseText extends StatelessWidget {
  const ProseText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
  });
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final scaler = MediaQuery.textScalerOf(context);
      // 잰 글꼴과 그리는 글꼴이 같아야 계산한 줄이 그대로 나온다
      final st = appFontStyle(DefaultTextStyle.of(context).style.merge(style));
      final laid = c.maxWidth.isFinite
          ? proseLayout(text, st, c.maxWidth, scaler)
          : splitSentences(text);
      return IconText(laid, style: st, textAlign: textAlign, glue: false);
    },
  );
}

/// ① 문장 끝 뒤 빈칸을 줄바꿈으로. 'Lv.3' · '2.5' 처럼 빈칸 없는 점은 그대로.
String splitSentences(String s) => s
    .replaceAllMapped(
      RegExp(r'([.!?…。！？]+["”’」』)）]?)[ \t]+(?=\S)'),
      (m) => '${m[1]}\n',
    )
    .replaceAll(RegExp(r'\n{3,}'), '\n\n');

/// ①을 한 뒤 각 줄을 폭 [maxWidth] 안에서 고르게 나눈다.
String proseLayout(
  String s,
  TextStyle style,
  double maxWidth,
  TextScaler scaler,
) {
  final limit = maxWidth * 0.96; // 글자 계산 오차 여유
  double width(String t) {
    final tp = TextPainter(
      text: TextSpan(
        // 아이콘 토큰은 글자 하나 남짓 폭으로 잰다
        text: t.replaceAll(RegExp(r'\[\[[a-z_0-9:]+\]\]'), '■'),
        style: style,
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  final out = <String>[];
  for (final line in splitSentences(s).split('\n')) {
    final words = line.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < 3 || width(line) <= limit) {
      out.add(line);
      continue;
    }
    out.add(_balance(words, width, limit).join('\n'));
  }
  return out.join('\n');
}

/// 낱말들을 폭 [limit] 안의 가장 적은 줄 수로, 줄 길이가 고르게 나눈다 (동적 계획법).
/// 마지막 줄에 낱말 하나만 남는 나눔은 피한다.
List<String> _balance(
  List<String> words,
  double Function(String) width,
  double limit,
) {
  final n = words.length;
  final space = width('a b') - width('ab');
  final w = [for (final x in words) width(x)];
  double span(int i, int j) {
    var t = 0.0;
    for (var k = i; k < j; k++) {
      t += w[k];
    }
    return t + space * (j - i - 1);
  }

  // 가장 적은 줄 수부터 차례로: 그 줄 수에서 '가장 긴 줄'이 가장 짧은 나눔
  for (var lines = 1; lines <= n; lines++) {
    // best[k][i] = 앞 i 낱말을 k 줄로 나눌 때 가장 긴 줄 폭 (불가능하면 무한)
    final inf = double.infinity;
    final best = List.generate(lines + 1, (_) => List.filled(n + 1, inf));
    final cut = List.generate(lines + 1, (_) => List.filled(n + 1, -1));
    best[0][0] = 0;
    for (var k = 1; k <= lines; k++) {
      for (var i = 1; i <= n; i++) {
        for (var j = k - 1; j < i; j++) {
          if (best[k - 1][j] == inf) continue;
          final sw = span(j, i);
          if (sw > limit) continue;
          // 마지막 줄이 낱말 하나면 크게 손해 (다른 나눔이 있으면 그쪽)
          final orphan = k == lines && i == n && i - j == 1 && n > 2;
          final cost = max(best[k - 1][j], sw) + (orphan ? limit : 0);
          if (cost < best[k][i]) {
            best[k][i] = cost;
            cut[k][i] = j;
          }
        }
      }
    }
    if (best[lines][n] == inf) continue;
    // 고르게 나눈 결과의 가장 긴 줄보다 조금 넉넉하게 위에서부터 채워 본다:
    // 같은 줄 수이고 마지막 줄이 낱말 하나가 아니면, 윗줄이 긴 쪽이 읽기 자연스럽다.
    if (lines > 1) {
      final cap = min(limit, best[lines][n] * 1.12);
      final g = <String>[];
      var cur = <String>[];
      for (final x in words) {
        if (cur.isNotEmpty && width([...cur, x].join(' ')) > cap) {
          g.add(cur.join(' '));
          cur = [];
        }
        cur.add(x);
      }
      g.add(cur.join(' '));
      if (g.length == lines && (n <= 2 || cur.length > 1)) return g;
    }
    final out = <String>[];
    var i = n;
    for (var k = lines; k >= 1; k--) {
      final j = cut[k][i];
      out.insert(0, words.sublist(j, i).join(' '));
      i = j;
    }
    return out;
  }
  return [words.join(' ')];
}
