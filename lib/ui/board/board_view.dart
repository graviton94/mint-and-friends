import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../art/art.dart';
import '../../game/config.dart';
import '../../game/game_state.dart';
import '../theme.dart';

/// 머지 보드.
///
/// 레이어 (아래 → 위), 각각 RepaintBoundary 로 분리:
///  L0 칸     : 바닥 타일, 잠긴 칸(자물쇠), 합칠 수 있는 칸 강조.
///  L1 아이템 : 아이템, 비눗방울, 선택 테두리, 부탁 표시.
///  L2 드래그 : 손가락을 따라오는 아이템.
///  L3 이펙트 : 합치기 반짝임.
///
/// 입력: 드래그 = 이동/합치기/교환, 탭 = 선택(판매·정보), 잠긴 칸 탭 = 칸 열기, 비눗방울 탭 = 꺼내기.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.game,
    required this.selected,
    required this.onSelect,
    required this.onLockedTap,
    required this.onBubbleTap,
  });

  final GameState game;
  final int? selected;
  final void Function(int? cell) onSelect;
  final void Function(int cell) onLockedTap;
  final void Function(int cell) onBubbleTap;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _Burst {
  final int cell;
  final int key;
  _Burst(this.cell, this.key);
}

class _BoardViewState extends State<BoardView> {
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
      if (e is MergedEvent) {
        final b = _Burst(e.cell, _burstKey++);
        setState(() => _bursts.add(b));
        Future.delayed(const Duration(milliseconds: 500), () {
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

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: GameConfig.cols / GameConfig.rows,
      child: LayoutBuilder(
        builder: (context, c) {
          const pad = 5.0;
          final cell = (c.maxWidth - pad * 2) / GameConfig.cols;
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
              if (i == null || !game.isCellOpen(i)) return;
              final it = game.board[i];
              if (it == null || it.isBubble) return;
              widget.onSelect(i);
              setState(() {
                _dragFrom = i;
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
                  // L2 드래그
                  if (dragItem != null)
                    Positioned(
                      left: _dragPos.dx - _grabOffset.dx,
                      top: _dragPos.dy - _grabOffset.dy,
                      width: cell,
                      height: cell,
                      child: IgnorePointer(
                        child: Transform.scale(
                          scale: 1.15,
                          child: ItemTile(
                            item: dragItem,
                            size: cell,
                            lifted: true,
                          ),
                        ),
                      ),
                    ),
                  // L3 이펙트
                  for (final b in _bursts)
                    at(
                      b.cell,
                      IgnorePointer(
                        child: _BurstFx(key: ValueKey(b.key), size: cell),
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
    final base = (i ~/ GameConfig.cols + i % GameConfig.cols).isEven
        ? Palette.cell
        : Palette.cellAlt;
    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: !open
              ? const Color(0xFFD9CFB8)
              : highlight
              ? Palette.accent.withValues(alpha: hover == i ? 0.75 : 0.35)
              : base,
          borderRadius: BorderRadius.circular(cell * 0.2),
        ),
        child: open
            ? null
            : Center(
                child: Opacity(
                  opacity: 0.55,
                  child: ArtImage(Art.lock, size: cell * 0.36),
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
          ),
        ),
      );
    }
    return out;
  }

  void _onTap(int? i) {
    if (i == null) return widget.onSelect(null);
    if (!game.isCellOpen(i)) return widget.onLockedTap(i);
    final it = game.board[i];
    if (it == null) return widget.onSelect(null);
    if (it.isBubble) return widget.onBubbleTap(i);
    widget.onSelect(widget.selected == i ? null : i);
  }

  void _drop(int? target) {
    final from = _dragFrom;
    setState(() => _dragFrom = null);
    if (from == null || target == null) return;
    final r = game.move(from, target);
    if (r == MoveResult.merged ||
        r == MoveResult.moved ||
        r == MoveResult.swapped) {
      widget.onSelect(game.board[target] == null ? null : target);
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
  });
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
          Container(
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
          right: size * 0.07,
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
        if (wanted)
          Positioned(
            left: size * 0.06,
            top: size * 0.04,
            child: Text('💌', style: TextStyle(fontSize: size * 0.22)),
          ),
      ],
    );
    if (popKey == null) return tile;
    return TweenAnimationBuilder<double>(
      key: ValueKey(popKey),
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: tile,
    );
  }
}

class _BurstFx extends StatelessWidget {
  const _BurstFx({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      builder: (_, v, _) => Opacity(
        opacity: 1 - v,
        child: Transform.scale(
          scale: 0.6 + v * 0.9,
          child: Center(
            child: Text('✨', style: TextStyle(fontSize: size * 0.6)),
          ),
        ),
      ),
    );
  }
}
