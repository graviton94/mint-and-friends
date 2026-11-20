import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/config.dart';

/// 문구 속 아이콘 토큰을 그림으로 바꿔 그리는 Text.
///
/// 토큰: `[[coin]]` `[[star]]` `[[energy]]` … (Art.icon), `[[item:flower:3]]`, `[[friend:bori]]`, `[[decor:bench]]`.
/// 다국어 문구(assets/i18n/*.json)에는 이모지 대신 이 토큰을 쓴다. 아트가 없으면 Art 가 이모지로 대신 그린다.
class IconText extends StatelessWidget {
  const IconText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.iconScale = 1.25,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final double iconScale;

  static final RegExp _token = RegExp(r'\[\[([a-z_0-9:]+)\]\]');

  static ArtRef resolve(String token) {
    final p = token.split(':');
    switch (p.first) {
      case 'item':
        if (p.length == 3) {
          return Art.item(Chain.values.byName(p[1]), int.tryParse(p[2]) ?? 1);
        }
      case 'friend':
        if (p.length == 2) {
          return p[1] == 'visitor'
              ? Art.visitor()
              : Art.friend(Friends.byId(p[1]));
        }
      case 'decor':
        if (p.length == 2) {
          for (final a in Garden.areas) {
            for (final d in a.decor) {
              if (d.id == p[1]) return Art.decor(d);
            }
          }
        }
    }
    return Art.icon(token);
  }

  /// 한국어는 낱말 사이(띄어쓰기)에서만 줄을 바꾼다: 붙어 있는 글자 사이에
  /// 줄바꿈 금지 문자(U+2060)를 넣는다. 한글이 섞인 낱말에만 적용 (영어 · 일본어는 그대로).
  static String keepWords(String s) {
    bool space(int x) => x == 0x20 || x == 0x0A || x == 0x2060;
    bool hangul(int c) =>
        (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x3131 && c <= 0x318E);
    final b = StringBuffer();
    final runes = s.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      final c = runes[i];
      // " · " 로 묶인 말(레벨업 · 출석 · 업적)은 가운뎃점 앞뒤에서 줄을 바꾸지 않는다
      if (c == 0x20 &&
          ((i + 1 < runes.length && runes[i + 1] == 0xB7) ||
              (i > 0 && runes[i - 1] == 0xB7))) {
        b.write('\u00A0');
        continue;
      }
      b.writeCharCode(c);
      if (i + 1 < runes.length) {
        final n = runes[i + 1];
        if (!space(c) && !space(n) && (hangul(c) || hangul(n)))
          b.write('\u2060');
      }
    }
    return b.toString();
  }

  /// 토큰을 지운 순수 글자 (접근성 라벨, 길이 계산용).
  static String plain(String s) => s.replaceAll(_token, '').trim();

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final size = (base.fontSize ?? 14) * iconScale;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _token.allMatches(text)) {
      if (m.start > last)
        spans.add(TextSpan(text: keepWords(text.substring(last, m.start))));
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: ArtImage(resolve(m.group(1)!), size: size),
          ),
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: keepWords(text.substring(last))));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      semanticsLabel: plain(text),
    );
  }
}

/// 문구 자리표시자에 넣을 아이콘 토큰.
String itemToken(Chain c, int level) => '[[item:${c.name}:$level]]';
String friendToken(String id) => '[[friend:$id]]';
String decorToken(DecorDef d) => '[[decor:${d.id}]]';

/// 꾸미지 않은 장식 자리 표시. 프레임 그림(ui_frames: slot)이 오면 그 그림을 쓴다.
class SlotMarker extends StatelessWidget {
  const SlotMarker({
    super.key,
    required this.size,
    required this.locked,
    required this.affordable,
    required this.cost,
  });
  final double size;
  final bool locked;
  final bool affordable;
  final int cost;

  @override
  Widget build(BuildContext context) {
    final frame = Art.frame('slot');
    return Container(
      width: size,
      height: size,
      decoration: frame.available
          ? BoxDecoration(
              image: DecorationImage(
                image: AssetImage(frame.path),
                fit: BoxFit.contain,
              ),
            )
          : BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: affordable ? 0.75 : 0.35),
              border: Border.all(color: Colors.white, width: 2),
            ),
      alignment: Alignment.center,
      child: locked
          ? ArtImage(Art.lock, size: size * 0.4)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArtImage(
                  Art.icon(affordable ? 'sparkle' : 'decorate'),
                  size: size * 0.3,
                ),
                IconText(
                  '[[star]]$cost',
                  style: TextStyle(
                    fontSize: size * 0.2,
                    color: const Color(0xFF4A5A3A),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 메뉴 · 버튼 오른쪽 위의 빨간 알림 점 (숫자가 있으면 숫자).
class RedDot extends StatelessWidget {
  const RedDot({super.key, this.count});
  final int? count;

  @override
  Widget build(BuildContext context) {
    final n = count;
    final text = n == null || n <= 0 ? null : (n > 99 ? '99+' : '$n');
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: EdgeInsets.symmetric(horizontal: text == null ? 0 : 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE84A3C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: text == null
          ? null
          : Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.1,
              ),
            ),
    );
  }
}
