import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/config.dart';
import '../../game/format.dart';
import '../../game/game_state.dart';
import '../../i18n/l10n.dart';
import '../../i18n/names.dart';

/// 위쪽 정원 씬.
///
/// 레이어 (아래 → 위), 각 레이어는 RepaintBoundary 로 분리해 따로 다시 그린다.
///  L0 배경   : 하늘·땅 (구역 배경 이미지가 있으면 그 이미지). 구역이 바뀔 때만 다시 그림.
///  L1 월드   : 장식 + 친구 + 손님. 발 위치(y) 기준으로 앞뒤 정렬해 겹침이 자연스럽다.
///  L2 이펙트 : 말풍선, 하트·코인 떠오름.
///  L3 UI     : 구역 이름, 메뉴 버튼 등 (부모가 overlay 로 넘김).
///
/// 캐릭터 움직임은 모두 코드 애니메이션이라 그림은 정지 이미지 2장(기본/기쁨)이면 된다.
class GardenScene extends StatefulWidget {
  const GardenScene({
    super.key,
    required this.game,
    required this.area,
    required this.onSlotTap,
    required this.onVisitorTap,
    this.overlay = const [],
  });

  final GameState game;
  final int area;
  final void Function(int slot) onSlotTap;
  final VoidCallback onVisitorTap;
  final List<Widget> overlay;

  @override
  State<GardenScene> createState() => _GardenSceneState();
}

class _Walker {
  Offset pos;
  Offset target;
  double pauseLeft;
  bool facingRight = false;
  double happyLeft = 0;
  double speechLeft = 0;
  _Walker(this.pos, this.target, this.pauseLeft);
}

class _Float {
  final Offset pos;
  final String text;
  double age = 0;
  _Float(this.pos, this.text);
}

class _GardenSceneState extends State<GardenScene>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _rng = Random();
  final Map<String, _Walker> _walkers = {};
  final List<_Float> _floats = [];
  Duration _last = Duration.zero;
  double _t = 0;
  double _visitorX = 1.1;

  static const groundTop = 0.28; // 씬 높이 대비 땅 시작 위치
  static const _speed = 0.07; // 초당 이동량 (씬 크기 대비)

  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 지금 보고 있는 구역의 걸을 수 있는 땅에서 무작위 지점.
  Offset _randomSpot() {
    final zones = Garden.areaAt(widget.area).walk;
    final z = zones[_rng.nextInt(zones.length)];
    return Offset(
      z.x0 + _rng.nextDouble() * (z.x1 - z.x0),
      z.y0 + _rng.nextDouble() * (z.y1 - z.y0),
    );
  }

  int? _walkArea;

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _t += dt;

    // 구역을 넘기면 친구들을 그 구역의 땅 위로 옮긴다
    if (_walkArea != widget.area) {
      _walkArea = widget.area;
      for (final w in _walkers.values) {
        w.pos = _randomSpot();
        w.target = _randomSpot();
      }
    }
    for (final id in game.friends) {
      _walkers.putIfAbsent(
        id,
        () => _Walker(_randomSpot(), _randomSpot(), _rng.nextDouble() * 2),
      );
    }
    _walkers.removeWhere((id, _) => !game.friends.contains(id));

    for (final w in _walkers.values) {
      w.happyLeft = max(0, w.happyLeft - dt);
      w.speechLeft = max(0, w.speechLeft - dt);
      if (w.pauseLeft > 0 || w.happyLeft > 0) {
        w.pauseLeft = max(0, w.pauseLeft - dt);
        continue;
      }
      final d = w.target - w.pos;
      final dist = d.distance;
      if (dist < 0.01) {
        w.pauseLeft = 1 + _rng.nextDouble() * 3.5;
        w.target = _randomSpot();
      } else {
        w.pos += d / dist * min(dist, _speed * dt);
        w.facingRight = d.dx > 0;
      }
    }

    for (final f in _floats) {
      f.age += dt;
    }
    _floats.removeWhere((f) => f.age > 1.2);

    _visitorX = game.visitorVisible ? max(0.5, _visitorX - dt * 0.05) : 1.1;
    setState(() {});
  }

  void _tapFriend(String id, Offset at) {
    final w = _walkers[id];
    final coins = game.tapFriend(id);
    if (w != null) {
      w.happyLeft = 0.6;
      w.speechLeft = 2.5;
    }
    _floats.add(_Float(at, coins == null ? '💗' : '💗 +${fmt(coins)}'));
  }

  @override
  Widget build(BuildContext context) {
    final area = Garden.areaAt(widget.area);
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: _BackgroundLayer(area: area, t: _nightTwinkle(area)),
                ),
              ),
              Positioned.fill(
                child: RepaintBoundary(
                  child: Stack(children: _worldLayer(area, size)),
                ),
              ),
              Positioned.fill(
                child: RepaintBoundary(
                  child: IgnorePointer(child: Stack(children: _fxLayer(size))),
                ),
              ),
              ...widget.overlay,
            ],
          ),
        );
      },
    );
  }

  // 밤 구역의 별 반짝임만 배경을 다시 그리게 한다 (낮 구역은 상수 → 다시 그리지 않음).
  double _nightTwinkle(AreaDef a) =>
      Color(a.sky).computeLuminance() < 0.2 ? (_t * 2).floorToDouble() : 0;

  // ---------------------------------------------------------------- L1 월드

  List<Widget> _worldLayer(AreaDef area, Size s) {
    final unit = min(s.width, s.height * 1.6);
    Offset px(double x, double y) => Offset(x * s.width, y * s.height);
    final building = widget.area == game.currentArea;
    final layers = <({double y, Widget child})>[];

    for (var i = 0; i < area.decor.length; i++) {
      final d = area.decor[i];
      final p = px(d.x, d.y);
      final sz = unit * 0.21;
      Widget child;
      if (game.isPlaced(widget.area, i)) {
        child = TweenAnimationBuilder<double>(
          key: ValueKey('decor-${widget.area}-$i'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (_, v, ch) => Transform.scale(
            scale: v,
            alignment: Alignment.bottomCenter,
            child: ch,
          ),
          child: ArtImage(Art.decor(d), size: sz),
        );
      } else if (building) {
        final affordable = game.canPlace(i);
        final pulse = affordable ? 1 + 0.08 * sin(_t * 5) : 1.0;
        child = GestureDetector(
          onTap: () => widget.onSlotTap(i),
          child: Transform.scale(
            scale: pulse,
            child: Container(
              width: sz,
              height: sz,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: affordable ? 0.75 : 0.35),
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                game.areaLocked
                    ? '🔒'
                    : '${affordable ? '✨' : '+'}\n⭐${game.decorCost(i)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: sz * 0.22,
                  height: 1.1,
                  color: const Color(0xFF4A5A3A),
                ),
              ),
            ),
          ),
        );
      } else {
        continue;
      }
      layers.add((
        y: d.y,
        child: Positioned(
          left: p.dx - sz * 0.6,
          top: p.dy - sz * 0.6,
          width: sz * 1.2,
          height: sz * 1.2,
          child: Center(child: child),
        ),
      ));
    }

    for (final e in _walkers.entries) {
      final f = Friends.byId(e.key);
      final wk = e.value;
      final p = px(wk.pos.dx, wk.pos.dy);
      final sz = unit * 0.17;
      final walking = wk.pauseLeft <= 0 && wk.happyLeft <= 0;
      final bob = walking ? -(sin(_t * 10).abs()) * sz * 0.12 : 0.0;
      final jump = wk.happyLeft > 0
          ? -sin((0.6 - wk.happyLeft) / 0.6 * pi) * sz * 0.4
          : 0.0;
      layers.add((
        y: wk.pos.dy,
        child: Positioned(
          left: p.dx - sz * 0.6,
          top: p.dy - sz + bob + jump,
          width: sz * 1.2,
          height: sz * 1.2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapFriend(e.key, p - Offset(0, sz)),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(bottom: 0, child: _Shadow(width: sz * 0.7)),
                ArtImage(
                  Art.friend(f, happy: wk.happyLeft > 0),
                  size: sz,
                  flipX: wk.facingRight,
                ),
              ],
            ),
          ),
        ),
      ));
    }

    if (game.visitorVisible) {
      final p = px(_visitorX, Garden.areaAt(widget.area).walk.first.y1 - 0.04);
      final sz = unit * 0.17;
      final bounce = sin(_t * 6).abs() * sz * 0.1;
      layers.add((
        y: 0.62,
        child: Positioned(
          left: p.dx - sz,
          top: p.dy - sz * 1.6 - bounce,
          width: sz * 2,
          height: sz * 1.9,
          child: GestureDetector(
            onTap: widget.onVisitorTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArtImage(Art.gift, size: sz * 0.55),
                ArtImage(Art.visitor(), size: sz),
              ],
            ),
          ),
        ),
      ));
    }

    layers.sort((a, b) => a.y.compareTo(b.y));
    return [for (final l in layers) l.child];
  }

  // ---------------------------------------------------------------- L2 이펙트

  List<Widget> _fxLayer(Size s) {
    final out = <Widget>[];
    final unit = min(s.width, s.height * 1.6);
    for (final e in _walkers.entries) {
      final wk = e.value;
      if (wk.speechLeft <= 0) continue;
      final p = Offset(wk.pos.dx * s.width, wk.pos.dy * s.height);
      out.add(
        Positioned(
          left: (p.dx - 90).clamp(4.0, max(4.0, s.width - 184)),
          top: max(4.0, p.dy - unit * 0.13 * 2.1),
          width: 180,
          child: _Bubble(text: '${friendName(e.key)}: ${friendLine(e.key)}'),
        ),
      );
    }
    for (final f in _floats) {
      out.add(
        Positioned(
          left: f.pos.dx - 60,
          top: f.pos.dy - f.age * 40,
          width: 120,
          child: Opacity(
            opacity: (1.2 - f.age).clamp(0.0, 1.0),
            child: Text(
              f.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }
}

// ---------------------------------------------------------------- L0 배경

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer({required this.area, required this.t});
  final AreaDef area;
  final double t;

  @override
  Widget build(BuildContext context) {
    final bg = Art.areaBackground(area);
    if (bg.available) return Image.asset(bg.path, fit: BoxFit.cover);
    final night = Color(area.sky).computeLuminance() < 0.2;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        return Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: Color(area.sky))),
            if (night)
              for (var i = 0; i < 12; i++)
                Positioned(
                  left: (i * 0.083 + 0.03) * w,
                  top: ((i * 37) % 23) / 100 * h,
                  child: Opacity(
                    opacity: 0.5 + 0.5 * sin(t + i).abs(),
                    child: const Text(
                      '✦',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            Positioned(
              left: -w * 0.1,
              right: -w * 0.1,
              top: h * _GardenSceneState.groundTop,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(area.ground),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.elliptical(w, h * 0.12),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Shadow extends StatelessWidget {
  const _Shadow({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 0.22,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(width),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: Color(0xFF3A3A3A)),
    ),
  );
}

/// L3 오버레이에서 쓰는 구역 이름표.
String areaLabel(GameState game, int areaIndex) {
  final a = Garden.areaAt(areaIndex);
  final name = areaName(a);
  if (areaIndex < game.currentArea) return '${a.emoji} $name ✅';
  if (game.areaLocked)
    return '${a.emoji} $name  ${tr('common.lockedLevel', {'n': game.areaRequiredLevel})}';
  return '${a.emoji} $name  ${game.placed.length}/${Garden.slotsPerArea}';
}
