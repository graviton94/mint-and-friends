import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/config.dart';
import '../../game/format.dart';
import '../../game/game_state.dart';
import '../../i18n/l10n.dart';
import '../../services/audio_service.dart';
import '../theme.dart';
import '../widgets/frame_box.dart';

/// 머지 보드.
///
/// 레이어 (아래 → 위), 각각 RepaintBoundary 로 분리:
///  L0 칸     : 바닥 타일, 잠긴 칸(자물쇠), 합칠 수 있는 칸 강조.
///  L1 아이템 : 아이템, 비눗방울, 선택 테두리, 부탁 표시.
///  L2 이펙트 : 합치기 반짝임.
///  L3 드래그 : 손가락을 따라오는 아이템. 보드 밖(부탁 카드, 정보 줄, 버튼) 위로도 보여야 하므로
///             화면 최상단 Overlay 에 그린다 (OverlayPortal).
///
/// 입력: 드래그 = 이동/합치기/교환, 탭 = 선택(판매·정보), 잠긴 칸 탭 = 칸 열기, 비눗방울 탭 = 꺼내기.
class BoardView extends StatefulWidget {
  /// 미리보기: 자동 진행 표시 방식 ('fill' · 'bar').
  static void debugAutoFx(String style) => _BoardViewState.autoFxStyle = style;

  const BoardView({
    super.key,
    required this.game,
    required this.selected,
    required this.onSelect,
    required this.onLockedTap,
    this.floating,
    required this.onBubbleTap,
  });

  final GameState game;
  final int? selected;
  final void Function(int? cell) onSelect;
  final void Function(int cell) onLockedTap;

  /// 판 위에 띄우는 정보 카드 (선택한 아이템 등). 선택 칸이 아래쪽이면 위에, 위쪽이면 아래에 뜬다.
  final Widget? floating;
  final void Function(int cell) onBubbleTap;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _Burst {
  final int cell;
  final int key;
  final int level; // 0 = 행운 바구니
  final bool label; // 행운 글자를 띄울지 (연달아 나오면 첫 번째만)
  _Burst(this.cell, this.key, this.level, {this.label = true});
}

class _BoardViewState extends State<BoardView> {
  /// 자동 진행 표시 방식 (미리보기에서 바꿔 본다): 'fill' 칸 배경 차오름, 'bar' 칸 아래 막대.
  static String autoFxStyle = 'fill';

  List<Widget> _autoFx(
    double cell,
    Widget Function(int, Widget, {Key? key}) at,
  ) {
    final out = <Widget>[];
    final pair = game.autoMergeInterval == null ? null : game.nextAutoMergePair;
    if (pair != null) {
      for (final c in [pair.$1, pair.$2]) {
        out.add(
          at(
            c,
            key: ValueKey('m$c'),
            _AutoFill(
              frac: game.autoMergeFrac,
              size: cell,
              color: const Color(0xFF7CCB4E),
              bar: autoFxStyle == 'bar',
            ),
          ),
        );
      }
    }
    final sc = game.nextAutoSpawnCell;
    if (sc != null) {
      out.add(
        at(
          sc,
          key: ValueKey('s$sc'),
          _AutoFill(
            frac: game.autoSpawnFrac,
            size: cell,
            color: const Color(0xFFF2B33D),
            bar: autoFxStyle == 'bar',
            basket: Chains.basketIcon[game.basket],
          ),
        ),
      );
    }
    return out; // IgnorePointer 는 _AutoFill 안에서 (Positioned 는 Stack 바로 아래여야 한다)
  }

  final _dragPortal = OverlayPortalController();
  double _cellSize = 0;
  int? _dragFrom;
  Offset _dragPos = Offset.zero;
  Offset _grabOffset = Offset.zero;
  final List<_Burst> _bursts = [];
  int _burstKey = 0;
  StreamSubscription<GameEvent>? _sub;

  GameState get game => widget.game;

  // 행운 글자는 1.5초에 한 번만 (빠르게 누르거나 자동 놓기가 겹치면 글자가 여러 개 떠 보였다, D-087)
  DateTime _lastLuckyLabel = DateTime(2000);
  bool _luckyLabelOk() {
    final now = DateTime.now();
    if (now.difference(_lastLuckyLabel).inMilliseconds < 1500) return false;
    _lastLuckyLabel = now;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _sub = game.events.listen((e) {
      final b = e is MergedEvent
          ? _Burst(e.cell, _burstKey++, e.level)
          : e is LuckySpawnEvent
          ? _Burst(e.cell, _burstKey++, 0, label: _luckyLabelOk())
          : null;
      if (b != null) {
        setState(() => _bursts.add(b));
        Future.delayed(const Duration(milliseconds: 750), () {
          if (mounted) setState(() => _bursts.remove(b));
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// 최상단 Overlay 에 그리는 드래그 중인 아이템.
  Widget _dragOverlay(BuildContext overlayContext) {
    final from = _dragFrom;
    final it = from == null ? null : game.board[from];
    final board = context.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (it == null || board == null || overlayBox == null || !board.attached) {
      return const SizedBox.shrink();
    }
    final global = board.localToGlobal(_dragPos - _grabOffset);
    final local = overlayBox.globalToLocal(global);
    return Positioned(
      left: local.dx,
      top: local.dy,
      width: _cellSize,
      height: _cellSize,
      child: IgnorePointer(
        child: Transform.scale(
          scale: 1.15,
          child: ItemTile(item: it, size: _cellSize, lifted: true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _dragPortal,
      overlayChildBuilder: _dragOverlay,
      child: _board(context),
    );
  }

  Widget _board(BuildContext context) {
    return AspectRatio(
      aspectRatio: GameConfig.cols / GameConfig.rows,
      child: LayoutBuilder(
        builder: (context, c) {
          const pad = 5.0;
          final cell = (c.maxWidth - pad * 2) / GameConfig.cols;
          _cellSize = cell;
          Offset origin(int i) => Offset(
            pad + (i % GameConfig.cols) * cell,
            pad + (i ~/ GameConfig.cols) * cell,
          );
          int? cellAt(Offset p) {
            final col = ((p.dx - pad) / cell).floor();
            final row = ((p.dy - pad) / cell).floor();
            if (col < 0 ||
                row < 0 ||
                col >= GameConfig.cols ||
                row >= GameConfig.rows)
              return null;
            return row * GameConfig.cols + col;
          }

          Positioned at(int i, Widget child, {Key? key}) {
            final o = origin(i);
            return Positioned(
              key: key,
              left: o.dx,
              top: o.dy,
              width: cell,
              height: cell,
              child: child,
            );
          }

          final dragItem = _dragFrom == null ? null : game.board[_dragFrom!];
          final hover = _dragFrom == null ? null : cellAt(_dragPos);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onTap(cellAt(d.localPosition)),
            onPanStart: (d) {
              final i = cellAt(d.localPosition);
              if (i == null || !game.canTake(i)) return;
              final it = game.board[i];
              if (it == null || it.isBubble) return;
              // 끌기 시작하면 정보 카드는 닫는다 (카드는 아이템을 '눌렀을' 때만)
              widget.onSelect(null);
              game.holdCell = i;
              setState(() {
                _dragFrom = i;
                _dragPortal.show();
                _dragPos = d.localPosition;
                _grabOffset = d.localPosition - origin(i);
              });
            },
            onPanUpdate: (d) {
              if (_dragFrom != null) setState(() => _dragPos = d.localPosition);
            },
            onPanEnd: (_) => _drop(cellAt(_dragPos)),
            onPanCancel: () => _drop(null),
            child: Container(
              decoration: BoxDecoration(
                color: Palette.board,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // L0 칸
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Stack(
                        children: [
                          for (var i = 0; i < GameConfig.cellCount; i++)
                            at(i, _cellCached(i, dragItem, hover, cell)),
                        ],
                      ),
                    ),
                  ),
                  // L0.5 자동 합치기 · 자동 놓기 진행 (D-094): 다음에 움직일 칸이 차오른다
                  // 늘 한 층으로 (표시 칸 수가 바뀌어도 아래 아이템 층의 자리가 밀리지 않게:
                  // 밀리면 아이템 층이 통째로 새로 만들어져 모든 아이템이 '뿅' 했다, D-100)
                  Positioned.fill(
                    key: const ValueKey('autoFx'),
                    child: IgnorePointer(
                      child: Stack(
                        clipBehavior: Clip.none,
                        // 끄는 동안에도 차오름은 그대로 (D-107)
                        children: _autoFx(cell, at),
                      ),
                    ),
                  ),
                  // L1 아이템
                  Positioned.fill(
                    key: const ValueKey('items'),
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: Stack(children: _itemLayer(cell, origin)),
                      ),
                    ),
                  ),
                  // L3 정보 카드
                  if (widget.floating != null)
                    KeyedSubtree(
                      key: const ValueKey('floating'),
                      child: _floatingAt(widget.floating!, cell, pad),
                    ),
                  // L2 이펙트
                  for (final b in _bursts)
                    at(
                      key: ValueKey('fx${b.key}'),
                      b.cell,
                      IgnorePointer(
                        child: b.level == 0
                            ? _LuckyFx(
                                key: ValueKey(b.key),
                                size: cell,
                                label: b.label,
                              )
                            : _BurstFx(
                                key: ValueKey(b.key),
                                size: cell,
                                level: b.level,
                              ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _floatingAt(Widget child, double cell, double pad) {
    final sel = widget.selected;
    const h = 52.0;
    if (sel == null) {
      return Positioned(
        left: 8,
        right: 8,
        bottom: pad + 4,
        child: Center(child: child),
      );
    }
    final row = sel ~/ GameConfig.cols;
    final above = row >= GameConfig.rows ~/ 2;
    final y = above ? pad + row * cell - h - 2 : pad + (row + 1) * cell + 2;
    return Positioned(
      left: 6,
      right: 6,
      top: y,
      height: h,
      child: Center(child: child),
    );
  }

  final Map<int, (Object, Widget)> _cellsMemo = {};

  /// 칸 그림도 모습이 같으면 지난 위젯 그대로 (D-108).
  Widget _cellCached(int i, Item? dragItem, int? hover, double cell) {
    final t = game.board[i];
    final sig = (
      game.isCellOpen(i),
      t != null,
      t?.chain,
      t?.level,
      t?.isBubble,
      dragItem?.chain,
      dragItem?.level,
      i == _dragFrom,
      hover == i,
      cell,
    );
    final hit = _cellsMemo[i];
    if (hit != null && hit.$1 == sig) return hit.$2;
    final w = _cellTile(i, dragItem, hover, cell);
    _cellsMemo[i] = (sig, w);
    return w;
  }

  Widget _cellTile(int i, Item? dragItem, int? hover, double cell) {
    final open = game.isCellOpen(i);
    final target = game.board[i];
    final highlight =
        dragItem != null &&
        target != null &&
        i != _dragFrom &&
        !target.isBubble &&
        target.level == dragItem.level &&
        target.chain == dragItem.chain;
    final vault = GameConfig.isVault(i);
    final base = vault
        ? const Color(0xFFE6E0F5) // 보관 칸: 연보라
        : (i ~/ GameConfig.cols + i % GameConfig.cols).isEven
        ? Palette.cell
        : Palette.cellAlt;
    // 판 칸 그림 (오목한 칸, D-098): 평소 칸은 그림, 끌어다 맞출 때 반짝 강조는 단색
    final kit = !open
        ? 'cell_locked'
        : vault
        ? 'cell_vault'
        : (i ~/ GameConfig.cols + i % GameConfig.cols).isEven
        ? 'cell'
        : 'cell_alt';
    final useKit = !highlight && Art.frame(kit).available;
    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: AnimatedContainer(
        duration: Duration(milliseconds: useKit ? 0 : 120),
        decoration: useKit
            ? FrameBox.decorationFor(
                kit,
                BoxDecoration(color: base),
                corner: cell * 0.2,
              )
            : BoxDecoration(
                color: !open
                    ? (vault
                          ? const Color(0xFFD6CFE6)
                          : const Color(0xFFD9CFB8))
                    : highlight
                    ? Palette.accent.withValues(alpha: hover == i ? 0.75 : 0.35)
                    : base,
                borderRadius: BorderRadius.circular(cell * 0.2),
              ),
        child: open || target != null
            ? null
            : Center(
                child: Opacity(
                  opacity: 0.55,
                  child: ArtImage(
                    vault ? Art.icon('diamond') : Art.lock,
                    size: cell * 0.36,
                  ),
                ),
              ),
      ),
    );
  }

  /// 같은 모습이면 지난번 위젯을 그대로 돌려준다 (D-108): 게임 시계가 0.1초마다 화면을 다시 그려도
  /// 바뀐 아이템만 새로 만든다 (예전엔 매번 판의 모든 아이템을 다시 만들었다).
  final Map<int, (Object, Widget)> _tiles = {};

  Widget _tile(
    Item it,
    double cell, {
    required double wiggle,
    required bool selected,
    required bool wanted,
  }) {
    final perHour = game.itemIncomePerHour(it);
    final secs = it.isBubble
        ? max(0, it.bubbleUntil!.difference(game.now).inSeconds)
        : 0;
    final sig = (
      it.chain,
      it.level,
      it.isBubble,
      cell,
      wiggle,
      selected,
      wanted,
      secs,
      perHour,
    );
    final hit = _tiles[it.id];
    if (hit != null && hit.$1 == sig) return hit.$2;
    final w = ItemTile(
      wiggle: wiggle,
      item: it,
      size: cell,
      popKey: '${it.id}-${it.level}-${it.isBubble}',
      selected: selected,
      wanted: wanted,
      now: game.now,
      perHour: perHour,
    );
    _tiles[it.id] = (sig, w);
    return w;
  }

  List<Widget> _itemLayer(double cell, Offset Function(int) origin) {
    final wanted = {for (final o in game.orders) '${o.chain.index}-${o.level}'};
    // 곧 자동으로 합쳐질 두 칸: 차오를수록 흔들흔들 (D-099)
    final pair = game.autoMergeInterval == null ? null : game.nextAutoMergePair;
    final out = <Widget>[];
    final ids = <int>{};
    for (var i = 0; i < GameConfig.cellCount; i++) {
      final it = game.board[i];
      if (it == null || i == _dragFrom) continue;
      // 번호가 겹치면 (있어서는 안 되지만) 칸 번호로: 겹친 key 는 아이템끼리 자리를 바꿔 그린다
      final key = ids.add(it.id) ? ValueKey(it.id) : ValueKey('c$i');
      final o = origin(i);
      out.add(
        AnimatedPositioned(
          key: key,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          left: o.dx,
          top: o.dy,
          width: cell,
          height: cell,
          child: _tile(
            it,
            cell,
            wiggle: pair != null && (pair.$1 == i || pair.$2 == i)
                ? game.autoMergeFrac
                : 0,
            selected: widget.selected == i,
            wanted:
                !it.isBubble &&
                wanted.contains('${it.chain.index}-${it.level}'),
          ),
        ),
      );
    }
    _tiles.removeWhere((id, _) => !ids.contains(id));
    return out;
  }

  void _onTap(int? i) {
    if (i == null) return widget.onSelect(null);
    if (!game.canTake(i)) return widget.onLockedTap(i);
    final it = game.board[i];
    if (it == null) return widget.onSelect(null);
    if (it.isBubble) return widget.onBubbleTap(i);
    widget.onSelect(widget.selected == i ? null : i);
  }

  void _drop(int? target) {
    final from = _dragFrom;
    _dragPortal.hide();
    game.holdCell = null;
    setState(() => _dragFrom = null);
    if (from == null || target == null) return;
    final r = game.move(from, target);
    // 손으로 합쳤을 때만 진동 (자동 합치기 · 바구니는 없음, D-114)
    if (r == MoveResult.merged) {
      final it = game.board[target];
      // 최고 단계를 막 만들었으면 조금 세게
      haptic(
        it != null && it.level >= Chains.maxLevel(it.chain)
            ? Haptic.big
            : Haptic.tap,
      );
    }
    if (r == MoveResult.maxMerged) haptic(Haptic.big);
    if (r == MoveResult.merged ||
        r == MoveResult.moved ||
        r == MoveResult.swapped) {
      widget.onSelect(null);
    } else if (r == MoveResult.maxMerged) {
      widget.onSelect(null);
    }
  }
}

/// 아이템 한 칸. 그림은 ArtImage 가 담당 (아트가 있으면 PNG, 없으면 이모지).
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.size,
    this.popKey,
    this.lifted = false,
    this.wanted = false,
    this.selected = false,
    this.now,
    this.perHour,
    this.wiggle = 0,
  });

  /// 자동 합치기 차오름 (0~1): 아이템 그림만 흔들흔들 (레벨 · 수익 꼬리표는 그대로, D-099).
  final double wiggle;

  /// 이 아이템의 시간당 방치 수익 (오른쪽 아래에 작게). null 이면 표시 안 함.
  final double? perHour;
  final Item item;
  final double size;
  final String? popKey;
  final bool lifted;
  final bool wanted;
  final bool selected;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final bubble = item.isBubble;
    final tile = Stack(
      alignment: Alignment.center,
      children: [
        if (selected)
          Container(
            margin: EdgeInsets.all(size * 0.03),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.2),
              border: Border.all(color: Palette.accent, width: 3),
            ),
          ),
        if (lifted)
          Container(
            margin: EdgeInsets.all(size * 0.12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 6),
                ),
              ],
            ),
          ),
        _Wiggle(
          amount: wiggle,
          child: Opacity(
            opacity: bubble ? 0.75 : 1,
            child: ArtImage(
              Art.item(item.chain, item.level),
              size: size * 0.66,
            ),
          ),
        ),
        if (bubble)
          Art.bubble.available
              ? Opacity(
                  opacity: 0.85,
                  child: ArtImage(Art.bubble, size: size * 0.92),
                )
              : Container(
                  margin: EdgeInsets.all(size * 0.06),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.05),
                        const Color(0x8899D8FF),
                      ],
                      stops: const [0.6, 1],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 2,
                    ),
                  ),
                ),
        Positioned(
          left: size * 0.07,
          bottom: size * 0.05,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: size * 0.06,
              vertical: size * 0.005,
            ),
            decoration: BoxDecoration(
              color: (bubble ? const Color(0xFF4AA3D8) : Palette.primary)
                  .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(size * 0.12),
            ),
            child: Text(
              bubble && now != null
                  ? '${max(0, item.bubbleUntil!.difference(now!).inSeconds)}s'
                  : '${item.level}',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.17,
                height: 1.2,
              ),
            ),
          ),
        ),
        // 생산력: 시간당 코인 (오른쪽 아래, 작게)
        if (perHour != null && !bubble)
          Positioned(
            right: size * 0.05,
            bottom: size * 0.05,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                size * 0.02,
                size * 0.005,
                size * 0.05,
                size * 0.005,
              ),
              decoration: BoxDecoration(
                color: const Color(0xEEFFF6DA),
                borderRadius: BorderRadius.circular(size * 0.12),
                border: Border.all(color: const Color(0x99B8892E), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ArtImage(Art.coin, size: size * 0.15),
                  Text(
                    fmt(perHour!),
                    style: TextStyle(
                      color: const Color(0xFF7A5A12),
                      fontSize: size * 0.13,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (wanted)
          Positioned(
            right: size * 0.06,
            top: size * 0.04,
            child: ArtImage(Art.icon('letter'), size: size * 0.26),
          ),
      ],
    );
    if (popKey == null) return tile;
    // 또이잉 (D-081): 바닥에 붙은 채 납작 → 길쭉 → 납작… 젤리처럼 몇 번 출렁이다 멈춘다.
    return TweenAnimationBuilder<double>(
      key: ValueKey(popKey),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      builder: (_, t, child) {
        final d = exp(-4.2 * t) * cos(2 * pi * 2.6 * t);
        final sy = 1 - 0.34 * d;
        final sx = 1 + 0.26 * d;
        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(sx, sy, 1),
          child: child,
        );
      },
      child: tile,
    );
  }
}

/// 합치기 이펙트 (D-081): 별 조각이 사방으로 살짝 튄다 (물결은 빼고 탄력은 타일이 맡는다).
/// 결과 단계가 높을수록 조금 더 크고 많이 (5단계마다 한 계층, 소리와 같은 기준).
class _BurstFx extends StatelessWidget {
  const _BurstFx({super.key, required this.size, required this.level});
  final double size;
  final int level;

  @override
  Widget build(BuildContext context) {
    final tier = ((level - 1) ~/ 5).clamp(0, 5);
    final n = 5 + tier;
    final reach = size * (0.55 + 0.06 * tier);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 별 조각
          for (var i = 0; i < n; i++)
            Transform.translate(
              offset: Offset.fromDirection(-pi / 2 + 2 * pi * i / n, reach * v),
              child: Opacity(
                opacity: (1 - v).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 1 - 0.5 * v,
                  child: ArtImage(Art.icon('sparkle'), size: size * 0.24),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 행운 바구니 (+1단계)가 나왔을 때 (D-080): 금빛 후광이 번지고 '+1' 이 떠오른다.
class _LuckyFx extends StatelessWidget {
  const _LuckyFx({super.key, required this.size, this.label = true});
  final double size;
  final bool label;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 750),
      builder: (_, v, _) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: (1 - v * v).clamp(0.0, 1.0),
            child: Container(
              width: size * (1.0 + 0.6 * v),
              height: size * (1.0 + 0.6 * v),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFFFFD34D), const Color(0x00FFE27A)],
                ),
              ),
            ),
          ),
          if (label)
            Transform.translate(
              offset: Offset(0, -size * (0.2 + 0.45 * v)),
              child: Opacity(
                opacity: v < 0.7 ? 1 : (1 - v) / 0.3,
                child: Text(
                  tr('board.lucky'),
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: size * 0.24,
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Color(0xFFB8860B), offset: Offset(1.5, 0)),
                      Shadow(color: Color(0xFFB8860B), offset: Offset(-1.5, 0)),
                      Shadow(color: Color(0xFFB8860B), offset: Offset(0, 1.5)),
                      Shadow(color: Color(0xFFB8860B), offset: Offset(0, -1.5)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 자동 진행 칸 (D-094). fill: 칸 바닥부터 은은한 색이 차오르고 위쪽에 밝은 물결선.
/// bar: 칸 아래쪽 안에 가는 막대가 왼쪽부터 찬다. 자동 놓기 칸에는 바구니 그림이 흐리게.
class _AutoFill extends StatelessWidget {
  const _AutoFill({
    required this.frac,
    required this.size,
    required this.color,
    this.bar = false,
    this.basket,
  });
  final double frac;
  final double size;
  final Color color;
  final bool bar;
  final String? basket;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size * 0.2);
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: TweenAnimationBuilder<double>(
          // 0.1초마다 오는 값을 부드럽게 잇는다 (0 으로 돌아갈 때는 바로)
          tween: Tween(end: frac),
          duration: Duration(milliseconds: frac < 0.05 ? 0 : 140),
          builder: (_, v, _) => Stack(
            fit: StackFit.expand,
            children: [
              if (basket != null)
                Center(
                  child: _Wiggle(
                    amount: v,
                    child: Opacity(
                      opacity: 0.18 + 0.3 * v,
                      child: ArtImage(Art.icon(basket!), size: size * 0.5),
                    ),
                  ),
                ),
              if (!bar)
                ClipRRect(
                  borderRadius: r,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: v,
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              color.withValues(alpha: 0.55),
                              color.withValues(alpha: 0.28),
                            ],
                            stops: const [0.0, 0.25],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      size * 0.14,
                      0,
                      size * 0.14,
                      size * 0.07,
                    ),
                    child: Container(
                      height: size * 0.07,
                      decoration: BoxDecoration(
                        color: const Color(0x33000000),
                        borderRadius: BorderRadius.circular(size),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: v,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(size),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 흔들흔들 (D-099): amount(0~1, 자동 진행 차오름)가 커질수록 빨리 · 크게 흔들린다.
/// 끝나면 합치기 · 놓기가 일어나며 '뿅'(통 튀는 탄력)으로 이어진다. 거의 0 이면 그대로 그린다.
class _Wiggle extends StatefulWidget {
  const _Wiggle({required this.amount, required this.child});
  final double amount;
  final Widget child;

  @override
  State<_Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<_Wiggle> with TickerProviderStateMixin {
  AnimationController? _c;

  double get _a => ((widget.amount - 0.3) / 0.7).clamp(0.0, 1.0);

  void _sync() {
    if (_a > 0 && _c == null) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 1),
      )..repeat();
    } else if (_a <= 0 && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Wiggle old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 흔들기 시작 · 끝에 위젯 구조가 바뀌면 아이템의 '뿅'(놓일 때 탄력)이 다시 재생된다:
    // 늘 같은 구조(AnimatedBuilder + Transform)로 그리고, 멈춰 있을 땐 움직이지 않는 애니메이션을 준다
    final c = _c;
    return AnimatedBuilder(
      animation: c ?? kAlwaysDismissedAnimation,
      builder: (_, child) {
        final a = _a;
        final t = (c?.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
        // 살랑살랑: 진할수록 조금 빠르게 (초당 1.2 → 2.2번)
        final w = c == null ? 0.0 : sin(t * pi * 2 * (1.2 + 1.0 * a));
        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..rotateZ(w * 0.05 * a) // 최대 약 3°
            ..scaleByDouble(1 + 0.02 * a, 1 + 0.02 * a, 1, 1),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
