import 'package:material_ui/material_ui.dart';

import '../game/config.dart';
import '../game/game_state.dart';
import 'theme.dart';

/// 5x7 머지 보드. 드래그로 이동/합치기/교환.
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
      child: LayoutBuilder(builder: (context, c) {
        const pad = 6.0;
        final cell = (c.maxWidth - pad * 2) / GameConfig.cols;

        Offset cellOrigin(int i) =>
            Offset(pad + (i % GameConfig.cols) * cell, pad + (i ~/ GameConfig.cols) * cell);

        int? cellAt(Offset p) {
          final col = ((p.dx - pad) / cell).floor();
          final row = ((p.dy - pad) / cell).floor();
          if (col < 0 || row < 0 || col >= GameConfig.cols || row >= GameConfig.rows) return null;
          return row * GameConfig.cols + col;
        }

        final dragItem = _dragFrom == null ? null : game.board[_dragFrom!];
        final hoverCell = _dragFrom == null ? null : cellAt(_dragPos);

        final children = <Widget>[];
        for (var i = 0; i < GameConfig.cellCount; i++) {
          final o = cellOrigin(i);
          final target = game.board[i];
          final highlight = dragItem != null && target != null && i != _dragFrom && target.level == dragItem.level;
          children.add(Positioned(
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
                      ? Palette.accent.withValues(alpha: hoverCell == i ? 0.75 : 0.35)
                      : ((i ~/ GameConfig.cols + i % GameConfig.cols).isEven ? Palette.cell : Palette.cellAlt),
                  borderRadius: BorderRadius.circular(cell * 0.18),
                ),
              ),
            ),
          ));
        }

        for (var i = 0; i < GameConfig.cellCount; i++) {
          final it = game.board[i];
          if (it == null || i == _dragFrom) continue;
          final o = cellOrigin(i);
          children.add(AnimatedPositioned(
            key: ValueKey(it.id),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            left: o.dx,
            top: o.dy,
            width: cell,
            height: cell,
            child: IgnorePointer(child: ItemTile(level: it.level, size: cell, popKey: '${it.id}-${it.level}')),
          ));
        }

        if (dragItem != null) {
          final p = _dragPos - _grabOffset;
          children.add(Positioned(
            left: p.dx,
            top: p.dy,
            width: cell,
            height: cell,
            child: IgnorePointer(
              child: Transform.scale(scale: 1.15, child: ItemTile(level: dragItem.level, size: cell, lifted: true)),
            ),
          ));
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
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Stack(clipBehavior: Clip.none, children: children),
          ),
        );
      }),
    );
  }

  void _drop(int? target) {
    final from = _dragFrom;
    setState(() => _dragFrom = null);
    if (from != null && target != null) game.move(from, target);
  }
}

const _tierGlow = [
  [Color(0x00000000), Color(0x00000000)],
  [Color(0xFFFFF4C2), Color(0xFFF2B705)], // 황금
  [Color(0xFFE6FBFF), Color(0xFF5BC8E8)], // 다이아
];

/// 아이템 한 칸. 아트 교체 시 이 위젯만 바꾸면 된다.
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.level, required this.size, this.popKey, this.lifted = false});
  final int level;
  final double size;
  final String? popKey;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final def = GameConfig.item(level);
    final tile = Stack(
      alignment: Alignment.center,
      children: [
        if (lifted)
          Container(
            margin: EdgeInsets.all(size * 0.08),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 6))],
            ),
          ),
        if (GameConfig.tierOf(level) > 0)
          Container(
            margin: EdgeInsets.all(size * 0.07),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: _tierGlow[GameConfig.tierOf(level)]),
              border: Border.all(color: _tierGlow[GameConfig.tierOf(level)].last, width: size * 0.04),
            ),
          ),
        Text(def.emoji, style: TextStyle(fontSize: size * 0.56)),
        Positioned(
          right: size * 0.08,
          bottom: size * 0.06,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: size * 0.06, vertical: size * 0.01),
            decoration: BoxDecoration(
              color: Palette.primary.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(size * 0.12),
            ),
            child: Text(
              '$level',
              style: TextStyle(color: Colors.white, fontSize: size * 0.17, fontWeight: FontWeight.w800),
            ),
          ),
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
