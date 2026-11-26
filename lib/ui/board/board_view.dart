import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/config.dart';
import '../../game/format.dart';
import '../../game/game_state.dart';
import '../theme.dart';

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
  _Burst(this.cell, this.key, this.level);
}

class _BoardViewState extends State<BoardView> {
  final _dragPortal = OverlayPortalController();
  double _cellSize = 0;
  int? _dragFrom;
  Offset _dragPos = Offset.zero;
  Offset _grabOffset = Offset.zero;
  final List<_Burst> _bursts = [];
  int _burstKey = 0;
  StreamSubscription<GameEvent>? _sub;

  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    _sub = game.events.listen((e) {
      final b = e is MergedEvent
          ? _Burst(e.cell, _burstKey++, e.level)
          : e is LuckySpawnEvent
          ? _Burst(e.cell, _burstKey++, 0)
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

          Positioned at(int i, Widget child) {
            final o = origin(i);
            return Positioned(
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
                            at(i, _cellTile(i, dragItem, hover, cell)),
                        ],
                      ),
                    ),
                  ),
                  // L1 아이템
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: Stack(children: _itemLayer(cell, origin)),
                      ),
                    ),
                  ),
                  // L3 정보 카드
                  if (widget.floating != null)
                    _floatingAt(widget.floating!, cell, pad),
                  // L2 이펙트
                  for (final b in _bursts)
                    at(
                      b.cell,
                      IgnorePointer(
                        child: b.level == 0
                            ? _LuckyFx(key: ValueKey(b.key), size: cell)
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
    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: !open
              ? (vault ? const Color(0xFFD6CFE6) : const Color(0xFFD9CFB8))
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

  List<Widget> _itemLayer(double cell, Offset Function(int) origin) {
    final wanted = {for (final o in game.orders) '${o.chain.index}-${o.level}'};
    final out = <Widget>[];
    for (var i = 0; i < GameConfig.cellCount; i++) {
      final it = game.board[i];
      if (it == null || i == _dragFrom) continue;
      final o = origin(i);
      out.add(
        AnimatedPositioned(
          key: ValueKey(it.id),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          left: o.dx,
          top: o.dy,
          width: cell,
          height: cell,
          child: ItemTile(
            item: it,
            size: cell,
            popKey: '${it.id}-${it.level}-${it.isBubble}',
            selected: widget.selected == i,
            wanted:
                !it.isBubble &&
                wanted.contains('${it.chain.index}-${it.level}'),
            now: game.now,
            perHour: game.itemIncomePerHour(it),
          ),
        ),
      );
    }
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
    setState(() => _dragFrom = null);
    if (from == null || target == null) return;
    final r = game.move(from, target);
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
  });

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
        Opacity(
          opacity: bubble ? 0.75 : 1,
          child: ArtImage(Art.item(item.chain, item.level), size: size * 0.66),
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
    // 말랑한 탄성 (D-080): 납작하게 눌렸다가 위로 늘어나며 통 튀고 제자리
    return TweenAnimationBuilder<double>(
      key: ValueKey(popKey),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (_, t, child) {
        double sx, sy;
        if (t < 0.18) {
          final k = t / 0.18; // 0.55 → 1.25 x 0.8 (눌림)
          sx = 0.55 + 0.7 * k;
          sy = 0.55 + 0.25 * k;
        } else if (t < 0.45) {
          final k = (t - 0.18) / 0.27; // 1.25x0.8 → 0.9x1.15 (늘어남)
          sx = 1.25 - 0.35 * k;
          sy = 0.8 + 0.35 * k;
        } else {
          final k = Curves.elasticOut.transform((t - 0.45) / 0.55);
          sx = 0.9 + 0.1 * k;
          sy = 1.15 - 0.15 * k;
        }
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

/// 합치기 이펙트 (D-080): 동그란 물결 + 별 조각이 사방으로 튀어 나간다.
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
          // 물결
          Opacity(
            opacity: (1 - v) * 0.8,
            child: Container(
              width: size * (0.5 + v * (0.9 + 0.08 * tier)),
              height: size * (0.5 + v * (0.9 + 0.08 * tier)),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFF1B0),
                  width: 4 * (1 - v) + 1,
                ),
              ),
            ),
          ),
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
  const _LuckyFx({super.key, required this.size});
  final double size;

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
            opacity: (1 - v) * 0.9,
            child: Container(
              width: size * (0.7 + 0.5 * v),
              height: size * (0.7 + 0.5 * v),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFE27A).withValues(alpha: 0.9),
                    const Color(0x00FFE27A),
                  ],
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(0, -size * (0.2 + 0.45 * v)),
            child: Opacity(
              opacity: v < 0.7 ? 1 : (1 - v) / 0.3,
              child: Text(
                '+1',
                style: TextStyle(
                  fontSize: size * 0.32,
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
