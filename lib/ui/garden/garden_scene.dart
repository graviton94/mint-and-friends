import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/config.dart';
import '../../game/format.dart';
import '../../game/game_state.dart';
import '../../i18n/l10n.dart';
import '../../i18n/names.dart';
import '../widgets/icon_text.dart';
import '../widgets/frame_box.dart';

/// 위쪽 정원 씬.
///
/// 레이어 (아래 → 위), 각 레이어는 RepaintBoundary 로 분리해 따로 다시 그린다.
///  L0 배경   : 하늘·땅 (구역 배경 이미지가 있으면 그 이미지). 구역이 바뀔 때만 다시 그림.
///  L1 월드   : 장식 + 친구 + 손님. 발 위치(y) 기준으로 앞뒤 정렬해 겹침이 자연스럽다.
///  L2 표시   : 아직 꾸미지 않은 장식 자리 (탭 대상이라 캐릭터 위).
///  L3 이펙트 : 말풍선, 하트·코인 떠오름. 터치를 받지 않는다.
///  L4 UI     : 구역 이름, 메뉴 버튼, 알림 (부모가 overlay 로 넘김).
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
    this.radius = 20,
    this.focusY = 0.8,
    this.markerScale = 1,
    this.showEmptySlots = true,
  });

  /// 빈 장식 자리 표시 · 가격표 (친구 정원 구경처럼 보기 전용이면 끈다).
  final bool showEmptySlots;

  final GameState game;
  final int area;
  final void Function(int slot) onSlotTap;
  final VoidCallback onVisitorTap;
  final List<Widget> overlay;

  /// 모서리 둥글기 (전체 화면 정원은 0).
  final double radius;

  /// 상자가 3:2 보다 납작할 때 캔버스의 어느 높이를 보여 줄지 (0 위 ~ 1 아래). 땅이 보이게 아래쪽 기본.
  final double focusY;

  /// 빈 장식 자리 표시 크기 배율 (작은 창에서는 키워서 누르기 쉽게).
  final double markerScale;

  /// 배경 그림 비율 (1536x1024). 씬 안의 모든 좌표는 이 비율의 캔버스 기준.
  static const double aspect = 1.5;

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
  String say = '';

  /// 잠깐 다른 자세 ('sleep' · 'wave'), 남은 시간.
  String? pose;
  double poseLeft = 0;

  /// 장식을 구경하러 가는 중이면 그 장식 이름 (도착하면 한마디).
  String? visitingDecor;

  /// 대화 상대에게 답할 차례 (남은 시간, 상대 id).
  double replyIn = 0;
  String? replyTo;
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
  StreamSubscription<GameEvent>? _sub;
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
    _sub = game.events.listen(_onGameEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
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

    _lifeTimer -= dt;
    if (_lifeTimer <= 0) {
      _lifeTimer = 6 + _rng.nextDouble() * 8;
      _randomLife();
    }
    for (final e in _walkers.entries) {
      final w = e.value;
      if (w.replyTo != null) {
        w.replyIn -= dt;
        if (w.replyIn <= 0) {
          _speak(e.key, pick('line.chatB', 3), hop: true);
          w.replyTo = null;
        }
      }
    }

    for (final w in _walkers.values) {
      w.happyLeft = max(0, w.happyLeft - dt);
      w.speechLeft = max(0, w.speechLeft - dt);
      w.poseLeft = max(0, w.poseLeft - dt);
      if (w.poseLeft <= 0) w.pose = null;
      if (w.pauseLeft > 0 || w.happyLeft > 0) {
        w.pauseLeft = max(0, w.pauseLeft - dt);
        continue;
      }
      final d = w.target - w.pos;
      final dist = d.distance;
      if (dist < 0.01) {
        w.pauseLeft = 1 + _rng.nextDouble() * 3.5;
        w.target = _randomSpot();
        final decor = w.visitingDecor;
        if (decor != null) {
          w.visitingDecor = null;
          w.pauseLeft = 3;
          w.say = tr('line.decor.${_rng.nextInt(2)}', {'decor': decor});
          w.speechLeft = 3;
          w.happyLeft = 0.6;
        }
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

  // ---------------------------------------------------------------- 대사 · 행동

  double _lifeTimer = 4;

  String pick(String prefix, int n) => tr('$prefix.${_rng.nextInt(n)}');

  /// 친구 대사 하나: 성격 대사 위주, 가끔 시간대 · 물 · 계절 대사.
  String _lineFor(String id) {
    final w = _walkers[id];
    final area = Garden.areaAt(widget.area);
    final inWater =
        w != null && area.water.any((z) => z.contains(w.pos.dx, w.pos.dy));
    final r = _rng.nextDouble();
    if (inWater && r < 0.5) return pick('line.water', 2);
    if (r < 0.25) {
      final h = DateTime.now().hour;
      final part = h < 11
          ? 'morning'
          : h < 17
          ? 'day'
          : h < 21
          ? 'evening'
          : 'night';
      return pick('line.$part', 2);
    }
    final key = 'friend.$id.line.${_rng.nextInt(6)}';
    final t = tr(key);
    return t == key ? friendLine(id) : t;
  }

  void _speak(String id, String text, {bool hop = false}) {
    final w = _walkers[id];
    if (w == null) return;
    w.say = text;
    w.speechLeft = 3.2;
    if (hop) w.happyLeft = 0.6;
  }

  /// 몇 초마다 한 가지: 혼잣말 · 둘이 대화 · 장식 구경 · 깡충.
  void _randomLife() {
    if (_walkers.isEmpty) return;
    // 자는 친구는 건드리지 않는다
    final ids = [
      for (final e in _walkers.entries)
        if (e.value.pose != 'sleep') e.key,
    ]..shuffle(_rng);
    if (ids.isEmpty) return;
    final a = ids.first;
    final r = _rng.nextDouble();
    final h = DateTime.now().hour;
    final night = h >= 21 || h < 6;
    if (night && r < 0.3) {
      // 밤에는 꾸벅꾸벅 존다 (탭하면 깬다)
      final w = _walkers[a]!;
      w.pauseLeft = 10 + _rng.nextDouble() * 8;
      w.pose = 'sleep';
      w.poseLeft = w.pauseLeft;
      // 졸기 그림에 Zzz 가 그려져 있으면 말풍선은 띄우지 않는다
      if (Art.friendPose(Friends.byId(a), 'sleep') == null) {
        w.say = 'Zzz…';
        w.speechLeft = 2.5;
      }
      return;
    }
    if (r < 0.35) {
      _speak(a, _lineFor(a));
    } else if (r < 0.6 && ids.length >= 2) {
      // 가장 가까운 친구에게 말 걸기 → 상대가 잠시 뒤 대답
      final wa = _walkers[a]!;
      final b =
          (ids.skip(1).toList()..sort(
                (x, y) => (_walkers[x]!.pos - wa.pos).distance.compareTo(
                  (_walkers[y]!.pos - wa.pos).distance,
                ),
              ))
              .first;
      final wb = _walkers[b]!;
      wa.facingRight = wb.pos.dx > wa.pos.dx;
      wb.facingRight = wa.pos.dx > wb.pos.dx;
      wa.pauseLeft = 3;
      wb.pauseLeft = 3;
      wa.pose = 'wave';
      wa.poseLeft = 1.4;
      _speak(a, tr('line.chatA.${_rng.nextInt(3)}', {'name': friendName(b)}));
      wb.replyTo = a;
      wb.replyIn = 1.3;
    } else if (r < 0.8 && widget.area == game.currentArea) {
      // 놓인 장식 하나를 구경하러 간다
      final area = Garden.areaAt(widget.area);
      final placed = [
        for (var i = 0; i < area.decor.length; i++)
          if (game.isPlaced(widget.area, i)) i,
      ];
      if (placed.isEmpty) return _speak(a, _lineFor(a));
      final d = area.decor[placed[_rng.nextInt(placed.length)]];
      final w = _walkers[a]!;
      w.target = Offset(
        (d.x + (_rng.nextBool() ? 0.07 : -0.07)).clamp(0.05, 0.95),
        (d.y + 0.05).clamp(0.1, 0.95),
      );
      w.pauseLeft = 0;
      w.visitingDecor = decorName(d);
    } else {
      _walkers[a]!.happyLeft = 0.6; // 기분 좋아서 깡충
    }
  }

  /// 부탁을 들어준 친구는 깡충 뛰며 고맙다고 한다.
  void _onGameEvent(GameEvent e) {
    if (e is OrderDeliveredEvent && mounted) {
      _speak(e.friendId, pick('line.thanks', 2), hop: true);
    }
  }

  void _tapFriend(String id, Offset at) {
    final w = _walkers[id];
    final coins = game.tapFriend(id);
    if (w != null) {
      w.pose = null;
      w.poseLeft = 0;
      w.pauseLeft = 0;
      w.happyLeft = 0.6;
      w.say = _lineFor(id);
      w.speechLeft = 3;
    }
    _floats.add(
      _Float(at, coins == null ? '[[heart]]' : '[[heart]] +${fmt(coins)}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final area = Garden.areaAt(widget.area);
    return LayoutBuilder(
      builder: (context, c) {
        // 배경 비율(3:2) 그대로의 캔버스가 상자를 덮게 놓는다. 배경 · 장식 · 친구 좌표가 모두
        // 같은 캔버스 기준이라 상자 모양이 바뀌어도 서로 어긋나거나 배경만 잘리지 않는다.
        final cw = max(c.maxWidth, c.maxHeight * GardenScene.aspect);
        final canvas = Size(cw, cw / GardenScene.aspect);
        final left = (c.maxWidth - canvas.width) / 2;
        final top = (c.maxHeight - canvas.height) * widget.focusY;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: canvas.width,
                height: canvas.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: _BackgroundLayer(
                          area: area,
                          t: _nightTwinkle(area),
                        ),
                      ),
                    ),
                    // 빈 장식 자리: 땅에 그린 표식이라 캐릭터 · 장식보다 아래 (캐릭터를 가리지 않는다)
                    if (widget.showEmptySlots)
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: IgnorePointer(
                            child: Stack(children: _markerLayer(area, canvas)),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: Stack(children: _worldLayer(area, canvas)),
                      ),
                    ),
                    // 빈 자리 탭 영역: 보이지 않는 층 (표식을 눌렀는데 캐릭터가 가로채지 않게)
                    if (widget.showEmptySlots)
                      Positioned.fill(
                        child: Stack(children: _markerHits(area, canvas)),
                      ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: IgnorePointer(
                          child: Stack(
                            children: _fxLayer(
                              canvas,
                              Rect.fromLTWH(
                                -left,
                                -top,
                                c.maxWidth,
                                c.maxHeight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
          child: ArtImage(
            Art.decor(d, style: game.styleOf(widget.area, i)),
            size: sz,
          ),
        );
      } else {
        continue;
      }
      layers.add((
        // 정렬 기준 = 바닥에 닿는 높이 (그림 아래 여백 6% 반영)
        y: p.dy + sz * 0.44,
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
      final inWater = area.water.any((w) => w.contains(wk.pos.dx, wk.pos.dy));
      // 물속에서는 통통 뛰지 않고 살랑살랑 떠 있는다
      final bob = inWater
          ? sin(_t * 3 + wk.pos.dx * 10) * sz * 0.025
          : walking
          ? -(sin(_t * 10).abs()) * sz * 0.12
          : 0.0;
      final outfit = game.outfitOf(f.id);
      // 의상을 입었으면 의상 그림(기본 · 기쁨)을, 아니면 자세 그림(졸기 · 인사)을 쓴다
      final posed = wk.pose == null || wk.happyLeft > 0 || outfit != null
          ? null
          : Art.friendPose(f, wk.pose!);
      final image = ArtImage(
        posed ?? Art.friend(f, happy: wk.happyLeft > 0, outfit: outfit),
        size: sz,
        flipX: wk.facingRight,
      );
      final jump = wk.happyLeft > 0
          ? -sin((0.6 - wk.happyLeft) / 0.6 * pi) * sz * 0.4
          : 0.0;
      layers.add((
        y: p.dy + sz * 0.04, // 발 위치
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
              children: inWater
                  ? [
                      // 물결 뒤쪽 반: 몸 뒤
                      _splash(sz, wk, walking, front: false),
                      // 물에 잠긴 모습: 몸 아래 28%를 수면에서 자른다
                      SizedBox(
                        width: sz,
                        height: sz,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: 0.72,
                              child: image,
                            ),
                          ),
                        ),
                      ),
                      // 물결 앞쪽 반 + 물방울: 몸 앞
                      _splash(sz, wk, walking, front: true),
                    ]
                  : [
                      Positioned(
                        // 그림자는 발 밑에 (그림 아래 여백 · 칸 여백만큼 올림)
                        bottom: sz * 0.12,
                        child: _Shadow(width: sz * 0.62),
                      ),
                      image,
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
        y: p.dy, // 발 위치
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

  /// 수면 물결: 뒤쪽 반은 캐릭터 뒤, 앞쪽 반은 캐릭터 앞에 그려 물속에 선 것처럼 보이게 한다.
  Widget _splash(double sz, _Walker wk, bool walking, {required bool front}) =>
      Positioned(
        left: 0,
        right: 0,
        top: sz * 0.1 + sz * 0.72 - sz * 0.3,
        height: sz * 0.6,
        child: CustomPaint(
          painter: _SplashPainter(
            t: _t + wk.pos.dx * 7,
            moving: walking,
            front: front,
          ),
        ),
      );

  // ---------------------------------------------------------------- 빈 장식 자리
  // 장식이 놓일 바닥에 납작한 점선 타원 + 작은 비용 표 (땅 그림, 월드 아래).
  // 누르는 영역은 _markerHits 가 월드 위에 투명하게 따로 둔다.

  ({Offset c, double w}) _slotGeom(AreaDef area, int i, Size s) {
    final unit = min(s.width, s.height * 1.6);
    final d = area.decor[i];
    final sz = unit * 0.21;
    // 장식 그림의 바닥 (월드 정렬 기준과 같은 높이)
    final w = sz * 0.95 * widget.markerScale;
    // 캔버스 아래 끝에 걸린 자리는 표가 잘리지 않게 안쪽으로 올린다
    final y = min(d.y * s.height + sz * 0.36, s.height - w * 0.2);
    return (c: Offset(d.x * s.width, y), w: w);
  }

  List<Widget> _markerLayer(AreaDef area, Size s) {
    if (widget.area != game.currentArea) return const [];
    final out = <Widget>[];
    for (var i = 0; i < area.decor.length; i++) {
      if (game.isPlaced(widget.area, i)) continue;
      final g = _slotGeom(area, i, s);
      final affordable = game.canPlace(i) && !game.areaLocked;
      final glow = affordable ? 0.5 + 0.5 * sin(_t * 4) : 0.0;
      out.add(
        Positioned(
          left: g.c.dx - g.w / 2,
          top: g.c.dy - g.w * 0.62,
          width: g.w,
          height: g.w * 0.8,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: g.w * 0.36,
                child: CustomPaint(
                  painter: _PlotPainter(affordable: affordable, glow: glow),
                ),
              ),
              Positioned(
                bottom: g.w * 0.1,
                child: _CostTag(
                  locked: game.areaLocked,
                  affordable: affordable,
                  cost: game.decorCost(i),
                  size: g.w * 0.24,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _markerHits(AreaDef area, Size s) {
    if (widget.area != game.currentArea) return const [];
    return [
      for (var i = 0; i < area.decor.length; i++)
        if (!game.isPlaced(widget.area, i))
          Builder(
            builder: (_) {
              final g = _slotGeom(area, i, s);
              return Positioned(
                left: g.c.dx - g.w / 2,
                top: g.c.dy - g.w * 0.45,
                width: g.w,
                height: g.w * 0.6,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => widget.onSlotTap(i),
                ),
              );
            },
          ),
    ];
  }

  // ---------------------------------------------------------------- L3 이펙트

  /// [visible] = 캔버스 좌표로 본 실제 화면에 보이는 영역 (창이 캔버스 일부만 보여 줄 때 말풍선이 잘리지 않게).
  List<Widget> _fxLayer(Size s, Rect visible) {
    final out = <Widget>[];
    final unit = min(s.width, s.height * 1.6);
    for (final e in _walkers.entries) {
      final wk = e.value;
      if (wk.speechLeft <= 0) continue;
      final p = Offset(wk.pos.dx * s.width, wk.pos.dy * s.height);
      out.add(
        Positioned(
          left: (p.dx - 90).clamp(
            visible.left + 4,
            max(visible.left + 4, visible.right - 184),
          ),
          top: (p.dy - unit * 0.13 * 2.1).clamp(
            visible.top + 4,
            max(visible.top + 4, visible.bottom - 60),
          ),
          width: 180,
          child: _Bubble(text: '${friendName(e.key)}: ${wk.say}'),
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
            child: IconText(
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
    if (bg.available) {
      return Image.asset(
        bg.path,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      );
    }
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

/// 첨벙첨벙: 물결 2겹 + 걸을 때 튀는 물방울.
/// [front] 가 false 면 타원의 위쪽(먼 쪽) 반만, true 면 아래쪽(가까운 쪽) 반과 물방울만 그린다.
class _SplashPainter extends CustomPainter {
  _SplashPainter({required this.t, required this.moving, required this.front});
  final double t;
  final bool moving;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final w = size.width;
    canvas.save();
    canvas.clipRect(
      front
          ? Rect.fromLTRB(-w, c.dy, w * 2, size.height * 2)
          : Rect.fromLTRB(-w, -size.height, w * 2, c.dy),
    );
    // 수면 테두리 (몸이 잘린 선을 부드럽게): 앞쪽만, 얇게
    if (front) {
      canvas.drawOval(
        Rect.fromCenter(center: c, width: w * 0.62, height: w * 0.13),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xCCE8F7FF),
      );
    }
    for (var k = 0; k < 2; k++) {
      final phase = (t * 0.7 + k * 0.5) % 1.0;
      final rw = w * (0.5 + 0.45 * phase);
      canvas.drawOval(
        Rect.fromCenter(center: c, width: rw, height: rw * 0.26),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.8 * (1 - phase)),
      );
    }
    canvas.restore();
    if (front && moving) {
      final drop = Paint()..color = const Color(0xCCBFE8FF);
      for (var i = 0; i < 3; i++) {
        final ph = (t * 2.2 + i / 3) % 1.0;
        final dx = (i - 1) * w * 0.22 + (i - 1) * w * 0.08 * ph;
        final dy = -sin(ph * pi) * size.height * 0.45;
        canvas.drawCircle(c + Offset(dx, dy), w * 0.025 * (1 - ph * 0.5), drop);
      }
    }
  }

  @override
  bool shouldRepaint(_SplashPainter old) =>
      old.t != t || old.moving != moving || old.front != front;
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
    decoration: FrameBox.decorationFor(
      'speech',
      BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
      ),
      corner: 14,
    ),
    child: IconText(
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
  final icon = '[[area_${a.id}]]';
  if (areaIndex < game.currentArea) return '$icon $name [[check]]';
  if (game.areaLocked)
    return '$icon $name  ${tr('common.lockedLevel', {'n': game.areaRequiredLevel})}';
  return '$icon $name  ${game.placed.length}/${Garden.slotsPerArea}';
}

/// 빈 장식 자리의 땅 표식: 납작한 점선 타원 (살 수 있으면 금빛으로 은은히 빛난다).
class _PlotPainter extends CustomPainter {
  _PlotPainter({required this.affordable, required this.glow});
  final bool affordable;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawOval(
      r,
      Paint()
        ..color = (affordable ? const Color(0xFFFFE27A) : Colors.white)
            .withValues(alpha: affordable ? 0.25 + 0.25 * glow : 0.22),
    );
    final path = Path()..addOval(r.deflate(1.5));
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = affordable ? const Color(0xFFF2B33D) : const Color(0xCCFFFFFF);
    for (final m in path.computeMetrics()) {
      const on = 7.0, off = 5.0;
      for (var d = 0.0; d < m.length; d += on + off) {
        canvas.drawPath(m.extractPath(d, d + on), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_PlotPainter o) =>
      o.affordable != affordable || o.glow != glow;
}

/// 빈 자리 위 작은 표: 자물쇠 또는 망치 + 별 비용.
class _CostTag extends StatelessWidget {
  const _CostTag({
    required this.locked,
    required this.affordable,
    required this.cost,
    required this.size,
  });
  final bool locked;
  final bool affordable;
  final int cost;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.25,
        vertical: size * 0.08,
      ),
      decoration: BoxDecoration(
        color: affordable
            ? const Color(0xFFFFF3C4)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(size),
        border: Border.all(
          color: affordable ? const Color(0xFFF2B33D) : const Color(0xFFBBA98A),
          width: 1.5,
        ),
      ),
      child: locked
          ? ArtImage(Art.lock, size: size * 0.9)
          : IconText(
              '[[decorate]][[star]]$cost',
              iconScale: 1.0,
              style: TextStyle(
                fontSize: size * 0.8,
                height: 1.0,
                color: const Color(0xFF4A5A3A),
              ),
            ),
    );
  }
}
