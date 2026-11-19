import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';

/// 위쪽 정원 씬. 장식이 놓이고 친구들이 돌아다닌다.
/// 움직임은 전부 코드 애니메이션이라 캐릭터 그림은 정지 이미지 2장(기본/기쁨)이면 된다.
class GardenScene extends StatefulWidget {
  const GardenScene({
    super.key,
    required this.game,
    required this.area,
    required this.onSlotTap,
    required this.onVisitorTap,
  });

  final GameState game;
  final int area;
  final void Function(int slot) onSlotTap;
  final VoidCallback onVisitorTap;

  @override
  State<GardenScene> createState() => _GardenSceneState();
}

class _Walker {
  Offset pos;
  Offset target;
  double pauseLeft;
  bool facingRight = false;
  double happyLeft = 0; // 탭했을 때 기쁨 표정 + 점프
  String? speech;
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

  static const _groundTop = 0.28; // 화면 높이 대비 땅 시작 위치
  static const _speed = 0.07; // 초당 이동 (씬 크기 대비)

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

  Offset _randomSpot() =>
      Offset(0.08 + _rng.nextDouble() * 0.84, 0.40 + _rng.nextDouble() * 0.50);

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _t += dt;

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
        final step = min(dist, _speed * dt);
        w.pos += d / dist * step;
        w.facingRight = d.dx > 0;
      }
    }

    for (final f in _floats) {
      f.age += dt;
    }
    _floats.removeWhere((f) => f.age > 1.2);

    if (game.visitorVisible) {
      _visitorX = max(0.5, _visitorX - dt * 0.05);
    } else {
      _visitorX = 1.1;
    }

    setState(() {});
  }

  void _tapFriend(String id, Offset at) {
    final w = _walkers[id];
    final coins = game.tapFriend(id);
    if (w != null) {
      w.happyLeft = 0.6;
      w.speech = Friends.byId(id).line;
      w.speechLeft = 2.5;
    }
    _floats.add(_Float(at, coins == null ? '💗' : '💗 +${fmt(coins)}'));
  }

  @override
  Widget build(BuildContext context) {
    final area = Garden.areaAt(widget.area);
    final building = widget.area == game.currentArea;
    final night = Color(area.sky).computeLuminance() < 0.2;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final unit = min(w, h * 1.6);
        Offset px(double x, double y) => Offset(x * w, y * h);

        final layers = <({double y, Widget child})>[];

        // 장식
        for (var i = 0; i < area.decor.length; i++) {
          final d = area.decor[i];
          final p = px(d.x, d.y);
          final isPlaced = game.isPlaced(widget.area, i);
          final size = unit * 0.15;
          Widget child;
          if (isPlaced) {
            child = TweenAnimationBuilder<double>(
              key: ValueKey('decor-${widget.area}-$i'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (_, s, ch) => Transform.scale(
                scale: s,
                alignment: Alignment.bottomCenter,
                child: ch,
              ),
              child: Text(d.emoji, style: TextStyle(fontSize: size)),
            );
          } else if (building) {
            final affordable = game.canPlace(i);
            final pulse = affordable ? 1 + 0.08 * sin(_t * 5) : 1.0;
            child = GestureDetector(
              onTap: () => widget.onSlotTap(i),
              child: Transform.scale(
                scale: pulse,
                child: Container(
                  width: size * 1.1,
                  height: size * 1.1,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: affordable ? 0.75 : 0.35,
                    ),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    affordable
                        ? '✨\n⭐${game.decorCost(i)}'
                        : '+\n⭐${game.decorCost(i)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: size * 0.24,
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
              left: p.dx - size * 0.6,
              top: p.dy - size * 0.6,
              width: size * 1.2,
              height: size * 1.2,
              child: Center(child: child),
            ),
          ));
        }

        // 친구들
        for (final e in _walkers.entries) {
          final f = Friends.byId(e.key);
          final wk = e.value;
          final p = px(wk.pos.dx, wk.pos.dy);
          final size = unit * 0.13;
          final walking = wk.pauseLeft <= 0 && wk.happyLeft <= 0;
          final bob = walking ? -(sin(_t * 10).abs()) * size * 0.12 : 0.0;
          final jump = wk.happyLeft > 0
              ? -sin((0.6 - wk.happyLeft) / 0.6 * pi) * size * 0.4
              : 0.0;
          layers.add((
            y: wk.pos.dy,
            child: Positioned(
              left: p.dx - size * 0.6,
              top: p.dy - size + bob + jump,
              width: size * 1.2,
              height: size * 1.2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapFriend(e.key, p - Offset(0, size)),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: size * 0.7,
                        height: size * 0.16,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(size),
                        ),
                      ),
                    ),
                    Transform.flip(
                      flipX: wk.facingRight,
                      child: Text(
                        f.emoji,
                        style: TextStyle(fontSize: size * 0.85),
                      ),
                    ),
                    if (wk.happyLeft > 0)
                      Positioned(
                        top: -size * 0.1,
                        right: -size * 0.1,
                        child: Text(
                          '💗',
                          style: TextStyle(fontSize: size * 0.3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ));
          if (wk.speechLeft > 0 && wk.speech != null) {
            layers.add((
              y: 2, // 말풍선은 항상 맨 위
              child: Positioned(
                left: (p.dx - 90).clamp(4.0, w - 184),
                top: max(4.0, p.dy - size * 2.1),
                width: 180,
                child: IgnorePointer(
                  child: _Bubble(text: '${f.name}: ${wk.speech}'),
                ),
              ),
            ));
          }
        }

        // 깜짝 손님
        if (game.visitorVisible) {
          final p = px(_visitorX, 0.62);
          final size = unit * 0.14;
          final bounce = sin(_t * 6).abs() * size * 0.1;
          layers.add((
            y: 0.62,
            child: Positioned(
              left: p.dx - size,
              top: p.dy - size * 1.6 - bounce,
              width: size * 2,
              height: size * 1.9,
              child: GestureDetector(
                onTap: widget.onVisitorTap,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎁', style: TextStyle(fontSize: size * 0.5)),
                    Text(
                      Friends.visitorEmoji,
                      style: TextStyle(fontSize: size * 0.85),
                    ),
                  ],
                ),
              ),
            ),
          ));
        }

        layers.sort((a, b) => a.y.compareTo(b.y));

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // 하늘
              Positioned.fill(child: ColoredBox(color: Color(area.sky))),
              if (night)
                for (var i = 0; i < 12; i++)
                  Positioned(
                    left: (i * 0.083 + 0.03) * w,
                    top: ((i * 37) % 23) / 100 * h,
                    child: Opacity(
                      opacity: 0.5 + 0.5 * sin(_t * 2 + i).abs(),
                      child: const Text(
                        '✦',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
              // 땅
              Positioned(
                left: -w * 0.1,
                right: -w * 0.1,
                top: h * _groundTop,
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
              for (final l in layers) l.child,
              // 떠오르는 효과
              for (final f in _floats)
                Positioned(
                  left: f.pos.dx - 60,
                  top: f.pos.dy - f.age * 40,
                  width: 120,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1.2 - f.age).clamp(0.0, 1.0),
                      child: Text(
                        f.text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
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
}
