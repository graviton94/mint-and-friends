import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/social_service.dart' show FriendCode;
import 'garden/garden_scene.dart' show GardenScene;

/// 자랑 카드 종류 (D-045).
enum ShareKind { garden, area, renew, legendary }

/// 자랑 카드 (1080×1350, 4:5): 앱 안에서 그림으로 그려 휴대폰 공유창으로 보낸다.
/// 말풍선 · 리본 글자 · 쓸데없는 딱지 없이: 정원 카드는 장식과 친구를 모두 놓은 실제 정원,
/// 전설 아이템만 'LV.30!' 딱지, 아래 두 친구는 카드마다 다른 종류 · 포즈.
class ShareCard {
  static const double w = 1080, h = 1350;

  static final Map<String, ui.Image> _cache = {};

  static Future<ui.Image?> _img(String path) async {
    final c = _cache[path];
    if (c != null) return c;
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final img = (await codec.getNextFrame()).image;
      _cache[path] = img;
      return img;
    } catch (_) {
      return null;
    }
  }

  /// 그림 [img] 를 [dst] 안에 비율을 지켜 (contain) 아래 가운데로.
  static Rect _fit(Canvas c, ui.Image img, Rect dst, {bool flip = false}) {
    final s = min(dst.width / img.width, dst.height / img.height);
    final ww = img.width * s, hh = img.height * s;
    final r = Rect.fromLTWH(
      dst.left + (dst.width - ww) / 2,
      dst.bottom - hh,
      ww,
      hh,
    );
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final p = Paint()..filterQuality = FilterQuality.high;
    if (flip) {
      c.save();
      c.translate(r.center.dx, 0);
      c.scale(-1, 1);
      c.translate(-r.center.dx, 0);
      c.drawImageRect(img, src, r, p);
      c.restore();
    } else {
      c.drawImageRect(img, src, r, p);
    }
    return r;
  }

  /// 그림을 [dst] 에 꽉 채워 (cover) 가운데를 자른다.
  static void _cover(Canvas c, ui.Image img, Rect dst) {
    final s = max(dst.width / img.width, dst.height / img.height);
    final sw = dst.width / s, sh = dst.height / s;
    final src = Rect.fromLTWH(
      (img.width - sw) / 2,
      (img.height - sh) / 2,
      sw,
      sh,
    );
    c.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.high);
  }

  static void _text(
    Canvas c,
    String s,
    Offset center,
    double size,
    Color color, {
    double maxW = 860,
    Color? stroke,
  }) {
    final ja = L10n.instance.lang == 'ja';
    TextStyle st(Paint? fg) => TextStyle(
      fontFamily: ja ? 'MochiyPop' : 'Jua',
      fontFamilyFallback: ja ? const ['Jua'] : const ['MochiyPop'],
      fontSize: size,
      color: fg == null ? color : null,
      foreground: fg,
      height: 1.15,
    );
    TextPainter tp(Paint? fg) => TextPainter(
      text: TextSpan(text: s, style: st(fg)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    final t = tp(null);
    final o = center - Offset(t.width / 2, t.height / 2);
    if (stroke != null) {
      tp(
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.16
          ..strokeJoin = StrokeJoin.round
          ..color = stroke,
      ).paint(c, o);
    }
    t.paint(c, o);
  }

  /// 친구 그림 후보: 기본 · 기쁨 · 인사, 그리고 카드용 특별 자세가 있는 친구는 그 자세.
  static const Map<String, String> _special = {
    'bori': 'camera',
    'dubu': 'sign',
    'kwak': 'flag',
    'nabi': 'frame',
  };

  /// 오른쪽을 보고 있는 친구 그림 (나머지는 왼쪽을 본다).
  static const List<String> _facingRight = ['bori_camera'];

  static List<String> _cornerPaths(GameState g, Random rng) {
    final ids = g.friends.toList()..shuffle(rng);
    if (ids.length < 2) ids.addAll(['bori', 'dubu']);
    final out = <String>[];
    for (final id in ids) {
      if (out.length == 2) break;
      final f = Friends.byId(id);
      final poses = [
        Art.friend(f, happy: true).path,
        Art.friend(f).path,
        if (Art.friendPose(f, 'wave') != null) Art.friendPose(f, 'wave')!.path,
        if (_special[id] != null &&
            Art.friendPose(f, _special[id]!) != null) ...[
          Art.friendPose(f, _special[id]!)!.path,
          Art.friendPose(f, _special[id]!)!.path,
        ],
      ];
      out.add(poses[rng.nextInt(poses.length)]);
    }
    return out;
  }

  /// 정원 사진: 배경 + 놓은 장식(고른 디자인) + 친구들 (게임 화면과 같은 배치 규칙).
  static Future<void> _garden(
    Canvas c,
    Rect dst,
    GameState g,
    int area,
    Random rng,
  ) async {
    final a = Garden.areaAt(area);
    final bg = await _img(Art.areaBackground(a).path);
    // 장면 좌표 (가로 1.5:1) → 창을 꽉 채우게
    final sw = max(dst.width, dst.height * 1.5);
    final sh = sw / 1.5;
    final ox = dst.left + (dst.width - sw) / 2;
    final oy = dst.top + (dst.height - sh) / 2;
    c.save();
    c.clipRect(dst);
    if (bg != null) {
      _cover(c, bg, Rect.fromLTWH(ox, oy, sw, sh));
    } else {
      c.drawRect(dst, Paint()..color = Color(a.sky));
    }
    final unit = min(sw, sh * 1.6);
    final layers = <(double, ui.Image, Rect)>[];
    for (var i = 0; i < a.decor.length; i++) {
      if (!g.isPlaced(area, i)) continue;
      final d = a.decor[i];
      final img = await _img(Art.decor(d, style: g.styleOf(area, i)).path);
      if (img == null) continue;
      final sz = unit * GardenScene.decorK * 1.5; // 카드에서는 크게 (조금 겹쳐도 됨)
      final px = ox + d.x.clamp(0.08, 0.92) * sw, py = oy + d.y * sh;
      layers.add((
        py + sz * 0.44,
        img,
        Rect.fromCenter(
          center: Offset(px, py),
          width: sz * 1.02,
          height: sz * 1.02,
        ),
      ));
    }
    final friends = g.friends.toList()..shuffle(rng);
    final zone = a.walk.first;
    for (final id in friends.take(5)) {
      final img = await _img(
        Art.friend(
          Friends.byId(id),
          happy: rng.nextBool(),
          outfit: g.outfitOf(id),
        ).path,
      );
      if (img == null) continue;
      final fx = zone.x0 + 0.06 + rng.nextDouble() * (zone.x1 - zone.x0 - 0.12);
      final fy = zone.y0 + 0.15 + rng.nextDouble() * (zone.y1 - zone.y0 - 0.2);
      final sz = unit * GardenScene.friendK * 1.5;
      final px = ox + fx * sw, py = oy + fy * sh;
      layers.add((py, img, Rect.fromLTWH(px - sz / 2, py - sz, sz, sz)));
    }
    layers.sort((x, y) => x.$1.compareTo(y.$1));
    for (final (_, img, r) in layers) {
      _fit(c, img, r, flip: rng.nextInt(4) == 0);
    }
    c.restore();
  }

  /// 카드 한 장을 PNG 로.
  static Future<Uint8List> render({
    required ShareKind kind,
    required GameState game,
    int? area,
    Chain? chain,
    int seeds = 0,
    String? code,
    String? name,
    int? seed,
  }) async {
    final rng = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
    // 바탕: 크림색 + 위쪽 반짝이 조각
    c.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, h), const [
          Color(0xFFFFF7E6),
          Color(0xFFEAF6DC),
        ]),
    );
    // 새 배치 (D-083): 위쪽은 정원 사진을 크게, 아래 크림 칸에 제목 · 숫자 칩 · 친구 코드
    const win = Rect.fromLTWH(40, 40, 1000, 820);
    final winR = RRect.fromRectAndRadius(win, const Radius.circular(48));

    // ① 사진 (프레임 아래 층). 창 밖으로 나간 부분은 ② 프레임이 덮는다.
    c.save();
    c.clipRRect(winR);
    final a = area ?? game.currentArea;
    var title = '', sub = '';
    int? legendLevel;
    switch (kind) {
      case ShareKind.garden:
      case ShareKind.area:
        await _garden(c, win, game, a, rng);
        final an = areaName(Garden.areaAt(a));
        title = kind == ShareKind.area
            ? tr('share.areaTitle', {'name': an})
            : tr('share.gardenTitle');
        sub = kind == ShareKind.area
            ? tr('share.areaSub')
            : tr('share.gardenSub', {
                'name': name == null || name.isEmpty ? an : name,
                'level': game.level,
              });
      case ShareKind.renew:
        c.drawRect(win, Paint()..color = const Color(0xFFDDF0CF));
        final halo = await _img(Art.frame('share_halo').path);
        if (halo != null) _fit(c, halo, win.deflate(10));
        final hero = await _img(Art.frame('renew_hero').path);
        if (hero != null) _fit(c, hero, win.deflate(30));
        title = tr('share.renewTitle', {'n': game.renewCount});
        sub = tr('share.renewSub', {'n': seeds});
      case ShareKind.legendary:
        final ch = chain ?? Chain.flower;
        final lv = Chains.maxLevel(ch);
        c.drawRect(win, Paint()..color = const Color(0xFFFFF0C9));
        final rays = await _img(Art.frame('rays').path);
        if (rays != null) _cover(c, rays, win);
        final halo = await _img(Art.frame('share_halo').path);
        if (halo != null) {
          _fit(
            c,
            halo,
            Rect.fromCenter(
              center: win.center,
              width: win.height * 1.05,
              height: win.height * 1.05,
            ),
          );
        }
        final item = await _img(Art.item(ch, lv).path);
        if (item != null) {
          _fit(
            c,
            item,
            Rect.fromCenter(
              center: win.center.translate(0, 10),
              width: win.height * 0.72,
              height: win.height * 0.72,
            ),
          );
        }
        legendLevel = lv;
        title = tr('share.legendTitle', {
          'name': itemName(Chains.item(ch, lv)),
        });
        sub = tr('share.legendSub', {'chain': chainName(ch), 'n': lv});
    }
    c.restore();

    // ② 사진 테두리 (갈색 굵은 선 + 안쪽 흰 선)
    c.drawRRect(
      winR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = const Color(0xFF7A5230),
    );
    c.drawRRect(
      winR.deflate(9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // ③ 전설 아이템만: 창 오른쪽 위에 레벨 딱지 (프레임 위 맨 앞), 글자는 딱지 그림의 정가운데
    if (legendLevel != null) {
      final badge = await _img(Art.frame('share_level_badge').path);
      if (badge != null) {
        final br = _fit(
          c,
          badge,
          Rect.fromCenter(
            center: win.topRight.translate(-130, 124),
            width: 190,
            height: 190,
          ),
        );
        _text(
          c,
          'LV.$legendLevel!',
          br.center,
          46,
          Colors.white,
          maxW: br.width * 0.8,
          stroke: const Color(0xFFB8560E),
        );
      }
    }

    // 로고: 사진 왼쪽 위 모서리에 스티커처럼
    final lang = L10n.instance.lang;
    final logo =
        await _img('assets/art/title/logo_$lang.webp') ??
        await _img('assets/art/title/logo_en.webp');
    if (logo != null) {
      _fit(c, logo, const Rect.fromLTWH(76, 74, 340, 126)); // 테두리에서 띄워서
    }

    // 제목
    _text(
      c,
      title,
      const Offset(w / 2, 945),
      72,
      const Color(0xFF5C402C),
      maxW: 960,
    );
    _text(
      c,
      sub,
      const Offset(w / 2, 1018),
      34,
      const Color(0xFF8A6A4C),
      maxW: 900,
    );

    // 숫자 칩: 레벨 · 놓은 장식 · 친구
    var placed = 0;
    for (var i = 0; i < Garden.areas.length; i++) {
      for (var j = 0; j < Garden.areaAt(i).decor.length; j++) {
        if (game.isPlaced(i, j)) placed++;
      }
    }
    final chips = <(String?, String)>[
      (null, tr('share.lv', {'n': game.level})),
      (Art.icon('decorate').path, '$placed'),
      (Art.icon('friends').path, '${game.friends.length}'),
    ];
    const chipH = 76.0, gap = 18.0;
    final widths = <double>[];
    final painters = <TextPainter>[];
    for (final (icon, label) in chips) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: lang == 'ja' ? 'MochiyPop' : 'Jua',
            fontSize: 40,
            color: const Color(0xFF5C402C),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painters.add(tp);
      widths.add(tp.width + 56 + (icon == null ? 0 : 58));
    }
    var x =
        (w -
            widths.fold<double>(0, (a, b) => a + b) -
            gap * (chips.length - 1)) /
        2;
    const chipY = 1062.0;
    for (var i = 0; i < chips.length; i++) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chipY, widths[i], chipH),
        const Radius.circular(chipH / 2),
      );
      c.drawRRect(r, Paint()..color = Colors.white);
      c.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFFE2C48E),
      );
      var tx = x + 28;
      final icon = chips[i].$1;
      if (icon != null) {
        final im = await _img(icon);
        if (im != null) _fit(c, im, Rect.fromLTWH(tx, chipY + 12, 52, 52));
        tx += 58;
      }
      painters[i].paint(
        c,
        Offset(tx, chipY + (chipH - painters[i].height) / 2),
      );
      x += widths[i] + gap;
    }

    // 친구 코드 알약 (초록)
    final hasCode = code != null && code.isNotEmpty;
    if (hasCode) {
      final pill = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(w / 2, 1198),
          width: 600,
          height: 92,
        ),
        const Radius.circular(46),
      );
      c.drawRRect(pill, Paint()..color = const Color(0xFF6BBF59));
      c.drawRRect(
        pill,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = const Color(0xFF3F7F34),
      );
      _text(
        c,
        tr('share.code', {'code': FriendCode.display(code)}),
        const Offset(w / 2, 1198),
        44,
        Colors.white,
        maxW: 560,
        stroke: const Color(0xFF3F7F34),
      );
    }
    _text(
      c,
      tr('share.store'),
      Offset(w / 2, hasCode ? 1294 : 1210),
      30,
      const Color(0xFF8A6A4C),
      maxW: 560,
    );

    // 아래 양쪽 모서리에 친구 둘 (카드 안쪽을 바라본다)
    final corners = _cornerPaths(game, rng);
    bool facesRight(String path) => _facingRight.any(path.contains);
    final l = await _img(corners[0]);
    final r = await _img(corners[1]);
    if (l != null) {
      _fit(
        c,
        l,
        const Rect.fromLTWH(-10, 1110, 230, 245),
        flip: !facesRight(corners[0]),
      );
    }
    if (r != null) {
      _fit(
        c,
        r,
        const Rect.fromLTWH(860, 1110, 230, 245),
        flip: facesRight(corners[1]),
      );
    }

    final pic = rec.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }
}
