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

/// 자랑 카드 종류 (D-045).
enum ShareKind { garden, area, renew, legendary }

/// 자랑 카드 (1080×1350, 4:5): 앱 안에서 그림으로 그려 휴대폰 공유창으로 보낸다.
/// 말풍선 · 리본 글자 · 쓸데없는 딱지 없이: 정원 카드는 장식과 친구를 모두 놓은 실제 정원,
/// 전설 아이템만 'LV.30!' 딱지, 아래 두 친구는 카드마다 다른 종류 · 포즈.
class ShareCard {
  static const double w = 1080, h = 1350;

  // 프레임 그림(share_frame, 1024 정사각) 안에서 그림 부분 · 사진 창 · 글자 띠 위치.
  // 프레임 그림 전체 (잎 · 꽃 끝까지, 잘리지 않게) · 사진 창 갈색 선 안쪽 · 글자 띠.
  static const Rect _frameSrc = Rect.fromLTRB(121, 62, 903, 963);
  static const Rect _windowSrc = Rect.fromLTRB(235, 239, 778, 605);
  static const double _windowRadiusSrc = 30;
  static const Rect _bandSrc = Rect.fromLTRB(214, 700, 812, 812);
  static const double _frameW = 1040, _frameX = (w - _frameW) / 2;
  static const double _frameY = 18;
  static double get _s => _frameW / _frameSrc.width;
  static Rect _map(Rect r) => Rect.fromLTRB(
    _frameX + (r.left - _frameSrc.left) * _s,
    _frameY + (r.top - _frameSrc.top) * _s,
    _frameX + (r.right - _frameSrc.left) * _s,
    _frameY + (r.bottom - _frameSrc.top) * _s,
  );

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
  static void _fit(Canvas c, ui.Image img, Rect dst, {bool flip = false}) {
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
    c.clipRRect(
      RRect.fromRectAndRadius(dst, Radius.circular(_windowRadiusSrc * _s)),
    );
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
      final sz = unit * 0.18;
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
      final sz = unit * 0.15;
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
    final frame = await _img(Art.frame('share_frame').path);
    final win = _map(_windowSrc);
    final band = _map(_bandSrc);
    if (frame != null) {
      c.drawImageRect(
        frame,
        _frameSrc,
        Rect.fromLTWH(_frameX, _frameY, _frameW, _frameSrc.height * _s),
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(40, 34, 1000, 1196),
          const Radius.circular(60),
        ),
        Paint()..color = const Color(0xFFFFF3DD),
      );
    }

    // 사진 창
    final a = area ?? game.currentArea;
    var title = '', sub = '';
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
        c.save();
        c.clipRRect(
          RRect.fromRectAndRadius(win, Radius.circular(_windowRadiusSrc * _s)),
        );
        c.drawRect(win, Paint()..color = const Color(0xFFDDF0CF));
        final halo = await _img(Art.frame('share_halo').path);
        if (halo != null) _fit(c, halo, win.deflate(10));
        final hero = await _img(Art.frame('renew_hero').path);
        if (hero != null) _fit(c, hero, win.deflate(24));
        c.restore();
        title = tr('share.renewTitle', {'n': game.renewCount});
        sub = tr('share.renewSub', {'n': seeds});
      case ShareKind.legendary:
        final ch = chain ?? Chain.flower;
        final lv = Chains.maxLevel(ch);
        c.save();
        c.clipRRect(
          RRect.fromRectAndRadius(win, Radius.circular(_windowRadiusSrc * _s)),
        );
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
        c.restore();
        final badge = await _img(Art.frame('share_level_badge').path);
        final br = Rect.fromCenter(
          center: win.topRight.translate(-40, 10),
          width: 230,
          height: 230,
        );
        if (badge != null) _fit(c, badge, br);
        _text(
          c,
          'LV.$lv!',
          br.center,
          52,
          Colors.white,
          stroke: const Color(0xFFB8560E),
        );
        title = tr('share.legendTitle', {
          'name': itemName(Chains.item(ch, lv)),
        });
        sub = tr('share.legendSub', {'chain': chainName(ch), 'n': lv});
    }
    // 사진 가장자리를 프레임의 갈색 창 테두리로 다시 덮는다 (모서리가 튀어나오지 않게)
    c.drawRRect(
      RRect.fromRectAndRadius(
        win.inflate(3),
        Radius.circular(_windowRadiusSrc * _s + 3),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = const Color(0xFF7A4A2A),
    );

    // 로고: 프레임 위쪽 나무 위
    final lang = L10n.instance.lang;
    final logo =
        await _img('assets/art/title/logo_$lang.webp') ??
        await _img('assets/art/title/logo_en.webp');
    if (logo != null) {
      _fit(
        c,
        logo,
        Rect.fromCenter(
          center: const Offset(w / 2, 104),
          width: 430,
          height: 150,
        ),
      );
    }

    // 제목 (창 아래 크림 칸) · 띠 안에 한 줄 설명 + 친구 코드
    _text(
      c,
      title,
      Offset(w / 2, (win.bottom + band.top) / 2 + 4),
      60,
      const Color(0xFF5C402C),
      maxW: 900,
    );
    final hasCode = code != null && code.isNotEmpty;
    _text(
      c,
      sub,
      Offset(w / 2, band.top + band.height * (hasCode ? 0.3 : 0.5)),
      34,
      const Color(0xFF4E6B3A),
      maxW: band.width - 40,
    );
    if (hasCode) {
      _text(
        c,
        tr('share.code', {'code': FriendCode.display(code)}),
        Offset(w / 2, band.top + band.height * 0.72),
        42,
        const Color(0xFF2F7D4A),
        maxW: band.width - 40,
      );
    }

    // 아래: 스토어 안내 + 두 친구 (카드마다 다르게)
    _text(
      c,
      tr('share.store'),
      const Offset(w / 2, 1300),
      32,
      const Color(0xFF8A6A4C),
      maxW: 560,
    );
    // 두 친구는 카드 안쪽(가운데)을 바라본다. 친구 그림은 대부분 왼쪽을 보고, 카메라 토끼만 오른쪽을 본다.
    final corners = _cornerPaths(game, rng);
    bool facesRight(String path) => _facingRight.any(path.contains);
    final l = await _img(corners[0]);
    final r = await _img(corners[1]);
    if (l != null) {
      _fit(
        c,
        l,
        const Rect.fromLTWH(-4, 1046, 280, 300),
        flip: !facesRight(corners[0]),
      );
    }
    if (r != null) {
      _fit(
        c,
        r,
        const Rect.fromLTWH(804, 1046, 280, 300),
        flip: facesRight(corners[1]),
      );
    }

    final pic = rec.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }
}
