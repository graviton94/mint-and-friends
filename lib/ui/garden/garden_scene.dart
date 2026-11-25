import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
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
    this.onOrderTap,
    this.orderTopInset = 0,
    this.onLandmarkTap,
  });

  /// 랜드마크를 누르면 (D-048). null 이면 보기만.
  final void Function(int area)? onLandmarkTap;

  /// 부탁 말풍선이 올라가지 않을 위쪽 띠 (창 위에 겹친 버튼 · 이름표 자리).
  final double orderTopInset;

  /// 부탁 말풍선을 친구 머리 위에 띄운다 (홈 화면). 누르면 그 부탁 번호로 부른다.
  final void Function(int index)? onOrderTap;

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

  /// 장식 · 친구 크기 (장면 폭 대비). D-048: 18% · 15% → 15% · 12% (가운데 랜드마크 자리).
  static const double decorK = 0.15, friendK = 0.12;

  /// 정원에 동시에 보이는 친구 수 (부탁을 든 친구는 늘 보이고, 나머지는 시간마다 번갈아).
  static const int maxFriends = 8;

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
    var p = Offset.zero;
    // 랜드마크 바닥은 피한다 (몇 번 다시 뽑기)
    for (var i = 0; i < 8; i++) {
      final z = zones[_rng.nextInt(zones.length)];
      p = Offset(
        z.x0 + _rng.nextDouble() * (z.x1 - z.x0),
        z.y0 + _rng.nextDouble() * (z.y1 - z.y0),
      );
      if (!_inLandmark(p)) break;
    }
    return p;
  }

  /// 이 구역에 세운 랜드마크 그림 (안 세웠거나 그림이 없으면 null).
  ArtRef? get _landmarkArt {
    final lv = game.landmarkLevel(widget.area);
    if (lv <= 0 || widget.area >= Landmarks.ids.length) return null;
    final a = Art.landmark(widget.area, lv);
    return a.available ? a : null;
  }

  /// 아직 안 세운 랜드마크 자리를 '세우기' 로 보여 줄지.
  bool get _landmarkGhost =>
      _landmarkArt == null &&
      widget.showEmptySlots &&
      widget.onLandmarkTap != null &&
      game.landmarkOpen(widget.area) &&
      game.landmarkLevel(widget.area) == 0 &&
      Art.landmark(widget.area, 1).available;

  /// 랜드마크 바닥 근처 (친구 · 부탁 자리가 들어가지 않는 곳).
  bool _inLandmark(Offset p) {
    if (_landmarkArt == null && !_landmarkGhost) return false;
    final a = Garden.areaAt(widget.area);
    return (p.dx - a.landmarkX).abs() < 0.13 &&
        p.dy > a.landmarkY - 0.12 &&
        p.dy < a.landmarkY + 0.08;
  }

  int? _walkArea;

  /// 지금 정원에 나와 있는 친구: 부탁을 든 친구 먼저, 나머지는 한 시간마다 바뀌는 순서로 [GardenScene.maxFriends] 까지.
  Set<String> _shownFriends() {
    final all = game.friends.toList()..sort();
    if (all.length <= GardenScene.maxFriends) return all.toSet();
    final out = <String>{
      for (final o in game.orders)
        if (all.contains(o.friendId)) o.friendId,
    };
    final hour = DateTime.now().millisecondsSinceEpoch ~/ 3600000;
    final rest = all.where((f) => !out.contains(f)).toList()
      ..shuffle(Random(hour));
    for (final f in rest) {
      if (out.length >= GardenScene.maxFriends) break;
      out.add(f);
    }
    return out;
  }

  /// 부탁을 든 친구가 자기 자리에서 서성이는 범위 (씬 대비).
  static const double _orderRoam = 0.05;

  /// 자리 [spot] 근처의 걸을 수 있는 한 점.
  Offset _nearSpot(Offset spot) {
    final zones = Garden.areaAt(widget.area).walk;
    final p = Offset(
      spot.dx + (_rng.nextDouble() * 2 - 1) * _orderRoam,
      spot.dy + (_rng.nextDouble() * 2 - 1) * _orderRoam * 0.5,
    );
    if (_inLandmark(p)) return spot;
    for (final z in zones) {
      if (p.dx >= z.x0 && p.dx <= z.x1 && p.dy >= z.y0 && p.dy <= z.y1) {
        return p;
      }
    }
    return spot;
  }

  /// 부탁을 든 친구가 서 있을 자리: 부탁 순서대로 왼쪽 · 가운데 · 오른쪽에 고르게 (말풍선이 겹치지 않게).
  /// 걸을 수 있는 땅 안에서 그 x 에 가장 가까운 곳, 높이는 땅 위쪽 1/3 (말풍선이 화면 위로 넘치지 않게 조금 아래).
  Map<String, Offset> _orderSpots() {
    final ids = [
      for (final o in game.orders)
        if (_walkers.containsKey(o.friendId)) o.friendId,
    ];
    final zones = Garden.areaAt(widget.area).walk;
    final n = ids.length;
    final out = <String, Offset>{};
    for (var k = 0; k < n; k++) {
      final x = 0.18 + 0.64 * (n == 1 ? 0.5 : k / (n - 1));
      WalkZone best = zones.first;
      var bd = double.infinity;
      for (final z in zones) {
        final d = x < z.x0 ? z.x0 - x : (x > z.x1 ? x - z.x1 : 0.0);
        if (d < bd) {
          bd = d;
          best = z;
        }
      }
      var spot = Offset(
        x.clamp(best.x0, best.x1).toDouble(),
        best.y0 + (best.y1 - best.y0) * (0.45 + 0.1 * (k % 2)),
      );
      if (_inLandmark(spot)) {
        final a = Garden.areaAt(widget.area);
        spot = Offset(
          (spot.dx < a.landmarkX ? a.landmarkX - 0.13 : a.landmarkX + 0.13)
              .clamp(best.x0, best.x1)
              .toDouble(),
          spot.dy,
        );
      }
      out[ids[k]] = spot;
    }
    return out;
  }

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
    final shown = _shownFriends();
    for (final id in shown) {
      _walkers.putIfAbsent(
        id,
        () => _Walker(_randomSpot(), _randomSpot(), _rng.nextDouble() * 2),
      );
    }
    _walkers.removeWhere((id, _) => !shown.contains(id));

    _lifeTimer -= dt;
    if (_lifeTimer <= 0) {
      // 친구가 많아도 시끄럽지 않게: 15~30초에 한 번, 누가 말하는 중이면 건너뛴다
      _lifeTimer = 15 + _rng.nextDouble() * 15;
      final talking = _walkers.values.any(
        (w) => w.speechLeft > 0 || w.replyTo != null,
      );
      if (!talking) _randomLife();
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

    // 부탁을 든 친구는 정해진 자리로 가서 기다린다
    // (자리 근처에서는 조금씩 서성이며 쉰다: 말풍선이 따라다녀도 겹치지 않을 만큼만)
    final spots = _orderSpots();
    for (final e in spots.entries) {
      final w = _walkers[e.key]!;
      if ((w.target - e.value).distance > _orderRoam * 1.5) w.target = e.value;
      w.visitingDecor = null;
    }
    for (final e in _walkers.entries) {
      final w = e.value;
      final waiting = spots.containsKey(e.key);
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
      if (dist < 0.01 && waiting) {
        // 자리 근처에서 잠깐 쉬었다가 (가만히 서서) 가까운 곳으로 몇 걸음
        w.pauseLeft = 2.5 + _rng.nextDouble() * 4;
        w.target = _nearSpot(spots[e.key]!);
        w.facingRight = w.pos.dx < 0.5;
        continue;
      }
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
    final waiting = _orderSpots();
    final ids = [
      for (final e in _walkers.entries)
        if (e.value.pose != 'sleep' && !waiting.containsKey(e.key)) e.key,
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
    if (r < 0.25) {
      _speak(a, _lineFor(a));
    } else if (r < 0.4 && ids.length >= 2) {
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
    } else if (r < 0.6 && widget.area == game.currentArea) {
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
                    // 정원 효과: 계절 세트 풍경(그 구역, 진하게)이 우선, 아니면 새싹 정원 패키지의 옅은 계절 효과
                    if (game.landscapeOf(widget.area) != null ||
                        game.effectOn != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: switch (game.landscapeOf(widget.area)) {
                              final st? => _SeasonPainter(
                                t: _t,
                                season: Garden.seasonIndexOf(st),
                                intense: true,
                                night: Color(area.sky).computeLuminance() < 0.2,
                              ),
                              null => _SeasonPainter(
                                t: _t,
                                season: _SeasonPainter.seasonOfMonth(
                                  game.now.month,
                                ),
                              ),
                            },
                          ),
                        ),
                      ),
                    if (widget.onOrderTap != null)
                      Positioned.fill(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: _orderLayer(
                            canvas,
                            Rect.fromLTWH(-left, -top, c.maxWidth, c.maxHeight),
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

  /// 가로 위치: 가장자리 7% 안으로만 당긴다 (둥근 테두리에 장식 · 친구가 잘리지 않게,
  /// 가운데 장식은 배경 그림과의 자리가 그대로).
  static double gx(double x, double width) =>
      x.clamp(0.08, 0.92).toDouble() * width;

  List<Widget> _worldLayer(AreaDef area, Size s) {
    final unit = min(s.width, s.height * 1.6);
    Offset px(double x, double y) => Offset(gx(x, s.width), y * s.height);
    final layers = <({double y, Widget child})>[];

    // 랜드마크 (D-048): 구역 가운데 큰 조형물, 바닥 높이로 다른 것들과 앞뒤를 정한다
    final lm = _landmarkArt;
    if (lm != null) {
      final h = unit * GardenScene.decorK * Landmarks.scale;
      final p = px(area.landmarkX, area.landmarkY);
      layers.add((
        y: p.dy,
        child: Positioned(
          key: ValueKey('landmark-${widget.area}'),
          left: p.dx - h * 0.6,
          top: p.dy - h,
          width: h * 1.2,
          height: h,
          child: GestureDetector(
            onTap: widget.onLandmarkTap == null
                ? null
                : () => widget.onLandmarkTap!(widget.area),
            // 다른 장식처럼 구역을 넘기거나 모습 단계가 바뀌면 '퐁' 하고 나타난다
            child: TweenAnimationBuilder<double>(
              key: ValueKey('landmark-pop-${widget.area}-${lm.path}'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, v, ch) => Transform.scale(
                scale: v,
                alignment: Alignment.bottomCenter,
                child: ch,
              ),
              child: Image.asset(
                lm.path,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ));
    }

    for (var i = 0; i < area.decor.length; i++) {
      final d = area.decor[i];
      final p = px(d.x, d.y);
      final sz = unit * GardenScene.decorK;
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
        // 고정 키: 친구가 앞뒤로 지나가 그리는 순서가 바뀌어도 장식이 새로 '퐁' 튀어나오지 않게
        child: Positioned(
          key: ValueKey('decor-${widget.area}-$i'),
          left: p.dx - sz * 0.6,
          top: p.dy - sz * 0.6,
          width: sz * 1.2,
          height: sz * 1.2,
          // 놓은 장식을 누르면 디자인 화면 (D-063). 앞에 선 친구가 먼저 눌린다 (깊이 순서)
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTap: widget.area == game.currentArea
                ? () => widget.onSlotTap(i)
                : null,
            child: Center(child: child),
          ),
        ),
      ));
    }

    for (final e in _walkers.entries) {
      final f = Friends.byId(e.key);
      final wk = e.value;
      final p = px(wk.pos.dx, wk.pos.dy);
      final sz = unit * GardenScene.friendK;
      final walking = wk.pauseLeft <= 0 && wk.happyLeft <= 0;
      final inWater = area.water.any((w) => w.contains(wk.pos.dx, wk.pos.dy));
      // 물속에서는 통통 뛰지 않고 살랑살랑 떠 있는다
      final bob = inWater
          ? sin(_t * 3 + wk.pos.dx * 10) * sz * 0.025
          : walking
          ? -(sin(_t * 10).abs()) * sz * 0.12
          : 0.0;
      final outfit = game.outfitOf(f.id);
      // 자세 그림(졸기 · 인사)은 입은 의상의 것을 쓴다 (없으면 의상 기본 그림)
      final posed = wk.pose == null || wk.happyLeft > 0
          ? null
          : Art.friendPose(f, wk.pose!, outfit: outfit);
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
          key: ValueKey('friend-${e.key}'),
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
      final sz = unit * GardenScene.friendK;
      final bounce = sin(_t * 6).abs() * sz * 0.1;
      layers.add((
        y: p.dy, // 발 위치
        child: Positioned(
          key: const ValueKey('visitor'),
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
    final sz = unit * GardenScene.decorK;
    // 장식 그림의 바닥 (월드 정렬 기준과 같은 높이)
    final w = sz * 0.95 * widget.markerScale;
    // 캔버스 아래 끝에 걸린 자리는 표가 잘리지 않게 안쪽으로 올린다
    final y = min(d.y * s.height + sz * 0.36, s.height - w * 0.2);
    return (c: Offset(gx(d.x, s.width), y), w: w);
  }

  /// 랜드마크 빈자리 (장식 빈자리와 같은 모양, 조금 크게).
  ({Offset c, double w})? _landmarkSlot(AreaDef area, Size s) {
    if (!_landmarkGhost) return null;
    final unit = min(s.width, s.height * 1.6);
    final w = unit * GardenScene.decorK * 1.5 * widget.markerScale;
    return (
      c: Offset(gx(area.landmarkX, s.width), area.landmarkY * s.height),
      w: w,
    );
  }

  List<Widget> _markerLayer(AreaDef area, Size s) {
    final out = <Widget>[];
    final ls = _landmarkSlot(area, s);
    if (ls != null) {
      final ok = game.canBuildLandmark(widget.area);
      final glow = ok ? 0.5 + 0.5 * sin(_t * 4) : 0.0;
      out.add(
        Positioned(
          left: ls.c.dx - ls.w / 2,
          top: ls.c.dy - ls.w * 0.62,
          width: ls.w,
          height: ls.w * 0.8,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: ls.w * 0.36,
                child: CustomPaint(
                  painter: _PlotPainter(affordable: ok, glow: glow),
                ),
              ),
              Positioned(
                bottom: ls.w * 0.1,
                child: _CostTag(
                  locked: false,
                  affordable: ok,
                  cost: game.landmarkBuildStars(widget.area),
                  size: ls.w * 0.18,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.area != game.currentArea) return out;
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
    final ls = _landmarkSlot(area, s);
    return [
      // 랜드마크 빈자리: 별이 있으면 바로 세우고, 모자라면 랜드마크 창 (별 · 설명)
      if (ls != null)
        Positioned(
          left: ls.c.dx - ls.w / 2,
          top: ls.c.dy - ls.w * 0.45,
          width: ls.w,
          height: ls.w * 0.6,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (!game.buildLandmark(widget.area)) {
                widget.onLandmarkTap?.call(widget.area);
              }
            },
          ),
        ),
      if (widget.area == game.currentArea) ..._decorHits(area, s),
    ];
  }

  List<Widget> _decorHits(AreaDef area, Size s) {
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

  // ---------------------------------------------------------------- 부탁 말풍선

  List<Widget> _orderLayer(Size s, Rect visible) {
    final unit = min(s.width, s.height * 1.6);
    final sz = unit * GardenScene.friendK;
    final bw = max(
      game.openBaskets.length > 1 ? 74.0 : 66.0,
      unit * (game.openBaskets.length > 1 ? 0.21 : 0.19),
    );
    final bh = bw * 0.6;
    // 1) 친구 머리 위 자리
    final items = <({int i, double fx, double cx, double top})>[];
    for (var i = 0; i < game.orders.length; i++) {
      final wk = _walkers[game.orders[i].friendId];
      if (wk == null) continue;
      final p = Offset(gx(wk.pos.dx, s.width), wk.pos.dy * s.height);
      items.add((
        i: i,
        fx: p.dx,
        cx: p.dx,
        top: (p.dy - sz - bh - 2).clamp(
          visible.top + widget.orderTopInset + 2,
          visible.bottom - bh,
        ),
      ));
    }
    // 2) 말풍선은 언제나 친구 머리 바로 위 (피하려고 옆으로 밀면 꼬리가 비틀려 어색하다).
    //    친구들이 서는 자리를 떨어뜨려 두어 거의 겹치지 않고, 조금 겹쳐도 그대로 둔다. 화면 밖으로만 안 나가게.
    final lo = visible.left + bw / 2 + 2, hi = visible.right - bw / 2 - 2;
    final cx = [for (final it in items) it.cx.clamp(lo, hi).toDouble()];
    final top = [for (final it in items) it.top.toDouble()];
    final out = <Widget>[];
    for (var k = 0; k < items.length; k++) {
      final i = items[k].i;
      final o = game.orders[i];
      final ready = game.canDeliver(i);
      final stars = game.orderGivesStars(o);
      out.add(
        Positioned(
          key: ValueKey('order-$i'),
          left: cx[k] - bw / 2,
          top: top[k],
          width: bw,
          height: bh * 1.22,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onOrderTap!(i),
            child: _OrderBubble(
              item: Art.item(o.chain, o.level),
              // 바구니가 여럿이면 어느 바구니에서 나오는지
              basket: game.openBaskets.length > 1
                  ? Art.icon(
                      Chains.basketIcon[Chains.baskets.indexWhere(
                        (b) => b.contains(o.chain),
                      )],
                    )
                  : null,
              label: ready
                  ? tr('order.deliverShort')
                  : stars
                  ? '[[star]]${o.stars}'
                  : '[[coin]]${fmt(game.orderCoins(o))}',
              ready: ready,
              dim: !stars && !ready,
              tailX: (items[k].fx - (cx[k] - bw / 2)) / bw,
            ),
          ),
        ),
      );
    }
    return out;
  }

  // ---------------------------------------------------------------- L3 이펙트

  /// [visible] = 캔버스 좌표로 본 실제 화면에 보이는 영역 (창이 캔버스 일부만 보여 줄 때 말풍선이 잘리지 않게).
  List<Widget> _fxLayer(Size s, Rect visible) {
    final out = <Widget>[];
    final unit = min(s.width, s.height * 1.6);
    for (final e in _walkers.entries) {
      final wk = e.value;
      if (wk.speechLeft <= 0) continue;
      // 홈 화면 정원 창(부탁 말풍선이 뜨는 곳)에서는 잡담 말풍선을 띄우지 않는다 (크게 보기에서만)
      if (widget.onOrderTap != null) continue;
      final p = Offset(gx(wk.pos.dx, s.width), wk.pos.dy * s.height);
      out.add(
        Positioned(
          left: (p.dx - 90).clamp(
            visible.left + 4,
            max(visible.left + 4, visible.right - 184),
          ),
          top: (p.dy - unit * GardenScene.friendK * 1.8).clamp(
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
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
        horizontal: size * 0.4,
        vertical: size * 0.14,
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

/// 부탁 말풍선: 아이템 + 별(또는 전달!). 꼬리는 말풍선과 한 몸으로 그린다.
class _OrderBubble extends StatelessWidget {
  const _OrderBubble({
    required this.item,
    required this.label,
    required this.ready,
    required this.dim,
    required this.tailX,
    this.basket,
  });
  final ArtRef item;
  final ArtRef? basket;
  final String label;
  final bool ready;
  final bool dim;
  final double tailX;

  @override
  Widget build(BuildContext context) {
    final fill = ready
        ? const Color(0xFFFFF0B8)
        : dim
        ? const Color(0xFFEDE7DA)
        : const Color(0xFFFFFBF0);
    final line = ready ? const Color(0xFFE0A21B) : const Color(0xFF7A5230);
    return CustomPaint(
      painter: _BubblePainter(
        fill: fill,
        line: line,
        tailX: tailX.clamp(0.18, 0.82),
        glow: ready,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight / 1.22;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              h * 0.2,
              h * 0.1,
              h * 0.2,
              h * 0.1 + c.maxHeight - h,
            ),
            // 바구니 · 아이템 · 별 묶음을 말풍선 한가운데에
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 바구니는 아이템 왼쪽 위에 작은 딱지로 겹쳐 (묶음이 한가운데 오게)
                SizedBox(
                  width: h * (basket != null ? 0.86 : 0.74),
                  height: h * 0.8,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: ArtImage(item, size: h * 0.74),
                      ),
                      if (basket != null)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: ArtImage(basket!, size: h * 0.4),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: h * 0.04),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: IconText(
                      label,
                      iconScale: 1.0,
                      style: TextStyle(
                        fontSize: h * 0.44,
                        height: 1,
                        color: ready
                            ? const Color(0xFFB0640A)
                            : dim
                            ? const Color(0xFF7A6A52)
                            : const Color(0xFF4A3A22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.fill,
    required this.line,
    required this.tailX,
    required this.glow,
  });
  final Color fill;
  final Color line;
  final double tailX;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height / 1.22;
    final r = h * 0.42;
    final body = RRect.fromLTRBR(
      1.5,
      1.5,
      size.width - 1.5,
      h,
      Radius.circular(r),
    );
    final tx = size.width * tailX;
    final tw = h * 0.22;
    final tail = Path()
      ..moveTo(tx - tw, h - 1)
      ..quadraticBezierTo(tx - tw * 0.2, h + tw * 0.4, tx, size.height - 1.5)
      ..quadraticBezierTo(tx + tw * 0.2, h + tw * 0.4, tx + tw, h - 1)
      ..close();
    final shape = Path.combine(
      PathOperation.union,
      Path()..addRRect(body),
      tail,
    );
    if (glow) {
      canvas.drawPath(
        shape,
        Paint()
          ..color = const Color(0x99FFD54A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas.drawPath(
      shape.shift(const Offset(0, 2)),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawPath(shape, Paint()..color = fill);
    canvas.drawPath(
      shape,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter o) =>
      o.fill != fill || o.line != line || o.tailX != tailX || o.glow != glow;
}

/// 정원 효과 입자 그림 (assets/art/fx). 없으면 코드로 그린 도형을 쓴다.
class FxSprites {
  static final Map<String, ui.Image> _img = {};
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= () async {
    for (final id in const [
      'cherry_petal',
      'butterfly_open',
      'butterfly_closed',
      'maple_leaf',
      'ginkgo_leaf',
      'snowflake',
      'sun_sparkle',
      'firefly',
    ]) {
      try {
        final data = await rootBundle.load('assets/art/fx/$id.webp');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        _img[id] = (await codec.getNextFrame()).image;
      } catch (_) {}
    }
  }();

  /// 그림을 [c] 중심, 한 변 [size] 로 그린다. 그림이 없으면 false.
  static bool draw(
    Canvas canvas,
    String id,
    Offset c,
    double size, {
    double opacity = 1,
    double rot = 0,
  }) {
    final im = _img[id];
    if (im == null) return false;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (rot != 0) canvas.rotate(rot);
    canvas.drawImageRect(
      im,
      Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: size, height: size),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0)),
    );
    canvas.restore();
    return true;
  }
}

/// 계절 정원 효과. [season] 0 봄 · 1 여름 · 2 가을 · 3 겨울.
/// 기본(새싹 정원 패키지): 옅은 입자. [intense](계절 세트 완성 풍경): 입자 2배 + 색조 + 계절 연출.
class _SeasonPainter extends CustomPainter {
  _SeasonPainter({
    required this.t,
    required this.season,
    this.intense = false,
    this.night = false,
  });
  final double t;
  final int season;
  final bool intense;
  final bool night;

  static int seasonOfMonth(int m) => switch (m) {
    3 || 4 || 5 => 0,
    6 || 7 || 8 => 1,
    9 || 10 || 11 => 2,
    _ => 3,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final unit = w / 60;
    if (intense) _backdrop(canvas, size, unit);
    final n = intense ? 18 : 8;
    for (var i = 0; i < n; i++) {
      // 입자마다 고정된 씨앗 값 (매 프레임 같은 궤적)
      final a = (i * 0.618034) % 1.0;
      final b = (i * 0.414214 + 0.3) % 1.0;
      final speed = 0.04 + 0.05 * b;
      if (season == 1 && (night || !intense)) {
        _firefly(canvas, i, a, b, w, h, unit);
        continue;
      }
      if (season == 1) {
        // 여름 낮: 반짝이 (제자리에서 깜빡)
        final x = (a + 0.02 * sin(t * 0.5 + i)) * w;
        final y = (0.4 + 0.58 * b) * h;
        final tw = (0.5 + 0.5 * sin(t * 3 + i * 2.3)).clamp(0.0, 1.0);
        final r = unit * 0.5 * tw;
        if (FxSprites.draw(
          canvas,
          'sun_sparkle',
          Offset(x, y),
          unit * 1.6 * tw,
          opacity: tw,
        )) {
          continue;
        }
        final paint = Paint()..color = Colors.white.withValues(alpha: 0.9 * tw);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(x, y),
            width: r * 0.35,
            height: r * 2.2,
          ),
          paint,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(x, y),
            width: r * 2.2,
            height: r * 0.35,
          ),
          paint,
        );
        continue;
      }
      // 떨어지는 입자: 위에서 아래로, 좌우로 살랑
      final p = (t * speed + a) % 1.0;
      final x = ((b + 0.15 * sin(t * 0.8 + i)) % 1.0) * w;
      final y = (p * 1.1 - 0.05) * h;
      final rot = t * (0.8 + b) + i;
      final sprite = switch (season) {
        0 => 'cherry_petal',
        2 => i % 3 == 0 ? 'ginkgo_leaf' : 'maple_leaf',
        _ => 'snowflake',
      };
      final sz = switch (season) {
        0 => unit * 1.6,
        2 => unit * 2.0,
        _ => unit * (0.9 + 0.6 * b) * (intense ? 1.2 : 1),
      };
      if (FxSprites.draw(
        canvas,
        sprite,
        Offset(x, y),
        sz,
        rot: season == 3 ? 0 : rot,
      )) {
        continue;
      }
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      switch (season) {
        case 0: // 꽃잎
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: unit * 1.5,
              height: unit * 0.9,
            ),
            Paint()..color = const Color(0xFFFFB7CE).withValues(alpha: 0.9),
          );
        case 2: // 낙엽
          final path = Path()
            ..moveTo(0, -unit)
            ..quadraticBezierTo(unit, 0, 0, unit)
            ..quadraticBezierTo(-unit, 0, 0, -unit);
          canvas.drawPath(
            path,
            Paint()
              ..color =
                  (i % 3 == 0
                          ? const Color(0xFFF2C14E)
                          : i.isEven
                          ? const Color(0xFFE8823A)
                          : const Color(0xFFD9543A))
                      .withValues(alpha: 0.92),
          );
        default: // 눈 (밝은 배경에서도 보이게 옅은 테두리)
          final r = unit * (0.45 + 0.3 * b) * (intense ? 1.2 : 1);
          canvas.drawCircle(
            Offset.zero,
            r + 1,
            Paint()..color = const Color(0x339DB6CC),
          );
          canvas.drawCircle(
            Offset.zero,
            r,
            Paint()..color = Colors.white.withValues(alpha: 0.95),
          );
      }
      canvas.restore();
    }
    if (intense && season == 0) _butterflies(canvas, w, h, unit);
  }

  void _firefly(
    Canvas canvas,
    int i,
    double a,
    double b,
    double w,
    double h,
    double unit,
  ) {
    final x = (a + 0.04 * sin(t * 0.7 + i)) * w;
    final y = (0.35 + 0.6 * b + 0.03 * sin(t * 0.9 + i * 2)) * h;
    final glow = 0.5 + 0.5 * sin(t * 2.2 + i * 1.7);
    if (FxSprites.draw(
      canvas,
      'firefly',
      Offset(x, y),
      unit * 2.2,
      opacity: glow,
    )) {
      return;
    }
    canvas.drawCircle(
      Offset(x, y),
      unit * 0.9,
      Paint()
        ..color = const Color(0xFFFFF59D).withValues(alpha: 0.35 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(x, y),
      unit * 0.28,
      Paint()..color = const Color(0xFFFFFDE7).withValues(alpha: glow),
    );
  }

  /// 세트 풍경의 색조 · 빛 (하늘 쪽을 진하게, 땅은 밝게).
  void _backdrop(Canvas canvas, Size size, double unit) {
    final rect = Offset.zero & size;
    final (top, bottom) = switch (season) {
      0 => (const Color(0x30FFB0C8), const Color(0x08FFE0EC)),
      1 => (const Color(0x30FFF0A0), const Color(0x00FFFFFF)),
      2 => (const Color(0x40FF9A50), const Color(0x10D8642E)),
      _ => (const Color(0x504A64B4), const Color(0x00FFFFFF)),
    };
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
          stops: const [0, 0.55],
        ).createShader(rect),
    );
    if (season == 1 && !night) {
      // 여름 햇살 줄기 (오른쪽 위에서 비스듬히, 천천히 숨쉬듯)
      final o = Offset(size.width * 0.88, -size.height * 0.05);
      final k = 0.75 + 0.25 * sin(t * 0.6);
      final ray = Paint()
        ..color = const Color(0xFFFFFAD2).withValues(alpha: 0.22 * k)
        ..strokeWidth = unit * 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      for (var j = 0; j < 3; j++) {
        canvas.drawLine(
          o,
          Offset(o.dx - size.width * (0.35 + j * 0.15), size.height),
          ray,
        );
      }
    }
    if (season == 3) {
      // 겨울: 땅에 쌓인 눈
      final snow = Paint()..color = Colors.white.withValues(alpha: 0.7);
      for (var j = 0; j < 9; j++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * (j / 8), size.height * 0.99),
            width: size.width * 0.18,
            height: size.height * 0.05,
          ),
          snow,
        );
      }
    }
  }

  void _butterflies(Canvas canvas, double w, double h, double unit) {
    final fill = Paint()..color = const Color(0xFFFFE07A);
    final line = Paint()
      ..color = const Color(0xFF7A5230)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 2; i++) {
      final ph = t * 0.35 + i * 1.3;
      final x = (0.15 + 0.7 * (0.5 + 0.5 * sin(ph))) * w;
      final y = (0.35 + 0.35 * (0.5 + 0.5 * sin(ph * 1.7 + i))) * h;
      final flap = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 14 + i)).abs();
      if (FxSprites.draw(
        canvas,
        sin(t * 14 + i) > 0 ? 'butterfly_open' : 'butterfly_closed',
        Offset(x, y),
        unit * 2.0,
      )) {
        continue;
      }
      for (final sgn in [-1.0, 1.0]) {
        final r = Rect.fromCenter(
          center: Offset(x + sgn * unit * 0.55 * flap, y),
          width: unit * 1.1 * flap,
          height: unit * 1.3,
        );
        canvas.drawOval(r, fill);
        canvas.drawOval(r, line);
      }
    }
  }

  @override
  bool shouldRepaint(_SeasonPainter o) =>
      o.t != t ||
      o.season != season ||
      o.intense != intense ||
      o.night != night;
}
