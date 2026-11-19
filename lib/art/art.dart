import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/config.dart';

/// 아트 리소스 등록부.
///
/// 파일 이름 규칙(docs/ART_SPEC.md)에 맞는 PNG 를 assets/art/ 아래에 넣으면 자동으로 쓰이고,
/// 없으면 이모지 임시 그림으로 그린다. 코드 수정 없이 그림을 하나씩 바꿔 끼울 수 있다.
class Art {
  Art._();

  static Set<String> _available = {};

  /// 앱 시작 시 한 번 호출. 번들에 들어 있는 아트 파일 목록을 읽는다.
  static Future<void> init() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _available = manifest
          .listAssets()
          .where((p) => p.startsWith('assets/art/'))
          .toSet();
    } catch (_) {
      _available = {};
    }
  }

  static bool has(String path) => _available.contains(path);

  // ---- 경로 규칙 (docs/ART_SPEC.md 와 같아야 함)
  static ArtRef item(Chain c, int level) => ArtRef(
    'assets/art/items/${c.name}_${level.toString().padLeft(2, '0')}.png',
    Chains.item(c, level).emoji,
  );

  /// 기쁨 표정 그림이 아직 없으면 기본 그림을 쓴다 (탭할 때 이모지로 바뀌지 않게).
  static ArtRef friend(FriendDef f, {bool happy = false}) {
    final idle = ArtRef('assets/art/friends/${f.id}_idle.png', f.emoji);
    if (!happy) return idle;
    final h = ArtRef('assets/art/friends/${f.id}_happy.png', f.emoji);
    return h.available || !idle.available ? h : idle;
  }

  static ArtRef visitor() =>
      const ArtRef('assets/art/friends/visitor_idle.png', Friends.visitorEmoji);

  static ArtRef decor(DecorDef d) =>
      ArtRef('assets/art/decor/${d.id}.png', d.emoji);

  static ArtRef areaBackground(AreaDef a) =>
      ArtRef('assets/art/areas/${a.id}_bg.png', '');

  static ArtRef ui(String name, String emoji) =>
      ArtRef('assets/art/ui/$name.png', emoji);

  static const coin = ArtRef('assets/art/ui/coin.png', '🪙');
  static const star = ArtRef('assets/art/ui/star.png', '⭐');
  static const basket = ArtRef('assets/art/ui/basket.png', '🧺');
  static const lock = ArtRef('assets/art/ui/lock.png', '🔒');
  static const bubble = ArtRef('assets/art/ui/bubble.png', '🫧');
  static const gift = ArtRef('assets/art/ui/gift.png', '🎁');
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
