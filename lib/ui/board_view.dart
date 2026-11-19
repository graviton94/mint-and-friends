import 'package:material_ui/material_ui.dart';

import '../game/config.dart';
import '../game/game_state.dart';
import 'theme.dart';

/// 머지 보드. 드래그로 이동, 합치기, 교환.
class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.game});
  final GameState game;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  int? _dragFrom;
  Offset _dragPos = Offset.zero;
  Offset _grabOffset = Offset.zero;

  GameState get game => widget.game;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: GameConfig.cols / GameConfig.rows,
      child: LayoutBuilder(
        builder: (context, c) {
          const pad = 5.0;
          final cell = (c.maxWidth - pad * 2) / GameConfig.cols;

          Offset cellOrigin(int i) => Offset(
            pad + (i % GameConfig.cols) * cell,
            pad + (i ~/ GameConfig.cols) * cell,
          );

          int? cellAt(Offset p) {
            final col = ((p.dx - pad) / cell).floor();
            final row = ((p.dy - pad) / cell).floor();
            if (col < 0 ||
                row < 0 ||
                col >= GameConfig.cols ||
                row >= GameConfig.rows) {
              return null;
            }
            return row * GameConfig.cols + col;
          }

          final dragItem = _dragFrom == null ? null : game.board[_dragFrom!];
          final hoverCell = _dragFrom == null ? null : cellAt(_dragPos);
          final wanted = {
            for (final o in game.orders) '${o.chain.index}-${o.level}',
          };

          final children = <Widget>[];
          for (var i = 0; i < GameConfig.cellCount; i++) {
            final o = cellOrigin(i);
            final target = game.board[i];
            final highlight =
                dragItem != null &&
                target != null &&
                i != _dragFrom &&
                target.level == dragItem.level &&
                target.chain == dragItem.chain;
            children.add(
              Positioned(
                left: o.dx,
                top: o.dy,
                width: cell,
                height: cell,
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      color: highlight
                          ? Palette.accent.withValues(
                              alpha: hoverCell == i ? 0.75 : 0.35,
                            )
                          : ((i ~/ GameConfig.cols + i % GameConfig.cols).isEven
                                ? Palette.cell
                                : Palette.cellAlt),
                      borderRadius: BorderRadius.circular(cell * 0.2),
                    ),
                  ),
                ),
              ),
            );
          }

          for (var i = 0; i < GameConfig.cellCount; i++) {
            final it = game.board[i];
            if (it == null || i == _dragFrom) continue;
            final o = cellOrigin(i);
            children.add(
              AnimatedPositioned(
                key: ValueKey(it.id),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                left: o.dx,
                top: o.dy,
                width: cell,
                height: cell,
                child: IgnorePointer(
                  child: ItemTile(
                    item: it.def,
                    level: it.level,
                    size: cell,
                    popKey: '${it.id}-${it.level}',
                    wanted: wanted.contains('${it.chain.index}-${it.level}'),
                  ),
                ),
              ),
            );
          }

          if (dragItem != null) {
            final p = _dragPos - _grabOffset;
            children.add(
              Positioned(
                left: p.dx,
                top: p.dy,
                width: cell,
                height: cell,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 1.15,
                    child: ItemTile(
                      item: dragItem.def,
                      level: dragItem.level,
                      size: cell,
                      lifted: true,
                    ),
                  ),
                ),
              ),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              final i = cellAt(d.localPosition);
              if (i == null || game.board[i] == null) return;
              setState(() {
                _dragFrom = i;
                _dragPos = d.localPosition;
                _grabOffset = d.localPosition - cellOrigin(i);
              });
            },
            onPanUpdate: (d) {
              if (_dragFrom == null) return;
              setState(() => _dragPos = d.localPosition);
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
              child: Stack(clipBehavior: Clip.none, children: children),
            ),
          );
        },
      ),
    );
  }

  void _drop(int? target) {
    final from = _dragFrom;
    setState(() => _dragFrom = null);
    if (from != null && target != null) game.move(from, target);
  }
}

/// 아이템 한 칸. 아트로 바꿀 때 이 위젯만 고치면 된다.
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.level,
    required this.size,
    this.popKey,
    this.lifted = false,
    this.wanted = false,
  });
  final ItemDef item;
  final int level;
  final double size;
  final String? popKey;
  final bool lifted;
  final bool wanted;

  @override
  Widget build(BuildContext context) {
    final tile = Stack(
      alignment: Alignment.center,
      children: [
        if (lifted)
          Container(
            margin: EdgeInsets.all(size * 0.1),
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
        Text(item.emoji, style: TextStyle(fontSize: size * 0.54)),
        Positioned(
          right: size * 0.07,
          bottom: size * 0.05,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: size * 0.06,
              vertical: size * 0.005,
            ),
            decoration: BoxDecoration(
              color: Palette.primary.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(size * 0.12),
            ),
            child: Text(
              '$level',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.18,
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
