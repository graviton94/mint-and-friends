import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/config.dart';
import '../ui/garden/garden_scene.dart' show FxSprites;

/// 아트 리소스 등록부.
///
/// 파일 이름 규칙(docs/ART_SPEC.md)에 맞는 PNG 를 assets/art/ 아래에 넣으면 자동으로 쓰이고,
/// 없으면 이모지 임시 그림으로 그린다. 코드 수정 없이 그림을 하나씩 바꿔 끼울 수 있다.
class Art {
  Art._();

  static Set<String> _available = {};

  /// 앱 시작 시 한 번 호출. 번들에 들어 있는 아트 파일 목록을 읽는다.
  static Future<void> init() async {
    unawaited(FxSprites.load());
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      try {
        final raw = await rootBundle.loadString(
          'assets/art/frames/frames.json',
        );
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _frameSizes = {
          for (final e in m.entries)
            e.key: Size(
              ((e.value as List)[0] as num).toDouble(),
              ((e.value as List)[1] as num).toDouble(),
            ),
        };
      } catch (_) {
        _frameSizes = {};
      }
      _available = manifest
          .listAssets()
          .where((p) => p.startsWith('assets/art/'))
          .toSet();
    } catch (_) {
      _available = {};
    }
    // 새 구역은 배경 · 장식 · 데려오는 친구 그림이 모두 들어와야 연다
    Garden.ready = (a) =>
        Garden.areas.indexOf(a) < Garden.coreAreas ||
        (areaBackground(a).available &&
            a.decor.every((d) => decor(d).available) &&
            a.decor.every(
              (d) =>
                  d.bringsFriend == null ||
                  friend(Friends.byId(d.bringsFriend!)).available,
            ));
    // 새 체인은 단계 그림이 모두 들어와야 연다 (꽃 · 간식은 언제나)
    Chains.ready = (c) =>
        c == Chain.flower ||
        c == Chain.snack ||
        [for (var l = 1; l <= Chains.baseArtLevels(c); l++) _itemRef(c, l)]
            .every((r) => r.available);
  }

  static bool has(String path) => _available.contains(path);

  // ---- 경로 규칙 (docs/ART_SPEC.md 와 같아야 함)
  static ArtRef _itemRef(Chain c, int level) => ArtRef(
    'assets/art/items/${c.name}_${level.toString().padLeft(2, '0')}.webp',
    Chains.item(c, level).emoji,
  );

  /// 아이템 그림. 아직 그림이 없는 높은 단계(30단계 확장분)는 그 체인의 가장 높은 그림으로 대신한다.
  static ArtRef item(Chain c, int level) {
    final r = _itemRef(c, level);
    if (r.available || _available.isEmpty) return r;
    for (var l = level - 1; l >= 1; l--) {
      final f = _itemRef(c, l);
      if (f.available) return f;
    }
    return r;
  }

  /// 기쁨 표정 그림이 아직 없으면 기본 그림을 쓴다 (탭할 때 이모지로 바뀌지 않게).
  static ArtRef friend(FriendDef f, {bool happy = false, String? outfit}) {
    if (outfit != null) {
      final o = outfitArt(f, outfit, happy: happy);
      if (o.available) return o;
      final oi = outfitArt(f, outfit);
      if (oi.available) return oi;
    }
    final idle = ArtRef('assets/art/friends/${f.id}_idle.webp', f.emoji);
    if (!happy) return idle;
    final h = ArtRef('assets/art/friends/${f.id}_happy.webp', f.emoji);
    return h.available || !idle.available ? h : idle;
  }

  static ArtRef outfitArt(FriendDef f, String outfit, {bool happy = false}) =>
      ArtRef(
        'assets/art/friends/${f.id}_${outfit}_${happy ? 'happy' : 'idle'}.webp',
        f.emoji,
      );

  /// 이 친구가 입을 수 있는 의상 (그림이 들어온 것만).
  static List<OutfitDef> outfitsFor(FriendDef f) => [
    for (final o in Outfits.all)
      if (outfitArt(f, o.id).available) o,
  ];

  /// 추가 자세 (sleep · wave). 의상을 입었으면 그 의상의 자세 그림을 먼저 찾는다.
  /// 그림이 없으면 null → 기본 자세로 행동만 한다.
  static ArtRef? friendPose(FriendDef f, String pose, {String? outfit}) {
    if (outfit != null) {
      final o = ArtRef(
        'assets/art/friends/${f.id}_${outfit}_$pose.webp',
        f.emoji,
      );
      // 의상 자세 그림이 아직 없으면 기본 옷 자세로 갈아입히지 않고 의상 기본 그림을 쓴다
      return o.available ? o : null;
    }
    final r = ArtRef('assets/art/friends/${f.id}_$pose.webp', f.emoji);
    return r.available ? r : null;
  }

  static ArtRef visitor() => const ArtRef(
    'assets/art/friends/visitor_idle.webp',
    Friends.visitorEmoji,
  );

  /// 장식 그림. style 1 = 고급(_b), 2 = 특별(_c). 그 그림이 아직 없으면 기본 그림.
  static ArtRef decor(DecorDef d, {int style = 0}) {
    final base = ArtRef('assets/art/decor/${d.id}.webp', d.emoji);
    if (style == 0) return base;
    final v = decorStyle(d, style);
    return v.available ? v : base;
  }

  static ArtRef decorStyle(DecorDef d, int style) => ArtRef(
    'assets/art/decor/${d.id}_${switch (style) {
      1 => 'b',
      2 => 'c',
      _ => Garden.seasonStyles[style] ?? 'c',
    }}.webp',
    d.emoji,
  );

  /// 이 장식에 고를 수 있는 디자인 (그림이 들어온 것만).
  static List<int> decorStyles(DecorDef d) => [
    0,
    for (var s = 1; s < Garden.styles; s++)
      if (decorStyle(d, s).available) s,
  ];

  static ArtRef areaBackground(AreaDef a) =>
      ArtRef('assets/art/areas/${a.id}_bg.webp', '');

  static ArtRef ui(String name, String emoji) =>
      ArtRef('assets/art/ui/$name.webp', emoji);

  /// UI 아이콘. 발주서 "UI 아이콘 2·3" 시트로 받는다. 파일이 없으면 이모지로 대신 그린다.
  static const Map<String, String> iconFallback = {
    'golden_seed': '🌰',
    'renew': '🔄',
    'seed_basket': '🧺',
    'seed_coin': '🪙',
    'seed_memory': '🫙',
    'round_badge': '🏅',
    'xp': '🌱',
    'heart_level': '💗',
    'close': '✖️',
    'back': '⬅️',
    'expand': '⛶',
    'edit': '✏️',
    'plus': '➕',
    'chevron': '▶',
    'energy': '⚡',
    'ad': '📺',
    'settings': '⚙️',
    'no_ads': '🚫',
    'book': '📖',
    'upgrade': '⬆️',
    'decorate': '🔨',
    'heart': '💗',
    'refresh': '🔄',
    'sparkle': '✨',
    'letter': '💌',
    'unknown': '❔',
    'arrow_left': '◀️',
    'arrow_right': '▶️',
    'check': '✅',
    'trophy': '🏆',
    'party': '🎉',
    'moon': '🌙',
    'auto': '🤖',
    'timer': '⏱️',
    'coinbag': '💰',
    'quality': '🌟',
    'area_yard': '🏡',
    'area_pond': '🪷',
    'area_greenhouse': '🪴',
    'area_starry_hill': '🌙',
    'sprout': '🌱',
    'storage': '📦',
    'boost': '',
    'energy_jar': '',
    'hand_point': '',
    'hand_press': '',
    'menu': '',
    'friends': '',
    'visit': '',
    'notice': '',
    'diamond': '',
    'dia_1': '',
    'dia_2': '',
    'dia_3': '',
    'dia_4': '',
    'dia_5': '',
    'shop': '',
    'calendar': '',
    'swap': '',
    'tea_basket': '',
    'star_jar': '',
    'outfit': '',
    'area_seaside': '',
    'area_snow_village': '',
  };

  /// 이미 받은 UI 그림(assets/art/ui)으로 그리는 아이콘.
  static const Map<String, ArtRef> _uiIcons = {
    'coin': coin,
    'star': star,
    'basket': basket,
    'lock': lock,
    'bubble': bubble,
    'gift': gift,
  };

  static ArtRef icon(String id) {
    final ui = _uiIcons[id];
    if (ui != null) return ui;
    if (id == 'visitor') return visitor();
    if (id == 'sprout') return item(Chain.flower, 2);
    // 로그인 회사 로고: 공식 리소스에서 뽑은 그림 (design/login/official)
    if (id == 'kakao')
      return const ArtRef('assets/art/brand/kakao_symbol.png', '');
    if (id == 'google')
      return const ArtRef('assets/art/brand/google_g.png', '');
    final r = ArtRef('assets/art/icons/$id.webp', iconFallback[id] ?? '•');
    // 구역 엠블럼이 아직 없으면 그 구역의 첫 장식 그림으로
    if (!r.available && id.startsWith('area_')) {
      for (final a in Garden.areas) {
        if ('area_${a.id}' == id) return decor(a.decor.first);
      }
    }
    return r;
  }

  static ArtRef areaIcon(AreaDef a) => icon('area_${a.id}');

  /// 9-slice 프레임 (버튼, 모달, 카드, 토스트, 말풍선…). 384x384 정사각, 가장자리 30% 는 늘어나지 않는다.
  static ArtRef frame(String id) => ArtRef('assets/art/frames/$id.webp', '');

  /// 프레임 원본 크기 (assets/art/frames/frames.json, tool/import_art.py 가 만든다).
  static Map<String, Size> _frameSizes = {};

  /// 프레임 그림 원본 크기 (frames.json). 없으면 null.
  static Size? frameSize(String id) => _frameSizes[id];

  /// 9-slice 가운데 영역: 짧은 변의 40% 를 모서리로 남긴다 (알약 버튼의 둥근 끝이 찌그러지지 않게).
  static Rect? frameCenter(String id) {
    final sz = _frameSizes[id];
    if (sz == null) return null;
    final inset = min(sz.width, sz.height) * 0.4;
    return Rect.fromLTRB(inset, inset, sz.width - inset, sz.height - inset);
  }

  /// 모서리(가장자리) 크기 px — 화면에서 원하는 모서리 크기로 배율을 정할 때 쓴다.
  static double frameInset(String id) {
    final sz = _frameSizes[id];
    return sz == null ? 0 : min(sz.width, sz.height) * 0.4;
  }

  static const coin = ArtRef('assets/art/ui/coin.webp', '🪙');
  static const star = ArtRef('assets/art/ui/star.webp', '⭐');
  static const basket = ArtRef('assets/art/ui/basket.webp', '🧺');
  static const lock = ArtRef('assets/art/ui/lock.webp', '🔒');
  static const bubble = ArtRef('assets/art/ui/bubble.webp', '🫧');
  static const gift = ArtRef('assets/art/ui/gift.webp', '🎁');
}

class ArtRef {
  final String path;
  final String emoji;
  const ArtRef(this.path, this.emoji);

  bool get available => Art.has(path);
}

/// 아트가 있으면 이미지, 없으면 이모지로 그리는 위젯.
class ArtImage extends StatelessWidget {
  const ArtImage(this.ref, {super.key, required this.size, this.flipX = false});
  final ArtRef ref;
  final double size;
  final bool flipX;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (ref.available) {
      child = Image.asset(
        ref.path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    } else if (ref.emoji.isEmpty) {
      // 다이아 그림이 오기 전: 코드로 그린 민트 보석
      if (ref.path.contains('/icons/diamond') ||
          ref.path.contains('/icons/dia_')) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _GemPainter()),
        );
      }
      return SizedBox(width: size, height: size);
    } else {
      child = SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            ref.emoji,
            style: TextStyle(fontSize: size * 0.82, height: 1.0),
          ),
        ),
      );
    }
    return flipX ? Transform.flip(flipX: true, child: child) : child;
  }
}

/// 다이아 임시 그림: 외곽선 있는 민트빛 보석 (게임 그림체와 같은 갈색 외곽선).
class _GemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = h * 0.2, mid = h * 0.42, bottom = h * 0.88;
    final outline = Path()
      ..moveTo(w * 0.28, top)
      ..lineTo(w * 0.72, top)
      ..lineTo(w * 0.9, mid)
      ..lineTo(w * 0.5, bottom)
      ..lineTo(w * 0.1, mid)
      ..close();
    canvas.drawPath(outline, Paint()..color = const Color(0xFF7FE0D0));
    final upper = Path()
      ..moveTo(w * 0.28, top)
      ..lineTo(w * 0.72, top)
      ..lineTo(w * 0.9, mid)
      ..lineTo(w * 0.1, mid)
      ..close();
    canvas.drawPath(upper, Paint()..color = const Color(0xFFB8F2E8));
    final shine = Path()
      ..moveTo(w * 0.32, top + h * 0.04)
      ..lineTo(w * 0.46, top + h * 0.04)
      ..lineTo(w * 0.38, mid - h * 0.03)
      ..lineTo(w * 0.2, mid - h * 0.03)
      ..close();
    canvas.drawPath(shine, Paint()..color = const Color(0xCCFFFFFF));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, w * 0.06)
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF5A3A1E);
    canvas.drawPath(outline, stroke);
    canvas.drawLine(
      Offset(w * 0.1, mid),
      Offset(w * 0.9, mid),
      stroke..strokeWidth = max(1.0, w * 0.035),
    );
    canvas.drawLine(Offset(w * 0.5, bottom), Offset(w * 0.36, mid), stroke);
    canvas.drawLine(Offset(w * 0.5, bottom), Offset(w * 0.64, mid), stroke);
  }

  @override
  bool shouldRepaint(_GemPainter oldDelegate) => false;
}
